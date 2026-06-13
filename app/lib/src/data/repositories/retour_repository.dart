import 'dart:convert';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

/// Une ligne retournée (produit + quantité rendue + prix unitaire d'origine).
class LigneRetour {
  final String produitId;
  final String produitNom;
  final int quantite;
  final num prixUnitaire;
  LigneRetour({
    required this.produitId,
    required this.produitNom,
    required this.quantite,
    required this.prixUnitaire,
  });
  num get montant => quantite * prixUnitaire;
}

class RetourResult {
  final String retourTransactionId;
  final String avoirId;
  final num montant;
  final int jetonsAnnules;
  RetourResult({
    required this.retourTransactionId,
    required this.avoirId,
    required this.montant,
    required this.jetonsAnnules,
  });
}

/// Retours & avoirs (§5.6). Un retour (partiel ou total) crée une transaction
/// de type `retour` rattachée à la vente d'origine, réintègre le stock, annule
/// les jetons gagnés proportionnellement, et génère un AVOIR au nom du client.
/// (Remboursement : avoir uniquement — pas de cash rendu.)
class RetourRepository {
  final PowerSyncDatabase db;
  final _uuid = const Uuid();
  RetourRepository(this.db);

  /// Ventes retournables du magasin (type vente, avec client identifié).
  Future<List<Map<String, dynamic>>> ventesRetournables(String magasinId) async {
    final rs = await db.getAll(
      "SELECT t.id AS id, t.date AS date, t.total AS total, "
      "t.client_id AS client_id, c.nom AS client_nom "
      'FROM transactions t JOIN clients c ON c.id = t.client_id '
      "WHERE t.magasin_id = ? AND t.type = 'vente' "
      'ORDER BY t.date DESC LIMIT 50',
      [magasinId],
    );
    return rs
        .map((r) => {
              'id': r['id'],
              'date': r['date'],
              'total': r['total'],
              'client_id': r['client_id'],
              'client_nom': r['client_nom'],
            })
        .toList();
  }

  /// Lignes (produits) d'origine d'une vente — quantités positives.
  Future<List<LigneRetour>> lignesVendues(String transactionId) async {
    final rs = await db.getAll(
      'SELECT l.produit_id AS produit_id, p.nom AS nom, '
      'l.quantite AS quantite, l.prix_unitaire AS prix '
      'FROM lignes_transaction l JOIN produits p ON p.id = l.produit_id '
      'WHERE l.transaction_id = ? AND l.quantite > 0',
      [transactionId],
    );
    return rs
        .map((r) => LigneRetour(
              produitId: r['produit_id'] as String,
              produitNom: (r['nom'] as String?) ?? '',
              quantite: ((r['quantite'] as num?) ?? 0).toInt(),
              prixUnitaire: (r['prix'] as num?) ?? 0,
            ))
        .toList();
  }

  Future<RetourResult> enregistrerRetour({
    required String transactionOrigineId,
    required String magasinId,
    required String caisseId,
    required String utilisateurId,
    required String clientId,
    required List<LigneRetour> lignes,
  }) async {
    if (lignes.isEmpty) {
      throw ArgumentError('Aucune ligne à retourner.');
    }
    final montant = lignes.fold<num>(0, (s, l) => s + l.montant);
    final jetonsAnnules = (montant ~/ 100);
    final txId = _uuid.v4();
    final avoirId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.writeTransaction((tx) async {
      // 1. Transaction de retour (total négatif).
      await tx.execute(
        'INSERT INTO transactions(id, magasin_id, caisse_id, client_id, '
        'utilisateur_id, type, transaction_origine_id, total, remise_globale, '
        'jetons_utilises, jetons_gagnes, avoir_utilise, statut_sync, date) '
        'VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          txId, magasinId, caisseId, clientId, utilisateurId, 'retour',
          transactionOrigineId, -montant, 0, 0, 0, 0, 'local', now,
        ],
      );

      // 2. Lignes (quantités négatives) + réintégration du stock.
      for (final l in lignes) {
        await tx.execute(
          'INSERT INTO lignes_transaction(id, transaction_id, produit_id, '
          'quantite, prix_unitaire, remise_ligne) VALUES(?,?,?,?,?,?)',
          [_uuid.v4(), txId, l.produitId, -l.quantite, l.prixUnitaire, 0],
        );
        await tx.execute(
          'INSERT INTO mouvements_stock(id, produit_id, magasin_id, type, '
          'quantite, motif, utilisateur_id, transaction_id, date) '
          'VALUES(?,?,?,?,?,?,?,?,?)',
          [
            _uuid.v4(), l.produitId, magasinId, 'retour', l.quantite,
            'retour', utilisateurId, txId, now,
          ],
        );
        await tx.execute(
          'UPDATE stocks_magasin SET quantite_disponible = '
          'quantite_disponible + ? WHERE produit_id = ? AND magasin_id = ?',
          [l.quantite, l.produitId, magasinId],
        );
      }

      // 3. Avoir au nom du client.
      await tx.execute(
        'INSERT INTO avoirs(id, client_id, magasin_id, montant_initial, '
        'montant_restant, transaction_retour_id, statut, date_creation) '
        'VALUES(?,?,?,?,?,?,?,?)',
        [avoirId, clientId, magasinId, montant, montant, txId, 'actif', now],
      );

      // 4. Annulation des jetons gagnés sur la part retournée.
      if (jetonsAnnules > 0) {
        await tx.execute(
          'INSERT INTO jeton_transactions(id, client_id, transaction_id, type, '
          'montant, motif, utilisateur_id, date) VALUES(?,?,?,?,?,?,?,?)',
          [_uuid.v4(), clientId, txId, 'annulation', -jetonsAnnules,
            'Retour produit', utilisateurId, now],
        );
        await tx.execute(
          'UPDATE clients SET solde_jetons = solde_jetons - ? WHERE id = ?',
          [jetonsAnnules, clientId],
        );
      }

      // 5. Journal d'audit (§9) — trace de la validation responsable.
      await tx.execute(
        'INSERT INTO journal_audit(id, utilisateur_id, magasin_id, action, '
        'entite, entite_id, details, date) VALUES(?,?,?,?,?,?,?,?)',
        [
          _uuid.v4(), utilisateurId, magasinId, 'retour', 'transactions', txId,
          jsonEncode({
            'transaction_origine': transactionOrigineId,
            'montant': montant,
            'avoir': avoirId,
            'validation': 'responsable',
          }),
          now,
        ],
      );
    });

    return RetourResult(
      retourTransactionId: txId,
      avoirId: avoirId,
      montant: montant,
      jetonsAnnules: jetonsAnnules,
    );
  }
}
