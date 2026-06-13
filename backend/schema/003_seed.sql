-- =====================================================================
-- BEJ Technologie — Données initiales (référentiel minimal).
--
-- UUID FIXES (et non aléatoires) : indispensables pour que l'app, qui sème le
-- même référentiel en local (base PowerSync vide au démarrage faute de service
-- de streaming), converge avec le serveur via ON CONFLICT (id). Les mêmes UUID
-- sont déclarés côté app dans app/lib/src/data/ref_ids.dart.
--
-- Idempotent : ON CONFLICT (id).
-- =====================================================================

-- Rôles (§6)
INSERT INTO roles (id, code, libelle) VALUES
  ('0a000000-0000-4000-8000-000000000001','admin',       'Administrateur'),
  ('0a000000-0000-4000-8000-000000000002','responsable', 'Responsable magasin'),
  ('0a000000-0000-4000-8000-000000000003','caissier',    'Caissier'),
  ('0a000000-0000-4000-8000-000000000004','technicien',  'Technicien')
ON CONFLICT (id) DO UPDATE SET code = EXCLUDED.code, libelle = EXCLUDED.libelle;

-- Magasins (§1)
INSERT INTO magasins (id, nom, code) VALUES
  ('0c000000-0000-4000-8000-000000000001','BEJ Cocody',   'COCODY'),
  ('0c000000-0000-4000-8000-000000000002','BEJ Yopougon', 'YOP'),
  ('0c000000-0000-4000-8000-000000000003','BEJ Marcory',  'MARCORY')
ON CONFLICT (id) DO UPDATE SET nom = EXCLUDED.nom, code = EXCLUDED.code;

-- Utilisateurs des 4 rôles (§6). Le PIN (mot_de_passe_hash) est en clair ici
-- (DEV uniquement) ; en production : hash fort via un vrai fournisseur d'auth.
INSERT INTO utilisateurs (id, magasin_id, role_id, nom, login, mot_de_passe_hash) VALUES
  ('0e000000-0000-4000-8000-000000000001', NULL,
     '0a000000-0000-4000-8000-000000000001','Administrateur','admin','1111'),
  ('0e000000-0000-4000-8000-000000000002',
     '0c000000-0000-4000-8000-000000000001',
     '0a000000-0000-4000-8000-000000000003','Awa (caissière Cocody)','awa','2222'),
  ('0e000000-0000-4000-8000-000000000003',
     '0c000000-0000-4000-8000-000000000001',
     '0a000000-0000-4000-8000-000000000002','Ben (responsable Cocody)','ben','3333'),
  ('0e000000-0000-4000-8000-000000000004',
     '0c000000-0000-4000-8000-000000000001',
     '0a000000-0000-4000-8000-000000000004','Koffi (technicien Cocody)','koffi','4444')
ON CONFLICT (id) DO UPDATE SET
  nom = EXCLUDED.nom, login = EXCLUDED.login,
  mot_de_passe_hash = EXCLUDED.mot_de_passe_hash, role_id = EXCLUDED.role_id;

-- Produits de démonstration (catalogue commun, §5.5)
INSERT INTO produits (id, nom, categorie, prix_achat, prix_vente, seuil_alerte) VALUES
  ('0d000000-0000-4000-8000-000000000001','Écran iPhone 11',      'Pièce',     35000, 55000, 2),
  ('0d000000-0000-4000-8000-000000000002','Batterie Samsung A10', 'Pièce',      8000, 15000, 3),
  ('0d000000-0000-4000-8000-000000000003','Chargeur USB-C 20W',   'Accessoire', 2500,  6000, 5),
  ('0d000000-0000-4000-8000-000000000004','Coque transparente',   'Accessoire',  800,  3000, 10),
  ('0d000000-0000-4000-8000-000000000005','Verre trempé',         'Accessoire',  500,  2500, 10)
ON CONFLICT (id) DO UPDATE SET
  nom = EXCLUDED.nom, prix_achat = EXCLUDED.prix_achat,
  prix_vente = EXCLUDED.prix_vente, seuil_alerte = EXCLUDED.seuil_alerte;

-- Stock initial du magasin Cocody pour ces produits.
INSERT INTO stocks_magasin (id, produit_id, magasin_id, quantite_disponible) VALUES
  ('0f000000-0000-4000-8000-000000000001','0d000000-0000-4000-8000-000000000001','0c000000-0000-4000-8000-000000000001', 3),
  ('0f000000-0000-4000-8000-000000000002','0d000000-0000-4000-8000-000000000002','0c000000-0000-4000-8000-000000000001', 5),
  ('0f000000-0000-4000-8000-000000000003','0d000000-0000-4000-8000-000000000003','0c000000-0000-4000-8000-000000000001', 12),
  ('0f000000-0000-4000-8000-000000000004','0d000000-0000-4000-8000-000000000004','0c000000-0000-4000-8000-000000000001', 20),
  ('0f000000-0000-4000-8000-000000000005','0d000000-0000-4000-8000-000000000005','0c000000-0000-4000-8000-000000000001', 25)
ON CONFLICT (id) DO UPDATE SET quantite_disponible = EXCLUDED.quantite_disponible;
