import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';
import '../../models/transfert.dart';

/// Transferts inter-magasins (Phase 2, §2.5), mécanique en deux temps.
/// Aucun magasin ne modifie directement le stock d'un autre : la SOURCE crée
/// (stock en transit), le DESTINATAIRE confirme (stock ajouté).
class TransfertRepository {
  final PowerSyncDatabase db;
  final _uuid = const Uuid();
  TransfertRepository(this.db);

  static const _selectJoin = '''
    SELECT t.*, p.nom AS produit_nom, ms.nom AS source_nom, md.nom AS dest_nom
    FROM transferts t
    JOIN produits p ON p.id = t.produit_id
    JOIN magasins ms ON ms.id = t.magasin_source_id
    JOIN magasins md ON md.id = t.magasin_dest_id
  ''';

  /// Tous les transferts touchant le magasin (sortants + entrants).
  Stream<List<Transfert>> watch(String magasinId) {
    return db
        .watch(
            '$_selectJoin WHERE t.magasin_source_id = ? OR t.magasin_dest_id = ? '
            'ORDER BY t.date_creation DESC',
            parameters: [magasinId, magasinId])
        .map((rs) => rs.map((r) => Transfert.fromRow(r)).toList());
  }

  Future<int> _disponible(String produitId, String magasinId) async {
    final rs = await db.getAll(
      'SELECT quantite_disponible AS q FROM stocks_magasin '
      'WHERE produit_id = ? AND magasin_id = ?',
      [produitId, magasinId],
    );
    if (rs.isEmpty) return 0;
    return ((rs.first['q'] as num?) ?? 0).toInt();
  }

  /// 1) Création par la SOURCE : décrémente le stock disponible source,
  /// crée le transfert (en transit) et marque la quantité en transit côté dest.
  Future<String> creer({
    required String produitId,
    required String magasinSourceId,
    required String magasinDestId,
    required int quantite,
    required String utilisateurId,
  }) async {
    if (magasinSourceId == magasinDestId) {
      throw ArgumentError('Source et destination identiques.');
    }
    if (quantite <= 0) throw ArgumentError('Quantité invalide.');
    final dispo = await _disponible(produitId, magasinSourceId);
    if (dispo < quantite) {
      throw StateError('Stock insuffisant ($dispo disponible).');
    }

    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.writeTransaction((tx) async {
      await tx.execute(
        'INSERT INTO transferts(id, produit_id, magasin_source_id, '
        'magasin_dest_id, quantite, statut, utilisateur_source_id, date_creation) '
        'VALUES(?,?,?,?,?,?,?,?)',
        [id, produitId, magasinSourceId, magasinDestId, quantite,
          'en_transit', utilisateurId, now],
      );
      // Sort du stock disponible de la source.
      await tx.execute(
        'UPDATE stocks_magasin SET quantite_disponible = quantite_disponible - ? '
        'WHERE produit_id = ? AND magasin_id = ?',
        [quantite, produitId, magasinSourceId],
      );
      await tx.execute(
        'INSERT INTO mouvements_stock(id, produit_id, magasin_id, type, '
        'quantite, motif, utilisateur_id, date) VALUES(?,?,?,?,?,?,?,?)',
        [_uuid.v4(), produitId, magasinSourceId, 'transfert', -quantite,
          'Transfert sortant', utilisateurId, now],
      );
      // Marque la quantité en transit côté destination (crée la ligne si absente).
      final exist = await tx.getAll(
        'SELECT id FROM stocks_magasin WHERE produit_id = ? AND magasin_id = ?',
        [produitId, magasinDestId],
      );
      if (exist.isEmpty) {
        await tx.execute(
          'INSERT INTO stocks_magasin(id, produit_id, magasin_id, '
          'quantite_disponible, quantite_en_transit) VALUES(?,?,?,?,?)',
          [_uuid.v4(), produitId, magasinDestId, 0, quantite],
        );
      } else {
        await tx.execute(
          'UPDATE stocks_magasin SET quantite_en_transit = '
          'quantite_en_transit + ? WHERE produit_id = ? AND magasin_id = ?',
          [quantite, produitId, magasinDestId],
        );
      }
    });
    return id;
  }

  /// 2) Confirmation par le DESTINATAIRE : ajoute au stock disponible dest,
  /// retire de l'en-transit, passe le transfert à « reçu ».
  Future<void> confirmerReception({
    required String transfertId,
    required String utilisateurId,
  }) async {
    final rs =
        await db.getAll('SELECT * FROM transferts WHERE id = ?', [transfertId]);
    if (rs.isEmpty) return;
    final t = Transfert.fromRow(rs.first);
    if (!t.enTransit) return;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.writeTransaction((tx) async {
      await tx.execute(
        'UPDATE stocks_magasin SET quantite_disponible = quantite_disponible + ?, '
        'quantite_en_transit = quantite_en_transit - ? '
        'WHERE produit_id = ? AND magasin_id = ?',
        [t.quantite, t.quantite, t.produitId, t.magasinDestId],
      );
      await tx.execute(
        'UPDATE transferts SET statut = ?, utilisateur_dest_id = ?, '
        'date_reception = ? WHERE id = ?',
        ['recu', utilisateurId, now, transfertId],
      );
      await tx.execute(
        'INSERT INTO mouvements_stock(id, produit_id, magasin_id, type, '
        'quantite, motif, utilisateur_id, date) VALUES(?,?,?,?,?,?,?,?)',
        [_uuid.v4(), t.produitId, t.magasinDestId, 'transfert', t.quantite,
          'Transfert reçu', utilisateurId, now],
      );
    });
  }

  /// Annulation par la SOURCE d'un transfert resté en transit : le stock
  /// disponible revient à la source, l'en-transit du destinataire est retiré,
  /// le transfert passe à « annulé ». Sans effet s'il est déjà reçu/annulé.
  Future<void> annuler({
    required String transfertId,
    required String utilisateurId,
  }) async {
    final rs =
        await db.getAll('SELECT * FROM transferts WHERE id = ?', [transfertId]);
    if (rs.isEmpty) return;
    final t = Transfert.fromRow(rs.first);
    if (!t.enTransit) return;
    final now = DateTime.now().toUtc().toIso8601String();

    await db.writeTransaction((tx) async {
      // Le stock revient au magasin source.
      await tx.execute(
        'UPDATE stocks_magasin SET quantite_disponible = quantite_disponible + ? '
        'WHERE produit_id = ? AND magasin_id = ?',
        [t.quantite, t.produitId, t.magasinSourceId],
      );
      // L'en-transit du destinataire est retiré.
      await tx.execute(
        'UPDATE stocks_magasin SET quantite_en_transit = quantite_en_transit - ? '
        'WHERE produit_id = ? AND magasin_id = ?',
        [t.quantite, t.produitId, t.magasinDestId],
      );
      await tx.execute(
        'UPDATE transferts SET statut = ?, date_reception = ? WHERE id = ?',
        ['annule', now, transfertId],
      );
      await tx.execute(
        'INSERT INTO mouvements_stock(id, produit_id, magasin_id, type, '
        'quantite, motif, utilisateur_id, date) VALUES(?,?,?,?,?,?,?,?)',
        [_uuid.v4(), t.produitId, t.magasinSourceId, 'transfert', t.quantite,
          'Transfert annulé', utilisateurId, now],
      );
    });
  }
}
