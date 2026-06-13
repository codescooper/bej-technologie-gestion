/// Inventaire physique d'un magasin (Finitions Phase 2+).
class Inventaire {
  final String id;
  final String magasinId;
  final String statut; // en_cours | valide | annule
  final String? note;
  final String? dateCreation;
  final String? dateValidation;

  Inventaire({
    required this.id,
    required this.magasinId,
    this.statut = 'en_cours',
    this.note,
    this.dateCreation,
    this.dateValidation,
  });

  bool get enCours => statut == 'en_cours';
  bool get valide => statut == 'valide';

  factory Inventaire.fromRow(Map<String, dynamic> r) => Inventaire(
        id: r['id'] as String,
        magasinId: r['magasin_id'] as String,
        statut: (r['statut'] as String?) ?? 'en_cours',
        note: r['note'] as String?,
        dateCreation: r['date_creation'] as String?,
        dateValidation: r['date_validation'] as String?,
      );
}

/// Ligne d'inventaire : un produit, son stock théorique et le comptage saisi.
class LigneInventaire {
  final String id;
  final String produitId;
  final String? produitNom;
  final int theorique;
  final int? comptee;
  final int ecart;

  LigneInventaire({
    required this.id,
    required this.produitId,
    this.produitNom,
    this.theorique = 0,
    this.comptee,
    this.ecart = 0,
  });

  factory LigneInventaire.fromRow(Map<String, dynamic> r) => LigneInventaire(
        id: r['id'] as String,
        produitId: r['produit_id'] as String,
        produitNom: r['produit_nom'] as String?,
        theorique: ((r['quantite_theorique'] as num?) ?? 0).toInt(),
        comptee: r['quantite_comptee'] == null
            ? null
            : (r['quantite_comptee'] as num).toInt(),
        ecart: ((r['ecart'] as num?) ?? 0).toInt(),
      );
}
