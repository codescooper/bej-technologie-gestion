# TEST COMPLET — BEJ Technologie (recette + script de démo)

> Parcours de validation **de bout en bout** de l'application. Sert à la fois de
> **recette** (cocher chaque cas) et de **script de démonstration client**.
> Durée ≈ 30–40 min. Coche `[x]` quand le résultat attendu est obtenu.

## 0. Préparation
- [ ] Lancer la pile : `powershell -File backend\scripts\restart-stack.ps1`
- [ ] Vérifier la santé : ouvrir **http://localhost:8080/health** → `{"status":"ok", ...}`
- [ ] Lancer l'app : `cd app ; flutter run -d chrome --web-port=5000`
- [ ] Écran de connexion **BEJ Technologie** affiché.

**Comptes de démonstration** (PIN à changer avant la vraie prod) :
`admin 1111` · `responsable 3333` · `caissier 2222` · `technicien 4444`

---

## 1. Authentification & rôles (§6)
| # | Étapes | Résultat attendu | OK |
|---|---|---|---|
| 1.1 | Se connecter en **caissier** (2222) | Accès caisse/vente/réparations ; **pas** de Dashboard global ni d'ajustement de stock | ☐ |
| 1.2 | Se déconnecter, saisir un **mauvais PIN** 3× | Message « PIN incorrect, N essai(s) restant(s) » | ☐ |
| 1.3 | Continuer jusqu'à **5 échecs** | **Compte verrouillé 5 min** (message explicite) | ☐ |
| 1.4 | Se connecter en **admin** (1111) | Accès complet (⚙️ Paramètres, Dashboard global, Mode démo) | ☐ |

## 2. Caisse (ouverture / clôture / rapprochement)
| # | Étapes | Résultat attendu | OK |
|---|---|---|---|
| 2.1 | Ouvrir la caisse avec un **fond de caisse** | Caisse « ouverte », montant initial enregistré | ☐ |
| 2.2 | (après ventes) **Clôturer** en saisissant l'espèce comptée | **Écart** calculé et affiché (théorique vs compté) | ☐ |

## 3. Vente au comptoir
| # | Étapes | Résultat attendu | OK |
|---|---|---|---|
| 3.1 | Ajouter des produits (recherche + **scan code-barres/QR**) | Panier mis à jour, sous-total correct | ☐ |
| 3.2 | Sur une ligne, saisir un **prix négocié** (< catalogue) | Prix **barré** + prix orange ; ligne « **Remise négociée** » au total | ☐ |
| 3.3 | Payer en **paiement mixte** (espèces + Wave/mobile) | Somme des paiements = total, vente validée | ☐ |
| 3.4 | Imprimer le **ticket** | PDF reçu 57 mm généré | ☐ |
| 3.5 | Vérifier le **stock** du produit vendu | Décrémenté du bon nombre | ☐ |

## 4. Réparations (cycle complet)
| # | Étapes | Résultat attendu | OK |
|---|---|---|---|
| 4.1 | Nouvelle réparation : choisir un **client existant** | Ses **appareils connus** sont proposés (pas de doublon) | ☐ |
| 4.2 | Choisir le modèle | **Pannes fréquentes** suggérées ; **devis auto** proposé (médiane historique) | ☐ |
| 4.3 | Ajouter des **photos à la réception** (multi-angles) | Vignettes affichées | ☐ |
| 4.4 | **Scanner/saisir un sticker QR** et l'affecter à l'appareil | QR lié à l'appareil | ☐ |
| 4.5 | Enregistrer → passer le statut **reçu → prêt → livré** | Historique du statut mis à jour | ☐ |
| 4.6 | (si Twilio configuré) au changement de statut | **SMS/WhatsApp** envoyé au client (sinon : ignoré, journalisé) | ☐ |
| 4.7 | **Encaisser** la réparation à la livraison | Paiement enregistré, réparation clôturée | ☐ |
| 4.8 | Rouvrir la même panne < 30 j sur le même appareil | **Alerte « possible garantie »** | ☐ |

