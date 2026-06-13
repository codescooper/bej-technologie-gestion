import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bej_gestion/src/data/powersync_db.dart';
import 'package:bej_gestion/src/data/bootstrap.dart';
import 'package:bej_gestion/src/data/ref_ids.dart';
import 'package:bej_gestion/src/data/api_client.dart';
import 'package:bej_gestion/src/data/sync_service.dart';
import 'package:bej_gestion/src/data/repositories/client_repository.dart';
import 'package:bej_gestion/src/data/repositories/caisse_repository.dart';
import 'package:bej_gestion/src/data/repositories/vente_repository.dart';
import 'package:bej_gestion/src/data/repositories/produit_repository.dart';
import 'package:bej_gestion/src/data/repositories/retour_repository.dart';
import 'package:bej_gestion/src/data/repositories/avoir_repository.dart';
import 'package:bej_gestion/src/models/produit.dart';
import 'package:bej_gestion/src/models/vente.dart';

/// Test E2E retour & avoir (§5.6) : vente avec client -> retour partiel ->
/// avoir créé + stock réintégré + jetons annulés -> nouvelle vente payée avec
/// l'avoir -> synchronisation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Retour partiel -> avoir -> paiement par avoir', (tester) async {
    final db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
    final api = ApiClient('http://localhost:8080');
    final sync = SyncService(db, api);
    final clientRepo = ClientRepository(db);
    final caisseRepo = CaisseRepository(db);
    final venteRepo = VenteRepository(db);
    final produitRepo = ProduitRepository(db);
    final retourRepo = RetourRepository(db);
    final avoirRepo = AvoirRepository(db);

    const magasin = RefIds.magasinCocody;
    const user = RefIds.userAwaCaissiere;
    const chargeur = '0d000000-0000-4000-8000-000000000003'; // 6000 FCFA

    var caisse = await caisseRepo.caisseOuverte(magasin);
    if (caisse == null) {
      await caisseRepo.ouvrir(magasinId: magasin, utilisateurId: user, fondInitial: 0);
      caisse = await caisseRepo.caisseOuverte(magasin);
    }

    final client = await clientRepo.create(nom: 'Retour Client', telephone: '0799001122');
    final cat = await db.getAll('SELECT * FROM produits WHERE id = ?', [chargeur]);
    final produit = Produit.fromRow(cat.first);
    final stock0 = await produitRepo.quantiteDispo(chargeur, magasin);

    // Vente : 2 chargeurs = 12 000, payés cash. Jetons gagnés = 120.
    final vente1 = await venteRepo.enregistrerVente(
      magasinId: magasin,
      caisseId: caisse!.id,
      utilisateurId: user,
      clientId: client.id,
      lignes: [CartLine(produit, quantite: 2)],
      paiements: [PaiementInput('cash', 12000)],
    );
    expect(await produitRepo.quantiteDispo(chargeur, magasin), stock0 - 2);

    // Retour de 1 chargeur -> avoir 6000, stock +1, jetons annulés 60.
    final retour = await retourRepo.enregistrerRetour(
      transactionOrigineId: vente1.transactionId,
      magasinId: magasin,
      caisseId: caisse.id,
      utilisateurId: user,
      clientId: client.id,
      lignes: [
        LigneRetour(
            produitId: chargeur,
            produitNom: 'Chargeur',
            quantite: 1,
            prixUnitaire: produit.prixVente),
      ],
    );
    expect(retour.montant, 6000);
    expect(retour.jetonsAnnules, 60);
    expect(await produitRepo.quantiteDispo(chargeur, magasin), stock0 - 1);
    expect(await avoirRepo.solde(client.id), 6000);

    // Nouvelle vente de 1 chargeur (6000) entièrement payée par l'avoir.
    final vente2 = await venteRepo.enregistrerVente(
      magasinId: magasin,
      caisseId: caisse.id,
      utilisateurId: user,
      clientId: client.id,
      lignes: [CartLine(produit, quantite: 1)],
      avoirId: retour.avoirId,
      avoirUtilise: 6000,
      paiements: [],
    );
    expect(vente2.total, 0);
    expect(vente2.avoirUtilise, 6000);
    expect(await avoirRepo.solde(client.id), 0); // avoir consommé
    expect(await produitRepo.quantiteDispo(chargeur, magasin), stock0 - 2);

    await sync.push();
    expect(await sync.pendingCount(), 0);
    debugPrint('E2E_RETOUR_AVOIR_OK tx=${retour.retourTransactionId}');
  });
}
