import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

/// Accès aux tables Phase 3 : FNE/DGI, Notifications SMS/WhatsApp, Campagnes fidélité.
class Phase3Repository {
  final PowerSyncDatabase db;
  final _uuid = const Uuid();

  Phase3Repository(this.db);

  // ──────────────────────────────────────────────
  // FNE / DGI
  // ──────────────────────────────────────────────

  Future<Map<String, dynamic>?> configFne(String magasinId) async {
    final rs = await db.getAll(
      'SELECT * FROM config_fne WHERE magasin_id = ? LIMIT 1',
      [magasinId],
    );
    return rs.isEmpty ? null : rs.first;
  }

  Future<void> sauvegarderConfigFne({
    required String magasinId,
    required bool actif,
    required String endpointUrl,
    required String merchantId,
    required String apiKey,
    required String numeroContrib,
  }) async {
    final existing = await configFne(magasinId);
    if (existing == null) {
      await db.execute(
        'INSERT INTO config_fne(id, magasin_id, actif, endpoint_url, '
        'merchant_id, api_key, numero_contrib) VALUES(?,?,?,?,?,?,?)',
        [_uuid.v4(), magasinId, actif ? 1 : 0, endpointUrl, merchantId, apiKey, numeroContrib],
      );
    } else {
      await db.execute(
        'UPDATE config_fne SET actif=?, endpoint_url=?, merchant_id=?, '
        'api_key=?, numero_contrib=? WHERE magasin_id=?',
        [actif ? 1 : 0, endpointUrl, merchantId, apiKey, numeroContrib, magasinId],
      );
    }
  }

  Future<void> logFactureFne({
    required String transactionId,
    required String magasinId,
    String? numeroFacture,
    String? qrCodeFiscal,
    required String statut,
    String? erreur,
  }) async {
    await db.execute(
      'INSERT INTO factures_fne(id, transaction_id, magasin_id, numero_facture, '
      'qr_code_fiscal, statut, erreur) VALUES(?,?,?,?,?,?,?)',
      [_uuid.v4(), transactionId, magasinId, numeroFacture, qrCodeFiscal, statut, erreur],
    );
  }

  Stream<List<Map<String, dynamic>>> watchFacturesFne(String magasinId) {
    return db.watch(
      'SELECT * FROM factures_fne WHERE magasin_id = ? ORDER BY date_emission DESC LIMIT 50',
      parameters: [magasinId],
    ).map((rs) => rs.toList());
  }

  // ──────────────────────────────────────────────
  // Notifications SMS/WhatsApp
  // ──────────────────────────────────────────────

  Future<Map<String, dynamic>?> configNotifications(String magasinId) async {
    final rs = await db.getAll(
      'SELECT * FROM config_notifications WHERE magasin_id = ? LIMIT 1',
      [magasinId],
    );
    return rs.isEmpty ? null : rs.first;
  }

  Future<void> sauvegarderConfigNotifications({
    required String magasinId,
    required bool actif,
    required String accountSid,
    required String authToken,
    required String fromNumber,
    required bool utiliserWhatsapp,
  }) async {
    final existing = await configNotifications(magasinId);
    if (existing == null) {
      await db.execute(
        'INSERT INTO config_notifications(id, magasin_id, actif, provider, '
        'account_sid, auth_token, from_number, utiliser_whatsapp) VALUES(?,?,?,?,?,?,?,?)',
        [_uuid.v4(), magasinId, actif ? 1 : 0, 'twilio', accountSid, authToken, fromNumber, utiliserWhatsapp ? 1 : 0],
      );
    } else {
      await db.execute(
        'UPDATE config_notifications SET actif=?, account_sid=?, auth_token=?, '
        'from_number=?, utiliser_whatsapp=? WHERE magasin_id=?',
        [actif ? 1 : 0, accountSid, authToken, fromNumber, utiliserWhatsapp ? 1 : 0, magasinId],
      );
    }
  }