## 5. Retours & avoirs
| # | Étapes | Résultat attendu | OK |
|---|---|---|---|
| 5.1 | Faire un **retour** d'un produit vendu | Avoir créé (montant), stock ré-incrémenté | ☐ |
| 5.2 | Utiliser l'**avoir** en paiement sur une nouvelle vente | Montant de l'avoir déduit ; `montant_restant` mis à jour | ☐ |

## 6. « Tout-QR » : étiquettes & scan universel
| # | Étapes | Résultat attendu | OK |
|---|---|---|---|
| 6.1 | ⚙️/menu **Étiquettes** → préparer un lot réparation | N stickers `BEJ-R-…` générés | ☐ |
| 6.2 | Imprimer en **3 formats** (A4 / rouleau / thermique 57 mm) | Étiquettes **orange BEJ** + **code en clair** sous le QR | ☐ |
| 6.3 | Onglet Vente → **générer QR produits** + imprimer | Un QR par article | ☐ |
| 6.4 | **Scan universel** d'un QR **produit** | Proposition « Ajouter à la vente » → panier | ☐ |
| 6.5 | **Scan universel** d'un QR **appareil** | Ouvre la **fiche réparation** (appareil + client + actions) | ☐ |
| 6.6 | **Saisie manuelle** du code imprimé (sans caméra/douchette) | Même résolution | ☐ |

## 7. Multi-magasins (Phase 2)
| # | Étapes | Résultat attendu | OK |
|---|---|---|---|
| 7.1 | (admin) **Transfert** inter-magasins d'un produit | Sortie magasin A / entrée magasin B ; état « en transit » | ☐ |
| 7.2 | **Annuler** un transfert en transit | Stock restauré | ☐ |
| 7.3 | **Inventaire** physique : compter → ajuster | Écart calculé, stock ajusté | ☐ |
| 7.4 | **Réapprovisionnement** : voir les alertes seuil | Produits sous le seuil listés | ☐ |
| 7.5 | **Dashboard global** (admin) | Agrégation multi-magasins (CA, stock, remises) | ☐ |

## 8. Paramètres (Phase 3)
| # | Étapes | Résultat attendu | OK |
|---|---|---|---|
| 8.1 | (caissier) ⚙️ Paramètres | **Seul** l'onglet **Notifications** ; identifiants Twilio **verrouillés** (encart 🔒) | ☐ |
| 8.2 | (admin) ⚙️ → Notifications → saisir Twilio → **« Tester »** | Sans vraies clés : **boîte d'erreur explicite** (comportement attendu) | ☐ |
| 8.3 | (admin) onglet **Fidélité** : créer une campagne ×2 | Pendant la campagne, jetons × multiplicateur en vente | ☐ |

## 9. Résilience offline (le cœur de la promesse)
| # | Étapes | Résultat attendu | OK |
|---|---|---|---|
| 9.1 | **Arrêter le backend** (fermer la fenêtre / `Stop-Process`) | App bascule « Hors ligne — données conservées » | ☐ |
| 9.2 | Faire **une vente** hors-ligne | Vente enregistrée **localement**, reçu imprimable | ☐ |
| 9.3 | **Relancer** le backend (`restart-stack.ps1`) puis **Synchroniser** | La vente hors-ligne **remonte** en base (vérifier via Dashboard/serveur) | ☐ |

## 10. Sauvegarde / restauration
| # | Étapes | Résultat attendu | OK |
|---|---|---|---|
| 10.1 | `backend\scripts\backup.ps1 -OutDir <externe>` | Fichier `bej_AAAAMMJJ_HHMMSS.dump` créé | ☐ |
| 10.2 | `backend\scripts\restore.ps1 <fichier.dump>` (sur une base test) | Restauration réussie, données présentes | ☐ |

---

## Résultat global
- Cas réussis : ____ / ~45
- Anomalies relevées : _______________________________________________
- Testé par : ____________________  Date : ____________

> **Automatisation** : les parcours critiques (vente mixte, caisse, transferts,
> inventaire, QR, suivi appareil) sont **rejoués à chaque push par la CI**
> (`.github/workflows/ci.yml`) contre un vrai PostgreSQL + backend.
