# =====================================================================
# BEJ Technologie — Sauvegarde QUOTIDIENNE automatique (tâche planifiée)
#
# Planifie backup.ps1 tous les jours vers un dossier EXTERNE (USB / disque
# secondaire / dossier synchronisé cloud), via une tâche planifiée au niveau
# utilisateur (sans droits admin). Ne PAS sauvegarder sur C: (même disque que
# la base = perdu ensemble en cas de panne disque).
#
# Usage :
#   powershell -File backend\scripts\setup-scheduled-backup.ps1 -OutDir "E:\Sauvegardes\BEJ" [-Time 21:00]
#   powershell -File backend\scripts\setup-scheduled-backup.ps1 -Remove
# =====================================================================
param(
    [string]$OutDir,
    [string]$Time = "21:00",
    [switch]$Remove
)
$ErrorActionPreference = "Stop"
$taskName = "BEJ-Sauvegarde-Quotidienne"

if ($Remove) {
    schtasks /Delete /TN $taskName /F 2>$null
    Write-Host "Tache retiree : $taskName"
    return
}

if (-not $OutDir) {
    Write-Host 'Precisez -OutDir <dossier EXTERNE>. Exemple :'
    Write-Host '  ...\setup-scheduled-backup.ps1 -OutDir "E:\Sauvegardes\BEJ"'
    exit 1
}

$backup = (Resolve-Path (Join-Path $PSScriptRoot "backup.ps1")).Path
$action = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $backup + '" -OutDir "' + $OutDir + '"'

schtasks /Create /TN $taskName /TR $action /SC DAILY /ST $Time /RL LIMITED /F
if ($LASTEXITCODE -eq 0) {
    Write-Host "Sauvegarde quotidienne planifiee a $Time -> $OutDir"
    Write-Host "  Verifier :  schtasks /Query /TN $taskName /V /FO LIST"
    Write-Host "  Tester maintenant :  schtasks /Run /TN $taskName"
    Write-Host ""
    Write-Host "IMPORTANT : testez une RESTAURATION reelle une fois :"
    Write-Host "  powershell -File backend\scripts\restore.ps1 <fichier.dump>"
} else {
    Write-Host "Echec de la planification (code $LASTEXITCODE)."
    Write-Host "Repli : Planificateur de taches Windows > Creer une tache de base :"
    Write-Host "  Declencheur : quotidien a $Time"
    Write-Host "  Action      : $action"
    exit 1
}
