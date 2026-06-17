import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';
import '../../models/produit.dart';

/// Catalogue produits + stock local par magasin (§2.4 / §5.7).
class ProduitRepository {
  final PowerSyncDatabase db;
  final _uuid = const Uuid();

  ProduitRepository(this.db);

  /// Catalogue du magasin courant avec la quantité disponible (jointure stock).
  Stream<List<ProduitStock>> watchCatalogue(String magasinId) {
    return db.watch(
      'SELECT p.*, COALESCE(s.quantite_disponible, 0) AS qte '
      'FROM produits p '
      'LEFT JOIN stocks_magasin s '
      '  ON s.produit_id = p.id AND s.magasin_id = ? '
      "WHERE COALESCE(p.actif, 1) = 1 "
      'ORDER BY p.nom',
      parameters: [magasinId],
    ).map((rs) => rs.map((r) => ProduitStock.fromRow(r)).toList());
  }

  /// Quantité disponible d'un produit dans un magasin (lecture ponctuelle).
  Future<int> quantiteDispo(String produitId, String magasinId) async {
    final rs = await db.getAll(
      'SELECT quantite_disponible AS q FROM stocks_magasin '
      'WHERE produit_id = ? AND magasin_id = ?',
      [produitId, magasinId],
    );
    if (rs.isEmpty) return 0;
    return ((rs.first['q'] as num?) ?? 0).toInt();
  }

  /// Recherche un produit actif par code-barres (scan comptoir, §8), avec sa
  /// quantité disponible dans le magasin. Renvoie null si introuvable.
  Future<ProduitStock?> findByCodeBarres(String magasinId, String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    final rs = await db.getAll(
      'SELECT p.*, COALESCE(s.quantite_disponible, 0) AS qte '
      'FROM produits p '
      'LEFT JOIN stocks_magasin s '
      '  ON s.produit_id = p.id AND s.magasin_id = ? '
      'WHERE p.code_barres = ? AND COALESCE(p.actif, 1) = 1 '
      'LIMIT 1',
      [magasinId, c],
    );
    return rs.isEmpty ? null : ProduitStock.fromRow(rs.first);
  }

  /// Recherche un produit actif par id, avec sa quantité disponible dans le
  /// magasin (routage du scan universel QR → vente). Null si introuvable.
  Future<ProduitStock?> findById(String magasinId, String id) async {
    final c = id.trim();
    if (c.isEmpty) return null;
    final rs = await db.getAll(
      'SELECT p.*, COALESCE(s.quantite_disponible, 0) AS qte '
      'FROM produits p '
      'LEFT JOIN stocks_magasin s '
      '  ON s.produit_id = p.id AND s.magasin_id = ? '
      'WHERE p.id = ? AND COALESCE(p.actif, 1) = 1 '
      'LIMIT 1',
      [magasinId, c],
    );
    return rs.isEmpty ? null : ProduitStock.fromRow(rs.first);
  }

  /// Génère un QR vente `BEJ-P-<id>` pour les produits sélectionnés qui n'en ont
  /// pas encore (colonne `qr_code` vide). Idempotent. Renvoie le nombre de QR
  /// nouvellement générés (comptés avant l'UPDATE — `execute` ne renvoie pas le
  /// nombre de lignes modifiées).
  Future<int> genererQrCodesManquants(List<String> produitIds) async {
    final ids = produitIds.where((e) => e.trim().isNotEmpty).toList();
    if (ids.isEmpty) return 0;
    final ph = List.filled(ids.length, '?').join(',');
    final manquants = await db.getAll(
      "SELECT count(*) AS c FROM produits "
      "WHERE id IN ($ph) AND (qr_code IS NULL OR qr_code = '')",
      ids,
    );
    final n = ((manquants.first['c'] as num?) ?? 0).toInt();
    if (n == 0) return 0;
    await db.writeTransaction((tx) async {
      for (final id in ids) {
        await tx.execute(
          "UPDATE produits SET qr_code = 'BEJ-P-' || id "
          "WHERE id = ? AND (qr_code IS NULL OR qr_code = '')",
          [id],
        );
      }
    });
    return n;
  }

  /// Données d'impression des étiquettes QR vente (nom, prix, code-barres en
  /// clair, payload QR généré à la volée si absent) pour les produits choisis.
  Future<List<Map<String, dynamic>>> qrLabelsVente(
      List<String> produitIds) async {
    final ids = produitIds.where((e) => e.trim().isNotEmpty).toList();
    if (ids.isEmpty) return const [];
    final ph = List.filled(ids.length, '?').join(',');
    return db.getAll(
      'SELECT id, nom, prix_vente, code_barres, '
      "COALESCE(NULLIF(qr_code,''), 'BEJ-P-' || id) AS payload "
      'FROM produits WHERE id IN ($ph)',
      ids,
    );
  }

