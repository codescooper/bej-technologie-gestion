import 'produit.dart';

/// Ligne de panier (en mémoire avant encaissement).
class CartLine {
  final Produit produit;
  int quantite;
  num remiseLigne;
  num? prixNegocie; // null = prix catalogue ; < prixCatalogue = négociation

  CartLine(this.produit,
      {this.quantite = 1, this.remiseLigne = 0, this.prixNegocie});

  num get prixCatalogue => produit.prixVente;
  num get prixUnitaire => prixNegocie ?? produit.prixVente;
  num get sousTotal => prixUnitaire * quantite - remiseLigne;
}

/// Un moyen de paiement saisi (paiement mixte = plusieurs).
class PaiementInput {
  final String methode; // cash | wave | orange_money | mtn_momo
  final num montant;
  PaiementInput(this.methode, this.montant);
}

/// Résultat d'une vente (pour le reçu interne).
class VenteResult {
  final String transactionId;
  final num sousTotal;
  final num remiseGlobale;
  final int jetonsUtilises;
  final num avoirUtilise;
  final num total;
  final int jetonsGagnes;

  VenteResult({
    required this.transactionId,
    required this.sousTotal,
    required this.remiseGlobale,
    required this.jetonsUtilises,
    this.avoirUtilise = 0,
    required this.total,
    required this.jetonsGagnes,
  });
}
