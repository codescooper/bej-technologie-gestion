-- =====================================================================
-- BEJ Technologie — Inventaires physiques (Finitions Phase 2+)
--
-- Comptage physique du stock d'un magasin -> ajustement tracé.
--   - inventaires      : entête (magasin, statut en_cours|valide|annule).
--   - lignes_inventaire: une ligne par produit (théorique vs compté, écart).
-- À la validation, le stock disponible est aligné sur le comptage et un
-- MouvementStock « inventaire » est tracé pour chaque écart.
-- À exécuter après 001..006.
-- =====================================================================

CREATE TABLE IF NOT EXISTS inventaires (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    magasin_id      uuid NOT NULL REFERENCES magasins(id),
    utilisateur_id  uuid REFERENCES utilisateurs(id),
    statut          text NOT NULL DEFAULT 'en_cours', -- en_cours | valide | annule
    note            text,
    date_creation   timestamptz NOT NULL DEFAULT now(),
    date_validation timestamptz,
    CONSTRAINT chk_inventaires_statut
        CHECK (statut IN ('en_cours','valide','annule'))
);

CREATE TABLE IF NOT EXISTS lignes_inventaire (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    inventaire_id      uuid NOT NULL REFERENCES inventaires(id),
    produit_id         uuid NOT NULL REFERENCES produits(id),
    quantite_theorique integer NOT NULL DEFAULT 0,
    quantite_comptee   integer,
    ecart              integer NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_inventaires_magasin   ON inventaires(magasin_id);
CREATE INDEX IF NOT EXISTS idx_lignes_inventaire_inv ON lignes_inventaire(inventaire_id);

ALTER TABLE inventaires       REPLICA IDENTITY FULL;
ALTER TABLE lignes_inventaire REPLICA IDENTITY FULL;

DO $$ BEGIN
  ALTER PUBLICATION powersync ADD TABLE inventaires;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION powersync ADD TABLE lignes_inventaire;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
