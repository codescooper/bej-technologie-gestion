import 'package:flutter/material.dart';
import '../app_session.dart';
import '../data/repositories/dashboard_repository.dart';
import '../models/reparation.dart';
import '../util/format.dart';
import 'reporting_page.dart';

/// Tableau de bord du magasin (§5) : indicateurs de la journée.
class DashboardPage extends StatefulWidget {
  final DashboardRepository repo;
  final AppSession session;
  const DashboardPage({super.key, required this.repo, required this.session});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    // Corps de bloc (et non `=>`) : la closure de setState NE DOIT PAS retourner
    // le Future de load(), sinon Flutter lève « setState callback returned a Future ».
    setState(() {
      _future = widget.repo.load(widget.session.magasinId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tableau de bord — ${widget.session.magasinNom}'),
        actions: [
          if (widget.session.peutDashboardGlobal)
            IconButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ReportingPage(repo: widget.repo),
              )),
              icon: const Icon(Icons.summarize),
              tooltip: 'Reporting consolidé (groupe)',
            ),
          IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Rafraîchir'),
        ],
      ),
      body: FutureBuilder<DashboardData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Aujourd\'hui',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _caTotalCard(d),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                      child: _metric('Ventes', '${d.nbVentes}',
                          Icons.point_of_sale, Colors.blue)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _metric('Réparations encaissées',
                          '${d.nbReparations}', Icons.build, Colors.teal)),
                ]),
                const SizedBox(height: 12),
                _reparationsCard(d),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _stockCard(d)),
                  const SizedBox(width: 12),
                  Expanded(child: _jetonsCard(d)),
                ]),
                if (d.remisesNegociees > 0) ...[
                  const SizedBox(height: 12),
                  _remisesNegCard(d),
                ],
                const SizedBox(height: 12),
                _caisseCard(d),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _caTotalCard(DashboardData d) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chiffre d\'affaires du jour'),
            const SizedBox(height: 4),
            Text(fcfa(d.caTotal),
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
                'Ventes ${fcfa(d.caVentes)}   •   Réparations ${fcfa(d.caReparations)}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _reparationsCard(DashboardData d) {
    final total =
        d.reparationsParStatut.values.fold<int>(0, (s, v) => s + v);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.build_circle, color: Colors.deepOrange),
              const SizedBox(width: 8),
              Text('Réparations en cours ($total)',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 8),
            if (d.reparationsParStatut.isEmpty)
              const Text('Aucune réparation en cours.',
                  style: TextStyle(color: Colors.grey))
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: d.reparationsParStatut.entries
                    .map((e) => Chip(
                          label: Text(
                              '${StatutReparation.libelle(e.key)} : ${e.value}'),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stockCard(DashboardData d) {
    final alerte = d.stockBasCount > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.inventory_2,
                color: alerte ? Colors.red.shade700 : Colors.green),
            const SizedBox(height: 8),
            Text('${d.stockBasCount}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: alerte ? Colors.red.shade700 : null)),
            const Text('produits en stock bas',
                style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _jetonsCard(DashboardData d) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.loyalty, color: Colors.purple),
            const SizedBox(height: 8),
            Text('${d.jetonsDistribues}',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Text('jetons distribués', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _remisesNegCard(DashboardData d) {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.price_change_outlined, color: Colors.orange.shade800),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Remises accordées (négociations)',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(fcfa(d.remisesNegociees),
                      style: TextStyle(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                  Text('Total des réductions accordées aux clients ce jour',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _caisseCard(DashboardData d) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(d.caisseOuverte ? Icons.lock_open : Icons.lock,
                color: d.caisseOuverte ? Colors.green : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.caisseOuverte ? 'Caisse ouverte' : 'Caisse fermée',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (d.caisseOuverte)
                    Text(
                        'Théorique — cash ${fcfa(d.caisseTheoriqueCash)} • mobile ${fcfa(d.caisseTheoriqueMobile)}',
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
