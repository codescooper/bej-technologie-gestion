-- =====================================================================
-- BEJ Technologie — Préparation PostgreSQL pour PowerSync
--
-- PowerSync consomme le WAL logique de PostgreSQL. Il faut :
--   1. wal_level = logical          (postgresql.conf — voir backend/scripts)
--   2. REPLICA IDENTITY FULL        pour obtenir la ligne complète sur UPDATE/DELETE
--   3. une PUBLICATION couvrant les tables à synchroniser
--
-- À exécuter APRÈS 001_init.sql.
-- =====================================================================

-- 1. REPLICA IDENTITY FULL sur toutes les tables métier synchronisées.
ALTER TABLE magasins            REPLICA IDENTITY FULL;
ALTER TABLE roles               REPLICA IDENTITY FULL;
ALTER TABLE utilisateurs        REPLICA IDENTITY FULL;
ALTER TABLE clients             REPLICA IDENTITY FULL;
ALTER TABLE appareils           REPLICA IDENTITY FULL;
ALTER TABLE reparations         REPLICA IDENTITY FULL;
ALTER TABLE photos_appareil     REPLICA IDENTITY FULL;
ALTER TABLE produits            REPLICA IDENTITY FULL;
ALTER TABLE stocks_magasin      REPLICA IDENTITY FULL;
ALTER TABLE caisses             REPLICA IDENTITY FULL;
ALTER TABLE transactions        REPLICA IDENTITY FULL;
ALTER TABLE lignes_transaction  REPLICA IDENTITY FULL;
ALTER TABLE paiements           REPLICA IDENTITY FULL;
ALTER TABLE mouvements_stock    REPLICA IDENTITY FULL;
ALTER TABLE jeton_transactions  REPLICA IDENTITY FULL;
ALTER TABLE fournisseurs        REPLICA IDENTITY FULL;
ALTER TABLE achats_fournisseur  REPLICA IDENTITY FULL;
ALTER TABLE journal_audit       REPLICA IDENTITY FULL;

-- 2. Publication PowerSync. On nomme la publication "powersync" (valeur par défaut
--    attendue par le service). On liste explicitement les tables synchronisées vers
--    les clients (le journal d'audit peut rester serveur-only si souhaité ; ici inclus).
DROP PUBLICATION IF EXISTS powersync;
CREATE PUBLICATION powersync FOR TABLE
    magasins,
    roles,
    utilisateurs,
    clients,
    appareils,
    reparations,
    photos_appareil,
    produits,
    stocks_magasin,
    caisses,
    transactions,
    lignes_transaction,
    paiements,
    mouvements_stock,
    jeton_transactions,
    fournisseurs,
    achats_fournisseur,
    journal_audit;
