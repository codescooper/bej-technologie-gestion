import 'package:flutter/material.dart';
import '../app_session.dart';
import '../data/api_client.dart';
import '../data/sync_service.dart';
import '../data/ref_ids.dart';
import '../data/repositories/client_repository.dart';
import '../data/repositories/produit_repository.dart';
import '../data/repositories/caisse_repository.dart';
import '../data/repositories/vente_repository.dart';
import '../data/repositories/reparation_repository.dart';
import '../data/repositories/appareil_repository.dart';
import '../data/repositories/photo_repository.dart';
import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/retour_repository.dart';
import '../data/repositories/avoir_repository.dart';
import '../data/repositories/catalogue_repository.dart';
import '../data/repositories/transfert_repository.dart';
import '../data/repositories/inventaire_repository.dart';
import '../data/demo_controller.dart';
import 'clients_page.dart';
import 'transferts_page.dart';
import 'dashboard_page.dart';
import 'stock_page.dart';
import 'caisse_page.dart';
import 'vente_page.dart';
import 'reparations_page.dart';
import 'guide_page.dart';
import 'demo_page.dart';

/// Coquille applicative : navigation 4 onglets, sélecteur de magasin et
/// synchronisation globale (état online + file en attente).
class AppShell extends StatefulWidget {
  final AppSession session;
  final ClientRepository clientRepo;
  final ProduitRepository produitRepo;
  final CaisseRepository caisseRepo;
  final VenteRepository venteRepo;
  final ReparationRepository reparationRepo;
  final AppareilRepository appareilRepo;
  final PhotoRepository photoRepo;
  final DashboardRepository dashboardRepo;
  final RetourRepository retourRepo;
  final AvoirRepository avoirRepo;
  final CatalogueRepository catalogueRepo;
  final TransfertRepository transfertRepo;
  final InventaireRepository inventaireRepo;
  final DemoController? demoController;
  final SyncService syncService;
  final ApiClient api;

