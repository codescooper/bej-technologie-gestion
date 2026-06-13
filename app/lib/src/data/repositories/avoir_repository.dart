import 'package:powersync/powersync.dart';
import '../../models/avoir.dart';

/// Lecture des avoirs (§5.6). La création se fait via RetourRepository ;
/// la consommation via VenteRepository (atomique avec la vente).
class AvoirRepository {
  final PowerSyncDatabase db;
  AvoirRepository(this.db);

  /// Avoirs actifs d'un client (crédit restant > 0).
  Future<List<Avoir>> actifsParClient(String clientId) async {
    final rs = await db.getAll(
      "SELECT * FROM avoirs WHERE client_id = ? AND statut = 'actif' "
      'AND montant_restant > 0 ORDER BY date_creation',
      [clientId],
    );
    return rs.map((r) => Avoir.fromRow(r)).toList();
  }

  /// Solde total d'avoirs actifs d'un client.
  Future<num> solde(String clientId) async {
    final rs = await db.getAll(
      "SELECT COALESCE(SUM(montant_restant),0) AS s FROM avoirs "
      "WHERE client_id = ? AND statut = 'actif'",
      [clientId],
    );
    return (rs.first['s'] as num?) ?? 0;
  }

  /// Tous les avoirs d'un client (actifs + utilisés).
  Future<List<Avoir>> tousParClient(String clientId) async {
    final rs = await db.getAll(
      'SELECT * FROM avoirs WHERE client_id = ? ORDER BY date_creation DESC',
      [clientId],
    );
    return rs.map((r) => Avoir.fromRow(r)).toList();
  }

  Stream<List<Avoir>> watchActifs(String clientId) {
    return db
        .watch(
            "SELECT * FROM avoirs WHERE client_id = ? AND statut = 'actif' "
            'AND montant_restant > 0 ORDER BY date_creation',
            parameters: [clientId])
        .map((rs) => rs.map((r) => Avoir.fromRow(r)).toList());
  }
}
