-- =====================================================================
-- BEJ Technologie — Application de gestion
-- Schéma PostgreSQL — Phase 0 / socle (couvre le modèle §7 du cahier des charges v1.1)
--
-- Conventions :
--   * Noms de tables au pluriel, snake_case (évite aussi le mot réservé "transaction").
--   * Clé primaire = uuid (généré côté client offline ET côté serveur).
--   * timestamptz partout (UTC), montants en NUMERIC (FCFA = entier, mais NUMERIC
--     reste sûr pour les remises/calculs). 1 FCFA n'a pas de centime → scale 2 gardé
--     par prudence pour les éventuels arrondis de jetons/remises.
--   * Compatible PowerSync : chaque table a une PK simple + REPLICA IDENTITY FULL
--     (voir 002_powersync.sql) et entre dans la publication logique.
--
-- Idempotent autant que possible (IF NOT EXISTS) pour réexécution en dev.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()

-- ---------------------------------------------------------------------
-- Référentiel : magasins, rôles, utilisateurs
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS magasins (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    nom           text        NOT NULL,
    code          text        UNIQUE,                 -- ex: COCODY, YOP, MARCORY
    adresse       text,
    telephone     text,
    actif         boolean     NOT NULL DEFAULT true,
    date_creation timestamptz NOT NULL DEFAULT now()
);

-- Rôles MVP (§6) : admin, responsable, caissier, technicien.
CREATE TABLE IF NOT EXISTS roles (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code        text UNIQUE NOT NULL,                 -- admin | responsable | caissier | technicien
    libelle     text NOT NULL
);

