/// UUID FIXES du référentiel — DOIVENT correspondre à backend/schema/003_seed.sql.
///
/// La base PowerSync locale démarre vide (pas de service de streaming en
/// Phase 0/1). On sème donc le référentiel localement avec ces mêmes UUID :
/// la remontée vers le serveur converge alors via ON CONFLICT (id).
class RefIds {
  // Rôles
  static const roleAdmin = '0a000000-0000-4000-8000-000000000001';
  static const roleResponsable = '0a000000-0000-4000-8000-000000000002';
  static const roleCaissier = '0a000000-0000-4000-8000-000000000003';
  static const roleTechnicien = '0a000000-0000-4000-8000-000000000004';

  // Magasins
  static const magasinCocody = '0c000000-0000-4000-8000-000000000001';
  static const magasinYopougon = '0c000000-0000-4000-8000-000000000002';
  static const magasinMarcory = '0c000000-0000-4000-8000-000000000003';

  // Utilisateurs
  static const userAdmin = '0e000000-0000-4000-8000-000000000001';
  static const userAwaCaissiere = '0e000000-0000-4000-8000-000000000002';
  static const userResponsable = '0e000000-0000-4000-8000-000000000003';
  static const userTechnicien = '0e000000-0000-4000-8000-000000000004';
}

/// Magasin de référence (id, nom).
class MagasinRef {
  final String id;
  final String nom;
  const MagasinRef(this.id, this.nom);
}

const magasinsRef = <MagasinRef>[
  MagasinRef(RefIds.magasinCocody, 'BEJ Cocody'),
  MagasinRef(RefIds.magasinYopougon, 'BEJ Yopougon'),
  MagasinRef(RefIds.magasinMarcory, 'BEJ Marcory'),
];
