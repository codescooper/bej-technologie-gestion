import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';
import '../../models/caisse.dart';

/// Gestion de la caisse (§5.4). Une seule caisse ouverte par magasin à la fois.
class CaisseRepository {
  final PowerSyncDatabase db;
  final _uuid = const Uuid();

  CaisseRepository(this.db);

  /// Flux de la caisse actuellement ouverte du magasin (ou null).
  Stream<Caisse?> watchCaisseOuverte(String magasinId) {
    return db.watch(
      "SELECT * FROM caisses WHERE magasin_id = ? AND statut = 'ouverte' "
      'ORDER BY ouverture DESC LIMIT 1',
      parameters: [magasinId],
    ).map((rs) => rs.isEmpty ? null : Caisse.fromRow(rs.first));
  }

  Future<Caisse?> caisseOuverte(String magasinId) async {
    final rs = await db.getAll(
      "SELECT * FROM caisses WHERE magasin_id = ? AND statut = 'ouverte' "
      'ORDER BY ouverture DESC LIMIT 1',
      [magasinId],
    );
    return rs.isEmpty ? null : Caisse.fromRow(rs.first);
  }

  /// Ouvre une caisse avec un fond initial.
  Future<String> ouvrir({
    required String magasinId,
    required String utilisateurId,
    required num fondInitial,
  }) async {
    final existante = await caisseOuverte(magasinId);
    if (existante != null) {
      throw StateError('Une caisse est déjà ouverte pour ce magasin.');
    }
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'INSERT INTO caisses(id, magasin_id, utilisateur_id, ouverture, '
      'fond_initial, statut) VALUES(?,?,?,?,?,?)',
      [id, magasinId, utilisateurId, now, fondInitial, 'ouverte'],
    );
    return id;
  }

  /// Totaux théoriques dérivés des paiements rattachés à la caisse (§5.4).
  /// Retourne {cash, mobile}.
  Future<({num cash, num mobile})> totauxTheoriques(String caisseId) async {
    final rs = await db.getAll(
      "SELECT p.methode AS methode, COALESCE(SUM(p.montant),0) AS s "
      'FROM paiements p JOIN transactions t ON t.id = p.transaction_id '
      'WHERE t.caisse_id = ? GROUP BY p.methode',
      [caisseId],
    );
    num cash = 0;
    num mobile = 0;
    for (final r in rs) {
      final m = r['methode'] as String;
      final s = (r['s'] as num?) ?? 0;
      if (m == 'cash') {
        cash += s;
      } else {
        mobile += s;
      }
    }
    return (cash: cash, mobile: mobile);
  }

  /// Clôture la caisse avec comptage réel et calcul d'écart (§5.4).
  Future<Caisse> cloturer({
    required String caisseId,
    required num cashReel,
    required num mobileReel,
  }) async {
    final caisse = (await db.getAll(
      'SELECT * FROM caisses WHERE id = ?',
      [caisseId],
    ))
        .first;
    final fond = (caisse['fond_initial'] as num?) ?? 0;
    final t = await totauxTheoriques(caisseId);
    final cashTheoriqueAvecFond = fond + t.cash;
    final ecart =
        (cashReel - cashTheoriqueAvecFond) + (mobileReel - t.mobile);
    final now = DateTime.now().toUtc().toIso8601String();

    await db.execute(
      'UPDATE caisses SET fermeture = ?, statut = ?, '
      'cash_theorique = ?, cash_reel = ?, '
      'mobile_money_theorique = ?, mobile_money_reel = ?, ecart = ? '
      'WHERE id = ?',
      [
        now,
        'cloturee',
        cashTheoriqueAvecFond,
        cashReel,
        t.mobile,
        mobileReel,
        ecart,
        caisseId,
      ],
    );
    return Caisse.fromRow(
        (await db.getAll('SELECT * FROM caisses WHERE id = ?', [caisseId]))
            .first);
  }
}
