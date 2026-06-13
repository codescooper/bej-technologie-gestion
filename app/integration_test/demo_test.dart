import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:powersync/powersync.dart';

import 'package:bej_gestion/src/app_session.dart';
import 'package:bej_gestion/src/data/powersync_db.dart';
import 'package:bej_gestion/src/data/bootstrap.dart';
import 'package:bej_gestion/src/data/api_client.dart';
import 'package:bej_gestion/src/data/sync_service.dart';
import 'package:bej_gestion/src/data/demo_controller.dart';
import 'package:bej_gestion/src/data/repositories/client_repository.dart';
import 'package:bej_gestion/src/data/repositories/produit_repository.dart';
import 'package:bej_gestion/src/data/repositories/caisse_repository.dart';
import 'package:bej_gestion/src/data/repositories/vente_repository.dart';
import 'package:bej_gestion/src/data/repositories/reparation_repository.dart';
import 'package:bej_gestion/src/data/repositories/appareil_repository.dart';
import 'package:bej_gestion/src/data/repositories/transfert_repository.dart';
import 'package:bej_gestion/src/data/repositories/inventaire_repository.dart';
import 'package:bej_gestion/src/data/repositories/retour_repository.dart';
import 'package:bej_gestion/src/data/repositories/dashboard_repository.dart';

/// Mode Démo : exécute tout le scénario de bout en bout et vérifie qu'aucune
/// étape ne tombe en erreur (la démo sert aussi de smoke-test global).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late PowerSyncDatabase db;

  setUpAll(() async {
    db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
  });

  testWidgets('Le scénario de démo se déroule sans erreur', (tester) async {
    final api = ApiClient('http://localhost:8080');
    final session = AppSession();
    final demo = DemoController(
      db: db,
      session: session,
      clientRepo: ClientRepository(db),
      produitRepo: ProduitRepository(db),
      caisseRepo: CaisseRepository(db),
      venteRepo: VenteRepository(db),
      reparationRepo: ReparationRepository(db),
      appareilRepo: AppareilRepository(db),
      transfertRepo: TransfertRepository(db),
      inventaireRepo: InventaireRepository(db),
      retourRepo: RetourRepository(db),
      dashboardRepo: DashboardRepository(db),
      syncService: SyncService(db, api),
    );
    demo.setVitesse(3.0); // accélère les pauses pour le test

    await demo.demarrer();

    expect(demo.statut, DemoStatut.termine,
        reason: demo.erreur ?? 'statut inattendu');
    for (var i = 0; i < demo.steps.length; i++) {
      final r = demo.resultat(i);
      expect(r, isNotNull, reason: 'Étape ${i + 1} sans résultat');
      expect(r!.startsWith('ERREUR'), isFalse,
          reason: 'Étape ${i + 1} (${demo.steps[i].titre}) : $r');
    }
    debugPrint('DEMO_OK ${demo.steps.length} étapes déroulées');
  });
}