  Future<void> logNotification({
    required String? clientId,
    required String magasinId,
    required String canal,
    required String numero,
    required String message,
    required String statut,
    String? erreur,
  }) async {
    await db.execute(
      'INSERT INTO notifications_log(id, client_id, magasin_id, canal, numero, '
      'message, statut, erreur) VALUES(?,?,?,?,?,?,?,?)',
      [_uuid.v4(), clientId, magasinId, canal, numero, message, statut, erreur],
    );
  }

  Stream<List<Map<String, dynamic>>> watchNotificationsLog(String magasinId) {
    return db.watch(
      'SELECT nl.*, c.nom AS client_nom FROM notifications_log nl '
      'LEFT JOIN clients c ON c.id = nl.client_id '
      'WHERE nl.magasin_id = ? ORDER BY nl.date_envoi DESC LIMIT 50',
      parameters: [magasinId],
    ).map((rs) => rs.toList());
  }

  // ──────────────────────────────────────────────
  // Campagnes fidélité
  // ──────────────────────────────────────────────

  Stream<List<CampagneFidelite>> watchCampagnes(String magasinId) {
    return db.watch(
      'SELECT * FROM campagnes_fidelite WHERE magasin_id = ? ORDER BY date_debut DESC',
      parameters: [magasinId],
    ).map((rs) => rs.map(CampagneFidelite.fromRow).toList());
  }

  Future<CampagneFidelite?> campagneActiveActuelle(String magasinId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rs = await db.getAll(
      'SELECT * FROM campagnes_fidelite '
      "WHERE magasin_id = ? AND actif = 1 AND date_debut <= ? AND date_fin >= ? "
      'ORDER BY multiplicateur DESC LIMIT 1',
      [magasinId, now, now],
    );
    return rs.isEmpty ? null : CampagneFidelite.fromRow(rs.first);
  }

  /// Retourne le multiplicateur de jetons actif (1 si aucune campagne).
  Future<double> multiplicateurJetonsActif(String magasinId) async {
    final c = await campagneActiveActuelle(magasinId);
    return c?.multiplicateur ?? 1.0;
  }

  Future<void> creerCampagne({
    required String magasinId,
    required String nom,
    required double multiplicateur,
    required DateTime dateDebut,
    required DateTime dateFin,
    String? description,
  }) async {
    await db.execute(
      'INSERT INTO campagnes_fidelite(id, magasin_id, nom, multiplicateur, '
      'date_debut, date_fin, actif, description) VALUES(?,?,?,?,?,?,?,?)',
      [
        _uuid.v4(), magasinId, nom, multiplicateur,
        dateDebut.toUtc().toIso8601String(),
        dateFin.toUtc().toIso8601String(),
        1, description,
      ],
    );
  }

  Future<void> toggleCampagne(String id, bool actif) async {
    await db.execute(
      'UPDATE campagnes_fidelite SET actif = ? WHERE id = ?',
      [actif ? 1 : 0, id],
    );
  }

  Future<void> supprimerCampagne(String id) async {
    await db.execute('DELETE FROM campagnes_fidelite WHERE id = ?', [id]);
  }
}

class CampagneFidelite {
  final String id;
  final String magasinId;
  final String nom;
  final double multiplicateur;
  final String dateDebut;
  final String dateFin;
  final bool actif;
  final String? description;

  CampagneFidelite({
    required this.id,
    required this.magasinId,
    required this.nom,
    required this.multiplicateur,
    required this.dateDebut,
    required this.dateFin,
    required this.actif,
    this.description,
  });

  factory CampagneFidelite.fromRow(Map<String, dynamic> r) => CampagneFidelite(
        id: r['id'] as String,
        magasinId: r['magasin_id'] as String,
        nom: r['nom'] as String,
        multiplicateur: (r['multiplicateur'] as num?)?.toDouble() ?? 2.0,
        dateDebut: r['date_debut'] as String,
        dateFin: r['date_fin'] as String,
        actif: (r['actif'] as int? ?? 0) == 1,
        description: r['description'] as String?,
      );
}
