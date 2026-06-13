import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bej_gestion/src/data/powersync_db.dart';
import 'package:bej_gestion/src/data/bootstrap.dart';
import 'package:bej_gestion/src/data/ref_ids.dart';
import 'package:bej_gestion/src/data/api_client.dart';
import 'package:bej_gestion/src/data/sync_service.dart';
import 'package:bej_gestion/src/data/repositories/client_repository.dart';
import 'package:bej_gestion/src/data/repositories/appareil_repository.dart';
import 'package:bej_gestion/src/data/repositories/reparation_repository.dart';
import 'package:bej_gestion/src/data/repositories/caisse_repository.dart';
import 'package:bej_gestion/src/data/repositories/produit_repository.dart';
import 'package:bej_gestion/src/models/reparation.dart';
import 'package:bej_gestion/src/models/vente.dart';

/// Test E2E du cycle réparation (§5.2) : réception -> pièce consommée ->
/// encaissement au retrait (Transaction type `reparation` rattachée à la
/// caisse) -> synchronisation. Vérification PostgreSQL via le marqueur émis.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Réparation complète encaissée et synchronisée', (tester) async {
    final db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
    final api = ApiClient('http://localhost:8080');
    final sync = SyncService(db, api);
    final clientRepo = ClientRepository(db);
    final appareilRepo = AppareilRepository(db);
    final reparationRepo = ReparationRepository(db);
    final caisseRepo = CaisseRepository(db);
    final produitRepo = ProduitRepository(db);

    const magasin = RefIds.magasinCocody;
    const user = RefIds.userAwaCaissiere;

    // Client + appareil + réparation (devis 20000 de main-d'œuvre).
    final client = await clientRepo.create(nom: 'Client Répa', telephone: '0708090910');
    final appareil = await appareilRepo.creer(
        clientId: client.id, marque: 'Apple', modele: 'iPhone 11', imei: '350000000000001');
    final repId = await reparationRepo.creer(
      appareilId: appareil.id,
      magasinId: magasin,
      technicienId: user,
      probleme: 'Écran cassé',
      devis: 20000,
    );

    // Consommer une pièce (Écran iPhone 11, prix 55000) -> stock -1, total +55000.
    const ecranId = '0d000000-0000-4000-8000-000000000001';
    final stockAvant = await produitRepo.quantiteDispo(ecranId, magasin);
    await reparationRepo.consommerPiece(
      reparationId: repId,
      produitId: ecranId,
      magasinId: magasin,
      prixUnitaire: 55000,
      utilisateurId: user,
    );
    expect(await produitRepo.quantiteDispo(ecranId, magasin), stockAvant - 1);

    final rep = await reparationRepo.getById(repId);
    expect(rep!.reparation.total, 75000); // 20000 main d'œuvre + 55000 pièce

    // Statut -> prêt, puis ouverture caisse + encaissement au retrait.
    await reparationRepo.changerStatut(repId, StatutReparation.pret);
    var caisse = await caisseRepo.caisseOuverte(magasin);
    if (caisse == null) {
      await caisseRepo.ouvrir(magasinId: magasin, utilisateurId: user, fondInitial: 0);
      caisse = await caisseRepo.caisseOuverte(magasin);
    }
    final result = await reparationRepo.encaisserRetrait(
      reparationId: repId,
      magasinId: magasin,
      caisseId: caisse!.id,
      utilisateurId: user,
      paiements: [PaiementInput('cash', 75000)],
    );
    expect(result.total, 75000);
    expect(result.jetonsGagnes, 750);

    // La réparation est livrée.
    final apres = await reparationRepo.getById(repId);
    expect(apres!.reparation.statut, StatutReparation.livre);

    // Synchroniser.
    await sync.push();
    expect(await sync.pendingCount(), 0);

    debugPrint('E2E_REPARATION_TX=${result.transactionId}');
  });
}
