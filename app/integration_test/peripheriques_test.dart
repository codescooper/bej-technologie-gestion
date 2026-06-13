import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:powersync/powersync.dart';

import 'package:bej_gestion/src/data/powersync_db.dart';
import 'package:bej_gestion/src/data/bootstrap.dart';
import 'package:bej_gestion/src/data/ref_ids.dart';
import 'package:bej_gestion/src/data/repositories/produit_repository.dart';
import 'package:bej_gestion/src/util/ticket_pdf.dart';

/// Périphériques boutique (§8) : scan code-barres + ticket imprimable.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late PowerSyncDatabase db;

  setUpAll(() async {
    db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
  });

  testWidgets('Scan : code-barres connu -> produit, inconnu -> null',
      (tester) async {
    final repo = ProduitRepository(db);
    final ps =
        await repo.findByCodeBarres(RefIds.magasinCocody, '6001230000035');
    expect(ps, isNotNull);
    expect(ps!.produit.nom, contains('Chargeur'));
    expect(
        await repo.findByCodeBarres(RefIds.magasinCocody, '0000000000000'),
        isNull);
    debugPrint('SCAN_OK ${ps.produit.nom}');
  });

  testWidgets('Ticket : génère un PDF non vide', (tester) async {
    final repo = ProduitRepository(db);
    final ps =
        await repo.findByCodeBarres(RefIds.magasinCocody, '6001230000035');
    final pu = ps!.produit.prixVente;
    final t = TicketData(
      magasin: 'BEJ Cocody',
      ref: 'abcd1234-0000-0000-0000-000000000000',
      date: DateTime(2026, 6, 9, 14, 30),
      client: 'Client Démo',
      lignes: [TicketLigne(ps.produit.nom, 2, pu, pu * 2)],
      sousTotal: pu * 2,
      remise: 0,
      jetons: 0,
      avoir: 0,
      total: pu * 2,
      paiements: [
        (methode: 'cash', montant: pu),
        (methode: 'wave', montant: pu),
      ],
      jetonsGagnes: (pu * 2) ~/ 100,
    );
    final pdf = await construireTicketPdf(t);
    expect(pdf.length, greaterThan(800));
    debugPrint('TICKET_OK ${pdf.length} octets');
  });
}
