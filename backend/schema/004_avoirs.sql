-- =====================================================================
-- BEJ Technologie — Retours & Avoirs (§5.6)
--
-- Un retour génère un AVOIR (crédit interne) au nom du client, réutilisable
-- comme moyen de paiement lors d'un achat ultérieur.
-- À exécuter après 001/002/003.
-- =====================================================================

-- Montant d'avoir consommé sur une transaction (parallèle à jetons_utilises).
ALTER TABLE transactions
  ADD COLUMN IF NOT EXISTS avoir_utilise numeric(14,2) NOT NULL DEFAULT 0;

-- Table des avoirs.
CREATE TABLE IF NOT EXISTS avoirs (
    id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id                  uuid NOT NULL REFERENCES clients(id),
    magasin_id                 uuid REFERENCES magasins(id),
    montant_initial            numeric(14,2) NOT NULL,
    montant_restant            numeric(14,2) NOT NULL,
    transaction_retour_id      uuid REFERENCES transactions(id),  -- le retour qui l'a créé
    transaction_utilisation_id uuid REFERENCES transactions(id),  -- la vente où il a été dépensé
    statut                     text NOT NULL DEFAULT 'actif',     -- actif | utilise
    date_creation              timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_avoirs_client ON avoirs(client_id);
CREATE INDEX IF NOT EXISTS idx_avoirs_statut ON avoirs(statut);

-- PowerSync : réplication logique de la nouvelle table.
ALTER TABLE avoirs REPLICA IDENTITY FULL;

DO $$ BEGIN
  ALTER PUBLICATION powersync ADD TABLE avoirs;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
