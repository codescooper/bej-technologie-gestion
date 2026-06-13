# Phase 1 — MVP opérationnel (en cours)

> *Critère de passage : une boutique travaille une journée entière, même avec
> coupure internet.*

> **✅ Cœur encaissement validé le 2026-06-01.** Test E2E (Chrome + chromedriver,
> vrai client PowerSync web) : `All tests passed`. Une vente comptoir complète
> (2 articles, **paiement mixte** Espèces 5 000 + Wave 7 000 = 12 000 FCFA) a
> généré côté PostgreSQL : 1 `transactions` (total 12 000, **120 jetons**),
> 1 `lignes_transaction`, 2 `paiements`, 1 `mouvements_stock`, et le **stock a
> été décrémenté** (12 → 10). Synchronisation sans perte, 0 conflit.
>
> **Test UI complet** (`integration_test/app_ui_test.dart`) : pilote toute
> l'interface (créer client → stock → ouvrir caisse → panier + paiement mixte →
> **reçu QR** → synchroniser → clôturer) — `All tests passed`.
>
> Un **guide d'utilisation est intégré à l'app** (icône **?** de la barre du haut).

### Corrections post-revue (2026-06-01)

- **Reçu de vente** : le `QrImageView` dans l'`AlertDialog` faisait planter le
  rendu (`LayoutBuilder` + mesure intrinsèque) → la vente semblait « ne pas
  marcher ». Corrigé en fixant la largeur du contenu (`SizedBox`).
