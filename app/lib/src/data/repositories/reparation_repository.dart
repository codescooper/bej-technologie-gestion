import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';
import '../../models/reparation.dart';
import '../../models/vente.dart';

/// Cycle de vie des réparations (§5.2) : réception, diagnostic, pièces,
/// statuts, et **encaissement au retrait** (Transaction type `reparation`
/// rattachée à la caisse — c'est ce qui fait entrer le CA réparation dans le
/// rapprochement de caisse, §5.4).
class ReparationRepository {
  final PowerSyncDatabase db;
  final _uuid = const Uuid();

  ReparationRepository(this.db);

  static const _selectJoin = '''
    SELECT r.*, a.marque AS marque, a.modele AS modele, a.imei AS imei,
           a.client_id AS client_id, c.nom AS client_nom
    FROM reparations r
    JOIN appareils a ON a.id = r.appareil_id
    LEFT JOIN clients c ON c.id = a.client_id
  ''';

  /// Flux des réparations du magasin, filtré par statut (null = toutes).
  Stream<List<ReparationListItem>> watch(String magasinId, {String? statut}) {
    final where = statut == null
        ? 'WHERE r.magasin_id = ?'
        : 'WHERE r.magasin_id = ? AND r.statut = ?';
    final params = statut == null ? [magasinId] : [magasinId, statut];
    return db
        .watch('$_selectJoin $where ORDER BY r.date_creation DESC',
            parameters: params)
        .map((rs) => rs.map((r) => ReparationListItem.fromRow(r)).toList());
  }

  Future<ReparationListItem?> getById(String id) async {
    final rs =
        await db.getAll('$_selectJoin WHERE r.id = ?', [id]);
    return rs.isEmpty ? null : ReparationListItem.fromRow(rs.first);
  }

  /// Réparations d'un client (toutes, via ses appareils).
  Future<List<ReparationListItem>> parClient(String clientId) async {
    final rs = await db.getAll(
        '$_selectJoin WHERE a.client_id = ? ORDER BY r.date_creation DESC',
        [clientId]);
    return rs.map((r) => ReparationListItem.fromRow(r)).toList();
  }

  /// Historique d'un appareil précis (suivi par appareil §5.2) — toutes ses
  /// réparations, de la plus récente à la plus ancienne.
  Future<List<ReparationListItem>> parAppareil(String appareilId) async {
    final rs = await db.getAll(
        '$_selectJoin WHERE r.appareil_id = ? ORDER BY r.date_creation DESC',
        [appareilId]);
    return rs.map((r) => ReparationListItem.fromRow(r)).toList();
  }

  /// Garantie : cherche une réparation récente du MÊME appareil pour la MÊME
  /// panne dans la fenêtre [jours]. Retourne sa date (ISO) ou null. Sert à
  /// signaler une possible reprise sous garantie à la création.
  Future<String?> garantieRecente({
    required String appareilId,
    required String probleme,
    int jours = 30,
  }) async {
    final depuis = DateTime.now()
        .toUtc()
        .subtract(Duration(days: jours))
        .toIso8601String();
    final rs = await db.getAll(
      'SELECT date_creation AS d FROM reparations '
      'WHERE appareil_id = ? AND lower(probleme) = lower(?) '
      "AND statut <> 'annule' AND date_creation >= ? "
      'ORDER BY date_creation DESC LIMIT 1',
      [appareilId, probleme, depuis],
    );
    return rs.isEmpty ? null : rs.first['d'] as String?;
  }

  /// Pannes les plus fréquentes pour un modèle (suggestions à la saisie),
  /// calculées sur l'historique local. Liste vide si pas encore d'historique.
  Future<List<String>> pannesFrequentes({
    String? marque,
    required String modele,
    int limite = 4,
  }) async {
    if (modele.trim().isEmpty) return [];
    final rs = await db.getAll(
      'SELECT r.probleme AS p, count(*) AS c '
      'FROM reparations r JOIN appareils a ON a.id = r.appareil_id '
      "WHERE a.modele = ? AND r.probleme IS NOT NULL AND r.probleme <> '' "
      'GROUP BY r.probleme ORDER BY c DESC, r.probleme LIMIT ?',
      [modele.trim(), limite],
    );
    return rs.map((r) => r['p'] as String).toList();
  }

