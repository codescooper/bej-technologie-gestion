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

/// Suivi par appareil : un client qui revient avec le même appareil → ses
/// réparations sont rattachées au MÊME appareil (pas de doublon), et comptées.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late PowerSyncDatabase db;

  setUpAll(() async {
    db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
  });

  testWidgets('Deux passages sur le même appareil sont reliés et comptés',
      (tester) async {
    final stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final clientRepo = ClientRepository(db);
    final appareilRepo = AppareilRepository(db);
    final reparationRepo = ReparationRepository(db);

    final c = await clientRepo.create(
        nom: 'Suivi Appareil', telephone: '07${stamp.substring(stamp.length - 8)}');
    final app = await appareilRepo.creer(
      clientId: c.id,
      type: 'téléphone',
      marque: 'Apple',
      modele: 'iPhone 11',
      imei: 'SUIVI$stamp',
    );

    // 1er passage : écran cassé.
    await reparationRepo.creer(
      appareilId: app.id,
      magasinId: RefIds.magasinCocody,
      technicienId: RefIds.userTechnicien,
      probleme: 'Écran cassé',
      devis: 15000,
    );
    // 2e passage (le client revient) : on RÉUTILISE le même appareil.
    await reparationRepo.creer(
      appareilId: app.id,
      magasinId: RefIds.magasinCocody,
      technicienId: RefIds.userTechnicien,
      probleme: 'Batterie défectueuse',
      devis: 8000,
    );
    // 3e passage : à nouveau l'écran → panne la plus fréquente du modèle.
    await reparationRepo.creer(
      appareilId: app.id,
      magasinId: RefIds.magasinCocody,
      technicienId: RefIds.userTechnicien,
      probleme: 'Écran cassé',
      devis: 15000,
    );

    // L'appareil est bien connu du client (présenté à la sélection).
    final apps = await appareilRepo.parClient(c.id);
    expect(apps.any((a) => a.id == app.id), isTrue);
    expect(apps.where((a) => a.imei == 'SUIVI$stamp').length, 1,
        reason: 'pas de doublon d\'appareil');

    // Les 2 réparations pointent vers le MÊME appareil → compteur = 2.
    final reps = await reparationRepo.parClient(c.id);
    final n = reps.where((r) => r.reparation.appareilId == app.id).length;
    expect(n, 3);

    // Historique par appareil = les 3 passages.
    final histo = await reparationRepo.parAppareil(app.id);
    expect(histo.length, 3);

    // Garantie : la même panne récente est détectée ; une panne inconnue ne l'est pas.
    final garantie = await reparationRepo.garantieRecente(
        appareilId: app.id, probleme: 'Écran cassé');
    expect(garantie, isNotNull);
    expect(
        await reparationRepo.garantieRecente(
            appareilId: app.id, probleme: 'Panne jamais vue ici'),
        isNull);

    // Pannes fréquentes pour ce modèle : l'écran (2 occurrences) en tête.
    final freq = await reparationRepo.pannesFrequentes(modele: 'iPhone 11');
    expect(freq, isNotEmpty);
    expect(freq.first, 'Écran cassé');

    // Devis auto : médiane du total des réparations similaires
    // (iPhone 11 + Écran cassé = 15000, au moins 2 cas, sans repli).
    final devis = await reparationRepo.devisSuggere(
        modele: 'iPhone 11', probleme: 'Écran cassé');
    expect(devis, isNotNull);
    expect(devis!.prix, 15000);
    expect(devis.nbCas, greaterThanOrEqualTo(2));
    expect(devis.elargi, isFalse);

    debugPrint('SUIVI_APPAREIL_OK reparations=$n historique=${histo.length} '
        'garantie=${garantie != null} topPanne=${freq.first}');
  });
}
