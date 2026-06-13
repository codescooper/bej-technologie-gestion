import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:bej_gestion/src/data/powersync_db.dart';
import 'package:bej_gestion/src/data/bootstrap.dart';
import 'package:bej_gestion/src/data/ref_ids.dart';
import 'package:bej_gestion/src/data/repositories/caisse_repository.dart';
import 'package:bej_gestion/src/data/repositories/vente_repository.dart';
import 'package:bej_gestion/src/models/produit.dart';
import 'package:bej_gestion/src/models/vente.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('diag totaux + cloture', (tester) async {
    final db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
    final caisseRepo = CaisseRepository(db);
    final venteRepo = VenteRepository(db);
    const magasin = RefIds.magasinCocody;
    const user = RefIds.userAwaCaissiere;

    var c = await caisseRepo.caisseOuverte(magasin);
    if (c == null) {
      await caisseRepo.ouvrir(
          magasinId: magasin, utilisateurId: user, fondInitial: 5000);
      c = await caisseRepo.caisseOuverte(magasin);
    }

    final cat = await db.getAll('SELECT * FROM produits LIMIT 1');
    await venteRepo.enregistrerVente(
      magasinId: magasin,
      caisseId: c!.id,
      utilisateurId: user,
      lignes: [CartLine(Produit.fromRow(cat.first), quantite: 1)],
      paiements: [PaiementInput('cash', 6000)],
    );

    // Si l'une de ces deux lignes lève, le framework imprimera l'exception.
    final t = await caisseRepo.totauxTheoriques(c.id);
    debugPrint('DIAG_TOTAUX cash=${t.cash} mobile=${t.mobile}');

    final closed = await caisseRepo.cloturer(
        caisseId: c.id, cashReel: 11000, mobileReel: 0);
    expect(closed.statut, 'cloturee');
    debugPrint('DIAG_CLOTURE_OK ecart=${closed.ecart}');
  });
}