  /// Devis suggéré pour (modèle + panne) = **médiane** du `total` facturé des
  /// réparations similaires récentes (fenêtre [moisFenetre] mois, min [minCas]
  /// cas, hors annulées et hors total nul). Repli sur la **panne seule** (tous
  /// modèles) si pas assez de cas exacts. Null si l'historique est insuffisant.
  /// 100 % local (offline) — prolonge l'atelier « intelligent ».
  Future<DevisSuggere?> devisSuggere({
    required String modele,
    required String probleme,
    int moisFenetre = 12,
    int minCas = 2,
  }) async {
    final p = probleme.trim();
    if (p.isEmpty) return null;
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(Duration(days: moisFenetre * 30))
        .toIso8601String();

    // 1) Cas exacts : même modèle + même panne.
    final m = modele.trim();
    if (m.isNotEmpty) {
      final exact = await db.getAll(
        'SELECT r.total AS t FROM reparations r '
        'JOIN appareils a ON a.id = r.appareil_id '
        'WHERE a.modele = ? AND lower(r.probleme) = lower(?) '
        "AND r.statut <> 'annule' AND r.total > 0 AND r.date_creation >= ?",
        [m, p, cutoff],
      );
      final vals =
          exact.map((r) => (r['t'] as num?) ?? 0).where((x) => x > 0).toList();
      if (vals.length >= minCas) {
        return DevisSuggere(
            prix: _mediane(vals), nbCas: vals.length, elargi: false);
      }
    }

    // 2) Repli : même panne, tous modèles.
    final large = await db.getAll(
      'SELECT r.total AS t FROM reparations r '
      'WHERE lower(r.probleme) = lower(?) '
      "AND r.statut <> 'annule' AND r.total > 0 AND r.date_creation >= ?",
      [p, cutoff],
    );
    final vals =
        large.map((r) => (r['t'] as num?) ?? 0).where((x) => x > 0).toList();
    if (vals.length >= minCas) {
      return DevisSuggere(prix: _mediane(vals), nbCas: vals.length, elargi: true);
    }
    return null;
  }

  static num _mediane(List<num> valeurs) {
    final v = [...valeurs]..sort();
    final n = v.length;
    if (n == 0) return 0;
    return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
  }

