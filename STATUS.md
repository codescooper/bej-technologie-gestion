# STATUS — BEJ Technologie (Application de gestion)
> Dernière MAJ : 2026-06-13

## 🎯 Objectif de la phase actuelle
Clôturer le durcissement « mise en production » (sécurité des accès, sauvegarde
serveur, installabilité) et les périphériques boutique, avant d'attaquer la
Phase 3 (FNE/DGI) — les Phases 0/1/2 étant livrées et validées.

## ✅ Fait (cette semaine)
- **Tests E2E dans la CI** — job dédié (PostgreSQL + backend de sync + Chrome sous Xvfb)
  qui rejoue `phase0` / `finitions` / `suivi_appareil` à chaque push : la donnée créée
  hors-ligne est poussée et vérifiée côté serveur. **CI complète verte.**
- **Commits en email *noreply*** — git configuré sur `…@users.noreply.github.com` (futurs
  commits ; réécriture des 5 anciens bloquée par le garde-fou de sécurité → manuel/autorisation).
- **Intégration continue (GitHub Actions)** — à chaque push : `flutter analyze`
  (`--no-fatal-infos`) + `flutter test` + `flutter build web` (app) et `dart analyze`
  (backend). **CI verte** ; badge dans le README. E2E (flutter drive) hors CI.
- **Publication GitHub (public)** — dépôt **github.com/codescooper/bej-technologie-gestion** ;
  le mot de passe Postgres de dev a été **retiré du code et de l'historique git** (déplacé
  dans `backend/scripts/local.env.ps1`, non versionné). `db.ps1` corrigé (schéma `001→009`).
- **Finition UX login** — spinner + bouton désactivé pendant la vérification du PIN
  (anti double-clic) ; `auth_test` re-validé.
- **Docs & versionnage** — `README.md` remis à jour (migrations `001→009`, durcissement,
  périphériques, suivi appareil) ; **dépôt git initialisé** + `.gitignore` (commit
  initial, non poussé) ; script `backend/scripts/restart-stack.ps1` (relance PG + backend).
- **App plus « intelligente » (data-driven, offline)** — au choix du modèle, les
  **pannes fréquentes** sont suggérées en un tap (depuis l'historique) ; à l'ajout
  d'une pièce, les **pièces compatibles** avec l'appareil passent en tête.
  (`reparation_repository.pannesFrequentes`, `reparation_detail_page`, `reparations_page`).
- **Suivi par appareil** — à la création d'une réparation, les appareils déjà connus
  du client sont présentés (avec leur nombre de réparations passées) ; on les réutilise
  au lieu de créer un doublon (« ➕ Nouvel appareil » sinon). `reparations_page.dart`
  + `suivi_appareil_test.dart` (vert).
- **Historique par appareil + alerte garantie** — fiche réparation : section
  « Historique de cet appareil » ; à la création, alerte « possible garantie » si la
  même panne revient < 30 j sur le même appareil (`reparation_repository.dart` :
  `parAppareil` / `garantieRecente`).
- **Verrouillage PIN validé** — `auth_test.dart` repassé **au vert** (login PBKDF2 +
  blocage après 5 échecs).
- **Hachage des PIN (PBKDF2)** — fin des PIN en clair : `app/lib/src/util/pin_hash.dart`,
  outil `app/tool/gen_pin_hashes.dart`, migration `backend/schema/008_pins.sql`.
- **Verrouillage anti-force-brute** — après 5 échecs, compte bloqué 5 min :
  migration `009_verrou.sql` (`tentatives_echouees`, `verrou_jusqu_a`),
  `auth_repository.dart` (→ `LoginResult`), `login_page.dart`.
- **Périphériques boutique (§8)** — ticket de vente **imprimable** (PDF reçu 57 mm,
  `app/lib/src/util/ticket_pdf.dart` + bouton « Imprimer ») et **scan code-barres**
  au comptoir (`ProduitRepository.findByCodeBarres` + champ scan dans `vente_page`).
- **Sauvegarde / restauration PostgreSQL** — `backend/scripts/backup.ps1` + `restore.ps1`
  (pg_dump format custom) + guide `SAUVEGARDE.md`.
- **PWA installable + écran de chargement** — `app/web/index.html` (splash retiré au
  premier rendu Flutter) + `manifest.json` brandé.
- *(rappel Phase 2, livrée)* transferts inter-magasins, inventaire, réappro,
  rapprochement caisse, reporting consolidé, Mode Démo.

## 🚧 En cours
- [ ] Rien d'actif. Choisir le prochain axe : **Phase 3 (FNE/DGI)** — bloquée tant que
  les accès/identifiants DGI ne sont pas fournis — ou une brique « smart » offline
  (devis auto, stock dormant, réassort selon la vitesse de vente).

## ⏭️ Prochaine étape (la SEULE chose à faire ensuite)
**Devis auto** : suggérer le prix d'une réparation pour (modèle + panne) d'après
l'historique local — prolonge l'atelier « intelligent » (pannes fréquentes + pièces
compatibles déjà en place).
> Pourquoi celle-ci : 0→2 + durcissement + périphériques + suivi appareil sont livrés ;
> la Phase 3 (FNE/DGI) dépend d'accès externes → on capitalise d'abord sur le
> data-driven offline, à forte valeur atelier et sans dépendance.

## 🧱 Décisions verrouillées
- Stack figée (cahier v1.1) : client **Flutter** (cible **web**/CanvasKit), base locale
  **SQLite via PowerSync**, serveur **PostgreSQL**, **pas de sync maison**.
- **Offline-first** : online-first, offline sur les opérations critiques ; pas de
  service de streaming PowerSync → seed local à UUID fixes + upload custom (push only).
- Tout en **mode utilisateur, sans admin, sans Docker** : **PostgreSQL 16 portable**
  sous `C:\dev`, lancé via `pg_ctl` (pas de service Windows).
- Validation = **`flutter analyze` (0 erreur/0 warning) + tests E2E** (`flutter drive`
  + chromedriver).
- Schéma métier = **migrations SQL numérotées `001`→`009`** (source de vérité, §7 du cahier).
- **PIN haché (PBKDF2, sel = id utilisateur)** + verrouillage — plus de PIN en clair.
- Périmètre : Phases 0→2 + durcissement + périphériques ; **FNE/DGI = Phase 3** à part
  (dépend d'accès externes DGI).

## ⚠️ Dettes / risques connus
- **Dépôt GitHub public** : `github.com/codescooper/bej-technologie-gestion` (secret de
  dev purgé). Futurs commits en *noreply* ; les **5 premiers commits** portent encore
  l'email perso (réécriture d'historique à autoriser/exécuter pour les purger).
- **PostgreSQL instable sur cette machine** : retombe régulièrement (interférence
  antivirus/disque sur `pgdata`), recovery lent (~33 s de fsync). Mitigation :
  **`backend/scripts/restart-stack.ps1`** (relance PG + backend en une commande).
- **Pas de down-sync temps réel** (streaming PowerSync non activé) : un poste ne voit
  pas en direct les données d'un autre (ex. conflit « caisse déjà ouverte » résolu à la main).
- **PIN à 4 chiffres** : petit espace de clés ; le verrouillage atténue mais une vraie
  robustesse passerait par un code plus long.
- **Login ~1-2 s** (PBKDF2 50 000 tours) en debug : atténué par le spinner ; plus
  rapide en build release.
- **Périphériques §8** : ticket + scan livrés (web) ; **tiroir-caisse** (ESC-POS) et
  **build Windows natif** restent indisponibles (Visual Studio + admin requis).
- **Icônes PWA** = icônes Flutter par défaut (à brander BEJ).
