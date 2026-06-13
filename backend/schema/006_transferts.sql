-- =====================================================================
-- BEJ Technologie — Transferts inter-magasins (Phase 2, §2.5)
--
-- Mécanique en deux temps :
--   1. Le magasin SOURCE crée un transfert -> stock en transit
--      (quantite_disponible source décrémentée, statut 'en_transit').
--   2. Le magasin DESTINATAIRE confirme la réception -> stock ajouté
--      (quantite_disponible dest incrémentée, statut 'recu').
-- Aucun magasin ne modifie directement le stock d'un autre.
-- À exécuter après 001..005.
-- =====================================================================

CREATE TABLE IF NOT EXISTS transferts (
    id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    produit_id           uuid NOT NULL REFERENCES produits(id),
    magasin_source_id    uuid NOT NULL REFERENCES magasins(id),
    magasin_dest_id      uuid NOT NULL REFERENCES magasins(id),
    quantite             integer NOT NULL,
    statut               text NOT NULL DEFAULT 'en_transit', -- en_transit | recu | annule
    utilisateur_source_id uuid REFERENCES utilisateurs(id),
    utilisateur_dest_id  uuid REFERENCES utilisateurs(id),
    date_creation        timestamptz NOT NULL DEFAULT now(),
    date_reception       timestamptz,
    CONSTRAINT chk_transferts_statut
        CHECK (statut IN ('en_transit','recu','annule'))
);

CREATE INDEX IF NOT EXISTS idx_transferts_source ON transferts(magasin_source_id);
CREATE INDEX IF NOT EXISTS idx_transferts_dest   ON transferts(magasin_dest_id);
CREATE INDEX IF NOT EXISTS idx_transferts_statut ON transferts(statut);

ALTER TABLE transferts REPLICA IDENTITY FULL;

DO $$ BEGIN
  ALTER PUBLICATION powersync ADD TABLE transferts;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
