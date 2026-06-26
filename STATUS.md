# STATUS — BEJ Technologie (Application de gestion)
> Dernière MAJ : 2026-06-18 (Phase 3 implémentée)

## 🎯 Objectif de la phase actuelle
**Phase 3 (FNE/DGI + Notifications + Fidélité)** — Services métier avancés implémentés
(migration 011, repos, services, UI Paramètres, campagnes). FNE/DGI configurable
mais non activé (endpoint DGI fictif à remplacer). App pleinement fonctionnelle sans
ces services (pattern nullable).

## ✅ Fait (cette semaine)
- **Sécurisation production (26/06/2026)** — 8 corrections critiques/importantes :
  CORS restreint à `BEJ_CORS_ORIGIN` (env var, plus de `*`) ; auth `/upload` par token
  Bearer (`BEJ_UPLOAD_TOKEN`, gated — inactif en dev) ; headers sécurité HTTP
  (`X-Content-Type-Options`, `X-Frame-Options`, `X-XSS-Protection`) ; config PG
  externalisée en env vars (`DB_HOST/PORT/NAME/USER`) ; `queryTimeout` 30 s ; PIN démo
  masqués en prod (`kDebugMode`) ; validation photos (type + taille max 5 Mo) ;
  messages d'exception génériques en réponse HTTP (`dart compile kernel` OK ;
  `flutter analyze` 0 erreur).
- **Prix négocié à la vente** — bouton ✏️ (icône `price_change`) par ligne de panier :
  saisie du prix négocié, affichage en orange avec barré sur le prix catalogue, ligne
  « Remise négociée » dans le sous-total. `remise_ligne` en base = remise implicite
  enregistrée. Dashboard : carte « Remises accordées » visible quand > 0 FCFA le jour.
  `flutter analyze` : 0 erreur (infos préexistants).
- **Phase 3 — FNE/DGI préparé** — migration `011_phase3.sql` (`config_fne`,
  `factures_fne`, `config_notifications`, `notifications_log`, `campagnes_fidelite`).
  `Phase3Repository`, `FneService` (HTTP POST fire-and-forget, logs dans SQLite, jamais
  bloquant), écran **Paramètres** 3 onglets (FNE/Notifications/Fidélité) accessible
  responsables. Endpoint/merchant_id/api_key configurables depuis l'app — **non activé
  tant que DGI ne fournit pas l'API officielle**.
- **Phase 3 — Notifications SMS/WhatsApp (Twilio)** — `NotificationService` ; envoi
  automatique au changement de statut réparation (reçu/prêt/livré) ; config Twilio
  dans l'écran Paramètres ; canal WhatsApp optionnel (`whatsapp:` préfixe).
- **Phase 3 — Campagnes fidélité (multiplicateur jetons)** — `campagnes_fidelite` +
  `Phase3Repository.multiplicateurJetonsActif` ; `VentePage` affiche le multiplicateur
  actif et l'applique au calcul des jetons ; `VenteRepository.enregistrerVente` reçoit
  `multiplicateurJetons` (défaut 1.0). Gestion CRUD des campagnes dans Paramètres.
- **Devis auto (data-driven)** — `reparationRepo.devisSuggere(modele, probleme)` calcule la
  médiane du `total` facturé sur les réparations similaires (fenêtre 12 mois, min 2 cas,
  repli panne-seule si besoin). Bannière dans « Nouvelle réparation » avec bouton
  « Utiliser » pour pré-remplir le champ devis. Test E2E dans `suivi_appareil_test` **vert**.
- **Fonctionnalité « tout-QR »** — étiquettes QR brandées BEJ (habillage **orange**,
  **code en clair sous le QR** pour saisie manuelle), **préparées en lot** et
  imprimables au choix (planche **A4** / **rouleau d'étiquettes** / **thermique 57 mm**) :
  réparation = pool de stickers vierges ; vente = un QR par article (`produits.qr_code`).
  **Scan universel** (douchette **+ caméra** `mobile_scanner`) : un QR/code-barres →
  **produit** (ajout à la Vente) ou **appareil** (fiche réparation : appareil +
  propriétaire + actions). **Intake réparation enrichi** : **photos sous toutes les
  coutures** + **affectation d'un sticker** à l'appareil. Migration `010_qr.sql`
  (`appareils.qr_code` + table `etiquettes_qr`) ; `EtiquetteQrRepository`,
  `util/qr_labels_pdf.dart`, écrans `qr_codes_page`/`scan_page`. **Migration `010`
  appliquée à la base + SYNC serveur vérifiée** (étiquettes/appareil/produit QR
  poussés dans PostgreSQL). analyze + build web + `flutter test` + E2E (`qr_labels`
  **avec push sync**, `phase0`, `finitions`, `suivi_appareil`) : **VERTS.**
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
- [ ] Rien d'actif.

## ⏭️ Prochaine étape (la SEULE chose à faire ensuite)
**Connecter les credentials réels** (Twilio account_sid/token et endpoint DGI) dans
l'écran ⚙️ Paramètres pour activer les notifications SMS/WhatsApp et la soumission FNE.

## 🧱 Décisions verrouillées
- Stack figée (cahier v1.1) : client **Flutter** (cible **web**/CanvasKit), base locale
  **SQLite via PowerSync**, serveur **PostgreSQL**, **pas de sync maison**.
- **Offline-first** : online-first, offline sur les opérations critiques ; pas de
  service de streaming PowerSync → seed local à UUID fixes + upload custom (push only).
- Tout en **mode utilisateur, sans admin, sans Docker** : **PostgreSQL 16 portable**
  sous `C:\dev`, lancé via `pg_ctl` (pas de service Windows).
- Validation = **`flutter analyze` (0 erreur/0 warning) + tests E2E** (`flutter drive`
  + chromedriver).
- Schéma métier = **migrations SQL numérotées `001`→`011`** (source de vérité, §7 du cahier).
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
- **Conflit de port 5432** : une AUTRE installation Postgres
  (`C:\Users\…\PostgreSQL\data`) peut occuper le 5432 et empêcher le cluster portable
  `C:\dev\pgdata` (mot de passe `bej_dev_pwd`) de démarrer. **Résolu cette session**
  (autre instance arrêtée via son `pg_ctl stop` ; portable relancé, backend OK, sync
  QR vérifiée). Les deux ne peuvent pas tourner ensemble : pour réutiliser l'autre,
  `db.ps1 stop` puis `pg_ctl start -D "C:\Users\…\PostgreSQL\data"`.
- **Pas de down-sync temps réel** (streaming PowerSync non activé) : un poste ne voit
  pas en direct les données d'un autre (ex. conflit « caisse déjà ouverte » résolu à la main).
- **PIN à 4 chiffres** : petit espace de clés ; le verrouillage atténue mais une vraie
  robustesse passerait par un code plus long.
- **Login ~1-2 s** (PBKDF2 50 000 tours) en debug : atténué par le spinner ; plus
  rapide en build release.
- **Périphériques §8** : ticket + scan livrés (web) ; **tiroir-caisse** (ESC-POS) et
  **build Windows natif** restent indisponibles (Visual Studio + admin requis).
- **Icônes PWA** = icônes Flutter par défaut (à brander BEJ).
