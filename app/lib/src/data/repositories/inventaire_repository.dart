import 'dart:convert';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';
import '../../models/inventaire.dart';

/// Inventaire physique (Finitions Phase 2+). On fige le stock théorique au
/// démarrage, on saisit le comptage produit par produit, puis la validation
/// aligne le stock disponible sur le comptage et trace chaque écart.
class InventaireRepository {
  final PowerSyncDatabase db;
  final _uuid = const Uuid();
  InventaireRepository(this.db);

  /// Inventaires d'un magasin (les plus récents d'abord).
  Stream<List<Inventaire>> watch(String magasinId) {
    return db
        .watch(
            'SELECT * FROM inventaires WHERE magasin_id = ? '
            'ORDER BY date_creation DESC',
            parameters: [magasinId])
        .map((rs) => rs.map((r) => Inventaire.fromRow(r)).toList());
  }

  /// Démarre un inventaire : snapshot des produits actifs du magasin avec leur
  /// stock disponible courant comme quantité théorique (comptage à saisir).
  Future<String> demarrer({
    required String magasinId,
    required String utilisateurId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final produits = await db.getAll(
      'SELECT p.id AS pid, COALESCE(s.quantite_disponible,0) AS q '
      'FROM produits p '
      'LEFT JOIN stocks_magasin s '
      '  ON s.produit_id = p.id AND s.magasin_id = ? '
      'WHERE COALESCE(p.actif,1) = 1 '
      'ORDER BY p.nom',
      [magasinId],
    );
    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO inventaires(id, magasin_id, utilisateur_id, statut, '
        'date_creation) VALUES(?,?,?,?,?)',
        [id, magasinId, utilisateurId, 'en_cours', now],
      );
      for (final p in produits) {
        final q = ((p['q'] as num?) ?? 0).toInt();
        await tx.execute(
          'INSERT INTO lignes_inventaire(id, inventaire_id, produit_id, '
          'quantite_theorique, quantite_comptee, ecart) VALUES(?,?,?,?,?,?)',
          [_uuid.v4(), id, p['pid'], q, null, 0],
        );
      }
    });
    return id;
  }

  /// Lignes d'un inventaire avec le nom du produit (pour la saisie / lecture).
  Future<List<LigneInventaire>> lignes(String inventaireId) async {
    final rs = await db.getAll(
      'SELECT li.*, p.nom AS produit_nom '
      'FROM lignes_inventaire li '
      'JOIN produits p ON p.id = li.produit_id '
      'WHERE li.inventaire_id = ? '
      'ORDER BY p.nom',
      [inventaireId],
    );
    return rs.map((r) => LigneInventaire.fromRow(r)).toList();
  }

  /// Enregistre le comptage d'une ligne et recalcule l'écart (compté - théorique).
  Future<void> saisir({required String ligneId, required int comptee}) async {
    final rs = await db.getAll(
      'SELECT quantite_theorique AS t FROM lignes_inventaire WHERE id = ?',
      [ligneId],
    );
    if (rs.isEmpty) return;
    final theo = ((rs.first['t'] as num?) ?? 0).toInt();
    await db.execute(
      'UPDATE lignes_inventaire SET quantite_comptee = ?, ecart = ? WHERE id = ?',
      [comptee, comptee - theo, ligneId],
    );
  }

  /// Valide l'inventaire : pour chaque ligne comptée avec un écart, aligne le
  /// stock disponible sur le comptage, trace un MouvementStock « inventaire »
  /// et journalise. L'inventaire passe à « validé ».
  Future<int> valider({
    required String inventaireId,
    required String utilisateurId,
  }) async {
    final entete = await db.getAll(
      'SELECT magasin_id FROM inventaires WHERE id = ?',
      [inventaireId],
    );
    if (entete.isEmpty) return 0;
    final magasinId = entete.first['magasin_id'] as String;

    final lignesRows = await db.getAll(
      'SELECT produit_id AS pid, quantite_comptee AS c, ecart AS e '
      'FROM lignes_inventaire '
      'WHERE inventaire_id = ? AND quantite_comptee IS NOT NULL',
      [inventaireId],
    );
    final now = DateTime.now().toUtc().toIso8601String();
    var nbAjustes = 0;

    await db.writeTransaction((tx) async {
      for (final l in lignesRows) {
        final e = ((l['e'] as num?) ?? 0).toInt();
        if (e == 0) continue;
        final c = ((l['c'] as num?) ?? 0).toInt();
        final pid = l['pid'] as String;
        nbAjustes++;
        // Aligne le stock disponible sur le comptage (crée la ligne si absente).
        final exist = await tx.getAll(
          'SELECT id FROM stocks_magasin WHERE produit_id = ? AND magasin_id = ?',
          [pid, magasinId],
        );
        if (exist.isEmpty) {
          await tx.execute(
            'INSERT INTO stocks_magasin(id, produit_id, magasin_id, '
            'quantite_disponible, quantite_en_transit) VALUES(?,?,?,?,?)',
            [_uuid.v4(), pid, magasinId, c, 0],
          );
        } else {
          await tx.execute(
            'UPDATE stocks_magasin SET quantite_disponible = ? '
            'WHERE produit_id = ? AND magasin_id = ?',
            [c, pid, magasinId],
          );
        }
        await tx.execute(
          'INSERT INTO mouvements_stock(id, produit_id, magasin_id, type, '
          'quantite, motif, utilisateur_id, date) VALUES(?,?,?,?,?,?,?,?)',
          [_uuid.v4(), pid, magasinId, 'inventaire', e,
            'Inventaire (écart ${e > 0 ? '+$e' : '$e'})', utilisateurId, now],
        );
      }
      await tx.execute(
        'UPDATE inventaires SET statut = ?, date_validation = ? WHERE id = ?',
        ['valide', now, inventaireId],
      );
      await tx.execute(
        'INSERT INTO journal_audit(id, utilisateur_id, magasin_id, action, '
        'entite, entite_id, details, date) VALUES(?,?,?,?,?,?,?,?)',
        [
          _uuid.v4(), utilisateurId, magasinId, 'inventaire_valide',
          'inventaire', inventaireId,
          // details est de type jsonb côté serveur : on écrit du JSON valide.
          jsonEncode({'produits_ajustes': nbAjustes}), now,
        ],
      );
    });
    return nbAjustes;
  }
}
