# =====================================================================
# BEJ Technologie — Relance de la pile locale (PostgreSQL + backend)
#
# Postgres est instable sur cette machine (interférence antivirus/disque sur
# `pgdata`). Ce script redémarre la base puis le backend de synchronisation,
# en une seule commande.
# Usage :  powershell -File backend\scripts\restart-stack.ps1
# =====================================================================
$ErrorActionPreference = "Continue"
$pgctl = "C:\dev\pgsql\bin\pg_ctl.exe"
$psql  = "C:\dev\pgsql\bin\psql.exe"
$data  = "C:\dev\pgdata"
if (Test-Path "$PSScriptRoot\local.env.ps1") { . "$PSScriptRoot\local.env.ps1" }
if (-not $env:PGPASSWORD) { $env:PGPASSWORD = "postgres" }
$serverDir = Join-Path $PSScriptRoot "..\server"

Write-Host "1/3 PostgreSQL..."
& $psql -U postgres -h localhost -p 5432 -d bej -tAc "SELECT 1" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    & $pgctl start -D $data -l "$data\server.log" -w -t 90 | Out-Null
}
$ok = $false
for ($i = 0; $i -lt 30; $i++) {
    & $psql -U postgres -h localhost -p 5432 -d bej -tAc "SELECT 1" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $ok = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $ok) { Write-Host "  Postgres ne repond pas — voir $data\server.log"; exit 1 }
Write-Host "  Postgres OK."

Write-Host "2/3 Backend de synchronisation..."
$c = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if ($c) { $c.OwningProcess | Select-Object -Unique | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue } }
Start-Sleep -Seconds 1
Start-Process -FilePath "C:\dev\flutter\bin\dart.bat" -ArgumentList "run", "bin/server.dart" -WorkingDirectory $serverDir -WindowStyle Hidden

Write-Host "3/3 Verification..."
$ok = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Seconds 3
    try {
        $h = (Invoke-WebRequest -Uri "http://localhost:8080/health" -TimeoutSec 3 -UseBasicParsing).Content
        if ($h -match '"status":"ok"') { Write-Host "  Backend OK : $h"; $ok = $true; break }
    } catch {}
}
if (-not $ok) { Write-Host "  Backend pas encore pret (reessayer)."; exit 1 }
Write-Host "Pile BEJ relancee. Lancer l'app : cd app ; flutter run -d chrome --web-port=5000"
