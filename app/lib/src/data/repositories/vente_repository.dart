import 'dart:math' as math;
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';
import '../../models/vente.dart';

/// Enregistrement d'une vente comptoir = **transaction encaissée unifiée** (§7).
///
/// Crée, en une seule transaction d'écriture :
///   - 1 `transactions` (type 'vente')
///   - N `lignes_transaction`
///   - N `mouvements_stock` (sortie, cause = transaction) + décrément du stock
///   - N `paiements` (un ou plusieurs => paiement mixte)
///   - les `jeton_transactions` (gain et/ou dépense) + mise à jour du solde client
///
/// Règle jetons (§5.9) : 100 FCFA dépensés = 1 jeton gagné.
class VenteRepository {
  final PowerSyncDatabase db;
  final _uuid = const Uuid();

  VenteRepository(this.db);

  Future<VenteResult> enregistrerVente({
    required String magasinId,
    required String caisseId,
    required String utilisateurId,
    String? clientId,
    required List<CartLine> lignes,
    num remiseGlobale = 0,
    int jetonsUtilises = 0,
    String? avoirId,
    num avoirUtilise = 0,
    required List<PaiementInput> paiements,
    double multiplicateurJetons = 1.0,
  }) async {
    if (lignes.isEmpty) {
      throw ArgumentError('Le panier est vide.');
    }
    final sousTotal = lignes.fold<num>(0, (s, l) => s + l.sousTotal);
    final total = math.max<num>(
        0, sousTotal - remiseGlobale - jetonsUtilises - avoirUtilise);
    final jetonsGagnes = ((total ~/ 100) * multiplicateurJetons).round();

    final txId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    await db.writeTransaction((tx) async {
      // 1. Transaction encaissée
      await tx.execute(
        'INSERT INTO transactions(id, magasin_id, caisse_id, client_id, '
        'utilisateur_id, type, total, remise_globale, jetons_utilises, '
        'jetons_gagnes, avoir_utilise, statut_sync, date) '
        'VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          txId,
          magasinId,
          caisseId,
          clientId,
          utilisateurId,
          'vente',
          total,
          remiseGlobale,
          jetonsUtilises,
          jetonsGagnes,
          avoirUtilise,
          'local',
          now,
        ],
      );

      // 2 + 3. Lignes + mouvements de stock + décrément
      for (final l in lignes) {
        // remise_ligne = remise explicite + remise implicite (négociation de prix)
        final remiseLigneTotale =
            l.remiseLigne + (l.prixCatalogue - l.prixUnitaire) * l.quantite;
        await tx.execute(
          'INSERT INTO lignes_transaction(id, transaction_id, produit_id, '
          'quantite, prix_unitaire, remise_ligne) VALUES(?,?,?,?,?,?)',
          [_uuid.v4(), txId, l.produit.id, l.quantite, l.prixUnitaire, remiseLigneTotale],
        );
        await tx.execute(
          'INSERT INTO mouvements_stock(id, produit_id, magasin_id, type, '
          'quantite, motif, utilisateur_id, transaction_id, date) '
          'VALUES(?,?,?,?,?,?,?,?,?)',
          [
            _uuid.v4(),
            l.produit.id,
            magasinId,
            'sortie',
            -l.quantite,
            'vente',
            utilisateurId,
            txId,
            now,
          ],
        );
        await tx.execute(
          'UPDATE stocks_magasin SET quantite_disponible = '
          'quantite_disponible - ? WHERE produit_id = ? AND magasin_id = ?',
          [l.quantite, l.produit.id, magasinId],
        );
      }

      // 4. Paiements (mixte = plusieurs)
      for (final p in paiements) {
        await tx.execute(
          'INSERT INTO paiements(id, transaction_id, methode, montant, date) '
          'VALUES(?,?,?,?,?)',
          [_uuid.v4(), txId, p.methode, p.montant, now],
        );
      }

      // 5. Jetons (uniquement si client identifié)
      if (clientId != null) {
        if (jetonsUtilises > 0) {
          await tx.execute(
            'INSERT INTO jeton_transactions(id, client_id, transaction_id, '
            'type, montant, motif, utilisateur_id, date) VALUES(?,?,?,?,?,?,?,?)',
            [_uuid.v4(), clientId, txId, 'depense', -jetonsUtilises,
              'Utilisés en réduction', utilisateurId, now],
          );
        }
        if (jetonsGagnes > 0) {
          await tx.execute(
            'INSERT INTO jeton_transactions(id, client_id, transaction_id, '
            'type, montant, motif, utilisateur_id, date) VALUES(?,?,?,?,?,?,?,?)',
            [_uuid.v4(), clientId, txId, 'gain', jetonsGagnes,
              'Gain sur achat', utilisateurId, now],
          );
        }
        final delta = jetonsGagnes - jetonsUtilises;
        if (delta != 0) {
          await tx.execute(
            'UPDATE clients SET solde_jetons = solde_jetons + ? WHERE id = ?',
            [delta, clientId],
          );
        }
      }

      // 6. Consommation de l'avoir appliqué (§5.6)
      if (avoirId != null && avoirUtilise > 0) {
        await tx.execute(
          'UPDATE avoirs SET montant_restant = montant_restant - ?, '
          "statut = CASE WHEN montant_restant - ? <= 0 THEN 'utilise' "
          "ELSE 'actif' END, transaction_utilisation_id = ? WHERE id = ?",
          [avoirUtilise, avoirUtilise, txId, avoirId],
        );
      }
    });

    return VenteResult(
      transactionId: txId,
      sousTotal: sousTotal,
      remiseGlobale: remiseGlobale,
      jetonsUtilises: jetonsUtilises,
      avoirUtilise: avoirUtilise,
      total: total,
      jetonsGagnes: jetonsGagnes,
    );
  }
}