  /// Crée une réparation (statut `reçu`). Le devis sert d'estimation ; la
  /// main-d'œuvre initiale = devis, les pièces s'ajoutent ensuite.
  Future<String> creer({
    required String appareilId,
    required String magasinId,
    String? technicienId,
    String? probleme,
    String? etatVisuel,
    num devis = 0,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'INSERT INTO reparations(id, appareil_id, magasin_id, technicien_id, '
      'probleme, etat_visuel, devis, statut, montant_main_oeuvre, '
      'montant_pieces, total, date_creation) '
      'VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        id, appareilId, magasinId, technicienId, probleme, etatVisuel,
        devis, StatutReparation.recu, devis, 0, devis, now,
      ],
    );
    return id;
  }

  Future<void> changerStatut(String id, String statut) async {
    await db.execute(
        'UPDATE reparations SET statut = ? WHERE id = ?', [statut, id]);
  }

  /// Met à jour diagnostic + main-d'œuvre, recalcule le total.
  Future<void> majDiagnostic(String id,
      {String? diagnostic, required num montantMainOeuvre}) async {
    await db.execute(
      'UPDATE reparations SET diagnostic = ?, montant_main_oeuvre = ?, '
      'total = ? + montant_pieces WHERE id = ?',
      [diagnostic, montantMainOeuvre, montantMainOeuvre, id],
    );
  }

  /// Consomme une pièce du stock pour la réparation (§5.2 / §5.7) :
  /// MouvementStock rattaché à `reparation_id`, décrément du stock, et
  /// `montant_pieces`/`total` mis à jour.
  Future<void> consommerPiece({
    required String reparationId,
    required String produitId,
    required String magasinId,
    required num prixUnitaire,
    int quantite = 1,
    required String utilisateurId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO mouvements_stock(id, produit_id, magasin_id, type, '
        'quantite, motif, utilisateur_id, reparation_id, date) '
        'VALUES(?,?,?,?,?,?,?,?,?)',
        [
          _uuid.v4(), produitId, magasinId, 'consommation', -quantite,
          'Pièce réparation', utilisateurId, reparationId, now,
        ],
      );
      await tx.execute(
        'UPDATE stocks_magasin SET quantite_disponible = quantite_disponible - ? '
        'WHERE produit_id = ? AND magasin_id = ?',
        [quantite, produitId, magasinId],
      );
      await tx.execute(
        'UPDATE reparations SET montant_pieces = montant_pieces + ?, '
        'total = montant_main_oeuvre + (montant_pieces + ?) WHERE id = ?',
        [prixUnitaire * quantite, prixUnitaire * quantite, reparationId],
      );
    });
  }

  /// Encaissement au retrait (§5.2) : génère une `Transaction` de type
  /// `reparation` rattachée à la caisse active, ses paiements, les jetons, et
  /// passe la réparation à `livré`.
  Future<VenteResult> encaisserRetrait({
    required String reparationId,
    required String magasinId,
    required String caisseId,
    required String utilisateurId,
    required List<PaiementInput> paiements,
  }) async {
    final repRows =
        await db.getAll('SELECT * FROM reparations WHERE id = ?', [reparationId]);
    final rep = Reparation.fromRow(repRows.first);
    final appRows = await db
        .getAll('SELECT client_id FROM appareils WHERE id = ?', [rep.appareilId]);
    final clientId =
        appRows.isEmpty ? null : appRows.first['client_id'] as String?;

    final total = rep.total;
    final jetonsGagnes = (total ~/ 100);
    final txId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO transactions(id, magasin_id, caisse_id, client_id, '
        'utilisateur_id, type, reparation_id, total, remise_globale, '
        'jetons_utilises, jetons_gagnes, statut_sync, date) '
        'VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          txId, magasinId, caisseId, clientId, utilisateurId, 'reparation',
          reparationId, total, 0, 0, jetonsGagnes, 'local', now,
        ],
      );
      for (final p in paiements) {
        await tx.execute(
          'INSERT INTO paiements(id, transaction_id, methode, montant, date) '
          'VALUES(?,?,?,?,?)',
          [_uuid.v4(), txId, p.methode, p.montant, now],
        );
      }
      if (clientId != null && jetonsGagnes > 0) {
        await tx.execute(
          'INSERT INTO jeton_transactions(id, client_id, transaction_id, type, '
          'montant, motif, utilisateur_id, date) VALUES(?,?,?,?,?,?,?,?)',
          [_uuid.v4(), clientId, txId, 'gain', jetonsGagnes,
            'Gain sur réparation', utilisateurId, now],
        );
        await tx.execute(
          'UPDATE clients SET solde_jetons = solde_jetons + ? WHERE id = ?',
          [jetonsGagnes, clientId],
        );
      }
      await tx.execute(
        'UPDATE reparations SET statut = ?, date_cloture = ? WHERE id = ?',
        [StatutReparation.livre, now, reparationId],
      );
    });

    return VenteResult(
      transactionId: txId,
      sousTotal: total,
      remiseGlobale: 0,
      jetonsUtilises: 0,
      total: total,
      jetonsGagnes: jetonsGagnes,
    );
  }
}
