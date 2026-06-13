import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';
import '../../models/appareil.dart';

/// Appareils clients (§5.2 / §2.6). Dédup sur IMEI (fusion serveur).
class AppareilRepository {
  final PowerSyncDatabase db;
  final _uuid = const Uuid();

  AppareilRepository(this.db);

  /// Appareils d'un client.
  Future<List<Appareil>> parClient(String clientId) async {
    final rs = await db.getAll(
      'SELECT * FROM appareils WHERE client_id = ? AND fusionne_vers IS NULL '
      'ORDER BY date_creation DESC',
      [clientId],
    );
    return rs.map((r) => Appareil.fromRow(r)).toList();
  }

  /// Recherche par IMEI (proposition de fiche existante, §2.6).
  Future<Appareil?> findByImei(String? imei) async {
    if (imei == null || imei.trim().isEmpty) return null;
    final rs = await db.getAll(
      'SELECT * FROM appareils WHERE imei = ? AND fusionne_vers IS NULL LIMIT 1',
      [imei.trim()],
    );
    return rs.isEmpty ? null : Appareil.fromRow(rs.first);
  }

  Future<Appareil> creer({
    required String clientId,
    String? type,
    String? marque,
    String? modele,
    String? imei,
    String? numeroSerie,
    String? notes,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'INSERT INTO appareils(id, client_id, type, marque, modele, imei, '
      'numero_serie, notes, date_creation) VALUES(?,?,?,?,?,?,?,?,?)',
      [id, clientId, type, marque, modele, imei?.trim(), numeroSerie, notes, now],
    );
    return Appareil(
      id: id,
      clientId: clientId,
      type: type,
      marque: marque,
      modele: modele,
      imei: imei?.trim(),
      numeroSerie: numeroSerie,
      notes: notes,
    );
  }
}
