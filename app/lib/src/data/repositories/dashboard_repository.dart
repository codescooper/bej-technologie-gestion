import 'package:powersync/powersync.dart';

/// Indicateurs agrégés du tableau de bord (§5 — dashboard simple).
class DashboardData {
  final num caVentes;
  final num caReparations;
  final int nbVentes;
  final int nbReparations;
  final Map<String, int> reparationsParStatut;
  final int stockBasCount;
  final bool caisseOuverte;
  final num caisseTheoriqueCash;
  final num caisseTheoriqueMobile;
  final int jetonsDistribues;

  DashboardData({
    required this.caVentes,
    required this.caReparations,
    required this.nbVentes,
    required this.nbReparations,
    required this.reparationsParStatut,
    required this.stockBasCount,
    required this.caisseOuverte,
    required this.caisseTheoriqueCash,
    required this.caisseTheoriqueMobile,
    required this.jetonsDistribues,
  });

  num get caTotal => caVentes + caReparations;
}

/// Ligne de reporting consolidé pour un magasin (vue admin, Phase 2).
class MagasinReport {
  final String magasinId;
  final String nom;
  final num ca;
  final int nbTransactions;
  final int stockTotal;
  final int stockBas;
  MagasinReport({
    required this.magasinId,
    required this.nom,
    required this.ca,
    required this.nbTransactions,
    required this.stockTotal,
    required this.stockBas,
  });
}

/// Rapprochement de caisse consolidé (Finitions Phase 2+) : par magasin, le
/// nombre de clôtures, l'écart cumulé et le dernier écart constaté.
class RapprochementCaisse {
  final String magasinId;
  final String nom;
  final int nbCloturees;
  final num ecartCumule;
  final num? dernierEcart;
  RapprochementCaisse({
    required this.magasinId,
    required this.nom,
    required this.nbCloturees,
    required this.ecartCumule,
    required this.dernierEcart,
  });
}

/// Calcule les indicateurs du magasin courant pour la journée en cours.
/// Lecture seule sur la base locale (les données du magasin).
class DashboardRepository {
  final PowerSyncDatabase db;
  DashboardRepository(this.db);

  /// Reporting consolidé multi-magasins (§ Phase 2). Agrège, par magasin,
  /// le CA (ventes + réparations), le nb de transactions et le stock.
  Future<List<MagasinReport>> consolide() async {
    final mags = await db.getAll('SELECT id, nom FROM magasins ORDER BY nom');

    Future<Map<String, num>> mapNum(String sql) async {
      final rs = await db.getAll(sql);
      return {for (final r in rs) (r['m'] as String): (r['v'] as num?) ?? 0};
    }

    final caParMag = await mapNum(
        "SELECT magasin_id AS m, COALESCE(SUM(total),0) AS v FROM transactions "
        "WHERE type IN ('vente','reparation') GROUP BY magasin_id");
    final nbParMag = await mapNum(
        "SELECT magasin_id AS m, count(*) AS v FROM transactions "
        "WHERE type IN ('vente','reparation') GROUP BY magasin_id");
    final stockParMag = await mapNum(
        'SELECT magasin_id AS m, COALESCE(SUM(quantite_disponible),0) AS v '
        'FROM stocks_magasin GROUP BY magasin_id');
    final basParMag = await mapNum(
        'SELECT s.magasin_id AS m, count(*) AS v FROM stocks_magasin s '
        'JOIN produits p ON p.id = s.produit_id '
        'WHERE s.quantite_disponible <= p.seuil_alerte GROUP BY s.magasin_id');

    return mags.map((r) {
      final id = r['id'] as String;
      return MagasinReport(
        magasinId: id,
        nom: (r['nom'] as String?) ?? '',
        ca: caParMag[id] ?? 0,
        nbTransactions: (nbParMag[id] ?? 0).toInt(),
        stockTotal: (stockParMag[id] ?? 0).toInt(),
        stockBas: (basParMag[id] ?? 0).toInt(),
      );
    }).toList();
  }