  /// Crée un produit et sa ligne de stock dans le magasin courant.
  Future<void> creerProduit({
    required String nom,
    String? categorie,
    required num prixAchat,
    required num prixVente,
    int seuilAlerte = 0,
    required String magasinId,
    int stockInitial = 0,
  }) async {
    final pid = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO produits(id, nom, categorie, prix_achat, prix_vente, '
        'seuil_alerte, actif, date_creation) VALUES(?,?,?,?,?,?,?,?)',
        [pid, nom, categorie, prixAchat, prixVente, seuilAlerte, 1, now],
      );
      await tx.execute(
        'INSERT INTO stocks_magasin(id, produit_id, magasin_id, '
        'quantite_disponible, quantite_en_transit) VALUES(?,?,?,?,?)',
        [_uuid.v4(), pid, magasinId, stockInitial, 0],
      );
    });
  }

  /// Ajustement de stock avec motif (§5.7) — crée un MouvementStock et met à
  /// jour la quantité. delta signé (+ entrée / - sortie).
  Future<void> ajusterStock({
    required String produitId,
    required String magasinId,
    required int delta,
    required String motif,
    required String utilisateurId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO mouvements_stock(id, produit_id, magasin_id, type, '
        'quantite, motif, utilisateur_id, date) VALUES(?,?,?,?,?,?,?,?)',
        [
          _uuid.v4(),
          produitId,
          magasinId,
          delta >= 0 ? 'entree' : 'ajustement',
          delta,
          motif,
          utilisateurId,
          now,
        ],
      );
      await tx.execute(
        'UPDATE stocks_magasin SET quantite_disponible = quantite_disponible + ? '
        'WHERE produit_id = ? AND magasin_id = ?',
        [delta, produitId, magasinId],
      );
    });
  }

  /// Suggestions de réapprovisionnement (Finitions Phase 2+) : produits du
  /// magasin sous leur seuil d'alerte, avec la liste des magasins capables de
  /// fournir (stock disponible > 0), du plus fourni au moins fourni.
  Future<List<ReapproSuggestion>> suggestionsReappro(String magasinId) async {
    final manquants = await db.getAll(
      'SELECT p.id AS pid, p.nom AS nom, p.seuil_alerte AS seuil, '
      '       COALESCE(s.quantite_disponible,0) AS dispo '
      'FROM produits p '
      'JOIN stocks_magasin s ON s.produit_id = p.id AND s.magasin_id = ? '
      'WHERE COALESCE(p.actif,1) = 1 AND p.seuil_alerte > 0 '
      '  AND COALESCE(s.quantite_disponible,0) <= p.seuil_alerte '
      'ORDER BY p.nom',
      [magasinId],
    );
    final res = <ReapproSuggestion>[];
    for (final r in manquants) {
      final pid = r['pid'] as String;
      final sources = await db.getAll(
        'SELECT s.magasin_id AS mid, m.nom AS nom, s.quantite_disponible AS q '
        'FROM stocks_magasin s JOIN magasins m ON m.id = s.magasin_id '
        'WHERE s.produit_id = ? AND s.magasin_id <> ? '
        '  AND s.quantite_disponible > 0 '
        'ORDER BY s.quantite_disponible DESC',
        [pid, magasinId],
      );
      res.add(ReapproSuggestion(
        produitId: pid,
        produitNom: (r['nom'] as String?) ?? '',
        disponible: ((r['dispo'] as num?) ?? 0).toInt(),
        seuil: ((r['seuil'] as num?) ?? 0).toInt(),
        sources: sources
            .map((s) => ReapproSource(
                  magasinId: s['mid'] as String,
                  magasinNom: (s['nom'] as String?) ?? '',
                  disponible: ((s['q'] as num?) ?? 0).toInt(),
                ))
            .toList(),
      ));
    }
    return res;
  }
}

/// Magasin capable de fournir un produit en rupture ailleurs.
class ReapproSource {
  final String magasinId;
  final String magasinNom;
  final int disponible;
  ReapproSource({
    required this.magasinId,
    required this.magasinNom,
    required this.disponible,
  });
}

/// Produit à réapprovisionner dans un magasin + sources possibles.
class ReapproSuggestion {
  final String produitId;
  final String produitNom;
  final int disponible;
  final int seuil;
  final List<ReapproSource> sources;
  ReapproSuggestion({
    required this.produitId,
    required this.produitNom,
    required this.disponible,
    required this.seuil,
    required this.sources,
  });

  /// Quantité à ramener pour repasser juste au-dessus du seuil (au moins 1).
  int get manque {
    final m = (seuil - disponible) + 1;
    return m < 1 ? 1 : m;
  }
}
