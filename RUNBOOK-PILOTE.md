# RUNBOOK — Pilote BEJ Technologie (mono-poste, une boutique)

> Fiche d'exploitation 1 page pour le poste de la boutique. Cible : **1 caisse,
> tout en local (localhost)**. Pas d'accès réseau tant que TLS + authentification
> ne sont pas en place (voir le plan multi-boutiques dans Obsidian).

## 0. Prérequis machine (à faire UNE fois)
- **Poste dédié de préférence.** BEJ utilise le port **5432** (PostgreSQL) et **8080**
  (backend). **Aucun autre PostgreSQL ni autre serveur** ne doit occuper ces ports.
  Vérifier : `Get-NetTCPConnection -LocalPort 5432,8080 -State Listen`.
- **Antivirus 360 Total Security — INDISPENSABLE :**
  1. **Exclure le dossier** `C:\dev\pgdata` de l'analyse en temps réel.
  2. **Autoriser dans le pare-feu** `C:\dev\pgsql\bin\postgres.exe` et
     `C:\dev\flutter\bin\dart.exe`.
  > Sans ça, PostgreSQL devient instable, se corrompt, ou n'arrive pas à ouvrir
  > son port (« Permission denied » au démarrage). **C'est la cause n°1 de panne.**
- **Changer les PIN par défaut** (1111 / 2222 / 3333 / 4444) avant remise au client
  (regénérer les hachages : `app/tool/gen_pin_hashes.dart`).
- **Installer l'auto-démarrage + la sauvegarde** (voir §4).

## 1. Démarrer la boutique
```
powershell -File backend\scripts\restart-stack.ps1
```
Puis l'application : `cd app ; flutter run -d chrome --web-port=5000`
(ou l'app web déjà servie). Comptes : voir le gérant (PIN modifiés).

## 2. Vérifier que tout va bien (30 s)
Ouvrir **http://localhost:8080/health** :
- `{"status":"ok", ...}` → **tout va bien.**
- `{"status":"db_indisponible"}` (**503**) ou **aucune réponse** → **PostgreSQL est
  tombé** → relancer : `powershell -File backend\scripts\restart-stack.ps1`.

> L'application **continue de fonctionner hors-ligne** même si le backend est down :
> les ventes/réparations sont **conservées localement** et remonteront à la reprise.
> Rien n'est perdu. Le backend ne sert qu'à **consolider et sauvegarder**.

## 3. En cas de problème
| Symptôme | Action |
|---|---|
| `/health` en 503 / pas de réponse | `restart-stack.ps1` (relance PG + backend). |
| PG refuse de démarrer (« un autre serveur… ») | Vérifier qu'aucun **autre** PostgreSQL n'occupe 5432 (`Get-NetTCPConnection -LocalPort 5432`). Arrêter l'intrus. |
| « Permission denied » au démarrage de PG | Exclusion antivirus / pare-feu manquante (§0). |
| Le backend ne prend pas 8080 | Un autre programme occupe 8080 — l'arrêter. |
| Lenteur au démarrage de PG (~30 s) | Normal après un arrêt brutal (recovery). Le backend ré-essaie tout seul 15×. |

## 4. Sauvegarde (VITAL — argent de la boutique)
- **Planifier** une sauvegarde quotidienne vers un **disque externe / USB** (jamais sur C:) :
  ```
  powershell -File backend\scripts\setup-scheduled-backup.ps1 -OutDir "E:\Sauvegardes\BEJ" -Time 21:00
  ```
- **Auto-démarrage** de la pile à l'ouverture de session :
  ```
  powershell -File backend\scripts\setup-autostart.ps1
  ```
- **Restaurer** (à tester une fois pour de vrai) :
  ```
  powershell -File backend\scripts\restore.ps1 "E:\Sauvegardes\BEJ\bej_AAAAMMJJ_HHMMSS.dump"
  ```

## 5. Limites connues du pilote (assumées)
- **Mono-poste** : une seule caisse. Le multi-boutiques (reporting consolidé) est un
  chantier séparé, décidé « après succès » (plan chiffré : Obsidian → ADR-0005).
- **Pas de TLS / pas d'accès réseau** : tout reste sur `localhost`. La sécurité repose
  sur l'**accès physique** au poste.
- **Tiroir-caisse ESC-POS** et **build Windows natif** : non disponibles (impression
  ticket/étiquettes = navigateur).

---
*Contact / support :* _(à compléter — nom + téléphone du responsable technique)_
