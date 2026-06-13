/// Produit du catalogue (§5.5 / §7).
class Produit {
  final String id;
  final String nom;
  final String? categorie;
  final num prixAchat;
  final num prixVente;
  final int seuilAlerte;

  Produit({
    required this.id,
    required this.nom,
    this.categorie,
    this.prixAchat = 0,
    this.prixVente = 0,
    this.seuilAlerte = 0,
  });

  factory Produit.fromRow(Map<String, dynamic> r) => Produit(
        id: r['id'] as String,
        nom: (r['nom'] as String?) ?? '',
        categorie: r['categorie'] as String?,
        prixAchat: (r['prix_achat'] as num?) ?? 0,
        prixVente: (r['prix_vente'] as num?) ?? 0,
        seuilAlerte: ((r['seuil_alerte'] as num?) ?? 0).toInt(),
      );
}

/// Produit + quantité disponible dans le magasin courant (vue catalogue/stock).
class ProduitStock {
  final Produit produit;
  final int quantiteDispo;

  ProduitStock(this.produit, this.quantiteDispo);

  bool get stockBas => quantiteDispo <= produit.seuilAlerte;

  factory ProduitStock.fromRow(Map<String, dynamic> r) => ProduitStock(
        Produit.fromRow(r),
        ((r['qte'] as num?) ?? 0).toInt(),
      );
}
