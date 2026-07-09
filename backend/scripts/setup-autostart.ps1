# =====================================================================
# BEJ Technologie — Démarrage automatique de la pile (PostgreSQL + backend)
#
# Installe le lancement de restart-stack.ps1 à CHAQUE ouverture de session
# Windows, SANS droits admin (via le dossier « Démarrage » de l'utilisateur).
# Après un reboot / une coupure de courant, la boutique redémarre seule.
#
# Usage :
#   powershell -File backend\scripts\setup-autostart.ps1            # installe
#   powershell -File backend\scripts\setup-autostart.ps1 -Remove    # retire
# =====================================================================
param([switch]$Remove)
$ErrorActionPreference = "Stop"

$startup  = [Environment]::GetFolderPath('Startup')
$launcher = Join-Path $startup "BEJ-Stack.cmd"
$restart  = (Resolve-Path (Join-Path $PSScriptRoot "restart-stack.ps1")).Path

if ($Remove) {
    if (Test-Path $launcher) {
        Remove-Item $launcher -Force
        Write-Host "Auto-démarrage BEJ retiré ($launcher)."
    } else {
        Write-Host "Aucun auto-démarrage BEJ installé."
    }
    return
}

# .cmd minimal : lance restart-stack.ps1 en fenêtre cachée à l'ouverture de session.
$cmd = "@echo off`r`n" +
       "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$restart`"`r`n"
Set-Content -Path $launcher -Value $cmd -Encoding ascii

Write-Host "Auto-démarrage installé : $launcher"
Write-Host "  -> à chaque ouverture de session, la pile BEJ démarre automatiquement."
Write-Host "  Tester maintenant (sans rebooter) :  powershell -File `"$restart`""
