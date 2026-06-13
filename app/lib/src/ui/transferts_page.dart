import 'package:flutter/material.dart';
import '../app_session.dart';
import '../data/ref_ids.dart';
import '../data/repositories/transfert_repository.dart';
import '../data/repositories/produit_repository.dart';
import '../models/transfert.dart';
import '../models/produit.dart';

/// Transferts inter-magasins (Phase 2, §2.5). Mécanique en deux temps :
/// la source crée (stock en transit), le destinataire confirme (stock ajouté).
class TransfertsPage extends StatelessWidget {
  final TransfertRepository transfertRepo;
  final ProduitRepository produitRepo;
  final AppSession session;

  const TransfertsPage({
    super.key,
    required this.transfertRepo,
    required this.produitRepo,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    final magasin = session.magasinId;
    return Scaffold(
      appBar: AppBar(title: Text('Transferts — ${session.magasinNom}')),
      body: StreamBuilder<List<Transfert>>(
        stream: transfertRepo.watch(magasin),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(child: Text('Aucun transfert. Créez-en un (+).'));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final t = items[i];
              final entrant = t.magasinDestId == magasin;
              final aRecevoir = entrant && t.enTransit;
              final sortantEnTransit = !entrant && t.enTransit;
              return ListTile(
                leading: Icon(
                  entrant ? Icons.call_received : Icons.call_made,
                  color: entrant ? Colors.green : Colors.blue,
                ),
                title: Text('${t.produitNom ?? 'Produit'} × ${t.quantite}'),
                subtitle: Text('${t.sourceNom} → ${t.destNom}'),
                trailing: aRecevoir
                    ? FilledButton(
                        onPressed: () => _confirmer(context, t),
                        child: const Text('Confirmer réception'),
                      )
                    : sortantEnTransit
                        ? OutlinedButton.icon(
                            onPressed: () => _annuler(context, t),
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Annuler'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700),
                          )
                        : Chip(
                            label: Text(
                              t.statut == 'recu'
                                  ? 'reçu'
                                  : (t.statut == 'annule'
                                      ? 'annulé'
                                      : (t.enTransit
                                          ? 'en transit'
                                          : t.statut)),
                              style: const TextStyle(fontSize: 12),
                            ),
                            backgroundColor: t.statut == 'recu'
                                ? Colors.teal.shade100
                                : (t.statut == 'annule'
                                    ? Colors.grey.shade300
                                    : Colors.orange.shade100),
                            visualDensity: VisualDensity.compact,
                          ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nouveau(context),
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Transfert'),
      ),
    );
  }

  Future<void> _confirmer(BuildContext context, Transfert t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmer la réception'),
        content: Text(
            'Recevoir ${t.quantite} × ${t.produitNom} depuis ${t.sourceNom} ?\n'
            'Le stock sera ajouté à ${t.destNom}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmer')),
        ],
      ),
    );
    if (ok == true) {
      await transfertRepo.confirmerReception(
          transfertId: t.id, utilisateurId: session.userId);
    }
  }

  Future<void> _annuler(BuildContext context, Transfert t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Annuler le transfert'),
        content: Text(
            'Annuler l\'envoi de ${t.quantite} × ${t.produitNom} vers '
            '${t.destNom} ?\nLe stock reviendra à ${t.sourceNom}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Non')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Annuler le transfert')),
        ],
      ),
    );
    if (ok == true) {
      await transfertRepo.annuler(
          transfertId: t.id, utilisateurId: session.userId);
    }
  }

  Future<void> _nouveau(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (_) => _NouveauTransfertDialog(
        transfertRepo: transfertRepo,
        produitRepo: produitRepo,
        session: session,
      ),
    );
  }
}

class _NouveauTransfertDialog extends StatefulWidget {
  final TransfertRepository transfertRepo;
  final ProduitRepository produitRepo;
  final AppSession session;
  const _NouveauTransfertDialog({
    required this.transfertRepo,
    required this.produitRepo,
    required this.session,
  });

  @override
  State<_NouveauTransfertDialog> createState() =>
      _NouveauTransfertDialogState();
}

class _NouveauTransfertDialogState extends State<_NouveauTransfertDialog> {
  ProduitStock? _produit;
  String? _destId;
  final _qte = TextEditingController(text: '1');
  String? _erreur;
  bool _saving = false;

  Future<void> _save(List<ProduitStock> produits) async {
    final qte = int.tryParse(_qte.text.trim()) ?? 0;
    if (_produit == null || _destId == null || qte <= 0) {
      setState(() => _erreur = 'Produit, destination et quantité requis.');
      return;
    }
    if (qte > _produit!.quantiteDispo) {
      setState(() => _erreur = 'Stock insuffisant (${_produit!.quantiteDispo}).');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.transfertRepo.creer(
        produitId: _produit!.produit.id,
        magasinSourceId: widget.session.magasinId,
        magasinDestId: _destId!,
        quantite: qte,
        utilisateurId: widget.session.userId,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _erreur = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinations =
        magasinsRef.where((m) => m.id != widget.session.magasinId).toList();
    return AlertDialog(
      title: const Text('Nouveau transfert'),
      content: SizedBox(
        width: 340,
        child: StreamBuilder<List<ProduitStock>>(
          stream: widget.produitRepo.watchCatalogue(widget.session.magasinId),
          builder: (context, snap) {
            final produits =
                (snap.data ?? []).where((p) => p.quantiteDispo > 0).toList();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _produit?.produit.id,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Produit *'),
                  items: produits
                      .map((p) => DropdownMenuItem(
                            value: p.produit.id,
                            child: Text(
                                '${p.produit.nom} (stock ${p.quantiteDispo})'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _produit =
                      produits.firstWhere((p) => p.produit.id == v)),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _destId,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Magasin destination *'),
                  items: destinations
                      .map((m) =>
                          DropdownMenuItem(value: m.id, child: Text(m.nom)))
                      .toList(),
                  onChanged: (v) => setState(() => _destId = v),
                ),
                TextField(
                  controller: _qte,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantité *'),
                ),
                if (_erreur != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_erreur!,
                        style: TextStyle(color: Colors.red.shade700)),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _saving ? null : () => _save(produits),
                    child: const Text('Envoyer'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer')),
      ],
    );
  }
}