  const AppShell({
    super.key,
    required this.session,
    required this.clientRepo,
    required this.produitRepo,
    required this.caisseRepo,
    required this.venteRepo,
    required this.reparationRepo,
    required this.appareilRepo,
    required this.photoRepo,
    required this.dashboardRepo,
    required this.retourRepo,
    required this.avoirRepo,
    required this.catalogueRepo,
    required this.transfertRepo,
    required this.inventaireRepo,
    this.demoController,
    required this.syncService,
    required this.api,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _online = false;
  int _pending = 0;
  DateTime? _lastSync;
  bool _syncing = false;

  static const _titles = ['Clients', 'Stock', 'Caisse', 'Vente', 'Réparations'];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final online = await widget.api.health();
    final pending = await widget.syncService.pendingCount();
    if (!mounted) return;
    setState(() {
      _online = online;
      _pending = pending;
    });
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final n = await widget.syncService.push();
      if (!mounted) return;
      setState(() => _lastSync = DateTime.now());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Synchronisation : $n opération(s) envoyée(s).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red.shade700,
        content: Text('Hors ligne — données conservées en local.'),
      ));
    } finally {
      if (mounted) setState(() => _syncing = false);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final pages = [
          ClientsPage(
            clientRepo: widget.clientRepo,
            reparationRepo: widget.reparationRepo,
            avoirRepo: widget.avoirRepo,
          ),
          StockPage(
            produitRepo: widget.produitRepo,
            transfertRepo: widget.transfertRepo,
            inventaireRepo: widget.inventaireRepo,
            session: widget.session,
          ),
          CaissePage(caisseRepo: widget.caisseRepo, session: widget.session),
          VentePage(
            produitRepo: widget.produitRepo,
            caisseRepo: widget.caisseRepo,
            venteRepo: widget.venteRepo,
            clientRepo: widget.clientRepo,
            retourRepo: widget.retourRepo,
            avoirRepo: widget.avoirRepo,
            session: widget.session,
            onVente: _refresh,
          ),
          ReparationsPage(
            reparationRepo: widget.reparationRepo,
            appareilRepo: widget.appareilRepo,
            clientRepo: widget.clientRepo,
            produitRepo: widget.produitRepo,
            caisseRepo: widget.caisseRepo,
            photoRepo: widget.photoRepo,
            catalogueRepo: widget.catalogueRepo,
            session: widget.session,
          ),
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text('BEJ — ${_titles[_index]}'),
            actions: [
              if (widget.session.peutChangerMagasin)
                _MagasinSelector(session: widget.session)
              else
                Center(
                    child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(widget.session.magasinNom,
                            style: const TextStyle(color: Colors.white)))),
              if (widget.session.peutDashboard)
                IconButton(
                  tooltip: 'Tableau de bord',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DashboardPage(
                        repo: widget.dashboardRepo,
                        session: widget.session,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.insights),
                ),
              if (widget.session.peutAjusterStock)
                IconButton(
                  tooltip: 'Transferts inter-magasins',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TransfertsPage(
                        transfertRepo: widget.transfertRepo,
                        produitRepo: widget.produitRepo,
                        session: widget.session,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.swap_horiz),
                ),
              if (widget.demoController != null &&
                  widget.session.peutDashboard)
                IconButton(
                  tooltip: 'Mode démo (présentation live)',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          DemoPage(controller: widget.demoController!),
                    ),
                  ),
                  icon: const Icon(Icons.slideshow),
                ),
              IconButton(
                tooltip: 'Guide d\'utilisation',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GuidePage()),
                ),
                icon: const Icon(Icons.help_outline),
              ),
              IconButton(
                tooltip: 'Synchroniser',
                onPressed: _syncing ? null : _sync,
                icon: Badge(
                  isLabelVisible: _pending > 0,
                  label: Text('$_pending'),
                  child: _syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_upload),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Compte',
                icon: const Icon(Icons.account_circle),
                onSelected: (v) {
                  if (v == 'logout') widget.session.logout();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    enabled: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.session.userNom,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text(widget.session.roleLibelle,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      leading: Icon(Icons.logout),
                      title: Text('Se déconnecter'),
                      dense: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Column(
            children: [
              _SyncStatusLine(
                  online: _online, pending: _pending, lastSync: _lastSync),
              const Divider(height: 1),
              Expanded(child: IndexedStack(index: _index, children: pages)),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.people), label: 'Clients'),
              NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Stock'),
              NavigationDestination(
                  icon: Icon(Icons.account_balance_wallet), label: 'Caisse'),
              NavigationDestination(
                  icon: Icon(Icons.point_of_sale), label: 'Vente'),
              NavigationDestination(
                  icon: Icon(Icons.build), label: 'Réparations'),
            ],
          ),
        );
      },
    );
  }
}

class _MagasinSelector extends StatelessWidget {
  final AppSession session;
  const _MagasinSelector({required this.session});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: session.magasinId,
        icon: const Icon(Icons.store, color: Colors.white),
        dropdownColor: Theme.of(context).colorScheme.primaryContainer,
        items: magasinsRef
            .map((m) => DropdownMenuItem(value: m.id, child: Text(m.nom)))
            .toList(),
        onChanged: (id) {
          if (id != null) session.setMagasin(id);
        },
        style: const TextStyle(color: Colors.white),
        selectedItemBuilder: (_) => magasinsRef
            .map((m) => Align(
                  alignment: Alignment.centerLeft,
                  child: Text(m.nom,
                      style: const TextStyle(color: Colors.white)),
                ))
            .toList(),
      ),
    );
  }
}

class _SyncStatusLine extends StatelessWidget {
  final bool online;
  final int pending;
  final DateTime? lastSync;
  const _SyncStatusLine(
      {required this.online, required this.pending, required this.lastSync});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: online ? Colors.green.shade50 : Colors.orange.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(online ? Icons.cloud_done : Icons.cloud_off,
              size: 18,
              color: online ? Colors.green.shade700 : Colors.orange.shade800),
          const SizedBox(width: 8),
          Text(online ? 'Serveur en ligne' : 'Hors ligne (local)',
              style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          if (pending > 0)
            Text('$pending en attente  •  ',
                style: Theme.of(context).textTheme.bodySmall),
          Text(
            lastSync == null
                ? 'jamais synchronisé'
                : 'sync ${lastSync!.hour.toString().padLeft(2, '0')}:${lastSync!.minute.toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
