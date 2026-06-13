# =====================================================================
# BEJ Technologie — Sauvegarde de la base PostgreSQL
#
# pg_dump au format « custom » (compressé), fichier horodaté.
# Usage :  powershell -File backend\scripts\backup.ps1 [-OutDir <dossier>]
# Par défaut : backend\backups\bej_AAAAMMJJ_HHMMSS.dump
# =====================================================================
param([string]$OutDir = (Join-Path $PSScriptRoot "..\backups"))

$ErrorActionPreference = "Stop"
$bin = "C:\dev\pgsql\bin"
if (Test-Path "$PSScriptRoot\local.env.ps1") { . "$PSScriptRoot\local.env.ps1" }
if (-not $env:PGPASSWORD) { $env:PGPASSWORD = "postgres" }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$file = Join-Path $OutDir "bej_$stamp.dump"

& "$bin\pg_dump.exe" -U postgres -h localhost -p 5432 -d bej -F c -f $file
if ($LASTEXITCODE -eq 0 -and (Test-Path $file)) {
    $size = [Math]::Round((Get-Item $file).Length / 1KB, 1)
    Write-Host "Sauvegarde OK -> $file ($size Ko)"
} else {
    Write-Host "Échec de la sauvegarde (code $LASTEXITCODE)"
    exit 1
}
