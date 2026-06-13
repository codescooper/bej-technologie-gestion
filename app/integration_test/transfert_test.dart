import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:powersync/powersync.dart';

import 'package:bej_gestion/src/data/powersync_db.dart';
import 'package:bej_gestion/src/data/bootstrap.dart';
import 'package:bej_gestion/src/data/ref_ids.dart';
import 'package:bej_gestion/src/data/api_client.dart';
import 'package:bej_gestion/src/data/sync_service.dart';
import 'package:bej_gestion/src/data/repositories/transfert_repository.dart';
import 'package:bej_gestion/src/data/repositories/produit_repository.dart';
import 'package:bej_gestion/src/data/repositories/dashboard_repository.dart';

/// Phase 2 : transfert inter-magasins (§2.5) + reporting consolidé.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late PowerSyncDatabase db;

  setUpAll(() async {
    db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
  });

  testWidgets('Transfert Cocody -> Yopougon en deux temps', (tester) async {
    final api = ApiClient('http://localhost:8080');
    final sync = SyncService(db, api);
    final transfertRepo = TransfertRepository(db);
    final produitRepo = ProduitRepository(db);

    const chargeur = '0d000000-0000-4000-8000-000000000003';
    const cocody = RefIds.magasinCocody;
    const yop = RefIds.magasinYopougon;
    const user = RefIds.userResponsable;

    Future<int> enTransit(String mag) async {
      final rs = await db.getAll(
        'SELECT COALESCE(quantite_en_transit,0) AS q FROM stocks_magasin '
        'WHERE produit_id = ? AND magasin_id = ?',
        [chargeur, mag],
      );
      return rs.isEmpty ? 0 : ((rs.first['q'] as num?) ?? 0).toInt();
    }

    final stockCocody0 = await produitRepo.quantiteDispo(chargeur, cocody);
    final stockYop0 = await produitRepo.quantiteDispo(chargeur, yop);

    final id = await transfertRepo.creer(
      produitId: chargeur,
      magasinSourceId: cocody,
      magasinDestId: yop,
      quantite: 3,
      utilisateurId: user,
    );

    expect(await produitRepo.quantiteDispo(chargeur, cocody), stockCocody0 - 3);
    expect(await produitRepo.quantiteDispo(chargeur, yop), stockYop0);
    expect(await enTransit(yop), 3);

    await transfertRepo.confirmerReception(transfertId: id, utilisateurId: user);

    expect(await produitRepo.quantiteDispo(chargeur, yop), stockYop0 + 3);
    expect(await enTransit(yop), 0);
    final rs = await db.getAll('SELECT statut FROM transferts WHERE id = ?', [id]);
    expect(rs.first['statut'], 'recu');

    await sync.push();
    expect(await sync.pendingCount(), 0);
    debugPrint('TRANSFERT_OK id=$id');
  });

  testWidgets('Reporting consolidé agrège par magasin', (tester) async {
    final rows = await DashboardRepository(db).consolide();
    expect(rows.length, greaterThanOrEqualTo(3)); // les 3 magasins
    final cocody = rows.firstWhere((r) => r.magasinId == RefIds.magasinCocody);
    expect(cocody.stockTotal, greaterThanOrEqualTo(0));
    // Yopougon a reçu 3 chargeurs via le transfert ci-dessus.
    final yop = rows.firstWhere((r) => r.magasinId == RefIds.magasinYopougon);
    expect(yop.stockTotal, greaterThanOrEqualTo(3));
    debugPrint('REPORTING_OK ${rows.length} magasins');
  });
}
