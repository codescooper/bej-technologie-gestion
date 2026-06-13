import 'package:flutter/material.dart';
import '../app_session.dart';
import '../data/repositories/produit_repository.dart';
import '../data/repositories/transfert_repository.dart';

/// Réapprovisionnement (Finitions Phase 2+) : produits du magasin courant sous
/// leur seuil d'alerte, avec les magasins capables de fournir. Un transfert
/// peut être déclenché directement depuis le fournisseur vers ce magasin
/// (le magasin destinataire devra confirmer la réception dans « Transferts »).
class ReapproPage extends StatefulWidget {
  final ProduitRepository produitRepo;
  final TransfertRepository transfertRepo;
  final AppSession session;
  const ReapproPage({
    super.key,
    required this.produitRepo,
    required this.transfertRepo,
    required this.session,
  });

  @override
  State<ReapproPage> createState() => _ReapproPageState();
}

class _ReapproPageState extends State<ReapproPage> {
  late Future<List<ReapproSuggestion>> _future;

  @override
  void initState() {
    super.initState();
    _recharger();
  }

  void _recharger() {
    setState(() {
      _future = widget.produitRepo.suggestionsReappro(widget.session.magasinId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Réappro — ${widget.session.magasinNom}'),
        actions: [
          IconButton(
              onPressed: _recharger,
              icon: const Icon(Icons.refresh),
              tooltip: 'Rafraîchir'),
        ],
      ),
      body: FutureBuilder<List<ReapproSuggestion>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aucun produit sous le seuil d\'alerte. Stock sain ✅',
                textAlign: TextAlign.center,
              ),
            ));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: items.length,
            itemBuilder: (_, i) => _carte(items[i]),
          );
        },
      ),
    );
  }

  Widget _carte(ReapproSuggestion s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.produitNom,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Chip(
                  label: Text('manque ${s.manque}'),
                  backgroundColor: Colors.red.shade50,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            Text('Disponible ${s.disponible}  •  seuil ${s.seuil}',
                style: TextStyle(color: Colors.red.shade700)),
            const Divider(),
            if (s.sources.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('Aucun autre magasin n\'a de stock à fournir.',
                    style: TextStyle(color: Colors.grey)),
              )
            else
              ...s.sources.map((src) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.store, size: 20),
                    title: Text(src.magasinNom),
                    subtitle: Text('stock ${src.disponible}'),
                    trailing: FilledButton.tonalIcon(
                      onPressed: () => _transferer(s, src),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Transférer'),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Future<void> _transferer(ReapproSuggestion s, ReapproSource src) async {
    final defaut =
        s.manque > src.disponible ? src.disponible : s.manque;
    final ctrl = TextEditingController(text: '$defaut');
    final qte = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Transférer ${s.produitNom}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Depuis ${src.magasinNom} (stock ${src.disponible})\n'
              'vers ${widget.session.magasinNom}.'),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Quantité à transférer'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(context, int.tryParse(ctrl.text.trim())),
              child: const Text('Envoyer')),
        ],
      ),
    );
    if (qte == null || qte <= 0) return;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.transfertRepo.creer(
        produitId: s.produitId,
        magasinSourceId: src.magasinId,
        magasinDestId: widget.session.magasinId,
        quantite: qte,
        utilisateurId: widget.session.userId,
      );
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text(
              'Transfert créé : $qte × ${s.produitNom} depuis ${src.magasinNom}. '
              'Confirmez la réception dans « Transferts ».')));
      _recharger();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('Erreur : $e')));
    }
  }
}
