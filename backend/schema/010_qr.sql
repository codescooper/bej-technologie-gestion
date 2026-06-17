-- =====================================================================
-- BEJ Technologie — QR centralisé (010)
--
-- Centralise les opérations autour de la lecture de QR codes :
--   - appareils.qr_code : étiquette QR (sticker du pool) collée sur l'appareil
--     en réparation. Permet, au scan, de retrouver l'appareil + son propriétaire.
--   - etiquettes_qr     : REGISTRE du pool de stickers QR pré-imprimés
--     (réparation surtout ; 'vente' permis pour traçabilité). Un sticker est
--     'libre' tant qu'il n'est pas apposé, puis 'utilise' et lié à un appareil.
--
-- La VENTE réutilise produits.qr_code (déjà présent depuis 001) : payload
-- `BEJ-P-<produit.id>`. Les stickers réparation portent `BEJ-R-<…>`.
--
-- À exécuter après 001..009.
-- IMPORTANT : redémarrer le backend après migration — server.dart _loadSchema()
-- lit information_schema au démarrage (sinon la nouvelle table est inconnue).
-- =====================================================================

-- 1) Appareils : colonne QR + index (résolution rapide au scan).
ALTER TABLE appareils ADD COLUMN IF NOT EXISTS qr_code text;
CREATE INDEX IF NOT EXISTS idx_appareils_qr ON appareils(qr_code);

-- 2) Pool d'étiquettes QR (registre).
CREATE TABLE IF NOT EXISTS etiquettes_qr (
    id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code             text NOT NULL,                       -- payload QR (BEJ-R-…)
    type             text NOT NULL DEFAULT 'reparation',  -- reparation | vente
    statut           text NOT NULL DEFAULT 'libre',       -- libre | utilise
    magasin_id       uuid REFERENCES magasins(id),
    appareil_id      uuid REFERENCES appareils(id),       -- null tant que 'libre'
    date_creation    timestamptz NOT NULL DEFAULT now(),
    date_utilisation timestamptz,
    CONSTRAINT uq_etiquettes_qr_code   UNIQUE (code),
    CONSTRAINT chk_etiquettes_qr_type   CHECK (type   IN ('reparation','vente')),
    CONSTRAINT chk_etiquettes_qr_statut CHECK (statut IN ('libre','utilise'))
);

CREATE INDEX IF NOT EXISTS idx_etiquettes_qr_magasin  ON etiquettes_qr(magasin_id);
CREATE INDEX IF NOT EXISTS idx_etiquettes_qr_appareil ON etiquettes_qr(appareil_id);

ALTER TABLE etiquettes_qr REPLICA IDENTITY FULL;

DO $$ BEGIN
  ALTER PUBLICATION powersync ADD TABLE etiquettes_qr;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
