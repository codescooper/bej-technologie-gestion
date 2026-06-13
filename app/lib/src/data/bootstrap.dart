import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';
import 'ref_ids.dart';

/// Sème le référentiel dans la base PowerSync locale si elle est vide.
///
/// Substitut au service de streaming PowerSync (absent en Phase 0/1) : sans lui,
/// la base locale ne reçoit pas les données serveur. On insère donc le même
/// référentiel (UUID fixes de [RefIds]) ; il remonte ensuite vers PostgreSQL via
/// la file CRUD (upserts ON CONFLICT id, donc convergence sans doublon).
Future<void> seedLocalReferenceIfEmpty(PowerSyncDatabase db) async {
  // Catalogues réparation (indépendants : s'appliquent aussi aux bases déjà
  // initialisées avant l'ajout de cette fonctionnalité).
  await _seedCataloguesIfEmpty(db);
  // Backfill des codes-barres pour les bases déjà installées (scan comptoir §8).
  await _seedCodeBarresIfMissing(db);

  final rs = await db.getAll('SELECT count(*) AS c FROM magasins');
  final count = (rs.first['c'] as num).toInt();
  if (count > 0) return; // référentiel déjà semé

  final now = DateTime.now().toUtc().toIso8601String();

  await db.writeTransaction((tx) async {
    // Rôles
    const roles = [
      [RefIds.roleAdmin, 'admin', 'Administrateur'],
      [RefIds.roleResponsable, 'responsable', 'Responsable magasin'],
      [RefIds.roleCaissier, 'caissier', 'Caissier'],
      [RefIds.roleTechnicien, 'technicien', 'Technicien'],
    ];
    for (final r in roles) {
      await tx.execute(
        'INSERT INTO roles(id, code, libelle) VALUES(?,?,?)',
        [r[0], r[1], r[2]],
      );
    }

    // Magasins
    for (final m in magasinsRef) {
      await tx.execute(
        'INSERT INTO magasins(id, nom, actif, date_creation) VALUES(?,?,?,?)',
        [m.id, m.nom, 1, now],
      );
    }

    // Utilisateurs des 4 rôles (§6) — PIN HACHÉ (PBKDF2-HMAC-SHA256, sel = id ;
    // cf. util/pin_hash.dart). Les PIN restent 1111/2222/3333/4444, mais seule
    // leur empreinte est stockée. [id, magasin_id, role_id, nom, login, empreinte]
    final users = [
      [RefIds.userAdmin, null, RefIds.roleAdmin, 'Administrateur', 'admin',
        'e81898846706852726b5bf4d66574b80928366365debd255d3cc1b279e9064f0'],
      [RefIds.userAwaCaissiere, RefIds.magasinCocody, RefIds.roleCaissier,
        'Awa (caissière Cocody)', 'awa',
        '605d87c7bcda7bd02fde79de257aa93432e049f546e764a369ffee0b5394b13c'],
      [RefIds.userResponsable, RefIds.magasinCocody, RefIds.roleResponsable,
        'Ben (responsable Cocody)', 'ben',
        '72fb4d8904996702a7c242a9f52a55a16645d5dd208db9c04c3230ca8b7f811a'],
      [RefIds.userTechnicien, RefIds.magasinCocody, RefIds.roleTechnicien,
        'Koffi (technicien Cocody)', 'koffi',
        'bcd31a2c483b11414a37c3b9e1ffa1480b68edc7cd9dafc90de0788df6b1a1db'],
    ];
    for (final u in users) {
      await tx.execute(
        'INSERT INTO utilisateurs(id, magasin_id, role_id, nom, login, '
        'mot_de_passe_hash, actif, date_creation) VALUES(?,?,?,?,?,?,?,?)',
        [u[0], u[1], u[2], u[3], u[4], u[5], 1, now],
      );
    }

    // Produits + stock initial Cocody :
    // [id, nom, categorie, achat, vente, seuil, stockId, qte, code_barres]
    const produits = [
      ['0d000000-0000-4000-8000-000000000001', 'Écran iPhone 11', 'Pièce', 35000, 55000, 2, '0f000000-0000-4000-8000-000000000001', 3, '6001230000011'],
      ['0d000000-0000-4000-8000-000000000002', 'Batterie Samsung A10', 'Pièce', 8000, 15000, 3, '0f000000-0000-4000-8000-000000000002', 5, '6001230000028'],
      ['0d000000-0000-4000-8000-000000000003', 'Chargeur USB-C 20W', 'Accessoire', 2500, 6000, 5, '0f000000-0000-4000-8000-000000000003', 12, '6001230000035'],
      ['0d000000-0000-4000-8000-000000000004', 'Coque transparente', 'Accessoire', 800, 3000, 10, '0f000000-0000-4000-8000-000000000004', 20, '6001230000042'],
      ['0d000000-0000-4000-8000-000000000005', 'Verre trempé', 'Accessoire', 500, 2500, 10, '0f000000-0000-4000-8000-000000000005', 25, '6001230000059'],
    ];
    for (final p in produits) {
      await tx.execute(
        'INSERT INTO produits(id, nom, categorie, code_barres, prix_achat, prix_vente, seuil_alerte, actif, date_creation) '
        'VALUES(?,?,?,?,?,?,?,?,?)',
        [p[0], p[1], p[2], p[8], p[3], p[4], p[5], 1, now],
      );
      await tx.execute(
        'INSERT INTO stocks_magasin(id, produit_id, magasin_id, quantite_disponible, quantite_en_transit) '
        'VALUES(?,?,?,?,?)',
        [p[6], p[0], RefIds.magasinCocody, p[7], 0],
      );
    }
  });
}