CREATE TABLE IF NOT EXISTS utilisateurs (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    magasin_id     uuid REFERENCES magasins(id),      -- magasin de rattachement (null = admin global)
    role_id        uuid NOT NULL REFERENCES roles(id),
    nom            text NOT NULL,
    login          text UNIQUE NOT NULL,
    -- L'authentification réelle est portée par le fournisseur d'auth (ex: Supabase Auth).
    -- On garde un hash local optionnel pour le mode 100% offline / poste autonome.
    mot_de_passe_hash text,
    actif          boolean NOT NULL DEFAULT true,
    date_creation  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_utilisateurs_magasin ON utilisateurs(magasin_id);

-- ---------------------------------------------------------------------
-- CRM client + appareils (déduplication §2.6)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS clients (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    nom                 text NOT NULL,
    telephone           text,
    telephone_normalise text,                         -- clé naturelle de dédup (format intl, sans séparateurs)
    whatsapp            text,
    email               text,
    adresse             text,
    solde_jetons        integer NOT NULL DEFAULT 0,   -- dérivé des jeton_transactions, matérialisé pour lecture rapide
    -- Traçabilité de la fusion serveur (§2.6) : si cette fiche a été absorbée,
    -- fusionne_vers pointe vers l'UUID conservé (le plus ancien).
    fusionne_vers       uuid REFERENCES clients(id),
    date_creation       timestamptz NOT NULL DEFAULT now()
);

-- Dédup : un même téléphone normalisé ne doit exister qu'une fois parmi les fiches actives.
-- Index partiel (les fiches fusionnées sont exclues de l'unicité).
CREATE UNIQUE INDEX IF NOT EXISTS uq_clients_tel_norm
    ON clients(telephone_normalise)
    WHERE telephone_normalise IS NOT NULL AND fusionne_vers IS NULL;
CREATE INDEX IF NOT EXISTS idx_clients_tel_norm ON clients(telephone_normalise);

CREATE TABLE IF NOT EXISTS appareils (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id     uuid NOT NULL REFERENCES clients(id),
    type          text,                               -- smartphone, tablette, PC...
    marque        text,
    modele        text,
    imei          text,                               -- clé naturelle de dédup (sinon numero_serie)
    numero_serie  text,
    notes         text,
    fusionne_vers uuid REFERENCES appareils(id),
    date_creation timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_appareils_imei
    ON appareils(imei)
    WHERE imei IS NOT NULL AND fusionne_vers IS NULL;
CREATE INDEX IF NOT EXISTS idx_appareils_client ON appareils(client_id);

-- ---------------------------------------------------------------------
-- Réparations + photos (§5.2 / §5.3)
-- ---------------------------------------------------------------------

-- Statuts §5.2 : recu, diagnostic, attente_validation, attente_piece,
--                en_reparation, pret, livre, annule.
CREATE TABLE IF NOT EXISTS reparations (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    appareil_id         uuid NOT NULL REFERENCES appareils(id),
    magasin_id          uuid NOT NULL REFERENCES magasins(id),
    technicien_id       uuid REFERENCES utilisateurs(id),
    probleme            text,                          -- problème déclaré
    etat_visuel         text,                          -- état visuel à la réception
    diagnostic          text,
    devis               numeric(14,2),                 -- montant du devis proposé
    statut              text NOT NULL DEFAULT 'recu',
    montant_main_oeuvre numeric(14,2) NOT NULL DEFAULT 0,
    montant_pieces      numeric(14,2) NOT NULL DEFAULT 0,  -- valorisé via mouvements_stock (reparation_id)
    total               numeric(14,2) NOT NULL DEFAULT 0,
    signature_depot     text,                          -- chemin/blob de la signature au dépôt
    signature_retrait   text,
    date_creation       timestamptz NOT NULL DEFAULT now(),
    date_cloture        timestamptz
);

CREATE INDEX IF NOT EXISTS idx_reparations_magasin ON reparations(magasin_id);
CREATE INDEX IF NOT EXISTS idx_reparations_statut  ON reparations(statut);
CREATE INDEX IF NOT EXISTS idx_reparations_appareil ON reparations(appareil_id);

-- Photos obligatoires/optionnelles à la réception (§5.3). Stockées localement
-- puis synchronisées (statut_sync).
CREATE TABLE IF NOT EXISTS photos_appareil (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reparation_id uuid NOT NULL REFERENCES reparations(id),
    type_photo    text,                                -- face_avant, face_arriere, cote, ecran, defaut...
    fichier_local text,
    url_sync      text,
    statut_sync   text NOT NULL DEFAULT 'local',       -- local | uploading | synced
    date_creation timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_photos_reparation ON photos_appareil(reparation_id);

-- ---------------------------------------------------------------------
-- Catalogue produit + stock par magasin (§5.5 / §5.7 / §2.4)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS produits (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    nom           text NOT NULL,
    categorie     text,
    code_barres   text,
    qr_code       text,
    prix_achat    numeric(14,2) NOT NULL DEFAULT 0,
    prix_vente    numeric(14,2) NOT NULL DEFAULT 0,
    seuil_alerte  integer NOT NULL DEFAULT 0,
    actif         boolean NOT NULL DEFAULT true,
    date_creation timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_produits_code_barres ON produits(code_barres);

-- Stock possédé par magasin (§2.4) : chaque magasin ne modifie que sa ligne.
CREATE TABLE IF NOT EXISTS stocks_magasin (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    produit_id           uuid NOT NULL REFERENCES produits(id),
    magasin_id           uuid NOT NULL REFERENCES magasins(id),
    quantite_disponible  integer NOT NULL DEFAULT 0,
    quantite_en_transit  integer NOT NULL DEFAULT 0,   -- pour les transferts Phase 2 (§2.5)
    derniere_sync        timestamptz,
    UNIQUE (produit_id, magasin_id)
);

CREATE INDEX IF NOT EXISTS idx_stocks_magasin ON stocks_magasin(magasin_id);

-- ---------------------------------------------------------------------
-- Caisse (§5.4)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS caisses (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    magasin_id            uuid NOT NULL REFERENCES magasins(id),
    utilisateur_id        uuid NOT NULL REFERENCES utilisateurs(id),  -- qui a ouvert
    ouverture             timestamptz NOT NULL DEFAULT now(),
    fermeture             timestamptz,
    fond_initial          numeric(14,2) NOT NULL DEFAULT 0,
    -- Compteurs théoriques dérivés des paiements (§5.4) — matérialisés à la clôture.
    cash_theorique        numeric(14,2) NOT NULL DEFAULT 0,
    cash_reel             numeric(14,2),
    mobile_money_theorique numeric(14,2) NOT NULL DEFAULT 0,
    mobile_money_reel     numeric(14,2),
    ecart                 numeric(14,2),
    statut                text NOT NULL DEFAULT 'ouverte'   -- ouverte | cloturee
);

CREATE INDEX IF NOT EXISTS idx_caisses_magasin ON caisses(magasin_id);
-- Au plus une caisse ouverte par magasin à la fois.
CREATE UNIQUE INDEX IF NOT EXISTS uq_caisse_ouverte_par_magasin
    ON caisses(magasin_id) WHERE statut = 'ouverte';

-- ---------------------------------------------------------------------
-- Transaction encaissée unifiée (§7 — remplace Vente)
--   type : vente | reparation | mixte | retour
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS transactions (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    magasin_id      uuid NOT NULL REFERENCES magasins(id),
    caisse_id       uuid NOT NULL REFERENCES caisses(id),
    client_id       uuid REFERENCES clients(id),          -- nullable : client de passage
    utilisateur_id  uuid NOT NULL REFERENCES utilisateurs(id),
    type            text NOT NULL,                         -- vente | reparation | mixte | retour
    reparation_id   uuid REFERENCES reparations(id),       -- si type reparation/mixte
    transaction_origine_id uuid REFERENCES transactions(id), -- si type retour : transaction d'origine (§5.6)
    total           numeric(14,2) NOT NULL DEFAULT 0,      -- calculé
    remise_globale  numeric(14,2) NOT NULL DEFAULT 0,
    jetons_utilises integer NOT NULL DEFAULT 0,
    jetons_gagnes   integer NOT NULL DEFAULT 0,
    statut_sync     text NOT NULL DEFAULT 'local',
    date            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_transactions_type
        CHECK (type IN ('vente','reparation','mixte','retour'))
);

CREATE INDEX IF NOT EXISTS idx_transactions_caisse  ON transactions(caisse_id);
CREATE INDEX IF NOT EXISTS idx_transactions_magasin ON transactions(magasin_id);
CREATE INDEX IF NOT EXISTS idx_transactions_client  ON transactions(client_id);
CREATE INDEX IF NOT EXISTS idx_transactions_repar   ON transactions(reparation_id);

-- Lignes produit d'une transaction (§7). La part réparation vient de reparation_id.
CREATE TABLE IF NOT EXISTS lignes_transaction (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id uuid NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    produit_id     uuid NOT NULL REFERENCES produits(id),
    quantite       integer NOT NULL,                       -- négatif possible pour un retour
    prix_unitaire  numeric(14,2) NOT NULL,                 -- prix appliqué = dernière synchro (§5.5)
    remise_ligne   numeric(14,2) NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_lignes_transaction ON lignes_transaction(transaction_id);

-- Paiements (§7) : une transaction = 1..n paiements (paiement mixte).
-- Un retour porte des montants négatifs.
CREATE TABLE IF NOT EXISTS paiements (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id uuid NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
    methode        text NOT NULL,                          -- cash | wave | orange_money | mtn_momo
    montant        numeric(14,2) NOT NULL,
    date           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_paiements_methode
        CHECK (methode IN ('cash','wave','orange_money','mtn_momo'))
);

CREATE INDEX IF NOT EXISTS idx_paiements_transaction ON paiements(transaction_id);
CREATE INDEX IF NOT EXISTS idx_paiements_methode ON paiements(methode);

-- ---------------------------------------------------------------------
-- Mouvements de stock (§5.7) — chaque mouvement porte SA CAUSE (§ corrigé)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS mouvements_stock (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    produit_id     uuid NOT NULL REFERENCES produits(id),
    magasin_id     uuid NOT NULL REFERENCES magasins(id),
    type           text NOT NULL,                          -- entree | sortie | ajustement | consommation | retour | transfert
    quantite       integer NOT NULL,                       -- signé
    motif          text,
    utilisateur_id uuid REFERENCES utilisateurs(id),
    -- Cause du mouvement : au plus l'une des deux est renseignée.
    transaction_id uuid REFERENCES transactions(id),
    reparation_id  uuid REFERENCES reparations(id),
    date           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mouvements_produit_magasin ON mouvements_stock(produit_id, magasin_id);
CREATE INDEX IF NOT EXISTS idx_mouvements_transaction ON mouvements_stock(transaction_id);
CREATE INDEX IF NOT EXISTS idx_mouvements_reparation ON mouvements_stock(reparation_id);

-- ---------------------------------------------------------------------
-- Jetons de fidélité (§5.9) — historique non supprimable, solde = somme
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS jeton_transactions (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id      uuid NOT NULL REFERENCES clients(id),
    transaction_id uuid REFERENCES transactions(id),       -- (ex vente_id) cause du gain/dépense
    type           text NOT NULL,                          -- gain | depense | ajustement | annulation
    montant        integer NOT NULL,                       -- signé (gain +, dépense -)
    motif          text,
    utilisateur_id uuid REFERENCES utilisateurs(id),
    date           timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chk_jetons_type
        CHECK (type IN ('gain','depense','ajustement','annulation'))
);

CREATE INDEX IF NOT EXISTS idx_jetons_client ON jeton_transactions(client_id);
CREATE INDEX IF NOT EXISTS idx_jetons_transaction ON jeton_transactions(transaction_id);

-- ---------------------------------------------------------------------
-- Fournisseurs (§5.8 — MVP simple)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS fournisseurs (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    nom           text NOT NULL,
    contact       text,
    telephone     text,
    dette         numeric(14,2) NOT NULL DEFAULT 0,
    date_creation timestamptz NOT NULL DEFAULT now()
);

-- Achats fournisseurs (historique + paiements). Léger, MVP.
CREATE TABLE IF NOT EXISTS achats_fournisseur (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    fournisseur_id uuid NOT NULL REFERENCES fournisseurs(id),
    magasin_id     uuid REFERENCES magasins(id),
    montant_total  numeric(14,2) NOT NULL DEFAULT 0,
    montant_paye   numeric(14,2) NOT NULL DEFAULT 0,
    date           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_achats_fournisseur ON achats_fournisseur(fournisseur_id);

-- ---------------------------------------------------------------------
-- Journal d'audit métier (§9) — encaissement, annulation, retour, remise,
-- correction stock, clôture caisse, modif réparation, jetons, FUSION dédup.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS journal_audit (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    utilisateur_id uuid REFERENCES utilisateurs(id),
    magasin_id     uuid REFERENCES magasins(id),
    action         text NOT NULL,                          -- ex: fusion_client, cloture_caisse, retour, remise...
    entite         text,                                   -- table concernée
    entite_id      uuid,
    details        jsonb,                                  -- payload libre (avant/après, écart, etc.)
    date           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_journal_entite ON journal_audit(entite, entite_id);
CREATE INDEX IF NOT EXISTS idx_journal_date ON journal_audit(date);