  /// Rapprochement de caisse consolidé : agrège les caisses clôturées par
  /// magasin (nombre, écart cumulé, dernier écart constaté).
  Future<List<RapprochementCaisse>> rapprochementCaisse() async {
    final mags = await db.getAll('SELECT id, nom FROM magasins ORDER BY nom');
    final agg = await db.getAll(
        "SELECT magasin_id AS m, count(*) AS nb, COALESCE(SUM(ecart),0) AS tot "
        "FROM caisses WHERE statut = 'cloturee' GROUP BY magasin_id");
    final aggMap = {for (final r in agg) (r['m'] as String): r};

    // Dernier écart par magasin (première occurrence en tri décroissant).
    final derniers = await db.getAll(
        "SELECT magasin_id AS m, ecart AS e FROM caisses "
        "WHERE statut = 'cloturee' ORDER BY fermeture DESC");
    final dernierMap = <String, num>{};
    for (final r in derniers) {
      final m = r['m'] as String;
      if (!dernierMap.containsKey(m)) {
        dernierMap[m] = (r['e'] as num?) ?? 0;
      }
    }

    return mags.map((r) {
      final id = r['id'] as String;
      final a = aggMap[id];
      return RapprochementCaisse(
        magasinId: id,
        nom: (r['nom'] as String?) ?? '',
        nbCloturees: a == null ? 0 : ((a['nb'] as num?) ?? 0).toInt(),
        ecartCumule: a == null ? 0 : ((a['tot'] as num?) ?? 0),
        dernierEcart: dernierMap[id],
      );
    }).toList();
  }

  Future<DashboardData> load(String magasinId) async {
    // Début de journée (locale) converti en UTC, format ISO comparable aux dates stockées.
    final now = DateTime.now();
    final debutJour =
        DateTime(now.year, now.month, now.day).toUtc().toIso8601String();

    Future<num> sumTotal(String type) async {
      final rs = await db.getAll(
        'SELECT COALESCE(SUM(total),0) AS s FROM transactions '
        'WHERE magasin_id = ? AND type = ? AND date >= ?',
        [magasinId, type, debutJour],
      );
      return (rs.first['s'] as num?) ?? 0;
    }

    Future<int> countTx(String type) async {
      final rs = await db.getAll(
        'SELECT count(*) AS c FROM transactions '
        'WHERE magasin_id = ? AND type = ? AND date >= ?',
        [magasinId, type, debutJour],
      );
      return ((rs.first['c'] as num?) ?? 0).toInt();
    }

    final caVentes = await sumTotal('vente');
    final caReparations = await sumTotal('reparation');
    final nbVentes = await countTx('vente');
    final nbReparations = await countTx('reparation');

    // Réparations actives par statut.
    final repRows = await db.getAll(
      "SELECT statut, count(*) AS c FROM reparations "
      "WHERE magasin_id = ? AND statut NOT IN ('livre','annule') "
      'GROUP BY statut',
      [magasinId],
    );
    final reparationsParStatut = <String, int>{
      for (final r in repRows)
        (r['statut'] as String): ((r['c'] as num?) ?? 0).toInt(),
    };

    // Stock bas.
    final stockRows = await db.getAll(
      'SELECT count(*) AS c FROM stocks_magasin s '
      'JOIN produits p ON p.id = s.produit_id '
      'WHERE s.magasin_id = ? AND s.quantite_disponible <= p.seuil_alerte',
      [magasinId],
    );
    final stockBasCount = ((stockRows.first['c'] as num?) ?? 0).toInt();

    // Caisse ouverte + théoriques (dérivés des paiements rattachés).
    final caisseRows = await db.getAll(
      "SELECT id, fond_initial FROM caisses "
      "WHERE magasin_id = ? AND statut = 'ouverte' ORDER BY ouverture DESC LIMIT 1",
      [magasinId],
    );
    var caisseOuverte = false;
    num cash = 0;
    num mobile = 0;
    if (caisseRows.isNotEmpty) {
      caisseOuverte = true;
      final fond = (caisseRows.first['fond_initial'] as num?) ?? 0;
      final caisseId = caisseRows.first['id'] as String;
      final payRows = await db.getAll(
        'SELECT p.methode AS methode, COALESCE(SUM(p.montant),0) AS s '
        'FROM paiements p JOIN transactions t ON t.id = p.transaction_id '
        'WHERE t.caisse_id = ? GROUP BY p.methode',
        [caisseId],
      );
      for (final r in payRows) {
        final m = r['methode'] as String;
        final s = (r['s'] as num?) ?? 0;
        if (m == 'cash') {
          cash += s;
        } else {
          mobile += s;
        }
      }
      cash += fond;
    }

    // Jetons distribués aujourd'hui (gains).
    final jetonRows = await db.getAll(
      "SELECT COALESCE(SUM(montant),0) AS s FROM jeton_transactions "
      "WHERE type = 'gain' AND date >= ?",
      [debutJour],
    );
    final jetons = ((jetonRows.first['s'] as num?) ?? 0).toInt();

    return DashboardData(
      caVentes: caVentes,
      caReparations: caReparations,
      nbVentes: nbVentes,
      nbReparations: nbReparations,
      reparationsParStatut: reparationsParStatut,
      stockBasCount: stockBasCount,
      caisseOuverte: caisseOuverte,
      caisseTheoriqueCash: cash,
      caisseTheoriqueMobile: mobile,
      jetonsDistribues: jetons,
    );
  }
}
