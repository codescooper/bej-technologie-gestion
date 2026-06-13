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

/// Reproduit le parcours UI de création d'une réparation avec les listes
/// recherchables (modèle + problème) et le bouton « Créer ».
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late PowerSyncDatabase db;

  setUpAll(() async {
    db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
  });

  Future<void> pump(WidgetTester tester) async {
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

  testWidgets('Créer une réparation via listes modèle/problème', (tester) async {
    await pump(tester);

    // 1. Créer un client (prérequis).
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Client'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Client Repa UI');
    await tester.tap(find.widgetWithText(FilledButton, 'Créer'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 2. Onglet Réparations.
    await tester.tap(find.byIcon(Icons.build));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 3. Nouvelle réparation.
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Réparation'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 4. Choisir le client.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Client Repa UI').last);
    await tester.pumpAndSettle();

    // 5. Choisir un modèle dans la liste recherchable.
    await tester.ensureVisible(find.text('Modèle d\'appareil'));
    await tester.tap(find.text('Modèle d\'appareil'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.text('Apple iPhone 11').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 6. Choisir un problème (le champ peut être plus bas : on le rend visible).
    await tester.ensureVisible(find.text('Problème déclaré *'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Problème déclaré *'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // 'Batterie défectueuse' est en tête de liste (rendue sans scroll).
    await tester.tap(find.text('Batterie défectueuse').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 7. Créer.
    await tester.tap(find.widgetWithText(FilledButton, 'Créer'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // La réparation doit apparaître dans la liste.
    expect(find.textContaining('iPhone 11'), findsWidgets);
    debugPrint('REPARATION_UI_OK');
  });
}
