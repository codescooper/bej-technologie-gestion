import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:powersync/powersync.dart';

import 'package:bej_gestion/src/data/powersync_db.dart';
import 'package:bej_gestion/src/data/bootstrap.dart';
import 'package:bej_gestion/src/data/ref_ids.dart';
import 'package:bej_gestion/src/data/repositories/client_repository.dart';
import 'package:bej_gestion/src/data/repositories/appareil_repository.dart';
import 'package:bej_gestion/src/data/repositories/reparation_repository.dart';
import 'package:bej_gestion/src/data/repositories/caisse_repository.dart';
import 'package:bej_gestion/src/data/repositories/vente_repository.dart';
import 'package:bej_gestion/src/data/repositories/dashboard_repository.dart';
import 'package:bej_gestion/src/models/produit.dart';
import 'package:bej_gestion/src/models/vente.dart';
import 'package:bej_gestion/src/app_session.dart';
import 'package:bej_gestion/src/ui/dashboard_page.dart';

/// Vérifie les agrégations du tableau de bord (§5) + le rendu de l'écran.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PowerSyncDatabase db;

  setUpAll(() async {
    db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
  });

  testWidgets('Dashboard agrège CA, opérations, caisse', (tester) async {
    const magasin = RefIds.magasinCocody;
    const user = RefIds.userAwaCaissiere;

    final clientRepo = ClientRepository(db);
    final appareilRepo = AppareilRepository(db);
    final reparationRepo = ReparationRepository(db);
    final caisseRepo = CaisseRepository(db);
    final venteRepo = VenteRepository(db);
    final dashboardRepo = DashboardRepository(db);

    var caisse = await caisseRepo.caisseOuverte(magasin);
    if (caisse == null) {
      await caisseRepo.ouvrir(magasinId: magasin, utilisateurId: user, fondInitial: 5000);
      caisse = await caisseRepo.caisseOuverte(magasin);
    }

    const chargeur = '0d000000-0000-4000-8000-000000000003';
    final cat = await db.getAll('SELECT * FROM produits WHERE id = ?', [chargeur]);
    final vente = await venteRepo.enregistrerVente(
      magasinId: magasin,
      caisseId: caisse!.id,
      utilisateurId: user,
      lignes: [CartLine(Produit.fromRow(cat.first), quantite: 1)],
      paiements: [PaiementInput('cash', 6000)],
    );

    final client = await clientRepo.create(nom: 'Dash Client', telephone: '0712131415');
    final app = await appareilRepo.creer(clientId: client.id, marque: 'Samsung');
    final repId = await reparationRepo.creer(
        appareilId: app.id, magasinId: magasin, devis: 20000);
    final repaResult = await reparationRepo.encaisserRetrait(
      reparationId: repId,
      magasinId: magasin,
      caisseId: caisse.id,
      utilisateurId: user,
      paiements: [PaiementInput('wave', 20000)],
    );

    final d = await dashboardRepo.load(magasin);

    expect(d.caVentes, greaterThanOrEqualTo(vente.total));
    expect(d.caReparations, greaterThanOrEqualTo(repaResult.total));
    expect(d.caTotal, d.caVentes + d.caReparations);
    expect(d.nbVentes, greaterThanOrEqualTo(1));
    expect(d.nbReparations, greaterThanOrEqualTo(1));
    expect(d.caisseOuverte, true);
    expect(d.caisseTheoriqueCash, greaterThanOrEqualTo(11000));
    expect(d.caisseTheoriqueMobile, greaterThanOrEqualTo(20000));
    expect(d.jetonsDistribues, greaterThan(0));

    debugPrint('DASHBOARD_OK caTotal=${d.caTotal}');
  });

  testWidgets('DashboardPage se rend sans crash', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DashboardPage(repo: DashboardRepository(db), session: AppSession()),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final ex1 = tester.takeException();
    final ex2 = tester.takeException();
    if (ex1 != null || ex2 != null) {
      fail('RENDER_EXCEPTION: [$ex1] || [$ex2]');
    }
    expect(find.text('Chiffre d\'affaires du jour'), findsWidgets);
  });
}
