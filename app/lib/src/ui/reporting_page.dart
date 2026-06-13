import 'package:flutter/material.dart';
import '../data/repositories/dashboard_repository.dart';
import '../util/format.dart';

/// Reporting consolidé multi-magasins (Phase 2) — réservé à l'administrateur.
class ReportingPage extends StatefulWidget {
  final DashboardRepository repo;
  const ReportingPage({super.key, required this.repo});

  @override
  State<ReportingPage> createState() => _ReportingPageState();
}

class _ReportingPageState extends State<ReportingPage> {
  late Future<List<MagasinReport>> _future;
  late Future<List<RapprochementCaisse>> _futureR;

  @override
  void initState() {
    super.initState();
    _recharger();
  }

  void _recharger() {
    setState(() {
      _future = widget.repo.consolide();
      _futureR = widget.repo.rapprochementCaisse();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporting consolidé'),
        actions: [
          IconButton(
            onPressed: _recharger,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<MagasinReport>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          final caTotal = rows.fold<num>(0, (s, r) => s + r.ca);
          final nbTotal = rows.fold<int>(0, (s, r) => s + r.nbTransactions);
          final stockTotal = rows.fold<int>(0, (s, r) => s + r.stockTotal);
          final basTotal = rows.fold<int>(0, (s, r) => s + r.stockBas);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Groupe (tous magasins)'),
                      const SizedBox(height: 4),
                      Text('CA total : ${fcfa(caTotal)}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(
                          '$nbTotal transactions • $stockTotal en stock • $basTotal en alerte',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Magasin')),
                    DataColumn(label: Text('CA'), numeric: true),
                    DataColumn(label: Text('Transac.'), numeric: true),
                    DataColumn(label: Text('Stock'), numeric: true),
                    DataColumn(label: Text('Alerte'), numeric: true),
                  ],
                  rows: rows
                      .map((r) => DataRow(cells: [
                            DataCell(Text(r.nom)),
                            DataCell(Text(fcfa(r.ca))),
                            DataCell(Text('${r.nbTransactions}')),
                            DataCell(Text('${r.stockTotal}')),
                            DataCell(Text(
                              '${r.stockBas}',
                              style: TextStyle(
                                  color: r.stockBas > 0
                                      ? Colors.red.shade700
                                      : null),
                            )),
                          ]))
                      .toList(),
                ),
              ),
              const SizedBox(height: 24),
              Text('Rapprochement de caisse',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Écarts de clôture cumulés par magasin (caisses clôturées).',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              _rapprochement(context),
            ],
          );
        },
      ),
    );
  }

  Widget _rapprochement(BuildContext context) {
    return FutureBuilder<List<RapprochementCaisse>>(
      future: _futureR,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          );
        }
        final rows = snap.data!;
        final totalEcart = rows.fold<num>(0, (s, r) => s + r.ecartCumule);
        final totalClot = rows.fold<int>(0, (s, r) => s + r.nbCloturees);
        if (totalClot == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Aucune caisse clôturée pour le moment.',
                style: TextStyle(color: Colors.grey)),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Magasin')),
              DataColumn(label: Text('Clôtures'), numeric: true),
              DataColumn(label: Text('Écart cumulé'), numeric: true),
              DataColumn(label: Text('Dernier écart'), numeric: true),
            ],
            rows: [
              ...rows.map((r) => DataRow(cells: [
                    DataCell(Text(r.nom)),
                    DataCell(Text('${r.nbCloturees}')),
                    DataCell(Text(fcfa(r.ecartCumule),
                        style: TextStyle(
                            color: r.ecartCumule != 0
                                ? Colors.red.shade700
                                : null))),
                    DataCell(Text(
                        r.dernierEcart == null ? '—' : fcfa(r.dernierEcart!),
                        style: TextStyle(
                            color: (r.dernierEcart ?? 0) != 0
                                ? Colors.red.shade700
                                : null))),
                  ])),
              DataRow(
                color: WidgetStatePropertyAll(Colors.grey.shade100),
                cells: [
                  const DataCell(Text('Total',
                      style: TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text('$totalClot',
                      style: const TextStyle(fontWeight: FontWeight.bold))),
                  DataCell(Text(fcfa(totalEcart),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color:
                              totalEcart != 0 ? Colors.red.shade700 : null))),
                  const DataCell(Text('')),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
