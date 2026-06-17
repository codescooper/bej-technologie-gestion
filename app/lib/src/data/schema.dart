import 'package:powersync/powersync.dart';

/// Schéma SQLite local PowerSync — miroir des tables PostgreSQL (§7).
///
/// PowerSync ne connaît que 3 types de colonnes : text / integer / real.
/// On y projette donc les types Postgres :
///   uuid, text, timestamptz   -> text
///   integer                   -> integer
///   numeric (FCFA), boolean   -> real / integer
///
/// La colonne `id` (text) est IMPLICITE pour chaque table PowerSync : on ne la
/// déclare pas, mais elle existe et reçoit l'UUID généré côté client (offline).
final schema = Schema([
  // ---- Référentiel ----
  Table('magasins', [
    Column.text('nom'),
    Column.text('code'),
    Column.text('adresse'),
    Column.text('telephone'),
    Column.integer('actif'),
    Column.text('date_creation'),
  ]),
  Table('roles', [
    Column.text('code'),
    Column.text('libelle'),
  ]),
  Table('utilisateurs', [
    Column.text('magasin_id'),
    Column.text('role_id'),
    Column.text('nom'),
    Column.text('login'),
    Column.text('mot_de_passe_hash'),
    Column.integer('actif'),
    Column.text('date_creation'),
    Column.integer('tentatives_echouees'),
    Column.text('verrou_jusqu_a'),
  ], indexes: [
    Index('utilisateurs_magasin', [IndexedColumn('magasin_id')]),
  ]),

  // ---- CRM (§2.6) ----
  Table('clients', [
    Column.text('nom'),
    Column.text('telephone'),
    Column.text('telephone_normalise'),
    Column.text('whatsapp'),
    Column.text('email'),
    Column.text('adresse'),
    Column.integer('solde_jetons'),
    Column.text('fusionne_vers'),
    Column.text('date_creation'),
  ], indexes: [
    Index('clients_tel_norm', [IndexedColumn('telephone_normalise')]),
  ]),
  Table('appareils', [
    Column.text('client_id'),
    Column.text('type'),
    Column.text('marque'),
    Column.text('modele'),
    Column.text('imei'),
    Column.text('numero_serie'),
    Column.text('notes'),
    Column.text('fusionne_vers'),
    Column.text('date_creation'),
    Column.text('qr_code'), // sticker QR apposé (réparation) — résolution au scan
  ], indexes: [
    Index('appareils_client', [IndexedColumn('client_id')]),
    Index('appareils_qr', [IndexedColumn('qr_code')]),
  ]),

  // ---- Réparations (§5.2 / §5.3) ----
  Table('reparations', [
    Column.text('appareil_id'),
    Column.text('magasin_id'),
    Column.text('technicien_id'),
    Column.text('probleme'),
    Column.text('etat_visuel'),
    Column.text('diagnostic'),
    Column.real('devis'),
    Column.text('statut'),
    Column.real('montant_main_oeuvre'),
    Column.real('montant_pieces'),
    Column.real('total'),
    Column.text('signature_depot'),
    Column.text('signature_retrait'),
    Column.text('date_creation'),
    Column.text('date_cloture'),
  ], indexes: [
    Index('reparations_magasin', [IndexedColumn('magasin_id')]),
  ]),
  Table('photos_appareil', [
    Column.text('reparation_id'),
    Column.text('type_photo'),
    Column.text('fichier_local'),
    Column.text('url_sync'),
    Column.text('statut_sync'),
    Column.text('date_creation'),
  ], indexes: [
    Index('photos_reparation', [IndexedColumn('reparation_id')]),
  ]),

  // ---- Catalogue + stock (§2.4 / §5.7) ----
  Table('produits', [
    Column.text('nom'),
    Column.text('categorie'),
    Column.text('code_barres'),
    Column.text('qr_code'),
    Column.real('prix_achat'),
    Column.real('prix_vente'),
    Column.integer('seuil_alerte'),
    Column.integer('actif'),
    Column.text('date_creation'),
  ]),
  Table('stocks_magasin', [
    Column.text('produit_id'),
    Column.text('magasin_id'),
    Column.integer('quantite_disponible'),
    Column.integer('quantite_en_transit'),
    Column.text('derniere_sync'),
  ], indexes: [
    Index('stocks_magasin', [IndexedColumn('magasin_id')]),
  ]),

  // ---- Caisse (§5.4) ----
  Table('caisses', [
    Column.text('magasin_id'),
    Column.text('utilisateur_id'),
    Column.text('ouverture'),
    Column.text('fermeture'),
    Column.real('fond_initial'),
    Column.real('cash_theorique'),
    Column.real('cash_reel'),
    Column.real('mobile_money_theorique'),
    Column.real('mobile_money_reel'),
    Column.real('ecart'),
    Column.text('statut'),
  ], indexes: [
    Index('caisses_magasin', [IndexedColumn('magasin_id')]),
  ]),

  // ---- Transaction encaissée unifiée (§7) ----
  Table('transactions', [
    Column.text('magasin_id'),
    Column.text('caisse_id'),
    Column.text('client_id'),
    Column.text('utilisateur_id'),
    Column.text('type'), // vente | reparation | mixte | retour
    Column.text('reparation_id'),
    Column.text('transaction_origine_id'),
    Column.real('total'),
    Column.real('remise_globale'),
    Column.integer('jetons_utilises'),
    Column.integer('jetons_gagnes'),
    Column.real('avoir_utilise'),
    Column.text('statut_sync'),
    Column.text('date'),
  ], indexes: [
    Index('transactions_caisse', [IndexedColumn('caisse_id')]),
  ]),

  // ---- Avoirs (crédits internes générés par un retour, §5.6) ----
  Table('avoirs', [
    Column.text('client_id'),
    Column.text('magasin_id'),
    Column.real('montant_initial'),
    Column.real('montant_restant'),
    Column.text('transaction_retour_id'),
    Column.text('transaction_utilisation_id'),
    Column.text('statut'), // actif | utilise
    Column.text('date_creation'),
  ], indexes: [
    Index('avoirs_client', [IndexedColumn('client_id')]),
  ]),
  Table('lignes_transaction', [
    Column.text('transaction_id'),
    Column.text('produit_id'),
    Column.integer('quantite'),
    Column.real('prix_unitaire'),
    Column.real('remise_ligne'),
  ], indexes: [
    Index('lignes_transaction', [IndexedColumn('transaction_id')]),
  ]),
  Table('paiements', [
    Column.text('transaction_id'),
    Column.text('methode'), // cash | wave | orange_money | mtn_momo
    Column.real('montant'),
    Column.text('date'),
  ], indexes: [
    Index('paiements_transaction', [IndexedColumn('transaction_id')]),
  ]),

  // ---- Mouvements de stock (§5.7 — cause rattachée) ----
  Table('mouvements_stock', [
    Column.text('produit_id'),
    Column.text('magasin_id'),
    Column.text('type'),
    Column.integer('quantite'),
    Column.text('motif'),
    Column.text('utilisateur_id'),
    Column.text('transaction_id'),
    Column.text('reparation_id'),
    Column.text('date'),
  ], indexes: [
    Index('mouvements_produit_magasin',
        [IndexedColumn('produit_id'), IndexedColumn('magasin_id')]),
  ]),

  // ---- Jetons (§5.9) ----
  Table('jeton_transactions', [
    Column.text('client_id'),
    Column.text('transaction_id'),
    Column.text('type'), // gain | depense | ajustement | annulation
    Column.integer('montant'),
    Column.text('motif'),
    Column.text('utilisateur_id'),
    Column.text('date'),
  ], indexes: [
    Index('jetons_client', [IndexedColumn('client_id')]),
  ]),

  // ---- Journal d'audit (§9) — écrit côté client (ex. retour) puis synchronisé.
  Table('journal_audit', [
    Column.text('utilisateur_id'),
    Column.text('magasin_id'),
    Column.text('action'),
    Column.text('entite'),
    Column.text('entite_id'),
    Column.text('details'),
    Column.text('date'),
  ]),

  // ---- Catalogues recherchables (réparations) ----
  Table('modeles_appareil', [
    Column.text('marque'),
    Column.text('modele'),
    Column.text('type'),
    Column.text('date_creation'),
  ], indexes: [
    Index('modeles_marque', [IndexedColumn('marque')]),
  ]),
  Table('pannes', [
    Column.text('libelle'),
    Column.text('date_creation'),
  ]),

  // ---- Transferts inter-magasins (Phase 2, §2.5) ----
  Table('transferts', [
    Column.text('produit_id'),
    Column.text('magasin_source_id'),
    Column.text('magasin_dest_id'),
    Column.integer('quantite'),
    Column.text('statut'), // en_transit | recu | annule
    Column.text('utilisateur_source_id'),
    Column.text('utilisateur_dest_id'),
    Column.text('date_creation'),
    Column.text('date_reception'),
  ], indexes: [
    Index('transferts_source', [IndexedColumn('magasin_source_id')]),
    Index('transferts_dest', [IndexedColumn('magasin_dest_id')]),
  ]),

  // ---- Inventaires physiques (Finitions Phase 2+) ----
  Table('inventaires', [
    Column.text('magasin_id'),
    Column.text('utilisateur_id'),
    Column.text('statut'), // en_cours | valide | annule
    Column.text('note'),
    Column.text('date_creation'),
    Column.text('date_validation'),
  ], indexes: [
    Index('inventaires_magasin', [IndexedColumn('magasin_id')]),
  ]),
  Table('lignes_inventaire', [
    Column.text('inventaire_id'),
    Column.text('produit_id'),
    Column.integer('quantite_theorique'),
    Column.integer('quantite_comptee'),
    Column.integer('ecart'),
  ], indexes: [
    Index('lignes_inventaire_inv', [IndexedColumn('inventaire_id')]),
  ]),

  // ---- Étiquettes QR (pool de stickers pré-imprimés, §QR centralisé) ----
  Table('etiquettes_qr', [
    Column.text('code'),
    Column.text('type'), // reparation | vente
    Column.text('statut'), // libre | utilise
    Column.text('magasin_id'),
    Column.text('appareil_id'),
    Column.text('date_creation'),
    Column.text('date_utilisation'),
  ], indexes: [
    Index('etiquettes_qr_code', [IndexedColumn('code')]),
    Index('etiquettes_qr_magasin', [IndexedColumn('magasin_id')]),
  ]),
]);
