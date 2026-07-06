import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';
import '../data/repositories/client_repository.dart';
import '../data/repositories/phase3_repository.dart';

/// Service de notifications SMS / WhatsApp via Twilio.
///
/// Désactivé par défaut : l'app fonctionne normalement sans configuration.
/// Pour activer : renseigner AccountSID, AuthToken et numéro expéditeur dans
/// Paramètres > Notifications, puis cocher "Actif".
///
/// Twilio SMS  : from_number = +1XXXXXXXXXX
/// Twilio WA   : from_number = whatsapp:+14155238886 (sandbox Twilio)
///               ou votre numéro WhatsApp Business homologué.
class NotificationService {
  final PowerSyncDatabase db;
  late final Phase3Repository _repo;

  NotificationService(this.db) : _repo = Phase3Repository(db);

  // ── Templates de messages ──────────────────────────────────────────────────

  static String _template(String evenement, String appareil, String magasin) {
    switch (evenement) {
      case 'recu':
        return 'Votre $appareil a bien été reçu chez $magasin. '
            'Nous vous contacterons dès le diagnostic effectué.';
      case 'pret':
        return 'Bonne nouvelle ! Votre $appareil est réparé et prêt à être '
            'récupéré chez $magasin. Merci de votre patience.';
      case 'livre':
        return 'Merci pour votre confiance. '
            'Votre $appareil a bien été récupéré. — $magasin';
      default:
        return 'Mise à jour de votre réparation ($appareil) chez $magasin.';
    }
  }

  // ── Envoi principal ────────────────────────────────────────────────────────

  /// Envoie une notification lors d'un changement de statut de réparation.
  /// Ne lève jamais d'exception — erreurs loggées dans [notifications_log].
  Future<void> notifierChangementStatut({
    required String magasinId,
    required String magasinNom,
    required String? clientId,
    required String appareilLibelle,
    required String statut,
  }) async {
    if (!_statutNotifiable(statut)) return;

    final cfg = await _repo.configNotifications(magasinId);
    if (cfg == null || (cfg['actif'] as int? ?? 0) == 0) return;

    final telephone = await _telephoneClient(clientId);
    if (telephone == null) return;

    final numero = ClientRepository.normalizePhone(telephone);
    if (numero == null) return;

    final msg = _template(statut, appareilLibelle, magasinNom);
    final whatsapp = (cfg['utiliser_whatsapp'] as int? ?? 0) == 1;
    final canal = whatsapp ? 'whatsapp' : 'sms';

    final to = whatsapp ? 'whatsapp:$numero' : numero;
    final from = cfg['from_number'] as String? ?? '';
    final from_ = whatsapp && !from.startsWith('whatsapp:') ? 'whatsapp:$from' : from;

    await _envoyerTwilio(
      accountSid: cfg['account_sid'] as String? ?? '',
      authToken: cfg['auth_token'] as String? ?? '',
      from: from_,
      to: to,
      body: msg,
      canal: canal,
      numero: numero,
      clientId: clientId,
      magasinId: magasinId,
      message: msg,
    );
  }

  /// Envoie un message de **test** avec des identifiants fournis directement
  /// (pas forcément encore enregistrés). Sert au bouton « Tester » de l'écran
  /// Paramètres. Ne journalise pas ; retourne `(ok, erreur)` pour affichage.
  Future<({bool ok, String? erreur})> envoyerTest({
    required String accountSid,
    required String authToken,
    required String from,
    required String numeroDest,
    required bool whatsapp,
  }) async {
    if (accountSid.isEmpty || authToken.isEmpty || from.isEmpty) {
      return (ok: false, erreur: 'Renseignez le SID, le token et le numéro expéditeur.');
    }
    final dest = ClientRepository.normalizePhone(numeroDest);
    if (dest == null) {
      return (ok: false, erreur: 'Numéro destinataire invalide.');
    }
    final to = whatsapp ? 'whatsapp:$dest' : dest;
    final fromN =
        whatsapp && !from.startsWith('whatsapp:') ? 'whatsapp:$from' : from;
    const body = 'BEJ Technologie : ceci est un message de test. '
        'Votre configuration de notifications fonctionne. ✅';
    try {
      final url = Uri.parse(
        'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json',
      );
      final credentials = base64Encode(utf8.encode('$accountSid:$authToken'));
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'To': to, 'From': fromN, 'Body': body},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (ok: true, erreur: null);
      }
      // Twilio renvoie un JSON { "message": "...", "code": ... } explicite.
      String detail = 'Erreur Twilio (HTTP ${response.statusCode})';
      try {
        final j = jsonDecode(response.body);
        if (j is Map && j['message'] != null) {
          detail = j['message'].toString();
        }
      } catch (_) {}
      return (ok: false, erreur: detail);
    } catch (e) {
      return (ok: false, erreur: 'Échec réseau : $e');
    }
  }

  // ── Interne ────────────────────────────────────────────────────────────────

  static bool _statutNotifiable(String s) =>
      s == 'recu' || s == 'pret' || s == 'livre';

  Future<String?> _telephoneClient(String? clientId) async {
    if (clientId == null) return null;
    final rs = await db.getAll(
      'SELECT telephone FROM clients WHERE id = ? LIMIT 1',
      [clientId],
    );
    return rs.isEmpty ? null : rs.first['telephone'] as String?;
  }

  Future<void> _envoyerTwilio({
    required String accountSid,
    required String authToken,
    required String from,
    required String to,
    required String body,
    required String canal,
    required String numero,
    required String? clientId,
    required String magasinId,
    required String message,
  }) async {
    if (accountSid.isEmpty || authToken.isEmpty || from.isEmpty) {
      await _repo.logNotification(
        clientId: clientId,
        magasinId: magasinId,
        canal: canal,
        numero: numero,
        message: message,
        statut: 'erreur',
        erreur: 'Configuration Twilio incomplète (SID/token/from manquant)',
      );
      return;
    }

    try {
      final url = Uri.parse(
        'https://api.twilio.com/2010-04-01/Accounts/$accountSid/Messages.json',
      );
      final credentials = base64Encode(utf8.encode('$accountSid:$authToken'));
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'To': to, 'From': from, 'Body': body},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _repo.logNotification(
          clientId: clientId,
          magasinId: magasinId,
          canal: canal,
          numero: numero,
          message: message,
          statut: 'envoye',
        );
      } else {
        await _repo.logNotification(
          clientId: clientId,
          magasinId: magasinId,
          canal: canal,
          numero: numero,
          message: message,
          statut: 'erreur',
          erreur: 'Twilio HTTP ${response.statusCode}',
        );
      }
    } catch (e) {
      await _repo.logNotification(
        clientId: clientId,
        magasinId: magasinId,
        canal: canal,
        numero: numero,
        message: message,
        statut: 'erreur',
        erreur: e.toString().substring(0, e.toString().length.clamp(0, 200)),
      );
    }
  }
}
