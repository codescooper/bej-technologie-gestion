# =====================================================================
# BEJ Technologie — Restauration de la base PostgreSQL
#
# Restaure une sauvegarde pg_dump (format custom) dans la base « bej ».
# Usage :  powershell -File backend\scripts\restore.ps1 -File <chemin .dump>
#
# ATTENTION : remplace les données actuelles (DROP/CREATE des objets
# présents dans la sauvegarde). Faites une sauvegarde avant si besoin.
# =====================================================================
param([Parameter(Mandatory = $true)][string]$File)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $File)) {
    Write-Host "Fichier introuvable : $File"
    exit 1
}
$bin = "C:\dev\pgsql\bin"
if (Test-Path "$PSScriptRoot\local.env.ps1") { . "$PSScriptRoot\local.env.ps1" }
if (-not $env:PGPASSWORD) { $env:PGPASSWORD = "postgres" }

& "$bin\pg_restore.exe" -U postgres -h localhost -p 5432 -d bej `
    --clean --if-exists --no-owner $File
if ($LASTEXITCODE -eq 0) {
    Write-Host "Restauration terminée depuis $File"
} else {
    Write-Host "Restauration terminée avec des avertissements (code $LASTEXITCODE)"
}
