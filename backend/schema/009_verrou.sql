-- =====================================================================
-- BEJ Technologie — Durcissement : verrouillage anti-force-brute du PIN (§6)
--
-- Après N échecs de PIN, le compte est verrouillé pour quelques minutes
-- (vraie défense vu le petit espace d'un code à 4 chiffres). L'état est porté
-- par l'utilisateur :
--   - tentatives_echouees : compteur d'échecs consécutifs
--   - verrou_jusqu_a       : instant jusqu'auquel la connexion est bloquée
-- À exécuter après 001..008.
-- =====================================================================

ALTER TABLE utilisateurs
  ADD COLUMN IF NOT EXISTS tentatives_echouees integer NOT NULL DEFAULT 0;

ALTER TABLE utilisateurs
  ADD COLUMN IF NOT EXISTS verrou_jusqu_a timestamptz;