- **Sync tolérante aux conflits** : le backend `/upload` journalise et ignore
  désormais aussi les **violations de clé étrangère (23503)** — un enfant
  (vente) dont le parent (client/caisse) a été ignoré par la dédup ne bloque
  plus la synchronisation (principe « la synchro n'est jamais bloquée »).

Cette première itération de la Phase 1 livre le **cœur encaissement** : produits,
stock local, caisse et vente comptoir (la « transaction encaissée unifiée » du §7,
qui est la principale difficulté de modélisation du cahier).

## Modules livrés dans cette itération

| Module | Écran | Détail |
|--------|-------|--------|
| CRM client | **Clients** | liste + création avec détection de doublon (§2.6) |
| Stock | **Stock** | catalogue + quantité par magasin, alerte stock bas, ajout produit, ajustement avec motif (§5.7) |
| Caisse | **Caisse** | ouverture (fond initial), clôture avec comptage réel et **écart** théorique/réel dérivé des paiements (§5.4) |
| Vente | **Vente** | panier multi-lignes, remise, **client optionnel**, **jetons** en réduction, **paiement mixte** (plusieurs moyens), décrément du stock, **jetons gagnés**, **reçu interne avec QR** (§5.5) |
| Réparations | **Réparations** | appareil (IMEI) via **catalogues recherchables et enrichissables** (modèles + pannes : on tape, on filtre, on ajoute si absent), cycle de statuts (§5.2), diagnostic + main-d'œuvre, **pièces consommées** (décrément stock, mouvement rattaché), **photos** à la réception (§5.3), **encaissement au retrait** = `Transaction` type `reparation` rattachée à la caisse (§5.2) |
| Dashboard | **Tableau de bord** (icône 📊 barre du haut) | CA du jour (ventes + réparations), nb d'opérations, réparations en cours par statut, alertes stock bas, état caisse + théoriques, jetons distribués |
| Retours / Avoirs | **Vente → Retour / Avoir** | retour **partiel ou total** d'une vente, **réintégration stock**, **annulation des jetons**, génération d'un **avoir** (crédit client) — validation responsable. L'avoir est **réutilisable comme paiement** à un achat suivant (§5.6) |
| Détail client | **Clients → fiche** | infos + **édition**, solde jetons, **avoirs**, **historique** des transactions et des réparations (§5.1) |
| Authentification | **Écran de connexion** | login par compte + **PIN**, 4 **rôles** (§6) ; droits appliqués (encaissement, caisse, ajustement stock, validation retour, dashboard) ; menu compte + déconnexion |

Le tout est **offline-first** : chaque opération écrit dans la base PowerSync
locale et alimente la file CRUD, synchronisée vers PostgreSQL via le backend.

## La transaction encaissée unifiée (§7)

Une vente crée, en une seule transaction d'écriture (`VenteRepository`) :

```
transactions (type 'vente')
 ├─ lignes_transaction      (1 par produit)
 ├─ mouvements_stock        (sortie, cause = transaction_id) + décrément stocks_magasin
 ├─ paiements               (1..n  => paiement mixte)
 └─ jeton_transactions      (gain et/ou dépense) + maj clients.solde_jetons
```

- **Compteurs de caisse** (§5.4) dérivés des `paiements` rattachés (cash vs mobile money).
- **Jetons** (§5.9) : 100 FCFA dépensés = 1 jeton gagné ; les jetons utilisés en
  réduction génèrent une `jeton_transaction` de type `depense`.
- **Stock** (§2.4/§5.7) : possédé par magasin, chaque sortie est tracée par un
  `mouvement_stock` portant sa cause.

## Contexte de session (provisoire)

Faute d'authentification réelle (à venir), l'app démarre sur le magasin **Cocody**
avec la caissière **Awa**. Le **sélecteur de magasin** (barre du haut) change le
magasin courant ; stock et caisse sont filtrés en conséquence.

Le référentiel (3 magasins, rôles, 2 utilisateurs, 5 produits de démo + stock
Cocody) est semé **localement** au premier lancement avec des **UUID fixes**
(cf. `app/lib/src/data/ref_ids.dart` ↔ `backend/schema/003_seed.sql`), pour
converger avec le serveur via `ON CONFLICT (id)` (substitut au service de
streaming, absent en Phase 0/1).

## Démonstration manuelle (journée type)

1. Démarrer Postgres + backend + l'app (cf. `docs/PHASE0.md`).
2. Onglet **Caisse** → *Ouvrir la caisse* (fond initial).
3. Onglet **Stock** → vérifier le catalogue (produits de démo) ; ajouter/ajuster.
4. Onglet **Vente** → toucher des produits (panier), choisir un client (optionnel),
   remise éventuelle, *Encaisser* → répartir le paiement (cash + mobile = mixte) →
   **reçu avec QR**. Le stock décrémente, les jetons sont attribués.
5. Barre du haut → **Synchroniser** : tout remonte dans PostgreSQL.
6. Onglet **Caisse** → *Clôturer* : comptage réel vs théorique, **écart** affiché.

### Cycle réparation (onglet Réparations)

1. Onglet **Réparations** → *Réparation* : choisir le client, saisir appareil
   (marque/modèle/IMEI), problème, devis.
2. Ouvrir la fiche → faire évoluer le **statut**, saisir le **diagnostic** et la
   main-d'œuvre, **ajouter des pièces** (décrémentent le stock), **ajouter des
   photos** à la réception.
3. Quand c'est prêt : **Encaisser au retrait** → paiement (mixte possible) →
   la réparation passe à *livré* et le CA entre dans la caisse.

## Phase 1 — complète ✅

Tous les modules MVP du cahier (§4/§5) sont livrés et validés par des tests E2E.
Le critère de passage est atteint : **une boutique tient une journée entière, même
hors ligne** (CRM, stock, caisse, vente, réparations, retours/avoirs, jetons,
reçus, dashboard), avec **connexion et rôles**.

### Pistes Phase 2+ (hors MVP)
- Service **PowerSync de streaming** (sync temps réel bidirectionnelle multi-postes).
- **Transferts inter-magasins** (§2.5), reporting consolidé, rapprochement central.
- **Build Windows desktop natif** (Visual Studio) + périphériques (imprimante 80 mm, lecteur code-barres, §8).
- **Auth de production** (hash fort / fournisseur d'identité) et durcissement backend (TLS, auth des requêtes).
- Intégration **FNE/DGI**, WhatsApp/SMS, campagnes fidélité (§3, Phase 3).
- Durcissement backend (auth des requêtes, TLS).
