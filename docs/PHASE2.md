# Phase 2 — Multi-magasins renforcé (en cours)

> *Critère de passage : les 3 magasins utilisent l'application sans perte de
> données pendant plusieurs semaines.*

## Modules livrés

### Transferts inter-magasins (§2.5) — mécanique en deux temps

Onglet accessible via l'icône **⇄** de la barre du haut (responsable / admin).

1. **La SOURCE crée** un transfert (produit, quantité, magasin destinataire) :
   le stock disponible source est **décrémenté**, la quantité passe **en transit**
   (visible côté destinataire), un `MouvementStock` « transfert sortant » est tracé.
2. **Le DESTINATAIRE confirme** la réception : le stock disponible destinataire est
   **incrémenté**, l'en-transit retombe à 0, le transfert passe à **« reçu »**,
   `MouvementStock` « transfert reçu ».

Garantie §2.5 : **aucun magasin ne modifie directement le stock d'un autre** — le
mouvement n'est effectif chez le destinataire qu'après sa confirmation. Le stock
insuffisant à la source est refusé.

Données : table `transferts` (`006_transferts.sql`) + `stocks_magasin.quantite_en_transit`.

### Reporting consolidé (vue groupe) — administrateur

Depuis le tableau de bord (icône **résumé**, admin uniquement) : agrégation **par
magasin** du CA (ventes + réparations), du nombre de transactions, du stock total
et des alertes, avec le **total groupe**.

## Démonstration

1. Connexion **responsable** (3333) ou **admin** (1111).
2. Icône **⇄** (barre du haut) → *Transfert* : produit, quantité, destination
   (ex. BEJ Yopougon) → **Envoyer**. Le stock de Cocody baisse.
3. **Changer de magasin** (sélecteur en haut) pour Yopougon → le transfert apparaît
   en **entrant** → **Confirmer réception**. Le stock de Yopougon augmente.
4. (admin) Tableau de bord → icône **résumé** → vue **consolidée** des 3 magasins.

## Validé par test E2E

`integration_test/transfert_test.dart` : transfert Cocody → Yopougon (décrément
source, en transit, confirmation, incrément destinataire) + reporting consolidé.

## Finitions Phase 2+ (livrées)

- **Annulation de transfert** : tant qu'un envoi est « en transit », le magasin
  émetteur peut l'annuler — le stock lui revient (statut `annule`, mouvement tracé).
- **Réapprovisionnement** : l'onglet Stock → « Réappro » liste les produits sous
  le seuil d'alerte et les magasins capables de fournir ; un transfert peut être
  déclenché directement vers le magasin en manque (puis confirmation classique).
- **Inventaire physique** : Stock → « Inventaire » fige le stock théorique, laisse
  saisir le comptage produit par produit, puis **aligne le stock sur le comptage**
  à la validation (un `MouvementStock` « inventaire » par écart + journal d'audit).
- **Rapprochement de caisse** : le reporting consolidé (admin) agrège les écarts
  de clôture **par magasin** (nombre de clôtures, écart cumulé, dernier écart).

Données : migration `007_inventaires.sql` (tables `inventaires` +
`lignes_inventaire`). Validé par `integration_test/finitions_test.dart`
(annulation, réappro, inventaire, rapprochement).

## Reste / Phase 2+ (hors périmètre de cette itération)

- **Service PowerSync de streaming** : aujourd'hui la confirmation se fait sur le
  même poste (toutes les données magasins sont locales) ; en production, le
  transfert se synchronise vers le poste du magasin destinataire.
- Build Windows desktop natif + périphériques (§8), inventaires avancés
  (sessions partielles, écarts valorisés en FCFA), alertes de réapprovisionnement
  automatiques (notifications), seuils de réappro proposés par historique de ventes.
