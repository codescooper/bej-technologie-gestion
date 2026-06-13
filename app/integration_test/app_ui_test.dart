import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:powersync/powersync.dart';

import 'package:bej_gestion/main.dart';
import 'package:bej_gestion/src/app_session.dart';
import 'package:bej_gestion/src/data/powersync_db.dart';
import 'package:bej_gestion/src/data/bootstrap.dart';
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

/// Test E2E pilotant la VRAIE interface (taps + saisies) sur tout le parcours :
/// Clients -> Stock -> Caisse (ouvrir) -> Vente (panier + paiement mixte + reçu QR)
/// -> Synchroniser -> Caisse (clôturer). Exécuté dans un vrai Chrome.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PowerSyncDatabase db;

  Future<void> pumpApp(WidgetTester tester) async {
    final api = ApiClient('http://localhost:8080');
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
      syncService: SyncService(db, api),
      api: api,
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  setUpAll(() async {
    db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
  });

  testWidgets('Parcours UI complet (toutes fonctionnalités)', (tester) async {
    await pumpApp(tester);

    // --- 1. CLIENTS : créer un client via le dialogue ---
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Client'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau client'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Client Test UI');
    await tester.tap(find.widgetWithText(FilledButton, 'Créer'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Client Test UI'), findsWidgets);

    // --- 2. STOCK : le catalogue affiche les produits seedés ---
    await tester.tap(find.byIcon(Icons.inventory_2));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('Chargeur USB-C 20W'), findsWidgets);

    // --- 3. CAISSE : ouvrir si fermée ---
    await tester.tap(find.byIcon(Icons.account_balance_wallet));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    if (find.text('Ouvrir la caisse').evaluate().isNotEmpty) {
      await tester.tap(find.widgetWithText(FilledButton, 'Ouvrir la caisse'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '10000');
      await tester.tap(find.widgetWithText(FilledButton, 'Ouvrir'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }
    expect(find.text('Caisse ouverte'), findsOneWidget);

    // --- 4. VENTE : panier + paiement mixte + reçu QR (le crash d'avant) ---
    await tester.tap(find.byIcon(Icons.point_of_sale));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // Ajouter 2 produits au panier
    await tester.tap(find.text('Chargeur USB-C 20W').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coque transparente').first);
    await tester.pumpAndSettle();
    // Encaisser
    await tester.tap(find.textContaining('Encaisser'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Paiement'), findsWidgets);
    // Paiement mixte : laisser le cash par défaut, ajouter un peu en Wave.
    // Ciblé DANS le dialogue (le champ de scan de la page de vente est aussi
    // un TextField, à l'écran derrière la modale → on l'exclut).
    final fields = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), '5000'); // espèces
    await tester.enterText(fields.at(1), '4000'); // wave
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // Le reçu QR doit s'afficher SANS crash
    expect(find.text('Reçu interne'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Terminer'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // --- 5. SYNCHRONISER (via le tooltip pour cibler l'IconButton) ---
    await tester.tap(find.byTooltip('Synchroniser'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // --- 6. CAISSE : clôturer ---
    await tester.tap(find.byIcon(Icons.account_balance_wallet));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.widgetWithText(FilledButton, 'Clôturer la caisse'));
    // _cloturer charge les totaux (requête DB) AVANT d'afficher le dialogue :
    // on pompe jusqu'à ce que les champs apparaissent.
    await tester.pumpAndSettle();
    for (var i = 0; i < 20 && find.byType(TextField).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // Diagnostic si le dialogue de clôture n'est pas là.
    if (find.byType(TextField).evaluate().isEmpty) {
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .join(' | ');
      fail('CLOTURE sans TextField. '
          'titre=${find.text('Clôture de caisse').evaluate().isNotEmpty} '
          'caisseOuverte=${find.text('Caisse ouverte').evaluate().isNotEmpty} '
          'btnCloturer=${find.widgetWithText(FilledButton, 'Clôturer la caisse').evaluate().length} '
          'btnOuvrir=${find.text('Ouvrir la caisse').evaluate().length} '
          'textes=[$texts]');
    }
    // Théorique : fond 10000 + 5000 cash = 15000 ; mobile = 4000 (wave).
    final clotureFields = find.byType(TextField);
    await tester.enterText(clotureFields.at(0), '15000'); // cash réel
    await tester.enterText(clotureFields.at(1), '4000'); // mobile réel
    await tester.tap(find.widgetWithText(FilledButton, 'Clôturer'));
    // cloturer() écrit en DB (await) avant d'afficher la confirmation.
    await tester.pumpAndSettle();
    for (var i = 0;
        i < 20 && find.text('Caisse clôturée').evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Caisse clôturée'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'OK'));
    await tester.pumpAndSettle();

    debugPrint('UI_E2E_OK');
  });
}
