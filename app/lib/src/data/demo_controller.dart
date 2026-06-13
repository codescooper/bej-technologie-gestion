import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

import '../app_session.dart';
import '../util/format.dart';
import 'ref_ids.dart';
import 'sync_service.dart';
import '../models/vente.dart';
import '../models/reparation.dart';
import 'repositories/client_repository.dart';
import 'repositories/produit_repository.dart';
import 'repositories/caisse_repository.dart';
import 'repositories/vente_repository.dart';
import 'repositories/reparation_repository.dart';
import 'repositories/appareil_repository.dart';
import 'repositories/transfert_repository.dart';
import 'repositories/inventaire_repository.dart';
import 'repositories/retour_repository.dart';
import 'repositories/dashboard_repository.dart';

enum DemoStatut { pret, enCours, enPause, termine, erreur }

/// Une étape du scénario de démonstration.
class DemoStep {
  final IconData icon;
  final String titre;
  final String narration;
  final Future<String> Function() action;
  DemoStep(this.icon, this.titre, this.narration, this.action);
}

/// Moteur du **Mode Démo** (présentation live + smoke-test autonome).
///
/// Joue un scénario complet de bout en bout en appelant les VRAIS dépôts :
/// chaque étape exécute une opération réelle (création de client, vente,
/// réparation, transfert, inventaire, retour, clôture, synchronisation) et en
/// affiche le résultat. Comme tout est réel, une régression est visible
/// immédiatement (l'étape passe en rouge). Les données créées sont préfixées
/// « DÉMO ».
class DemoController extends ChangeNotifier {
  final PowerSyncDatabase db;
  final AppSession session;
  final ClientRepository clientRepo;
  final ProduitRepository produitRepo;
  final CaisseRepository caisseRepo;
  final VenteRepository venteRepo;
  final ReparationRepository reparationRepo;
  final AppareilRepository appareilRepo;
  final TransfertRepository transfertRepo;
  final InventaireRepository inventaireRepo;
  final RetourRepository retourRepo;
  final DashboardRepository dashboardRepo;
  final SyncService syncService;

  final _uuid = const Uuid();

  DemoController({
    required this.db,
    required this.session,
    required this.clientRepo,
    required this.produitRepo,
    required this.caisseRepo,
    required this.venteRepo,
    required this.reparationRepo,
    required this.appareilRepo,
    required this.transfertRepo,
    required this.inventaireRepo,
    required this.retourRepo,
    required this.dashboardRepo,
    required this.syncService,
  });

  late final List<DemoStep> steps = _construireSteps();

  DemoStatut statut = DemoStatut.pret;
  int index = -1; // étape en cours (-1 avant démarrage)
  final List<String?> resultats = [];
  double vitesse = 1.0; // multiplicateur de vitesse (0.5x lent … 3x rapide)
  String? erreur;

  bool _pause = false;
  bool _stop = false;

  // --- état partagé entre étapes ---
  String? _clientId, _caisseId, _venteId, _repId;
  String? _transfertId, _transfertNom, _demoProduitId;
  num _fond = 0;

  String get _mag => session.magasinId;
  String get _user => session.userId;
  String get _autreMag => magasinsRef
      .firstWhere((m) => m.id != _mag, orElse: () => magasinsRef.first)
      .id;
  String _nomMag(String id) =>
      magasinsRef.firstWhere((m) => m.id == id, orElse: () => magasinsRef.first).nom;

  String? resultat(int i) => (i >= 0 && i < resultats.length) ? resultats[i] : null;

  bool get enCours => statut == DemoStatut.enCours || statut == DemoStatut.enPause;

  /// Lance (ou relance) le scénario depuis le début.
  Future<void> demarrer() async {
    if (enCours) return;
    _reset();
    statut = DemoStatut.enCours;
    notifyListeners();

    for (var i = 0; i < steps.length; i++) {
      if (_stop) break;
      index = i;
      notifyListeners();
      await _pause700(); // laisse lire le titre
      if (_stop) break;
      try {
        resultats[i] = await steps[i].action();
      } catch (e) {
        resultats[i] = 'ERREUR : $e';
        erreur = '${steps[i].titre} — $e';
        statut = DemoStatut.erreur;
        notifyListeners();
        return;
      }
      notifyListeners();
      await _pause1300(); // laisse lire le résultat
    }

    if (!_stop) {
      index = steps.length;
      statut = DemoStatut.termine;
    } else {
      statut = DemoStatut.pret;
    }
    notifyListeners();
  }

  void pause() {
    if (statut == DemoStatut.enCours) {
      _pause = true;
      statut = DemoStatut.enPause;
      notifyListeners();
    }
  }

  void reprendre() {
    if (statut == DemoStatut.enPause) {
      _pause = false;
      statut = DemoStatut.enCours;
      notifyListeners();
    }
  }

