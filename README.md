# BEJ Technologie — Application de gestion

Application de gestion pour BEJ Technologie (réparation + vente d'accessoires,
3 magasins en Côte d'Ivoire), **offline-first**. Priorité métier : CRM client +
stock + caisse/vente + réparations.

> **Source de vérité de l'avancement : [`STATUS.md`](STATUS.md)** (objectif de la
> phase, fait, prochaine action unique, risques). À lire en début de session.

## État

**Phases 0 → 2 livrées et validées** (tests E2E), plus le durcissement « mise en
production » et les périphériques boutique :

- **Phase 0 — Socle** : Flutter web + SQLite (PowerSync) + PostgreSQL + backend Dart.
- **Phase 1 — MVP** : connexion + rôles, CRM (dédup + fiche détaillée), stock,
  caisse, vente comptoir (paiement mixte, reçu QR), réparations, retours/avoirs,
  jetons, tableau de bord.
- **Phase 2 — Multi-magasins** : transferts inter-magasins, reporting consolidé,
  + finitions (réapprovisionnement, inventaire physique, rapprochement de caisse).
- **Durcissement** : **PIN hachés** (PBKDF2) + **verrouillage** anti-force-brute,
  **PWA installable** (écran de chargement), **sauvegarde/restauration** PostgreSQL.
- **Périphériques (§8)** : **ticket de vente imprimable** (PDF 57 mm), **scan
  code-barres** au comptoir.
- **Suivi par appareil** : réutilisation des appareils connus du client, historique
  par appareil, **alerte garantie** (même panne < 30 j), suggestions data-driven
  (**pannes fréquentes** par modèle, **pièces compatibles**).
- **Mode Démo** intégré (rejoue tout le parcours) + **guide d'utilisation** dans
  l'app (icône **?**).

Voir `docs/PHASE0.md`, `docs/PHASE1.md`, `docs/PHASE2.md`.

## Stack (cahier des charges v1.1)

| Couche | Choix |
|--------|-------|
| Client | **Flutter** (cible **web** / CanvasKit) |
| Base locale | **SQLite** (via PowerSync) |
| Backend | **PostgreSQL 16** + serveur Dart (shelf) |
| Synchronisation | **PowerSync** (offline-first ; aujourd'hui *push* via `/upload`) |

## Structure du dépôt

```
AppDeGestion/
├── STATUS.md                # avancement (source de vérité)
├── app/                     # Projet Flutter (client, cible web)
│   ├── lib/main.dart        # point d'entrée (DB, seed, repos, DemoController)
│   ├── lib/src/             # app_session, data/ (PowerSync, repos), ui/, util/
│   ├── web/                 # manifest PWA + index (écran de chargement)
│   ├── tool/                # outils dev (gen_pin_hashes.dart)
│   └── integration_test/    # suites E2E (flutter drive)
├── backend/
│   ├── schema/              # migrations PostgreSQL (§7) — 001 → 009
│   │   ├── 001_init · 002_powersync · 003_seed · 004_avoirs · 005_catalogues
│   │   └── 006_transferts · 007_inventaires · 008_pins · 009_verrou
│   ├── powersync/           # sync_rules.yaml
│   ├── server/              # backend Dart shelf+postgres (/upload, /health)
│   └── scripts/             # db.ps1, backup.ps1, restore.ps1, restart-stack.ps1, SAUVEGARDE.md
└── docs/                    # PHASE0 · PHASE1 · PHASE2
```

## Environnement local (cette machine)

Tout en **mode utilisateur, sans admin, sans Docker** (contraintes : pas d'admin,
~27 Go) :

- **Flutter SDK** → `C:\dev\flutter` (PATH utilisateur)
- **PostgreSQL 16 portable** → binaires `C:\dev\pgsql`, données `C:\dev\pgdata`
  (lancé via `pg_ctl`, pas de service Windows)
- **chromedriver** → `C:\dev\chromedriver-win64` (tests E2E)
- **Mot de passe Postgres local** (non versionné) : créer
  `backend/scripts/local.env.ps1` avec `$env:PGPASSWORD = "<votre_mot_de_passe>"`
  — lu par les scripts et le backend (défaut `postgres` sinon).

### Démarrer la base + le backend

```powershell
cd backend\scripts
.\db.ps1 init        # une seule fois : initialise le cluster + wal_level=logical
.\db.ps1 start       # démarre Postgres sur localhost:5432
.\db.ps1 schema      # applique le schéma + le seed sur la base 'bej'
# raccourci de relance (Postgres instable sur cette machine) :
.\restart-stack.ps1  # (re)démarre Postgres puis le backend de synchronisation
```

### Lancer l'app Flutter

```powershell
cd app
flutter pub get
flutter run -d chrome --web-port=5000   # http://localhost:5000
```

### Sauvegarde / restauration

Voir `backend/scripts/SAUVEGARDE.md` (`backup.ps1` / `restore.ps1`, format `pg_dump`).

## Validation

- **`flutter analyze`** : 0 erreur / 0 warning.
- **Tests E2E** via `flutter drive` + chromedriver (`app/integration_test/`).

## Phasage

- **Phase 0 — Socle technique** ✅
- **Phase 1 — MVP** ✅
- **Phase 2 — Multi-magasins** ✅ (+ finitions)
- **Durcissement & périphériques** ✅ (sécurité PIN, sauvegarde, PWA, ticket, scan)
- **Phase 3 — Fiscalité** ⏳ : intégration **FNE/DGI**, WhatsApp/SMS, campagnes
  fidélité *(nécessite des accès/identifiants externes DGI)*.

## Limites connues (cf. `STATUS.md`)

- **Sync temps réel (down-sync)** non activée : service de streaming PowerSync
  indisponible ici (pas de Docker/admin) → la remontée se fait en *push*.
- **Build Windows desktop natif** + périphériques bas niveau (tiroir-caisse ESC-POS)
  indisponibles (Visual Studio + admin requis).
- **PostgreSQL instable** sur cette machine (interférence antivirus/disque) :
  utiliser `restart-stack.ps1` au besoin.
