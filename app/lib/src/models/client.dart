/// Fiche client (§5.1 / §7). Le solde de jetons est global au client (§5.9).
class Client {
  final String id;
  final String nom;
  final String? telephone;
  final String? telephoneNormalise;
  final String? whatsapp;
  final int soldeJetons;
  final String dateCreation;

  Client({
    required this.id,
    required this.nom,
    this.telephone,
    this.telephoneNormalise,
    this.whatsapp,
    this.soldeJetons = 0,
    required this.dateCreation,
  });

  factory Client.fromRow(Map<String, dynamic> r) => Client(
        id: r['id'] as String,
        nom: (r['nom'] as String?) ?? '',
        telephone: r['telephone'] as String?,
        telephoneNormalise: r['telephone_normalise'] as String?,
        whatsapp: r['whatsapp'] as String?,
        soldeJetons: ((r['solde_jetons'] as num?) ?? 0).toInt(),
        dateCreation: (r['date_creation'] as String?) ?? '',
      );
}
