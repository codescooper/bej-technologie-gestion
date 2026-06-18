import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../app_session.dart';
import '../data/repositories/produit_repository.dart';
import '../data/repositories/caisse_repository.dart';
import '../data/repositories/vente_repository.dart';
import '../data/repositories/client_repository.dart';
import '../data/repositories/retour_repository.dart';
import '../data/repositories/avoir_repository.dart';
import '../data/repositories/phase3_repository.dart';
import '../models/produit.dart';
import '../models/caisse.dart';
import '../models/client.dart';
import '../models/vente.dart';
import '../util/format.dart';
import '../util/ticket_pdf.dart';
import '../services/fne_service.dart';
import 'widgets/paiement_dialog.dart';
import 'retour_page.dart';

/// Onglet Vente comptoir (§5.5) : panier multi-lignes, paiement mixte, reçu.
class VentePage extends StatefulWidget {
  final ProduitRepository produitRepo;
  final CaisseRepository caisseRepo;
  final VenteRepository venteRepo;
  final ClientRepository clientRepo;
  final RetourRepository retourRepo;
  final AvoirRepository avoirRepo;
  final AppSession session;
  final VoidCallback onVente;
  final ValueNotifier<ProduitStock?>? produitInjecte;
  final FneService? fneService;
  final Phase3Repository? phase3Repo;

  const VentePage({
    super.key,
    required this.produitRepo,
    required this.caisseRepo,
    required this.venteRepo,
    required this.clientRepo,
    required this.retourRepo,
    required this.avoirRepo,
    required this.session,
    required this.onVente,
    this.produitInjecte,
    this.fneService,
    this.phase3Repo,
  });

  @override
  State<VentePage> createState() => _VentePageState();
}

class _VentePageState extends State<VentePage> {
  final List<CartLine> _cart = [];
  Map<String, int> _dispo = {};
  Client? _client;
  num _remiseGlobale = 0;
  int _jetonsUtilises = 0;
  num _avoirDispo = 0; // solde d'avoirs actifs du client
  num _avoirUtilise = 0;
  String? _avoirId; // avoir appliqué (le plus ancien)

