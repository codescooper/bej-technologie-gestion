/// Modèle d'appareil du catalogue recherchable (marque + modèle).
class ModeleAppareil {
  final String id;
  final String marque;
  final String modele;
  final String? type;

  ModeleAppareil({
    required this.id,
    required this.marque,
    required this.modele,
    this.type,
  });

  String get libelle => '$marque $modele'.trim();

  factory ModeleAppareil.fromRow(Map<String, dynamic> r) => ModeleAppareil(
        id: r['id'] as String,
        marque: (r['marque'] as String?) ?? '',
        modele: (r['modele'] as String?) ?? '',
        type: r['type'] as String?,
      );
}
