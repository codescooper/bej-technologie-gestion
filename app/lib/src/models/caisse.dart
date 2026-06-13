/// Caisse d'un magasin (§5.4).
class Caisse {
  final String id;
  final String magasinId;
  final String utilisateurId;
  final String ouverture;
  final String? fermeture;
  final num fondInitial;
  final num cashTheorique;
  final num? cashReel;
  final num mobileMoneyTheorique;
  final num? mobileMoneyReel;
  final num? ecart;
  final String statut; // ouverte | cloturee

  Caisse({
    required this.id,
    required this.magasinId,
    required this.utilisateurId,
    required this.ouverture,
    this.fermeture,
    this.fondInitial = 0,
    this.cashTheorique = 0,
    this.cashReel,
    this.mobileMoneyTheorique = 0,
    this.mobileMoneyReel,
    this.ecart,
    this.statut = 'ouverte',
  });

  bool get estOuverte => statut == 'ouverte';

  factory Caisse.fromRow(Map<String, dynamic> r) => Caisse(
        id: r['id'] as String,
        magasinId: r['magasin_id'] as String,
        utilisateurId: r['utilisateur_id'] as String,
        ouverture: (r['ouverture'] as String?) ?? '',
        fermeture: r['fermeture'] as String?,
        fondInitial: (r['fond_initial'] as num?) ?? 0,
        cashTheorique: (r['cash_theorique'] as num?) ?? 0,
        cashReel: r['cash_reel'] as num?,
        mobileMoneyTheorique: (r['mobile_money_theorique'] as num?) ?? 0,
        mobileMoneyReel: r['mobile_money_reel'] as num?,
        ecart: r['ecart'] as num?,
        statut: (r['statut'] as String?) ?? 'ouverte',
      );
}