  final _scanCtrl = TextEditingController();
  final _scanFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.produitInjecte?.addListener(_consommerInjection);
    _chargerMultiplicateur();
  }

  Future<void> _chargerMultiplicateur() async {
    final m = await widget.phase3Repo
            ?.multiplicateurJetonsActif(widget.session.magasinId) ??
        1.0;
    if (mounted) setState(() => _multiplicateur = m);
  }

  /// Produit envoyé par le scan universel : ajout au panier, puis on vide le
  /// notifier pour ne pas ré-ajouter au prochain rebuild.
  void _consommerInjection() {
    final n = widget.produitInjecte;
    final ps = n?.value;
    if (ps != null) {
      _addProduit(ps);
      n!.value = null;
    }
  }

  @override
  void dispose() {
    widget.produitInjecte?.removeListener(_consommerInjection);
    _scanCtrl.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  num get _sousTotal => _cart.fold<num>(0, (s, l) => s + l.sousTotal);
  num get _total {
    final t = _sousTotal - _remiseGlobale - _jetonsUtilises - _avoirUtilise;
    return t < 0 ? 0 : t;
  }

  double _multiplicateur = 1.0;

  int get _jetonsGagnes => ((_total ~/ 100) * _multiplicateur).round();

  void _addProduit(ProduitStock ps) {
    final dispo = ps.quantiteDispo;
    final existing = _cart.where((l) => l.produit.id == ps.produit.id).toList();
    setState(() {
      if (existing.isNotEmpty) {
        if (existing.first.quantite < dispo) existing.first.quantite++;
      } else if (dispo > 0) {
        _cart.add(CartLine(ps.produit, quantite: 1));
      }
    });
  }

  void _changeQty(CartLine l, int delta) {
    final max = _dispo[l.produit.id] ?? l.quantite;
    setState(() {
      l.quantite += delta;
      if (l.quantite > max) l.quantite = max;
      if (l.quantite <= 0) _cart.remove(l);
    });
  }

  void _reset() {
    setState(() {
      _cart.clear();
      _client = null;
      _remiseGlobale = 0;
      _jetonsUtilises = 0;
      _avoirDispo = 0;
      _avoirUtilise = 0;
      _avoirId = null;
    });
  }

  void _ouvrirRetour() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RetourPage(
        retourRepo: widget.retourRepo,
        caisseRepo: widget.caisseRepo,
        session: widget.session,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Caisse?>(
      stream: widget.caisseRepo.watchCaisseOuverte(widget.session.magasinId),
      builder: (context, caisseSnap) {
        final caisse = caisseSnap.data;
        if (caisse == null) {
          return const Center(
            child: Text('Caisse fermée. Ouvrez la caisse pour vendre.'),
          );
        }
        return Row(
          children: [
            Expanded(flex: 2, child: _buildCatalogue()),
            const VerticalDivider(width: 1),
            Expanded(flex: 3, child: _buildPanier(caisse)),
          ],
        );
      },
    );
  }

  Widget _buildCatalogue() {
    return Column(
      children: [
        _buildScanField(),
        Expanded(
          child: StreamBuilder<List<ProduitStock>>(
            stream: widget.produitRepo.watchCatalogue(widget.session.magasinId),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snap.data!;
              _dispo = {
                for (final ps in items) ps.produit.id: ps.quantiteDispo
              };
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final ps = items[i];
                  final rupture = ps.quantiteDispo <= 0;
                  return ListTile(
                    dense: true,
                    enabled: !rupture,
                    title: Text(ps.produit.nom),
                    subtitle: Text(
                        '${fcfa(ps.produit.prixVente)}  •  stock ${ps.quantiteDispo}'),
                    trailing: const Icon(Icons.add_circle_outline),
                    onTap: rupture ? null : () => _addProduit(ps),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Champ de scan code-barres (§8) : un lecteur USB se comporte comme un
  /// clavier qui saisit le code puis envoie « Entrée ». On garde le focus pour
  /// enchaîner les scans.
  Widget _buildScanField() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TextField(
        controller: _scanCtrl,
        focusNode: _scanFocus,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.qr_code_scanner),
          hintText: 'Scanner ou saisir un code-barres',
          border: OutlineInputBorder(),
        ),
        onSubmitted: _onScan,
      ),
    );
  }

  Future<void> _onScan(String code) async {
    final c = code.trim();
    _scanCtrl.clear();
    if (c.isEmpty) {
      _scanFocus.requestFocus();
      return;
    }
    final ps =
        await widget.produitRepo.findByCodeBarres(widget.session.magasinId, c);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ps == null) {
      messenger.showSnackBar(SnackBar(
          content: Text('Code-barres inconnu : $c'),
          duration: const Duration(seconds: 2)));
    } else if (ps.quantiteDispo <= 0) {
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.orange.shade800,
          content: Text('${ps.produit.nom} — rupture de stock')));
    } else {
      _addProduit(ps);
    }
    _scanFocus.requestFocus();
  }

  Widget _buildPanier(Caisse caisse) {
    return Column(
      children: [
        Expanded(
          child: _cart.isEmpty
              ? const Center(child: Text('Panier vide — touchez un produit.'))
              : ListView(
                  children: _cart.map((l) {
                    return ListTile(
                      dense: true,
                      title: Text(l.produit.nom),
                      subtitle: Text(
                          '${fcfa(l.prixUnitaire)} × ${l.quantite} = ${fcfa(l.sousTotal)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              onPressed: () => _changeQty(l, -1),
                              icon: const Icon(Icons.remove_circle_outline)),
                          Text('${l.quantite}'),
                          IconButton(
                              onPressed: () => _changeQty(l, 1),
                              icon: const Icon(Icons.add_circle_outline)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const Divider(height: 1),
        _buildOptions(),
        _buildTotaux(caisse),
      ],
    );
  }

  Widget _buildOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _ouvrirRetour,
              icon: const Icon(Icons.assignment_return, size: 18),
              label: const Text('Retour / Avoir'),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.person, size: 18),
                  label: Text(_client == null ? 'Client de passage' : _client!.nom),
                  onPressed: _pickClient,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _setRemise,
                child: Text('Remise: ${fcfa(_remiseGlobale)}'),
              ),
            ],
          ),
          if (_client != null && _client!.soldeJetons > 0)
            Row(
              children: [
                Expanded(child: Text('Jetons (solde ${_client!.soldeJetons})')),
                OutlinedButton(
                  onPressed: _setJetons,
                  child: Text('Utiliser: $_jetonsUtilises'),
                ),
              ],
            ),
          if (_avoirDispo > 0)
            Row(
              children: [
                Expanded(child: Text('Avoir (solde ${fcfa(_avoirDispo)})')),
                OutlinedButton(
                  onPressed: _appliquerAvoir,
                  child: Text(_avoirUtilise > 0
                      ? 'Retirer (${fcfa(_avoirUtilise)})'
                      : 'Appliquer'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTotaux(Caisse caisse) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _ligne('Sous-total', fcfa(_sousTotal)),
          if (_remiseGlobale > 0) _ligne('Remise', '- ${fcfa(_remiseGlobale)}'),
          if (_jetonsUtilises > 0) _ligne('Jetons', '- ${fcfa(_jetonsUtilises)}'),
          if (_avoirUtilise > 0) _ligne('Avoir', '- ${fcfa(_avoirUtilise)}'),
          const Divider(),
          _ligne('TOTAL', fcfa(_total), bold: true),
          if (_jetonsGagnes > 0)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _multiplicateur > 1.0
                    ? '+ $_jetonsGagnes jetons × ${_multiplicateur.toStringAsFixed(1)} 🎉'
                    : '+ $_jetonsGagnes jetons gagnés',
                style: TextStyle(color: Colors.green.shade700, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_cart.isEmpty || !widget.session.peutEncaisser)
                  ? null
                  : () => _encaisser(caisse),
              icon: const Icon(Icons.payments),
              label: Text(widget.session.peutEncaisser
                  ? 'Encaisser ${fcfa(_total)}'
                  : 'Encaissement non autorisé'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ligne(String l, String v, {bool bold = false}) {
    final st = bold
        ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(l, style: st), Text(v, style: st)],
      ),
    );
  }

  Future<void> _pickClient() async {
    final clients = await widget.clientRepo.listAll();
    if (!mounted) return;
    final chosen = await showDialog<Client?>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Choisir le client'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('— Client de passage —'),
          ),
          ...clients.map((c) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, c),
                child: Text('${c.nom}  (jetons: ${c.soldeJetons})'),
              )),
        ],
      ),
    );
    // Réinitialise et charge le solde d'avoir du client choisi.
    num avoirDispo = 0;
    String? avoirId;
    if (chosen != null) {
      final avoirs = await widget.avoirRepo.actifsParClient(chosen.id);
      if (avoirs.isNotEmpty) {
        avoirDispo = avoirs.fold<num>(0, (s, a) => s + a.montantRestant);
        avoirId = avoirs.first.id; // applique le plus ancien
      }
    }
    if (!mounted) return;
    setState(() {
      _client = chosen;
      _jetonsUtilises = 0;
      _avoirDispo = avoirDispo;
      _avoirId = avoirId;
      _avoirUtilise = 0;
    });
  }

  Future<void> _appliquerAvoir() async {
    if (_avoirDispo <= 0) return;
    // Applique le min entre l'avoir dispo et le montant restant à payer.
    final base = _sousTotal - _remiseGlobale - _jetonsUtilises;
    final applicable = _avoirUtilise > 0
        ? 0
        : (base < _avoirDispo ? base : _avoirDispo);
    setState(() {
      _avoirUtilise = _avoirUtilise > 0 ? 0 : (applicable < 0 ? 0 : applicable);
    });
  }

  Future<void> _setRemise() async {
    final ctrl = TextEditingController(text: _remiseGlobale.toString());
    final v = await _askNumber('Remise globale (FCFA)', ctrl);
    if (v != null) setState(() => _remiseGlobale = v);
  }

  Future<void> _setJetons() async {
    final maxJetons = _client?.soldeJetons ?? 0;
    final ctrl = TextEditingController(text: _jetonsUtilises.toString());
    final v = await _askNumber('Jetons à utiliser (max $maxJetons)', ctrl);
    if (v != null) {
      setState(() => _jetonsUtilises = v.toInt().clamp(0, maxJetons));
    }
  }

  Future<num?> _askNumber(String label, TextEditingController ctrl) {
    return showDialog<num>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, num.tryParse(ctrl.text.trim()) ?? 0),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _encaisser(Caisse caisse) async {
    // Si l'avoir (et/ou jetons) couvre tout, pas de paiement cash à saisir.
    List<PaiementInput> paiements = [];
    if (_total > 0) {
      final saisi = await showDialog<List<PaiementInput>>(
        context: context,
        builder: (_) => PaiementDialog(total: _total),
      );
      if (saisi == null) return;
      paiements = saisi;
    }

    final result = await widget.venteRepo.enregistrerVente(
      magasinId: widget.session.magasinId,
      caisseId: caisse.id,
      utilisateurId: widget.session.userId,
      clientId: _client?.id,
      lignes: List.of(_cart),
      remiseGlobale: _remiseGlobale,
      jetonsUtilises: _jetonsUtilises,
      avoirId: _avoirUtilise > 0 ? _avoirId : null,
      avoirUtilise: _avoirUtilise,
      paiements: paiements,
      multiplicateurJetons: _multiplicateur,
    );

    // FNE/DGI : soumission asynchrone, non bloquante
    if (widget.fneService != null) {
      widget.fneService!.soumettre(
        transactionId: result.transactionId,
        magasinId: widget.session.magasinId,
        total: result.total,
        date: DateTime.now(),
        clientNom: _client?.nom,
        lignes: _cart
            .map((l) => (
                  libelle: l.produit.nom,
                  quantite: l.quantite,
                  prixUnitaire: l.prixUnitaire,
                ))
            .toList(),
      ).then((fne) {
        if (!mounted) return;
        if (fne?.numeroFacture != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Facture DGI : ${fne!.numeroFacture}'),
            backgroundColor: Colors.green.shade700,
          ));
        }
      });
    }

    // Capture les données du ticket AVANT la réinitialisation du panier.
    final ticket = TicketData(
      magasin: widget.session.magasinNom,
      ref: result.transactionId,
      date: DateTime.now(),
      client: _client?.nom,
      lignes: _cart
          .map((l) => TicketLigne(
              l.produit.nom, l.quantite, l.prixUnitaire, l.sousTotal))
          .toList(),
      sousTotal: _sousTotal,
      remise: _remiseGlobale,
      jetons: _jetonsUtilises,
      avoir: _avoirUtilise,
      total: result.total,
      paiements: paiements
          .map((p) => (methode: p.methode, montant: p.montant))
          .toList(),
      jetonsGagnes: result.jetonsGagnes,
    );

    _reset();
    widget.onVente();
    if (!mounted) return;
    _scanFocus.requestFocus();
    await showDialog(
      context: context,
      builder: (_) => _RecuDialog(result: result, ticket: ticket),
    );
  }
}

/// Reçu interne avec QR (§5.5).
class _RecuDialog extends StatelessWidget {
  final VenteResult result;
  final TicketData ticket;
  const _RecuDialog({required this.result, required this.ticket});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reçu interne'),
      // Largeur fixe : court-circuite la mesure intrinsèque de l'AlertDialog,
      // sinon le LayoutBuilder interne de QrImageView fait planter le rendu.
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 120,
              height: 120,
              child: QrImageView(
                data: 'BEJ:${result.transactionId}',
                size: 120,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText('Réf : ${result.transactionId}',
                style: Theme.of(context).textTheme.bodySmall),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total payé'),
              Text(fcfa(result.total),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            if (result.jetonsGagnes > 0)
              Text('+ ${result.jetonsGagnes} jetons gagnés',
                  style: TextStyle(color: Colors.green.shade700)),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => imprimerTicket(ticket),
          icon: const Icon(Icons.print),
          label: const Text('Imprimer'),
        ),
        FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Terminer')),
      ],
    );
  }
}
