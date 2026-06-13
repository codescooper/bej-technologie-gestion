import 'package:powersync/powersync.dart';
import 'api_client.dart';

/// Pousse la file CRUD locale de PowerSync vers le backend (PostgreSQL).
///
/// C'est la matérialisation du critère Phase 0 : les écritures faites hors
/// ligne s'accumulent dans la file CRUD ; `push()` les transmet au serveur dès
/// que la connexion (ici le backend Dart) est disponible.
class SyncService {
  final PowerSyncDatabase db;
  final ApiClient api;
  SyncService(this.db, this.api);

  /// Nombre d'opérations locales en attente de synchronisation.
  Future<int> pendingCount() async {
    final stats = await db.getUploadQueueStats();
    return stats.count;
  }

  /// Draine toute la file CRUD vers le backend. Renvoie le nombre d'opérations
  /// poussées. Lève une exception si le backend est injoignable (offline) — la
  /// file reste alors intacte et sera repoussée au prochain essai.
  Future<int> push() async {
    var total = 0;
    while (true) {
      final tx = await db.getNextCrudTransaction();
      if (tx == null) break;

      final batch = tx.crud
          .map((e) => {
                'op': e.op.name, // put | patch | delete
                'table': e.table,
                'id': e.id,
                'data': e.opData, // null pour delete
              })
          .toList();

      // En cas d'échec réseau, on NE complète PAS la transaction : la file
      // est préservée (réessai ultérieur), garantissant l'absence de perte.
      await api.upload(batch);
      await tx.complete();
      total += batch.length;
    }
    return total;
  }
}
