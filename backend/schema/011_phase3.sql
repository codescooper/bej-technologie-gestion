-- Phase 3 : FNE/DGI, Notifications SMS/WhatsApp, Campagnes fidélité
-- Application : .\backend\scripts\db.ps1 schema

-- ---- FNE/DGI ----
-- Config par magasin (1 ligne) — à remplir dans Paramètres > FNE
CREATE TABLE IF NOT EXISTS config_fne (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  magasin_id uuid NOT NULL REFERENCES magasins(id),
  actif boolean NOT NULL DEFAULT false,
  endpoint_url text NOT NULL DEFAULT '',
  merchant_id text NOT NULL DEFAULT '',
  api_key text NOT NULL DEFAULT '',
  numero_contrib text NOT NULL DEFAULT '',
  CONSTRAINT uq_config_fne_magasin UNIQUE(magasin_id)
);

-- Log des factures fiscales émises
CREATE TABLE IF NOT EXISTS factures_fne (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transaction_id text NOT NULL,
  magasin_id uuid NOT NULL REFERENCES magasins(id),
  numero_facture text,
  qr_code_fiscal text,
  statut text NOT NULL DEFAULT 'en_attente',
  date_emission timestamptz NOT NULL DEFAULT now(),
  erreur text,
  CONSTRAINT chk_factures_fne_statut CHECK (statut IN ('emise','en_attente','erreur'))
);
CREATE INDEX IF NOT EXISTS idx_factures_fne_transaction ON factures_fne(transaction_id);
CREATE INDEX IF NOT EXISTS idx_factures_fne_magasin ON factures_fne(magasin_id);

-- ---- Notifications SMS/WhatsApp ----
-- Config par magasin (provider Twilio)
CREATE TABLE IF NOT EXISTS config_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  magasin_id uuid NOT NULL REFERENCES magasins(id),
  actif boolean NOT NULL DEFAULT false,
  provider text NOT NULL DEFAULT 'twilio',
  account_sid text NOT NULL DEFAULT '',
  auth_token text NOT NULL DEFAULT '',
  from_number text NOT NULL DEFAULT '',
  utiliser_whatsapp boolean NOT NULL DEFAULT false,
  CONSTRAINT uq_config_notif_magasin UNIQUE(magasin_id),
  CONSTRAINT chk_config_notif_provider CHECK (provider IN ('twilio'))
);

-- Log des messages envoyés
CREATE TABLE IF NOT EXISTS notifications_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id text,
  magasin_id uuid NOT NULL REFERENCES magasins(id),
  canal text NOT NULL,
  numero text NOT NULL,
  message text NOT NULL,
  statut text NOT NULL DEFAULT 'en_attente',
  date_envoi timestamptz NOT NULL DEFAULT now(),
  erreur text,
  CONSTRAINT chk_notif_canal CHECK (canal IN ('sms','whatsapp')),
  CONSTRAINT chk_notif_statut CHECK (statut IN ('envoye','erreur','en_attente'))
);
CREATE INDEX IF NOT EXISTS idx_notifications_log_magasin ON notifications_log(magasin_id);

-- ---- Campagnes fidélité ----
-- Bonus de jetons sur une période (multiplicateur ≥ 1)
CREATE TABLE IF NOT EXISTS campagnes_fidelite (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  magasin_id uuid NOT NULL REFERENCES magasins(id),
  nom text NOT NULL,
  multiplicateur real NOT NULL DEFAULT 2.0,
  date_debut text NOT NULL,
  date_fin text NOT NULL,
  actif boolean NOT NULL DEFAULT true,
  description text
);
CREATE INDEX IF NOT EXISTS idx_campagnes_fidelite_magasin ON campagnes_fidelite(magasin_id);

-- REPLICA IDENTITY + publication PowerSync
ALTER TABLE config_fne REPLICA IDENTITY FULL;
ALTER TABLE factures_fne REPLICA IDENTITY FULL;
ALTER TABLE config_notifications REPLICA IDENTITY FULL;
ALTER TABLE notifications_log REPLICA IDENTITY FULL;
ALTER TABLE campagnes_fidelite REPLICA IDENTITY FULL;

DO $$
BEGIN
  BEGIN ALTER PUBLICATION powersync ADD TABLE config_fne;       EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION powersync ADD TABLE factures_fne;     EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION powersync ADD TABLE config_notifications; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION powersync ADD TABLE notifications_log; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER PUBLICATION powersync ADD TABLE campagnes_fidelite; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;
