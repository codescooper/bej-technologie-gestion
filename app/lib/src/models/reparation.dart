/// Statuts d'une réparation (§5.2), dans l'ordre du cycle.
class StatutReparation {
  static const recu = 'recu';
  static const diagnostic = 'diagnostic';
  static const attenteValidation = 'attente_validation';
  static const attentePiece = 'attente_piece';
  static const enReparation = 'en_reparation';
  static const pret = 'pret';
  static const livre = 'livre';
  static const annule = 'annule';

  static const ordre = [
    recu,
    diagnostic,
    attenteValidation,
    attentePiece,
    enReparation,
    pret,
    livre,
  ];

  static const libelles = {
    recu: 'Reçu',
    diagnostic: 'Diagnostic',
    attenteValidation: 'Attente validation',
    attentePiece: 'Attente pièce',
    enReparation: 'En réparation',
    pret: 'Prêt',
    livre: 'Livré',
    annule: 'Annulé',
  };

  static String libelle(String code) => libelles[code] ?? code;
}

/// Réparation (§5.2 / §7). Le devis/ventilation est porté ici ; l'encaissement
/// est une Transaction de type `reparation` (générée au retrait).
class Reparation {
  final String id;
  final String appareilId;
  final String magasinId;
  final String? technicienId;
  final String? probleme;
  final String? etatVisuel;
  final String? diagnostic;
  final num devis;
  final String statut;
  final num montantMainOeuvre;
  final num montantPieces;
  final num total;
  final String? dateCreation;
  final String? dateCloture;

  Reparation({
    required this.id,
    required this.appareilId,
    required this.magasinId,
    this.technicienId,
    this.probleme,
    this.etatVisuel,
    this.diagnostic,
    this.devis = 0,
    this.statut = StatutReparation.recu,
    this.montantMainOeuvre = 0,
    this.montantPieces = 0,
    this.total = 0,
    this.dateCreation,
    this.dateCloture,
  });

  factory Reparation.fromRow(Map<String, dynamic> r) => Reparation(
        id: r['id'] as String,
        appareilId: r['appareil_id'] as String,
        magasinId: r['magasin_id'] as String,
        technicienId: r['technicien_id'] as String?,
        probleme: r['probleme'] as String?,
        etatVisuel: r['etat_visuel'] as String?,
        diagnostic: r['diagnostic'] as String?,
        devis: (r['devis'] as num?) ?? 0,
        statut: (r['statut'] as String?) ?? StatutReparation.recu,
        montantMainOeuvre: (r['montant_main_oeuvre'] as num?) ?? 0,
        montantPieces: (r['montant_pieces'] as num?) ?? 0,
        total: (r['total'] as num?) ?? 0,
        dateCreation: r['date_creation'] as String?,
        dateCloture: r['date_cloture'] as String?,
      );
}

/// Vue liste : réparation + infos appareil et client (jointure).
class ReparationListItem {
  final Reparation reparation;
  final String appareilLibelle; // marque modèle
  final String? marque;
  final String? modele;
  final String? imei;
  final String? clientNom;
  final String? clientId;

  ReparationListItem({
    required this.reparation,
    required this.appareilLibelle,
    this.marque,
    this.modele,
    this.imei,
    this.clientNom,
    this.clientId,
  });

  factory ReparationListItem.fromRow(Map<String, dynamic> r) =>
      ReparationListItem(
        reparation: Reparation.fromRow(r),
        appareilLibelle: [
          (r['marque'] as String?) ?? '',
          (r['modele'] as String?) ?? '',
        ].where((s) => s.isNotEmpty).join(' ').trim(),
        marque: r['marque'] as String?,
        modele: r['modele'] as String?,
        imei: r['imei'] as String?,
        clientNom: r['client_nom'] as String?,
        clientId: r['client_id'] as String?,
      );
}

/// Suggestion de devis (data-driven) : médiane du total facturé des réparations
/// similaires. `elargi` = repli sur la panne seule (tous modèles).
class DevisSuggere {
  final num prix;
  final int nbCas;
  final bool elargi;
  DevisSuggere({required this.prix, required this.nbCas, required this.elargi});
}
