/// Utilisateur connecté, avec son rôle (§6).
class Utilisateur {
  final String id;
  final String nom;
  final String login;
  final String roleCode; // admin | responsable | caissier | technicien
  final String? magasinId;

  Utilisateur({
    required this.id,
    required this.nom,
    required this.login,
    required this.roleCode,
    this.magasinId,
  });

  factory Utilisateur.fromRow(Map<String, dynamic> r) => Utilisateur(
        id: r['id'] as String,
        nom: (r['nom'] as String?) ?? '',
        login: (r['login'] as String?) ?? '',
        roleCode: (r['role_code'] as String?) ?? 'caissier',
        magasinId: r['magasin_id'] as String?,
      );
}