  void arreter() {
    _stop = true;
    _pause = false;
    notifyListeners();
  }

  void setVitesse(double v) {
    vitesse = v.clamp(0.5, 3.0);
    notifyListeners();
  }

  void _reset() {
    index = -1;
    _stop = false;
    _pause = false;
    erreur = null;
    resultats
      ..clear()
      ..addAll(List<String?>.filled(steps.length, null));
    _clientId = _caisseId = _venteId = _repId = null;
    _transfertId = _transfertNom = _demoProduitId = null;
    _fond = 0;
  }

  Future<void> _pause700() => _sleep(700);
  Future<void> _pause1300() => _sleep(1300);

  /// Sommeil découpé qui respecte pause/stop et la vitesse choisie.
  Future<void> _sleep(int ms) async {
    final cible = (ms / vitesse).round();
    var passe = 0;
    while (passe < cible && !_stop) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      while (_pause && !_stop) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      passe += 100;
    }
  }

  // ===================================================================
  //  SCÉNARIO
  // ===================================================================
  List<DemoStep> _construireSteps() {
    final suffixe = DateTime.now().millisecondsSinceEpoch.toString();
    final suffixeCourt = suffixe.substring(suffixe.length - 5);

    return [
      DemoStep(Icons.verified_user, 'Connexion & rôles',
          'La démo s\'exécute avec le compte connecté. Les droits dépendent du rôle (§6).',
          () async {
        return 'Connecté : ${session.userNom} — ${session.roleLibelle} · '
            'magasin ${session.magasinNom}';
      }),

      DemoStep(Icons.person_add, 'Créer un client',
          'Création d\'une fiche client (anti-doublon sur le téléphone).', () async {
        final c = await clientRepo.create(
          nom: 'DÉMO — Client Vitrine',
          telephone: '07$suffixeCourt${suffixeCourt.substring(0, 3)}',
        );
        _clientId = c.id;
        return 'Client créé : ${c.nom} (${c.telephoneNormalise})';
      }),

      DemoStep(Icons.lock_open, 'Ouvrir la caisse',
          'Une seule caisse ouverte par magasin. Fond de caisse initial saisi.',
          () async {
        final existante = await caisseRepo.caisseOuverte(_mag);
        if (existante != null) {
          _caisseId = existante.id;
        } else {
          _caisseId = await caisseRepo.ouvrir(
              magasinId: _mag, utilisateurId: _user, fondInitial: 50000);
        }
        final f = await db
            .getAll('SELECT fond_initial AS f FROM caisses WHERE id = ?', [_caisseId]);
        _fond = (f.first['f'] as num?) ?? 0;
        return 'Caisse ouverte — fond ${fcfa(_fond)}';
      }),

      DemoStep(Icons.point_of_sale, 'Vente comptoir (paiement mixte)',
          'Vente d\'un produit avec règlement en espèces + Wave ; jetons crédités.',
          () async {
        final cat = await produitRepo.watchCatalogue(_mag).first;
        final dispo = cat.where((p) => p.quantiteDispo > 0).toList()
          ..sort((a, b) => b.quantiteDispo - a.quantiteDispo);
        if (dispo.isEmpty) throw 'Aucun produit en stock';
        final v = dispo.first;
        final q = v.quantiteDispo >= 2 ? 2 : 1;
        final total = v.produit.prixVente * q;
        final cash = total ~/ 2;
        final wave = total - cash;
        final res = await venteRepo.enregistrerVente(
          magasinId: _mag,
          caisseId: _caisseId!,
          utilisateurId: _user,
          clientId: _clientId,
          lignes: [CartLine(v.produit, quantite: q)],
          paiements: [PaiementInput('cash', cash), PaiementInput('wave', wave)],
        );
        _venteId = res.transactionId;
        return 'Vente ${fcfa(res.total)} — $q × ${v.produit.nom} '
            '(espèces ${fcfa(cash)} + Wave ${fcfa(wave)}) · ${res.jetonsGagnes} jetons';
      }),

      DemoStep(Icons.build_circle, 'Réparation — réception',
          'Enregistrement d\'un appareil + d\'une réparation (statut Reçu).', () async {
        final app = await appareilRepo.creer(
          clientId: _clientId!,
          type: 'Téléphone',
          marque: 'Apple',
          modele: 'iPhone 12',
          imei: 'DEMO$suffixeCourt',
        );
        _repId = await reparationRepo.creer(
          appareilId: app.id,
          magasinId: _mag,
          technicienId: RefIds.userTechnicien,
          probleme: 'Écran cassé',
          etatVisuel: 'Rayures au dos',
          devis: 15000,
        );
        return 'Réparation créée — iPhone 12, « Écran cassé » (devis ${fcfa(15000)})';
      }),

      DemoStep(Icons.handyman, 'Réparation — diagnostic & pièce',
          'Saisie du diagnostic, prélèvement d\'une pièce du stock, passage à Prêt.',
          () async {
        final cat = await produitRepo.watchCatalogue(_mag).first;
        final piece = cat.where((p) => p.quantiteDispo > 0).toList();
        var pieceTxt = 'sans pièce';
        if (piece.isNotEmpty) {
          final pc = piece.first;
          await reparationRepo.consommerPiece(
            reparationId: _repId!,
            produitId: pc.produit.id,
            magasinId: _mag,
            prixUnitaire: pc.produit.prixVente,
            quantite: 1,
            utilisateurId: _user,
          );
          pieceTxt = '1 × ${pc.produit.nom} prélevé du stock';
        }
        await reparationRepo.majDiagnostic(_repId!,
            diagnostic: 'Vitre à remplacer', montantMainOeuvre: 10000);
        await reparationRepo.changerStatut(_repId!, StatutReparation.pret);
        return 'Diagnostic saisi, $pieceTxt, main-d\'œuvre ${fcfa(10000)} → statut Prêt';
      }),

      DemoStep(Icons.assignment_turned_in, 'Réparation — encaissement au retrait',
          'Encaissement (transaction « réparation » rattachée à la caisse) → Livré.',
          () async {
        final rep = await reparationRepo.getById(_repId!);
        final total = rep?.reparation.total ?? 0;
        final res = await reparationRepo.encaisserRetrait(
          reparationId: _repId!,
          magasinId: _mag,
          caisseId: _caisseId!,
          utilisateurId: _user,
          paiements: [PaiementInput('cash', total)],
        );
        return 'Réparation encaissée ${fcfa(res.total)} (espèces) → statut Livré';
      }),

      DemoStep(Icons.call_made, 'Transfert inter-magasins — envoi',
          'Envoi de stock vers un autre magasin : la quantité part « en transit ».',
          () async {
        final cat = await produitRepo.watchCatalogue(_mag).first;
        final cand = cat.where((p) => p.quantiteDispo >= 3).toList();
        final p = cand.isNotEmpty
            ? cand.first
            : (cat.where((p) => p.quantiteDispo > 0).toList()
              ..sort((a, b) => b.quantiteDispo - a.quantiteDispo))
                .first;
        final q = p.quantiteDispo >= 3 ? 3 : p.quantiteDispo;
        _transfertNom = p.produit.nom;
        _transfertId = await transfertRepo.creer(
          produitId: p.produit.id,
          magasinSourceId: _mag,
          magasinDestId: _autreMag,
          quantite: q,
          utilisateurId: _user,
        );
        return '$q × ${p.produit.nom} : ${session.magasinNom} → ${_nomMag(_autreMag)} (en transit)';
      }),

      DemoStep(Icons.call_received, 'Transfert — réception',
          'Le magasin destinataire confirme : le stock lui est ajouté.', () async {
        if (_transfertId == null) return 'Aucun transfert à confirmer';
        await transfertRepo.confirmerReception(
            transfertId: _transfertId!, utilisateurId: _user);
        return 'Réception confirmée à ${_nomMag(_autreMag)} : '
            '${_transfertNom ?? 'produit'} ajouté au stock';
      }),

      DemoStep(Icons.move_to_inbox, 'Réapprovisionnement',
          'Détection d\'un produit sous le seuil et transfert depuis un magasin fournisseur.',
          () async {
        // Produit de démo sous seuil ici, bien fourni dans l'autre magasin.
        _demoProduitId = _uuid.v4();
        final now = DateTime.now().toUtc().toIso8601String();
        await db.writeTransaction((tx) async {
          await tx.execute(
            'INSERT INTO produits(id, nom, categorie, prix_achat, prix_vente, '
            'seuil_alerte, actif, date_creation) VALUES(?,?,?,?,?,?,?,?)',
            [_demoProduitId, 'DÉMO — Pièce rare $suffixeCourt', 'Démo', 3000,
              5000, 10, 1, now],
          );
          await tx.execute(
            'INSERT INTO stocks_magasin(id, produit_id, magasin_id, '
            'quantite_disponible, quantite_en_transit) VALUES(?,?,?,?,?)',
            [_uuid.v4(), _demoProduitId, _mag, 2, 0],
          );
          await tx.execute(
            'INSERT INTO stocks_magasin(id, produit_id, magasin_id, '
            'quantite_disponible, quantite_en_transit) VALUES(?,?,?,?,?)',
            [_uuid.v4(), _demoProduitId, _autreMag, 30, 0],
          );
        });
        final sugg = await produitRepo.suggestionsReappro(_mag);
        final s = sugg.firstWhere((x) => x.produitId == _demoProduitId,
            orElse: () => sugg.first);
        if (s.sources.isEmpty) {
          return '${s.produitNom} sous seuil (${s.disponible}/${s.seuil}) — '
              'aucun fournisseur disponible';
        }
        final src = s.sources.first;
        await transfertRepo.creer(
          produitId: s.produitId,
          magasinSourceId: src.magasinId,
          magasinDestId: _mag,
          quantite: 8,
          utilisateurId: _user,
        );
        return '${s.produitNom} sous seuil (${s.disponible}/${s.seuil}) → '
            'réappro de 8 depuis ${src.magasinNom} (à confirmer)';
      }),

      DemoStep(Icons.fact_check, 'Inventaire physique',
          'Comptage physique : un écart saisi est appliqué au stock à la validation.',
          () async {
        final invId =
            await inventaireRepo.demarrer(magasinId: _mag, utilisateurId: _user);
        final lignes = await inventaireRepo.lignes(invId);
        if (lignes.isEmpty) throw 'Aucun produit à inventorier';
        final cible = lignes.first;
        final compte = cible.theorique + 3;
        await inventaireRepo.saisir(ligneId: cible.id, comptee: compte);
        final n =
            await inventaireRepo.valider(inventaireId: invId, utilisateurId: _user);
        return '${cible.produitNom} compté $compte (théo ${cible.theorique}, '
            'écart +3) → $n produit(s) ajusté(s)';
      }),

      DemoStep(Icons.assignment_return, 'Retour / Avoir',
          'Retour partiel d\'une vente : stock réintégré, jetons annulés, AVOIR créé.',
          () async {
        if (_venteId == null) throw 'Pas de vente à retourner';
        final lignes = await retourRepo.lignesVendues(_venteId!);
        if (lignes.isEmpty) throw 'Vente sans ligne retournable';
        final l = lignes.first;
        final r = await retourRepo.enregistrerRetour(
          transactionOrigineId: _venteId!,
          magasinId: _mag,
          caisseId: _caisseId!,
          utilisateurId: _user,
          clientId: _clientId!,
          lignes: [
            LigneRetour(
                produitId: l.produitId,
                produitNom: l.produitNom,
                quantite: 1,
                prixUnitaire: l.prixUnitaire),
          ],
        );
        return 'Retour de 1 × ${l.produitNom} → avoir ${fcfa(r.montant)} '
            'pour le client (${r.jetonsAnnules} jetons annulés)';
      }),

      DemoStep(Icons.insights, 'Tableau de bord (jour)',
          'Indicateurs du magasin : CA, ventes, réparations, alertes de stock.',
          () async {
        final d = await dashboardRepo.load(_mag);
        return 'CA du jour ${fcfa(d.caTotal)} · ${d.nbVentes} vente(s) · '
            '${d.nbReparations} réparation(s) encaissée(s) · ${d.stockBasCount} alerte(s)';
      }),

      DemoStep(Icons.lock_clock, 'Clôture de caisse',
          'Comptage de fin de journée : l\'écart avec le théorique est calculé.',
          () async {
        final t = await caisseRepo.totauxTheoriques(_caisseId!);
        final theoCash = _fond + t.cash;
        const manque = 500; // écart volontaire pour illustrer la détection
        await caisseRepo.cloturer(
          caisseId: _caisseId!,
          cashReel: theoCash - manque,
          mobileReel: t.mobile,
        );
        return 'Théorique cash ${fcfa(theoCash)}, compté ${fcfa(theoCash - manque)} '
            '→ écart ${fcfa(-manque)} (manque simulé)';
      }),

      DemoStep(Icons.summarize, 'Reporting consolidé + rapprochement',
          'Vue groupe : CA par magasin et rapprochement des écarts de caisse.',
          () async {
        final cons = await dashboardRepo.consolide();
        final rap = await dashboardRepo.rapprochementCaisse();
        final caGroupe = cons.fold<num>(0, (s, r) => s + r.ca);
        final clots = rap.fold<int>(0, (s, r) => s + r.nbCloturees);
        final ecart = rap.fold<num>(0, (s, r) => s + r.ecartCumule);
        return 'Groupe : ${cons.length} magasins · CA ${fcfa(caGroupe)} · '
            '$clots clôture(s) · écart cumulé ${fcfa(ecart)}';
      }),

      DemoStep(Icons.cloud_upload, 'Synchronisation serveur',
          'Envoi de toutes les opérations locales vers le serveur (offline-first).',
          () async {
        try {
          final n = await syncService.push();
          final reste = await syncService.pendingCount();
          return '$n opération(s) synchronisée(s) · file restante : $reste';
        } catch (e) {
          final reste = await syncService.pendingCount();
          return 'Hors ligne — $reste opération(s) conservée(s) en local '
              '(envoi au retour du réseau)';
        }
      }),
    ];
  }
}
