/// Avoir = crédit interne au nom d'un client, généré par un retour (§5.6),
/// réutilisable comme moyen de paiement à un achat ultérieur.
class Avoir {
  final String id;
  final String clientId;
  final String? magasinId;
  final num montantInitial;
  final num montantRestant;
  final String? transactionRetourId;
  final String statut; // actif | utilise
  final String? dateCreation;

  Avoir({
    required this.id,
    required this.clientId,
    this.magasinId,
    this.montantInitial = 0,
    this.montantRestant = 0,
    this.transactionRetourId,
    this.statut = 'actif',
    this.dateCreation,
  });

  bool get estActif => statut == 'actif' && montantRestant > 0;

  factory Avoir.fromRow(Map<String, dynamic> r) => Avoir(
        id: r['id'] as String,
        clientId: r['client_id'] as String,
        magasinId: r['magasin_id'] as String?,
        montantInitial: (r['montant_initial'] as num?) ?? 0,
        montantRestant: (r['montant_restant'] as num?) ?? 0,
        transactionRetourId: r['transaction_retour_id'] as String?,
        statut: (r['statut'] as String?) ?? 'actif',
        dateCreation: r['date_creation'] as String?,
      );
}
