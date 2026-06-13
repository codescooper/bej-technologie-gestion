import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

import 'package:bej_gestion/src/data/powersync_db.dart';
import 'package:bej_gestion/src/data/bootstrap.dart';
import 'package:bej_gestion/src/data/ref_ids.dart';
import 'package:bej_gestion/src/data/api_client.dart';
import 'package:bej_gestion/src/data/sync_service.dart';
import 'package:bej_gestion/src/data/repositories/transfert_repository.dart';
import 'package:bej_gestion/src/data/repositories/produit_repository.dart';
import 'package:bej_gestion/src/data/repositories/caisse_repository.dart';
import 'package:bej_gestion/src/data/repositories/inventaire_repository.dart';
import 'package:bej_gestion/src/data/repositories/dashboard_repository.dart';

/// Finitions Phase 2+ : annulation de transfert, suggestions de
/// réapprovisionnement, inventaire physique (comptage -> ajustement) et
/// rapprochement de caisse consolidé.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late PowerSyncDatabase db;
  const uuid = Uuid();

  const chargeur = '0d000000-0000-4000-8000-000000000003';
  const cocody = RefIds.magasinCocody;
  const yop = RefIds.magasinYopougon;
  const user = RefIds.userResponsable;

  Future<int> enTransit(String mag) async {
    final rs = await db.getAll(
      'SELECT COALESCE(quantite_en_transit,0) AS q FROM stocks_magasin '
      'WHERE produit_id = ? AND magasin_id = ?',
      [chargeur, mag],
    );
    return rs.isEmpty ? 0 : ((rs.first['q'] as num?) ?? 0).toInt();
  }

  setUpAll(() async {
    db = await openDatabase();
    await seedLocalReferenceIfEmpty(db);
  });

  testWidgets('Annulation d\'un transfert en transit rend le stock', (tester) async {
    final transfertRepo = TransfertRepository(db);
    final produitRepo = ProduitRepository(db);

    final cocody0 = await produitRepo.quantiteDispo(chargeur, cocody);
    final transit0 = await enTransit(yop);

    final id = await transfertRepo.creer(
      produitId: chargeur,
      magasinSourceId: cocody,
      magasinDestId: yop,
      quantite: 2,
      utilisateurId: user,
    );
    expect(await produitRepo.quantiteDispo(chargeur, cocody), cocody0 - 2);
    expect(await enTransit(yop), transit0 + 2);

    await transfertRepo.annuler(transfertId: id, utilisateurId: user);

    // Le stock revient à la source, l'en-transit destinataire est rendu.
    expect(await produitRepo.quantiteDispo(chargeur, cocody), cocody0);
    expect(await enTransit(yop), transit0);
    final rs =
        await db.getAll('SELECT statut FROM transferts WHERE id = ?', [id]);
    expect(rs.first['statut'], 'annule');
    debugPrint('ANNULATION_OK id=$id');
  });

  testWidgets('Suggestions de réapprovisionnement', (tester) async {
    final produitRepo = ProduitRepository(db);

    // Force un manque à Cocody (seuil au-dessus du stock) et du stock à Yopougon.
    await db.execute(
        'UPDATE produits SET seuil_alerte = 999 WHERE id = ?', [chargeur]);
    final existYop = await db.getAll(
        'SELECT id FROM stocks_magasin WHERE produit_id = ? AND magasin_id = ?',
        [chargeur, yop]);
    if (existYop.isEmpty) {
      await db.execute(
        'INSERT INTO stocks_magasin(id, produit_id, magasin_id, '
        'quantite_disponible, quantite_en_transit) VALUES(?,?,?,?,?)',
        [uuid.v4(), chargeur, yop, 50, 0],
      );
    } else {
      await db.execute(
        'UPDATE stocks_magasin SET quantite_disponible = 50 '
        'WHERE produit_id = ? AND magasin_id = ?',
        [chargeur, yop],
      );
    }

    final suggestions = await produitRepo.suggestionsReappro(cocody);
    final s = suggestions.firstWhere((x) => x.produitId == chargeur);
    expect(s.seuil, 999);
    expect(s.sources.any((src) => src.magasinId == yop && src.disponible >= 1),
        isTrue);
    debugPrint('REAPPRO_OK ${suggestions.length} suggestion(s)');
  });

  testWidgets('Inventaire : comptage -> ajustement du stock', (tester) async {
    final inventaireRepo = InventaireRepository(db);
    final produitRepo = ProduitRepository(db);

    final theo = await produitRepo.quantiteDispo(chargeur, cocody);
    final cible = theo + 5;

    final invId =
        await inventaireRepo.demarrer(magasinId: cocody, utilisateurId: user);
    final lignes = await inventaireRepo.lignes(invId);
    expect(lignes, isNotEmpty);
    final ligne = lignes.firstWhere((l) => l.produitId == chargeur);
    expect(ligne.theorique, theo);

    await inventaireRepo.saisir(ligneId: ligne.id, comptee: cible);
    final nb =
        await inventaireRepo.valider(inventaireId: invId, utilisateurId: user);
    expect(nb, greaterThanOrEqualTo(1));

    // Le stock disponible est aligné sur le comptage.
    expect(await produitRepo.quantiteDispo(chargeur, cocody), cible);
    // Un mouvement « inventaire » a été tracé.
    final mv = await db.getAll(
      "SELECT count(*) AS c FROM mouvements_stock "
      "WHERE produit_id = ? AND magasin_id = ? AND type = 'inventaire'",
      [chargeur, cocody],
    );
    expect(((mv.first['c'] as num?) ?? 0).toInt(), greaterThanOrEqualTo(1));
    // L'inventaire est validé.
    final st = await db
        .getAll('SELECT statut FROM inventaires WHERE id = ?', [invId]);
    expect(st.first['statut'], 'valide');
    debugPrint('INVENTAIRE_OK inv=$invId ajustes=$nb');
  });

  testWidgets('Rapprochement de caisse consolidé', (tester) async {
    final caisseRepo = CaisseRepository(db);

    var caisse = await caisseRepo.caisseOuverte(cocody);
    caisse ??= await () async {
      await caisseRepo.ouvrir(
          magasinId: cocody, utilisateurId: user, fondInitial: 10000);
      return caisseRepo.caisseOuverte(cocody);
    }();
    // Clôture avec un écart volontaire (cash réel < théorique).
    await caisseRepo.cloturer(
        caisseId: caisse!.id, cashReel: 9500, mobileReel: 0);

    final rapport = await DashboardRepository(db).rapprochementCaisse();
    final ligneCocody = rapport.firstWhere((r) => r.magasinId == cocody);
    expect(ligneCocody.nbCloturees, greaterThanOrEqualTo(1));
    expect(ligneCocody.dernierEcart, isNotNull);
    debugPrint('RAPPROCHEMENT_OK cocody=${ligneCocody.nbCloturees} '
        'cloture(s) ecart=${ligneCocody.ecartCumule}');
  });

  testWidgets('Synchronisation des finitions vers le serveur', (tester) async {
    final api = ApiClient('http://localhost:8080');
    final sync = SyncService(db, api);
    await sync.push();
    expect(await sync.pendingCount(), 0);
    debugPrint('SYNC_FINITIONS_OK');
  });
}
