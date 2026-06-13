# Sauvegarde & restauration — base BEJ (PostgreSQL)

La base `bej` (PostgreSQL local) est la **source de vérité serveur**. Les
sauvegardes utilisent `pg_dump` au format *custom* (compressé, restaurable
sélectivement).

## Sauvegarder

```powershell
powershell -File backend\scripts\backup.ps1
# -> backend\backups\bej_AAAAMMJJ_HHMMSS.dump
```

Optionnel : choisir le dossier de destination.

```powershell
powershell -File backend\scripts\backup.ps1 -OutDir D:\Sauvegardes\BEJ
```

> Conseil : planifier une sauvegarde quotidienne (Planificateur de tâches
> Windows) et **copier les `.dump` hors de la machine** (clé USB / cloud).

## Restaurer

```powershell
powershell -File backend\scripts\restore.ps1 -File backend\backups\bej_20260609_141500.dump
```

⚠️ La restauration **écrase** les données actuelles par celles de la sauvegarde
(`--clean --if-exists`). En cas de doute, faire d'abord un `backup.ps1`.

Après une restauration, **redémarrer le backend de synchronisation** pour qu'il
reprenne une connexion fraîche :

```powershell
# dans backend\server
dart run bin/server.dart
```

## Notes

- Pré-requis : PostgreSQL démarré (`C:\dev\pgsql\bin`), variable `PGPASSWORD`
  gérée par les scripts.
- Le format custom permet aussi une restauration partielle (`pg_restore -t <table>`).
- Les données *locales* de chaque poste (PowerSync/OPFS) se reconstruisent depuis
  le serveur ; la sauvegarde serveur est donc le filet de sécurité principal.
