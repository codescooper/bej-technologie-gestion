import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bej_gestion/src/data/powersync_db.dart';
import 'package:bej_gestion/src/data/bootstrap.dart';
import 'package:bej_gestion/src/data/ref_ids.dart';
import 'package:bej_gestion/src/data/api_client.dart';
import 'package:bej_gestion/src/data/sync_service.dart';
import 'package:bej_gestion/src/data/repositories/catalogue_repository.dart';
import 'package:bej_gestion/src/data/repositories/client_repository.dart';
import 'package:bej_gestion/src/data/repositories/appareil_repository.dart';
import 'package:bej_gestion/src/data/repositories/reparation_repository.dart';

/// Catalogues recherchables et enrichissables (modèles, pannes) : recherche
/// d'un élément seedé, ajout d'un nouveau, puis usage dans une réparation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Recherche + ajout modèle/panne, réparation', (tester) async {
    final db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
    final api = ApiClient('http://localhost:8080');
    final sync = SyncService(db, api);
    final cat = CatalogueRepository(db);
    final clientRepo = ClientRepository(db);
    final appareilRepo = AppareilRepository(db);
    final reparationRepo = ReparationRepository(db);

    // Recherche dans le catalogue seedé.
    final iphones = await cat.rechercheModeles('iphone');
    expect(iphones, isNotEmpty);
    final ecran = await cat.recherchePannes('écran');
    expect(ecran, isNotEmpty);

    // Ajout (enrichissement) d'un nouveau modèle et d'une nouvelle panne.
    final nokia = await cat.ajouterModele('Nokia', '3310');
    expect(nokia.libelle, 'Nokia 3310');
    expect(await cat.rechercheModeles('nokia'), isNotEmpty);

    final panne = await cat.ajouterPanne('Problème réseau');
    expect(panne, 'Problème réseau');
    expect(await cat.recherchePannes('réseau'), contains('Problème réseau'));

    // Idempotence : ré-ajouter ne duplique pas.
    final nokia2 = await cat.ajouterModele('nokia', '3310');
    expect(nokia2.id, nokia.id);

    // Usage : réparation d'un appareil avec le modèle/panne choisis.
    final client = await clientRepo.create(nom: 'Cat Client', telephone: '0788990011');
    final app = await appareilRepo.creer(
        clientId: client.id, marque: nokia.marque, modele: nokia.modele);
    final repId = await reparationRepo.creer(
      appareilId: app.id,
      magasinId: RefIds.magasinCocody,
      technicienId: RefIds.userAwaCaissiere,
      probleme: panne,
      devis: 5000,
    );
    final rep = await reparationRepo.getById(repId);
    expect(rep!.reparation.probleme, 'Problème réseau');
    expect(rep.appareilLibelle, 'Nokia 3310');

    await sync.push();
    expect(await sync.pendingCount(), 0);
    debugPrint('CATALOGUE_OK');
  });
}
