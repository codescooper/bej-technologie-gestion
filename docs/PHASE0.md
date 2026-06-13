# Phase 0 — Socle technique

Ce document décrit le socle installé, comment le démarrer, et la procédure de
validation du **critère de passage Phase 0** :

> *« Créer une donnée offline et la retrouver côté serveur après synchronisation. »*

---

## 1. Ce qui a été installé sur cette machine

Tout est en **mode utilisateur, sans droits administrateur, sans Docker**
(contraintes de la machine : pas d'admin, ~27 Go libres, Windows 10).

| Composant | Version | Emplacement | Notes |
|-----------|---------|-------------|-------|
| Flutter SDK | 3.44.0 (stable) | `C:\dev\flutter` | au PATH utilisateur ; Dart 3.12.0 inclus |
| PostgreSQL | 16.14 (portable) | binaires `C:\dev\pgsql`, données `C:\dev\pgdata` | lancé via `pg_ctl`, pas de service Windows |
| chromedriver | 148.0.7778.178 | `C:\dev\chromedriver-win64` | pour les tests E2E web |

Outils déjà présents : Git, Chrome 148, Edge.

### Cibles de build Flutter

- ✅ **Web (Chrome)** — cible utilisée pour la Phase 0. PowerSync y tourne en
  **SQLite WASM/OPFS**, donc **aucun toolchain natif requis**.
- ⛔ **Windows desktop** — nécessite **Visual Studio + workload « Desktop
  development with C++ »** (plusieurs Go, droits admin). À installer avant le
  déploiement terrain (Phase 1). Le code Flutter est identique ; il suffira de
  régénérer la plateforme : `flutter create --platforms=windows .`
- ⛔ **Android** — Android SDK non installé (hors périmètre disque actuel).

> Note Windows desktop : les plugins natifs exigent le **Mode Développeur**
> (`HKLM\...\AllowDevelopmentWithoutDevLicense`, donc admin) pour les symlinks.
> À activer en même temps que Visual Studio.

---

## 2. Architecture du socle

```
   Flutter Web (Chrome)                 Serveur Dart            PostgreSQL 16
 ┌──────────────────────┐   POST /upload  ┌────────────┐  SQL  ┌────────────┐
 │  UI CRM (clients)     │  ─────────────► │  shelf +   │ ────► │  base bej  │
 │  PowerSync (SQLite    │   { batch:[…] } │  postgres  │       │  18 tables │
 │  WASM/OPFS) +         │                 │  /health   │       │  publication│
 │  file CRUD locale     │ ◄───────────── │  :8080     │       │  logique    │
 │  SyncService.push()   │   { applied:n } └────────────┘       └────────────┘
 └──────────────────────┘
        écritures offline                  applique les mutations
        (file qui s'accumule)              à PostgreSQL
```

**Pourquoi ce montage (et pas le service PowerSync complet) en Phase 0 ?**
Le service de streaming PowerSync se déploie via Docker (bloqué : admin + WSL)
ou via PowerSync Cloud (nécessite un compte). Pour rester **100 % local et
autonome**, on utilise :
- le **vrai client PowerSync** côté app (base locale + file CRUD offline-first) ;
- un **backend Dart minimal** qui applique la file CRUD à PostgreSQL.

Cela satisfait pleinement le critère Phase 0 (offline → serveur). Le passage au
streaming temps réel bidirectionnel (Phase 1+) ne demandera que :
1. lancer le service PowerSync (Docker/Cloud) ;
2. implémenter un `PowerSyncBackendConnector` (`fetchCredentials` + `uploadData`)
   et appeler `db.connect(connector)`.
Le schéma Postgres, les `sync_rules.yaml` et le schéma local sont **déjà prêts**.

---

## 3. Démarrer l'environnement

### 3.1 PostgreSQL

```powershell
cd "backend\scripts"
.\db.ps1 init     # 1ère fois seulement : initialise le cluster + wal_level=logical
.\db.ps1 start    # démarre sur localhost:5432
.\db.ps1 schema   # crée la base 'bej' + applique 001/002/003
.\db.ps1 status   # (optionnel) vérifie l'état
```

### 3.2 Backend de synchronisation (Dart)

```powershell
cd "backend\server"
dart pub get          # 1ère fois
dart run bin/server.dart
# -> "Backend BEJ à l'écoute sur http://localhost:8080"
```

### 3.3 Application Flutter (web)

```powershell
cd app
flutter pub get       # 1ère fois
flutter run -d chrome # lance l'app dans Chrome
```

---

## 4. Validation du critère Phase 0

> **✅ Critère validé le 2026-06-01.** Test E2E `flutter drive` exécuté dans
> Chrome 148 (chromedriver) : `All tests passed`. Le client créé offline dans
> la base PowerSync du navigateur (`E2E-1780323939343`,
> tél. normalisé `+2250701020304`) a été retrouvé dans la table `clients` de
> PostgreSQL après synchronisation. La chaîne PowerSync(web) → backend Dart →
> PostgreSQL fonctionne de bout en bout.

### 4.1 Automatisée (test E2E)

Le test `integration_test/phase0_test.dart` exécute, dans un vrai Chrome
(chromedriver), avec le vrai client PowerSync web :
création client offline → file CRUD → `push()` vers le backend → file vidée.

Pré-requis : Postgres démarré, backend démarré, chromedriver lancé.

```powershell
# 1. chromedriver (terminal séparé)
C:\dev\chromedriver-win64\chromedriver.exe --port=4444

# 2. le test
cd app
flutter drive `
  --driver=test_driver/integration_test.dart `
  --target=integration_test/phase0_test.dart `
  -d web-server --browser-name=chrome
```

Le test émet dans la sortie `E2E_MARKER=…` et `E2E_CLIENT_ID=…`.

### 4.2 Vérification côté serveur (PostgreSQL)

```powershell
$env:PGPASSWORD="<mot_de_passe_local>"
& "C:\dev\pgsql\bin\psql.exe" -U postgres -h localhost -p 5432 -d bej `
  -c "SELECT id, nom, telephone_normalise FROM clients WHERE nom LIKE 'E2E-%' ORDER BY date_creation DESC LIMIT 5;"
```

La présence de la ligne créée par l'app **prouve** que la donnée créée offline
est bien arrivée côté serveur après synchronisation. ✅

### 4.3 Démonstration manuelle (UI)

1. Démarrer Postgres + l'app (sans démarrer le backend).
2. Dans l'app : bandeau **« Hors ligne (local) »**. Ajouter quelques clients
   (bouton **+**). Le compteur **« N en attente »** augmente.
3. Démarrer le backend → cliquer **Rafraîchir** : bandeau **« Serveur en ligne »**.
4. Cliquer **Synchroniser** → snackbar « N opération(s) envoyée(s) », compteur à 0.
5. Vérifier en base avec la requête du §4.2.

> La détection de doublon (§2.6/§5.1) est démontrée : saisir deux clients avec
> le même téléphone déclenche l'avertissement « un client existe déjà ».

---

## 5. Détails de configuration

- **Base** : `bej` ; superutilisateur `postgres` / `<mot_de_passe_local>` (**dev only** —
  à changer en production).
- **Réplication logique** : `wal_level=logical`, publication `powersync`
  (cf. `backend/schema/002_powersync.sql`), prête pour le service PowerSync.
- **Adresse backend** dans l'app : `http://localhost:8080`, surchargeable au
  build via `--dart-define=BEJ_API=http://…`.
