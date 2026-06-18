import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';
import '../data/repositories/phase3_repository.dart';

/// Service d'émission des Factures Normalisées Électroniques (FNE) — DGI CI.
///
/// Désactivé par défaut : l'app fonctionne normalement sans configuration.
/// Pour activer : renseigner les champs dans Paramètres > FNE et cocher "Actif".
///
/// L'API DGI n'est pas documentée publiquement ; ce service implémente la
/// structure standard d'une e-invoice API REST. Adapter [soumettre] à la
/// spécification réelle fournie par la DGI lors de l'obtention des accès.
class FneService {
  final PowerSyncDatabase db;
  late final Phase3Repository _repo;

  FneService(this.db) : _repo = Phase3Repository(db);

  /// Soumet une vente à la DGI et retourne le résultat (numéro + QR fiscal).
  /// Retourne null si le service est désactivé ou si la config est incomplète.
  /// Ne lève jamais d'exception — erreurs loggées dans `factures_fne`.
  Future<FneResult?> soumettre({
    required String transactionId,
    required String magasinId,
    required num total,
    required DateTime date,
    String? clientNom,
    String? clientTelephone,
    List<({String libelle, int quantite, num prixUnitaire})> lignes = const [],
  }) async {
    final cfg = await _repo.configFne(magasinId);
    if (cfg == null || (cfg['actif'] as int? ?? 0) == 0) return null;

    final endpoint = cfg['endpoint_url'] as String? ?? '';
    final merchantId = cfg['merchant_id'] as String? ?? '';
    final apiKey = cfg['api_key'] as String? ?? '';
    final numeroContrib = cfg['numero_contrib'] as String? ?? '';

    if (endpoint.isEmpty || merchantId.isEmpty || apiKey.isEmpty) return null;

    final payload = {
      'merchant_id': merchantId,
      'numero_contribuable': numeroContrib,
      'transaction_ref': transactionId,
      'date_emission': date.toUtc().toIso8601String(),
      'montant_ttc': total,
      'client': clientNom != null ? {'nom': clientNom, 'telephone': clientTelephone} : null,
      'lignes': lignes.map((l) => {
        'libelle': l.libelle,
        'quantite': l.quantite,
        'prix_unitaire': l.prixUnitaire,
        'montant': l.quantite * l.prixUnitaire,
      }).toList(),
    };

    try {
      final response = await http.post(
        Uri.parse('$endpoint/factures'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final num = body['numero_facture'] as String?;
        final qr = body['qr_code'] as String?;
        await _repo.logFactureFne(
          transactionId: transactionId,
          magasinId: magasinId,
          numeroFacture: num,
          qrCodeFiscal: qr,
          statut: 'emise',
        );
        return FneResult(numeroFacture: num, qrCodeFiscal: qr);
      } else {
        await _repo.logFactureFne(
          transactionId: transactionId,
          magasinId: magasinId,
          statut: 'erreur',
          erreur: 'HTTP ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 200))}',
        );
        return null;
      }
    } catch (e) {
      await _repo.logFactureFne(
        transactionId: transactionId,
        magasinId: magasinId,
        statut: 'erreur',
        erreur: e.toString().substring(0, e.toString().length.clamp(0, 200)),
      );
      return null;
    }
  }
}

class FneResult {
  final String? numeroFacture;
  final String? qrCodeFiscal;
  const FneResult({this.numeroFacture, this.qrCodeFiscal});
}
