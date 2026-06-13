-- =====================================================================
-- BEJ Technologie — Catalogues recherchables (réparations)
--
-- Listes de référence enrichissables : modèles d'appareils et pannes
-- courantes. Recherche dynamique côté app + ajout à la volée.
-- Les tables sont créées vides ici ; le pré-remplissage se fait côté app
-- (bootstrap local) puis remonte par synchronisation (dédup tolérante).
-- À exécuter après 001..004.
-- =====================================================================

CREATE TABLE IF NOT EXISTS modeles_appareil (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    marque        text NOT NULL,
    modele        text NOT NULL,
    type          text,
    date_creation timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_modeles_appareil
    ON modeles_appareil (lower(marque), lower(modele));

CREATE TABLE IF NOT EXISTS pannes (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    libelle       text NOT NULL,
    date_creation timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_pannes ON pannes (lower(libelle));

ALTER TABLE modeles_appareil REPLICA IDENTITY FULL;
ALTER TABLE pannes REPLICA IDENTITY FULL;

DO $$ BEGIN
  ALTER PUBLICATION powersync ADD TABLE modeles_appareil;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  ALTER PUBLICATION powersync ADD TABLE pannes;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