/// Pré-remplit les catalogues recherchables (modèles d'appareils, pannes) s'ils
/// sont vides. Ces listes s'enrichissent ensuite à l'usage.
Future<void> _seedCataloguesIfEmpty(PowerSyncDatabase db) async {
  const uuid = Uuid();
  final now = DateTime.now().toUtc().toIso8601String();

  final p = (await db.getAll('SELECT count(*) AS c FROM pannes')).first['c'];
  if (((p as num?) ?? 0).toInt() == 0) {
    const pannes = [
      'Écran cassé',
      'Vitre fissurée',
      'Batterie défectueuse',
      'Ne s\'allume pas',
      'Problème de charge',
      'Connecteur de charge HS',
      'Haut-parleur muet',
      'Micro défectueux',
      'Caméra floue',
      'Bouton power HS',
      'Tactile ne répond pas',
      'Désoxydation (eau)',
      'Mise à jour logicielle',
      'Déblocage / réinitialisation',
    ];
    await db.writeTransaction((tx) async {
      for (final l in pannes) {
        await tx.execute(
          'INSERT INTO pannes(id, libelle, date_creation) VALUES(?,?,?)',
          [uuid.v4(), l, now],
        );
      }
    });
  }

  final m = (await db.getAll('SELECT count(*) AS c FROM modeles_appareil'))
      .first['c'];
  if (((m as num?) ?? 0).toInt() == 0) {
    const modeles = [
      ['Apple', 'iPhone 7', 'smartphone'],
      ['Apple', 'iPhone 8', 'smartphone'],
      ['Apple', 'iPhone X', 'smartphone'],
      ['Apple', 'iPhone 11', 'smartphone'],
      ['Apple', 'iPhone 12', 'smartphone'],
      ['Apple', 'iPhone 13', 'smartphone'],
      ['Samsung', 'Galaxy A04', 'smartphone'],
      ['Samsung', 'Galaxy A10', 'smartphone'],
      ['Samsung', 'Galaxy A20', 'smartphone'],
      ['Samsung', 'Galaxy A50', 'smartphone'],
      ['Samsung', 'Galaxy S21', 'smartphone'],
      ['Tecno', 'Spark 8', 'smartphone'],
      ['Tecno', 'Camon 19', 'smartphone'],
      ['Infinix', 'Hot 11', 'smartphone'],
      ['Infinix', 'Note 12', 'smartphone'],
      ['Itel', 'A56', 'smartphone'],
      ['Itel', 'P40', 'smartphone'],
      ['Xiaomi', 'Redmi 9A', 'smartphone'],
      ['Xiaomi', 'Redmi Note 11', 'smartphone'],
      ['Oppo', 'A16', 'smartphone'],
      ['Huawei', 'Y9', 'smartphone'],
    ];
    await db.writeTransaction((tx) async {
      for (final e in modeles) {
        await tx.execute(
          'INSERT INTO modeles_appareil(id, marque, modele, type, date_creation) '
          'VALUES(?,?,?,?,?)',
          [uuid.v4(), e[0], e[1], e[2], now],
        );
      }
    });
  }
}

/// Affecte un code-barres aux produits de référence qui n'en ont pas encore
/// (scan comptoir §8). Idempotent : ne touche que les lignes au code vide, donc
/// sûr pour les bases déjà installées comme pour les neuves.
Future<void> _seedCodeBarresIfMissing(PowerSyncDatabase db) async {
  const codes = <String, String>{
    '0d000000-0000-4000-8000-000000000001': '6001230000011',
    '0d000000-0000-4000-8000-000000000002': '6001230000028',
    '0d000000-0000-4000-8000-000000000003': '6001230000035',
    '0d000000-0000-4000-8000-000000000004': '6001230000042',
    '0d000000-0000-4000-8000-000000000005': '6001230000059',
  };
  await db.writeTransaction((tx) async {
    for (final e in codes.entries) {
      await tx.execute(
        "UPDATE produits SET code_barres = ? "
        "WHERE id = ? AND (code_barres IS NULL OR code_barres = '')",
        [e.value, e.key],
      );
    }
  });
}
