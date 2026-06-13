import 'package:flutter/material.dart';
import '../data/repositories/client_repository.dart';
import '../data/repositories/reparation_repository.dart';
import '../data/repositories/avoir_repository.dart';
import '../models/client.dart';
import '../models/reparation.dart';
import '../models/avoir.dart';
import '../util/format.dart';

/// Fiche client (§5.1) : infos, jetons, avoirs, historique achats et réparations.
class ClientDetailPage extends StatefulWidget {
  final String clientId;
  final ClientRepository clientRepo;
  final ReparationRepository reparationRepo;
  final AvoirRepository avoirRepo;

  const ClientDetailPage({
    super.key,
    required this.clientId,
    required this.clientRepo,
    required this.reparationRepo,
    required this.avoirRepo,
  });

  @override
  State<ClientDetailPage> createState() => _ClientDetailPageState();
}

class _ClientDetailPageState extends State<ClientDetailPage> {
  Client? _client;
  List<Map<String, dynamic>> _transactions = [];
  List<ReparationListItem> _reparations = [];
  List<Avoir> _avoirs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await widget.clientRepo.getById(widget.clientId);
    final tx = await widget.clientRepo.transactions(widget.clientId);
    final reps = await widget.reparationRepo.parClient(widget.clientId);
    final av = await widget.avoirRepo.tousParClient(widget.clientId);
    if (!mounted) return;
    setState(() {
      _client = c;
      _transactions = tx;
      _reparations = reps;
      _avoirs = av;
      _loading = false;
    });
  }

  static const _typeLibelle = {
    'vente': 'Vente',
    'reparation': 'Réparation',
    'retour': 'Retour',
    'mixte': 'Mixte',
  };

  @override
  Widget build(BuildContext context) {
    final c = _client;
    return Scaffold(
      appBar: AppBar(
        title: Text(c?.nom ?? 'Client'),
        actions: [
          if (c != null)
            IconButton(
                onPressed: () => _editer(c),
                icon: const Icon(Icons.edit),
                tooltip: 'Modifier'),
        ],
      ),
      body: _loading || c == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (c.telephone != null)
                          _ligne(Icons.phone, c.telephone!),
                        if (c.whatsapp != null)
                          _ligne(Icons.chat, 'WhatsApp ${c.whatsapp}'),
                        _ligne(Icons.loyalty, '${c.soldeJetons} jetons'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _section('Avoirs', Icons.assignment_return),
                if (_avoirs.isEmpty)
                  const Text('Aucun avoir.', style: TextStyle(color: Colors.grey))
                else
                  ..._avoirs.map((a) => ListTile(
                        dense: true,
                        leading: Icon(
                            a.estActif ? Icons.check_circle : Icons.cancel,
                            color: a.estActif ? Colors.green : Colors.grey),
                        title: Text(
                            '${fcfa(a.montantRestant)} / ${fcfa(a.montantInitial)}'),
                        subtitle: Text(a.estActif ? 'actif' : 'utilisé'),
                      )),
                const SizedBox(height: 12),
                _section('Historique des transactions', Icons.receipt_long),
                if (_transactions.isEmpty)
                  const Text('Aucune transaction.',
                      style: TextStyle(color: Colors.grey))
                else
                  ..._transactions.map((t) => ListTile(
                        dense: true,
                        title: Text(_typeLibelle[t['type']] ?? '${t['type']}'),
                        subtitle: Text(_date(t['date'] as String?)),
                        trailing: Text(fcfa((t['total'] as num?) ?? 0),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      )),
                const SizedBox(height: 12),
                _section('Réparations', Icons.build),
                if (_reparations.isEmpty)
                  const Text('Aucune réparation.',
                      style: TextStyle(color: Colors.grey))
                else
                  ..._reparations.map((r) => ListTile(
                        dense: true,
                        title: Text(r.appareilLibelle.isEmpty
                            ? 'Appareil'
                            : r.appareilLibelle),
                        subtitle:
                            Text(StatutReparation.libelle(r.reparation.statut)),
                        trailing: Text(fcfa(r.reparation.total)),
                      )),
              ],
            ),
    );
  }

  Widget _ligne(IconData i, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(i, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text(t),
        ]),
      );

  Widget _section(String t, IconData i) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Icon(i, size: 18),
          const SizedBox(width: 8),
          Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      );

  String _date(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _editer(Client c) async {
    final nom = TextEditingController(text: c.nom);
    final tel = TextEditingController(text: c.telephone ?? '');
    final wa = TextEditingController(text: c.whatsapp ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Modifier le client'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nom,
              decoration: const InputDecoration(labelText: 'Nom *')),
          TextField(
              controller: tel,
              decoration: const InputDecoration(labelText: 'Téléphone')),
          TextField(
              controller: wa,
              decoration: const InputDecoration(labelText: 'WhatsApp')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true && nom.text.trim().isNotEmpty) {
      await widget.clientRepo.update(
        id: c.id,
        nom: nom.text.trim(),
        telephone: tel.text.trim().isEmpty ? null : tel.text.trim(),
        whatsapp: wa.text.trim().isEmpty ? null : wa.text.trim(),
      );
      _load();
    }
  }
}
