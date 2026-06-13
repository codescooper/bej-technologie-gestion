import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:powersync/powersync.dart';

import 'package:bej_gestion/main.dart';
import 'package:bej_gestion/src/app_session.dart';
import 'package:bej_gestion/src/data/powersync_db.dart';
import 'package:bej_gestion/src/data/bootstrap.dart';
import 'package:bej_gestion/src/data/ref_ids.dart';
import 'package:bej_gestion/src/data/api_client.dart';
import 'package:bej_gestion/src/data/sync_service.dart';
import 'package:bej_gestion/src/data/repositories/client_repository.dart';
import 'package:bej_gestion/src/data/repositories/produit_repository.dart';
import 'package:bej_gestion/src/data/repositories/caisse_repository.dart';
import 'package:bej_gestion/src/data/repositories/vente_repository.dart';
import 'package:bej_gestion/src/data/repositories/reparation_repository.dart';
import 'package:bej_gestion/src/data/repositories/appareil_repository.dart';
import 'package:bej_gestion/src/data/repositories/photo_repository.dart';
import 'package:bej_gestion/src/data/repositories/dashboard_repository.dart';
import 'package:bej_gestion/src/data/repositories/retour_repository.dart';
import 'package:bej_gestion/src/data/repositories/avoir_repository.dart';
import 'package:bej_gestion/src/data/repositories/catalogue_repository.dart';
import 'package:bej_gestion/src/data/repositories/transfert_repository.dart';
import 'package:bej_gestion/src/data/repositories/inventaire_repository.dart';
import 'package:bej_gestion/src/data/repositories/auth_repository.dart';
import 'package:bej_gestion/src/ui/app_shell.dart';
import 'package:bej_gestion/src/models/produit.dart';
import 'package:bej_gestion/src/models/vente.dart';

/// Tests E2E (vrai Chrome via chromedriver, vrai client PowerSync web).
/// Vérification PostgreSQL faite à l'extérieur via les marqueurs émis.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PowerSyncDatabase db;
  late ApiClient api;
  late SyncService sync;

  setUpAll(() async {
    db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
    api = ApiClient('http://localhost:8080');
    sync = SyncService(db, api);
  });

  testWidgets('Phase 0 — client offline puis synchronisé', (tester) async {
    final repo = ClientRepository(db);
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final marker = 'E2E-$stamp';
    // Téléphone unique par exécution (évite les collisions de dédup §2.6).
    final phone = '07${stamp.toString().substring(stamp.toString().length - 8)}';
    final created = await repo.create(nom: marker, telephone: phone);
    expect(created.telephoneNormalise, startsWith('+225'));

    expect(await sync.pendingCount(), greaterThan(0));
    await sync.push();
    expect(await sync.pendingCount(), 0);
    debugPrint('E2E_CLIENT_MARKER=$marker');
  });

  testWidgets('Phase 1 — vente comptoir complète synchronisée', (tester) async {
    final produitRepo = ProduitRepository(db);
    final caisseRepo = CaisseRepository(db);
    final venteRepo = VenteRepository(db);
    const magasin = RefIds.magasinCocody;
    const user = RefIds.userAwaCaissiere;

    var caisse = await caisseRepo.caisseOuverte(magasin);
    if (caisse == null) {
      await caisseRepo.ouvrir(
          magasinId: magasin, utilisateurId: user, fondInitial: 10000);
      caisse = await caisseRepo.caisseOuverte(magasin);
    }

    const produitId = '0d000000-0000-4000-8000-000000000003'; // Chargeur USB-C
    final stockAvant = await produitRepo.quantiteDispo(produitId, magasin);
    expect(stockAvant, greaterThan(1));

    final cat =
        await db.getAll('SELECT * FROM produits WHERE id = ?', [produitId]);
    final lignes = [CartLine(Produit.fromRow(cat.first), quantite: 2)];

    final result = await venteRepo.enregistrerVente(
      magasinId: magasin,
      caisseId: caisse!.id,
      utilisateurId: user,
      lignes: lignes,
      paiements: [PaiementInput('cash', 5000), PaiementInput('wave', 7000)],
    );
    expect(result.total, greaterThan(0));

    // Stock décrémenté de 2 (cause = transaction).
    expect(await produitRepo.quantiteDispo(produitId, magasin), stockAvant - 2);

    await sync.push();
    expect(await sync.pendingCount(), 0);
    debugPrint('E2E_TX_MARKER=${result.transactionId}');
  });

  testWidgets('UI — le shell se monte', (tester) async {
    await tester.pumpWidget(BejApp(
      session: AppSession(),
      authRepo: AuthRepository(db),
      clientRepo: ClientRepository(db),
      produitRepo: ProduitRepository(db),
      caisseRepo: CaisseRepository(db),
      venteRepo: VenteRepository(db),
      reparationRepo: ReparationRepository(db),
      appareilRepo: AppareilRepository(db),
      photoRepo: PhotoRepository(db),
      dashboardRepo: DashboardRepository(db),
      retourRepo: RetourRepository(db),
      avoirRepo: AvoirRepository(db),
      catalogueRepo: CatalogueRepository(db),
      transfertRepo: TransfertRepository(db),
      inventaireRepo: InventaireRepository(db),
      syncService: sync,
      api: api,
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(AppShell), findsOneWidget);
  });
}
