# =====================================================================
# BEJ Technologie — Gestion du PostgreSQL portable (sans service, sans admin)
#
# Usage :
#   .\db.ps1 init      # initialise le cluster + configure wal_level=logical
#   .\db.ps1 start     # démarre le serveur (loopback, port 5432)
#   .\db.ps1 stop      # arrête le serveur
#   .\db.ps1 status    # état du serveur
#   .\db.ps1 schema    # applique 001/002/003 sur la base 'bej'
#   .\db.ps1 psql      # ouvre un shell psql sur 'bej'
#
# Tout est local : binaires dans C:\dev\pgsql, données dans C:\dev\pgdata.
# Superutilisateur 'postgres' / mot de passe défini ci-dessous (dev only).
# =====================================================================

param([Parameter(Mandatory=$true)][string]$cmd)

$ErrorActionPreference = "Stop"
$PG    = "C:\dev\pgsql\bin"
$DATA  = "C:\dev\pgdata"
$PORT  = 5432
$APPDB = "bej"
$LOG   = "C:\dev\pgdata\server.log"
$SCHEMA_DIR = Join-Path $PSScriptRoot "..\schema"

# Mot de passe Postgres local : depuis local.env.ps1 (non versionné) ou la
# variable PGPASSWORD ; défaut conventionnel sinon. (DEV — à changer en prod.)
if (Test-Path "$PSScriptRoot\local.env.ps1") { . "$PSScriptRoot\local.env.ps1" }
$DBPWD = if ($env:PGPASSWORD) { $env:PGPASSWORD } else { "postgres" }
$env:PGPASSWORD = $DBPWD

switch ($cmd) {

  "init" {
    if (Test-Path (Join-Path $DATA "PG_VERSION")) { Write-Host "Cluster déjà initialisé."; break }
    New-Item -ItemType Directory -Force -Path $DATA | Out-Null
    $pwfile = Join-Path $env:TEMP "pgpw.txt"
    Set-Content -Path $pwfile -Value $DBPWD -NoNewline -Encoding ascii
    & "$PG\initdb.exe" -D $DATA -U postgres -A scram-sha-256 --pwfile=$pwfile --encoding=UTF8 --locale=C
    Remove-Item $pwfile -Force
    # Active la réplication logique requise par PowerSync.
    Add-Content -Path (Join-Path $DATA "postgresql.conf") -Value @"

# --- BEJ / PowerSync ---
wal_level = logical
max_wal_senders = 10
max_replication_slots = 10
listen_addresses = 'localhost'
port = $PORT
"@
    Write-Host "Cluster initialisé + wal_level=logical."
  }

  "start" {
    & "$PG\pg_ctl.exe" -D $DATA -l $LOG -o "-p $PORT" start
  }

  "stop" {
    & "$PG\pg_ctl.exe" -D $DATA stop -m fast
  }

  "status" {
    & "$PG\pg_ctl.exe" -D $DATA status
  }

  "schema" {
    # Crée la base applicative si absente puis applique les migrations.
    $exists = & "$PG\psql.exe" -U postgres -h localhost -p $PORT -tAc "SELECT 1 FROM pg_database WHERE datname='$APPDB'"
    if ($exists -ne "1") { & "$PG\createdb.exe" -U postgres -h localhost -p $PORT $APPDB; Write-Host "Base '$APPDB' créée." }
    foreach ($f in @("001_init.sql","002_powersync.sql","003_seed.sql","004_avoirs.sql","005_catalogues.sql","006_transferts.sql","007_inventaires.sql","008_pins.sql","009_verrou.sql")) {
      $path = Join-Path $SCHEMA_DIR $f
      Write-Host "==> $f"
      & "$PG\psql.exe" -U postgres -h localhost -p $PORT -d $APPDB -v ON_ERROR_STOP=1 -f $path
    }
    Write-Host "Schéma appliqué sur '$APPDB'."
  }

  "psql" {
    & "$PG\psql.exe" -U postgres -h localhost -p $PORT -d $APPDB
  }

  default { Write-Host "Commande inconnue: $cmd (init|start|stop|status|schema|psql)" }
}
