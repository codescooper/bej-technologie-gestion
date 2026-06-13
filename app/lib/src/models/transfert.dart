/// Transfert de stock entre deux magasins (Phase 2, §2.5).
class Transfert {
  final String id;
  final String produitId;
  final String magasinSourceId;
  final String magasinDestId;
  final int quantite;
  final String statut; // en_transit | recu | annule
  final String? dateCreation;
  final String? dateReception;

  // Champs de jointure (affichage).
  final String? produitNom;
  final String? sourceNom;
  final String? destNom;

  Transfert({
    required this.id,
    required this.produitId,
    required this.magasinSourceId,
    required this.magasinDestId,
    required this.quantite,
    this.statut = 'en_transit',
    this.dateCreation,
    this.dateReception,
    this.produitNom,
    this.sourceNom,
    this.destNom,
  });

  bool get enTransit => statut == 'en_transit';

  factory Transfert.fromRow(Map<String, dynamic> r) => Transfert(
        id: r['id'] as String,
        produitId: r['produit_id'] as String,
        magasinSourceId: r['magasin_source_id'] as String,
        magasinDestId: r['magasin_dest_id'] as String,
        quantite: ((r['quantite'] as num?) ?? 0).toInt(),
        statut: (r['statut'] as String?) ?? 'en_transit',
        dateCreation: r['date_creation'] as String?,
        dateReception: r['date_reception'] as String?,
        produitNom: r['produit_nom'] as String?,
        sourceNom: r['source_nom'] as String?,
        destNom: r['dest_nom'] as String?,
      );
}
