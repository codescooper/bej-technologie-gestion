import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:powersync/powersync.dart';

import 'package:bej_gestion/src/data/powersync_db.dart';
import 'package:bej_gestion/src/data/bootstrap.dart';
import 'package:bej_gestion/src/data/ref_ids.dart';
import 'package:bej_gestion/src/data/api_client.dart';
import 'package:bej_gestion/src/data/sync_service.dart';
import 'package:bej_gestion/src/data/repositories/client_repository.dart';
import 'package:bej_gestion/src/data/repositories/appareil_repository.dart';
import 'package:bej_gestion/src/data/repositories/reparation_repository.dart';
import 'package:bej_gestion/src/data/repositories/produit_repository.dart';
import 'package:bej_gestion/src/data/repositories/etiquette_qr_repository.dart';

/// Tout-QR : préparer un lot de stickers réparation, en affecter un à un appareil,
/// résoudre le code vers l'appareil (→ fiche réparation), et résoudre un QR vente
/// vers son produit (→ vente). Code inconnu → null. Assertions RELATIVES (la base
/// OPFS persiste entre exécutions).
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

  testWidgets('QR : lot réparation, affectation, résolution, et QR produit',
      (tester) async {
    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final mag = RefIds.magasinCocody;
    final etiq = EtiquetteQrRepository(db);
    final prod = ProduitRepository(db);
    final clientRepo = ClientRepository(db);
    final appareilRepo = AppareilRepository(db);
    final reparationRepo = ReparationRepository(db);

    // 1) Préparer un lot de 5 stickers → +5 libres, codes brandés BEJ-R-.
    final avant = await etiq.comptes(mag);
    final codes = await etiq.preparerLotReparation(magasinId: mag, nombre: 5);
    expect(codes.length, 5);
    expect(codes.every((c) => c.startsWith('BEJ-R-')), isTrue);
    final apres = await etiq.comptes(mag);
    expect(apres.libres, avant.libres + 5);

    // Un code libre résout en « etiquetteLibre » tant qu'il n'est pas affecté.
    final libre = codes.first;
    final rLibre = await etiq.resoudre(libre);
    expect(rLibre?.cible, CibleQr.etiquetteLibre);

    // 2) Affecter à un appareil → résoudre = appareil.
    final c = await clientRepo.create(
        nom: 'QR Client', telephone: '07${stamp.substring(stamp.length - 8)}');
    final app = await appareilRepo.creer(
      clientId: c.id,
      type: 'téléphone',
      marque: 'Apple',
      modele: 'iPhone 12',
      imei: 'QR$stamp',
    );
    await etiq.affecterAppareil(code: libre, appareilId: app.id, magasinId: mag);
    final rApp = await etiq.resoudre(libre);
    expect(rApp?.cible, CibleQr.appareil);
    expect(rApp?.appareilId, app.id);

    // codeParAppareil renvoie le sticker lié (affichage lecture seule à la réutilisation).
    expect(await etiq.codeParAppareil(app.id), libre);

    // L'affectation a consommé une étiquette : libres -1, utilisées +1.
    final apres2 = await etiq.comptes(mag);
    expect(apres2.libres, apres.libres - 1);
    expect(apres2.utilisees, apres.utilisees + 1);

    // Ré-affecter le même code au même appareil est idempotent.
    await etiq.affecterAppareil(code: libre, appareilId: app.id, magasinId: mag);
    // L'affecter à un AUTRE appareil échoue (évite un mauvais lien).
    final app2 = await appareilRepo.creer(
        clientId: c.id, type: 'téléphone', imei: 'QR2$stamp');
    await expectLater(
      etiq.affecterAppareil(code: libre, appareilId: app2.id, magasinId: mag),
      throwsStateError,
    );

    // Lookup utilisé par le routing du scan : la réparation de l'appareil.
    await reparationRepo.creer(
      appareilId: app.id,
      magasinId: mag,
      technicienId: RefIds.userTechnicien,
      probleme: 'Écran cassé',
      devis: 15000,
    );
    final reps = await reparationRepo.parAppareil(app.id);
    expect(reps, isNotEmpty);
    expect(reps.first.reparation.appareilId, app.id);

    // 3) QR produit : créer un produit, générer son QR, résoudre vers le produit.
    await prod.creerProduit(
      nom: 'Coque QR $stamp',
      prixAchat: 500,
      prixVente: 1500,
      magasinId: mag,
      stockInitial: 3,
    );
    final cat = await prod.watchCatalogue(mag).first;
    final pid =
        cat.firstWhere((p) => p.produit.nom == 'Coque QR $stamp').produit.id;
    final nGeneres = await prod.genererQrCodesManquants([pid]);
    expect(nGeneres, 1);
    final rProd = await etiq.resoudre('BEJ-P-$pid');
    expect(rProd?.cible, CibleQr.produit);
    expect(rProd?.produitId, pid);

    // findById renvoie le produit + stock (routage vente du scan universel).
    final ps = await prod.findById(mag, pid);
    expect(ps, isNotNull);
    expect(ps!.produit.id, pid);

    // 4) Code inconnu → null.
    expect(await etiq.resoudre('XX-NOPE-$stamp'), isNull);

    // 5) SYNC serveur : pousse les écritures QR (etiquettes_qr +
    // appareils.qr_code + produits.qr_code). pendingCount→0 prouve que le
    // backend générique accepte la nouvelle table `etiquettes_qr`.
    expect(await sync.pendingCount(), greaterThan(0));
    await sync.push();
    expect(await sync.pendingCount(), 0);

    debugPrint('QR_OK lot=${codes.length} libres=${apres2.libres} '
        'appareil=${rApp?.appareilId == app.id} produit=${rProd?.produitId == pid}');
    debugPrint('QR_SYNC_MARKER code=$libre appareil=${app.id} produit=$pid');
  });
}
