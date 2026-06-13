import 'package:flutter/material.dart';
import '../app_session.dart';
import '../data/repositories/retour_repository.dart';
import '../data/repositories/caisse_repository.dart';
import '../util/format.dart';

/// Écran Retour / Avoir (§5.6) : choisir une vente, sélectionner les lignes et
/// quantités à rendre (partiel ou total), valider → génère un avoir.
class RetourPage extends StatefulWidget {
  final RetourRepository retourRepo;
  final CaisseRepository caisseRepo;
  final AppSession session;

  const RetourPage({
    super.key,
    required this.retourRepo,
    required this.caisseRepo,
    required this.session,
  });

  @override
  State<RetourPage> createState() => _RetourPageState();
}

class _RetourPageState extends State<RetourPage> {
  Map<String, dynamic>? _vente; // vente sélectionnée
  List<LigneRetour> _lignes = [];
  final Map<String, int> _qte = {}; // produitId -> quantité à retourner
  bool _saving = false;

  num get _montant {
    num m = 0;
    for (final l in _lignes) {
      m += (_qte[l.produitId] ?? 0) * l.prixUnitaire;
    }
    return m;
  }

  Future<void> _choisirVente(Map<String, dynamic> v) async {
    final lignes = await widget.retourRepo.lignesVendues(v['id'] as String);
    setState(() {
      _vente = v;
      _lignes = lignes;
      _qte.clear();
    });
  }

  Future<void> _valider() async {
    final lignesRetour = _lignes
        .where((l) => (_qte[l.produitId] ?? 0) > 0)
        .map((l) => LigneRetour(
              produitId: l.produitId,
              produitNom: l.produitNom,
              quantite: _qte[l.produitId]!,
              prixUnitaire: l.prixUnitaire,
            ))
        .toList();
    if (lignesRetour.isEmpty) return;

    final caisse = await widget.caisseRepo.caisseOuverte(widget.session.magasinId);
    if (!mounted) return;
    if (caisse == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ouvrez la caisse avant un retour.')));
      return;
    }

    // Validation responsable (simulée tant que les rôles n'existent pas).
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Validation responsable'),
        content: Text(
            'Confirmer le retour de ${fcfa(_montant)} ?\nUn avoir sera créé pour le client.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Valider le retour')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    final result = await widget.retourRepo.enregistrerRetour(
      transactionOrigineId: _vente!['id'] as String,
      magasinId: widget.session.magasinId,
      caisseId: caisse.id,
      utilisateurId: widget.session.userId,
      clientId: _vente!['client_id'] as String,
      lignes: lignesRetour,
    );
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Retour validé'),
        content: Text(
            'Avoir créé : ${fcfa(result.montant)}\n'
            '${result.jetonsAnnules > 0 ? '${result.jetonsAnnules} jetons annulés' : ''}'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Terminer')),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop(); // ferme la page retour
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_vente == null ? 'Retour — choisir la vente' : 'Retour / Avoir'),
      ),
      body: _vente == null ? _listeVentes() : _selectionLignes(),
    );
  }

  Widget _listeVentes() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: widget.retourRepo.ventesRetournables(widget.session.magasinId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final ventes = snap.data!;
        if (ventes.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'Aucune vente avec client à retourner.\n(Un avoir doit appartenir à un client identifié.)',
                  textAlign: TextAlign.center),
            ),
          );
        }
        return ListView.separated(
          itemCount: ventes.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final v = ventes[i];
            return ListTile(
              leading: const Icon(Icons.receipt_long),
              title: Text('${v['client_nom']} — ${fcfa((v['total'] as num?) ?? 0)}'),
              subtitle: Text(_date(v['date'] as String?)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _choisirVente(v),
            );
          },
        );
      },
    );
  }

  Widget _selectionLignes() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                  child: Text('Client : ${_vente!['client_nom']}',
                      style: const TextStyle(fontWeight: FontWeight.bold))),
              TextButton.icon(
                onPressed: () => setState(() {
                  for (final l in _lignes) {
                    _qte[l.produitId] = l.quantite;
                  }
                }),
                icon: const Icon(Icons.done_all, size: 18),
                label: const Text('Tout retourner'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            children: _lignes.map((l) {
              final q = _qte[l.produitId] ?? 0;
              return ListTile(
                title: Text(l.produitNom),
                subtitle: Text(
                    '${fcfa(l.prixUnitaire)} • vendu : ${l.quantite}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: q > 0
                          ? () => setState(() => _qte[l.produitId] = q - 1)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$q'),
                    IconButton(
                      onPressed: q < l.quantite
                          ? () => setState(() => _qte[l.produitId] = q + 1)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text('Avoir à créer : ${fcfa(_montant)}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              FilledButton.icon(
                onPressed: (_montant <= 0 ||
                        _saving ||
                        !widget.session.peutValiderRetour)
                    ? null
                    : _valider,
                icon: const Icon(Icons.assignment_return),
                label: Text(widget.session.peutValiderRetour
                    ? 'Valider le retour'
                    : 'Validation responsable requise'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _date(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
