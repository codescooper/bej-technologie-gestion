import 'package:flutter/material.dart';
import '../data/repositories/client_repository.dart';
import '../data/repositories/reparation_repository.dart';
import '../data/repositories/avoir_repository.dart';
import '../models/client.dart';
import 'client_detail_page.dart';

/// Onglet CRM client (§5.1) : liste + création avec détection de doublon (§2.6).
class ClientsPage extends StatelessWidget {
  final ClientRepository clientRepo;
  final ReparationRepository reparationRepo;
  final AvoirRepository avoirRepo;
  const ClientsPage({
    super.key,
    required this.clientRepo,
    required this.reparationRepo,
    required this.avoirRepo,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Client>>(
        stream: clientRepo.watchAll(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final clients = snap.data!;
          if (clients.isEmpty) {
            return const Center(child: Text('Aucun client. Ajoutez-en un (+).'));
          }
          return ListView.separated(
            itemCount: clients.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final c = clients[i];
              return ListTile(
                leading: CircleAvatar(
                    child: Text(c.nom.isNotEmpty ? c.nom[0].toUpperCase() : '?')),
                title: Text(c.nom),
                subtitle: Text([
                  if (c.telephone != null) c.telephone!,
                  'jetons: ${c.soldeJetons}',
                ].join('  •  ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ClientDetailPage(
                    clientId: c.id,
                    clientRepo: clientRepo,
                    reparationRepo: reparationRepo,
                    avoirRepo: avoirRepo,
                  ),
                )),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog(
          context: context,
          builder: (_) => ClientDialog(clientRepo: clientRepo),
        ),
        icon: const Icon(Icons.person_add),
        label: const Text('Client'),
      ),
    );
  }
}

/// Dialogue de création client avec détection de doublon (§5.1 / §2.6).
class ClientDialog extends StatefulWidget {
  final ClientRepository clientRepo;
  const ClientDialog({super.key, required this.clientRepo});

  @override
  State<ClientDialog> createState() => _ClientDialogState();
}

class _ClientDialogState extends State<ClientDialog> {
  final _nom = TextEditingController();
  final _tel = TextEditingController();
  final _wa = TextEditingController();
  Client? _doublon;
  bool _saving = false;

  Future<void> _checkDoublon() async {
    final norm = ClientRepository.normalizePhone(_tel.text);
    final existing = await widget.clientRepo.findByPhone(norm);
    if (mounted) setState(() => _doublon = existing);
  }

  Future<void> _save() async {
    if (_nom.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le nom du client est obligatoire.')),
      );
      return;
    }
    setState(() => _saving = true);
    await widget.clientRepo.create(
      nom: _nom.text.trim(),
      telephone: _tel.text.trim().isEmpty ? null : _tel.text.trim(),
      whatsapp: _wa.text.trim().isEmpty ? null : _wa.text.trim(),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau client'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nom,
              decoration: const InputDecoration(labelText: 'Nom *'),
              textCapitalization: TextCapitalization.words,
            ),
            TextField(
              controller: _tel,
              decoration: const InputDecoration(
                  labelText: 'Téléphone', hintText: 'ex : 07 07 00 00 00'),
              keyboardType: TextInputType.phone,
              onChanged: (_) => _checkDoublon(),
            ),
            TextField(
              controller: _wa,
              decoration: const InputDecoration(labelText: 'WhatsApp'),
              keyboardType: TextInputType.phone,
            ),
            if (_doublon != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(8),
                color: Colors.amber.shade100,
                child: Row(children: [
                  const Icon(Icons.warning_amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'Déjà : « ${_doublon!.nom} » avec ce numéro (§2.6).')),
                ]),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_doublon != null ? 'Créer quand même' : 'Créer'),
        ),
      ],
    );
  }
}
