import 'package:flutter/material.dart';
import 'src/app_session.dart';
import 'src/data/powersync_db.dart';
import 'src/data/bootstrap.dart';
import 'src/data/api_client.dart';
import 'src/data/sync_service.dart';
import 'src/data/repositories/client_repository.dart';
import 'src/data/repositories/produit_repository.dart';
import 'src/data/repositories/caisse_repository.dart';
import 'src/data/repositories/vente_repository.dart';
import 'src/data/repositories/reparation_repository.dart';
import 'src/data/repositories/appareil_repository.dart';
import 'src/data/repositories/photo_repository.dart';
import 'src/data/repositories/dashboard_repository.dart';
import 'src/data/repositories/retour_repository.dart';
import 'src/data/repositories/avoir_repository.dart';
import 'src/data/repositories/catalogue_repository.dart';
import 'src/data/repositories/transfert_repository.dart';
import 'src/data/repositories/inventaire_repository.dart';
import 'src/data/repositories/etiquette_qr_repository.dart';
import 'src/data/repositories/auth_repository.dart';
import 'src/data/repositories/phase3_repository.dart';
import 'src/data/demo_controller.dart';
import 'src/services/fne_service.dart';
import 'src/services/notification_service.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/login_page.dart';

/// Adresse du backend de synchronisation (serveur Dart local).
/// Surchargeable au build : --dart-define=BEJ_API=http://localhost:8080
const _apiBase = String.fromEnvironment(
  'BEJ_API',
  defaultValue: 'http://localhost:8080',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = await openDatabase();
  await seedLocalReferenceIfEmpty(db); // référentiel local (cf. bootstrap.dart)

  final api = ApiClient(_apiBase);
  final session = AppSession()..logout(); // démarre sur l'écran de connexion

  runApp(BejApp(
    session: session,
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
    etiquetteRepo: EtiquetteQrRepository(db),
    phase3Repo: Phase3Repository(db),
    fneService: FneService(db),
    notifService: NotificationService(db),
    demoController: DemoController(
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
    ),
    syncService: SyncService(db, api),
    api: api,
  ));
}

class BejApp extends StatelessWidget {
  final AppSession session;
  final AuthRepository authRepo;
  final ClientRepository clientRepo;
  final ProduitRepository produitRepo;
  final CaisseRepository caisseRepo;
  final VenteRepository venteRepo;
  final ReparationRepository reparationRepo;
  final AppareilRepository appareilRepo;
  final PhotoRepository photoRepo;
  final DashboardRepository dashboardRepo;
  final RetourRepository retourRepo;
  final AvoirRepository avoirRepo;
  final CatalogueRepository catalogueRepo;
  final TransfertRepository transfertRepo;
  final InventaireRepository inventaireRepo;
  final EtiquetteQrRepository? etiquetteRepo;
  final Phase3Repository? phase3Repo;
  final FneService? fneService;
  final NotificationService? notifService;
  final DemoController? demoController;
  final SyncService syncService;
  final ApiClient api;

  const BejApp({
    super.key,
    required this.session,
    required this.authRepo,
    required this.clientRepo,
    required this.produitRepo,
    required this.caisseRepo,
    required this.venteRepo,
    required this.reparationRepo,
    required this.appareilRepo,
    required this.photoRepo,
    required this.dashboardRepo,
    required this.retourRepo,
    required this.avoirRepo,
    required this.catalogueRepo,
    required this.transfertRepo,
    required this.inventaireRepo,
    this.etiquetteRepo,
    this.phase3Repo,
    this.fneService,
    this.notifService,
    this.demoController,
    required this.syncService,
    required this.api,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BEJ Gestion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (!session.authentifie) {
            return LoginPage(authRepo: authRepo, session: session);
          }
          return AppShell(
            session: session,
            clientRepo: clientRepo,
            produitRepo: produitRepo,
            caisseRepo: caisseRepo,
            venteRepo: venteRepo,
            reparationRepo: reparationRepo,
            appareilRepo: appareilRepo,
            photoRepo: photoRepo,
            dashboardRepo: dashboardRepo,
            retourRepo: retourRepo,
            avoirRepo: avoirRepo,
            catalogueRepo: catalogueRepo,
            transfertRepo: transfertRepo,
            inventaireRepo: inventaireRepo,
            etiquetteRepo: etiquetteRepo,
            phase3Repo: phase3Repo,
            fneService: fneService,
            notifService: notifService,
            demoController: demoController,
            syncService: syncService,
            api: api,
          );
        },
      ),
    );
  }
}
