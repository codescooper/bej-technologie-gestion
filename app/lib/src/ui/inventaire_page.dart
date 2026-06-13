import 'package:flutter/material.dart';
import '../app_session.dart';
import '../data/repositories/inventaire_repository.dart';
import '../models/inventaire.dart';

/// Inventaire physique (Finitions Phase 2+) : liste des inventaires du magasin
/// + saisie d'un comptage qui, une fois validé, ajuste le stock.
class InventairePage extends StatelessWidget {
  final InventaireRepository inventaireRepo;
  final AppSession session;
  const InventairePage({
    super.key,
    required this.inventaireRepo,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Inventaire — ${session.magasinNom}')),
      body: StreamBuilder<List<Inventaire>>(
        stream: inventaireRepo.watch(session.magasinId),
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
                'Aucun inventaire. Lancez-en un (+) pour compter physiquement '
                'le stock et corriger les écarts.',
                textAlign: TextAlign.center,
              ),
            ));
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final inv = items[i];
              return ListTile(
                leading: Icon(
                  inv.enCours ? Icons.fact_check_outlined : Icons.check_circle,
                  color: inv.enCours ? Colors.orange : Colors.green,
                ),
                title: Text(inv.enCours
                    ? 'Inventaire en cours'
                    : 'Inventaire validé'),
                subtitle: Text(_dateCourte(
                    inv.enCours ? inv.dateCreation : inv.dateValidation)),
                trailing: inv.enCours
                    ? const Icon(Icons.edit)
                    : const Icon(Icons.lock_outline),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _SaisieInventairePage(
                    inventaireRepo: inventaireRepo,
                    session: session,
                    inventaire: inv,
                  ),
                )),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _demarrer(context),
        icon: const Icon(Icons.add_task),
        label: const Text('Nouvel inventaire'),
      ),
    );
  }

  Future<void> _demarrer(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final id = await inventaireRepo.demarrer(
      magasinId: session.magasinId,
      utilisateurId: session.userId,
    );
    final lignes = await inventaireRepo.lignes(id);
    messenger.showSnackBar(SnackBar(
        content: Text('Inventaire démarré : ${lignes.length} produit(s) à compter.')));
    navigator.push(MaterialPageRoute(
      builder: (_) => _SaisieInventairePage(
        inventaireRepo: inventaireRepo,
        session: session,
        inventaire: Inventaire(id: id, magasinId: session.magasinId),
      ),
    ));
  }

  static String _dateCourte(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}

/// Écran de saisie du comptage. Affiche chaque produit, son stock théorique et
/// un champ « compté » ; l'écart est calculé en direct. La validation ajuste le
/// stock (lecture seule si l'inventaire est déjà validé).
class _SaisieInventairePage extends StatefulWidget {
  final InventaireRepository inventaireRepo;
  final AppSession session;
  final Inventaire inventaire;
  const _SaisieInventairePage({
    required this.inventaireRepo,
    required this.session,
    required this.inventaire,
  });

  @override
  State<_SaisieInventairePage> createState() => _SaisieInventairePageState();
}

class _SaisieInventairePageState extends State<_SaisieInventairePage> {
  late Future<List<LigneInventaire>> _future;
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, int> _ecarts = {};
  List<LigneInventaire> _lignes = [];
  bool _init = false;
  bool _saving = false;

  bool get _lecture => widget.inventaire.valide;

  @override
  void initState() {
    super.initState();
    _future = widget.inventaireRepo.lignes(widget.inventaire.id);
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _prepare(List<LigneInventaire> lignes) {
    if (_init) return;
    _init = true;
    _lignes = lignes;
    for (final l in lignes) {
      _ctrls[l.id] =
          TextEditingController(text: l.comptee?.toString() ?? '');
      _ecarts[l.id] = l.ecart;
    }
  }

  Future<void> _valider() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      for (final l in _lignes) {
        final txt = _ctrls[l.id]!.text.trim();
        if (txt.isEmpty) continue;
        final c = int.tryParse(txt);
        if (c == null) continue;
        await widget.inventaireRepo.saisir(ligneId: l.id, comptee: c);
      }
      final n = await widget.inventaireRepo.valider(
        inventaireId: widget.inventaire.id,
        utilisateurId: widget.session.userId,
      );
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text('Inventaire validé — $n produit(s) ajusté(s).')));
      navigator.pop();
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('Erreur : $e')));
    }
  }

  Future<void> _confirmerValidation() async {
    final nbSaisis = _lignes
        .where((l) => (_ctrls[l.id]?.text.trim().isNotEmpty ?? false))
        .length;
    final nbEcarts = _lignes.where((l) => (_ecarts[l.id] ?? 0) != 0).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Valider l\'inventaire'),
        content: Text(
            '$nbSaisis produit(s) compté(s), $nbEcarts écart(s).\n'
            'Le stock sera aligné sur le comptage. Cette action est définitive.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Valider')),
        ],
      ),
    );
    if (ok == true) await _valider();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_lecture ? 'Inventaire validé' : 'Saisie de l\'inventaire'),
      ),
      body: FutureBuilder<List<LigneInventaire>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          _prepare(snap.data!);
          if (_lignes.isEmpty) {
            return const Center(child: Text('Aucun produit à compter.'));
          }
          return Column(
            children: [
              Container(
                width: double.infinity,
                color: Colors.blue.shade50,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  _lecture
                      ? 'Inventaire validé — lecture seule.'
                      : 'Saisissez la quantité réellement comptée. L\'écart '
                          'apparaît à droite ; un produit non saisi est ignoré.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: _lignes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _ligneTile(_lignes[i]),
                ),
              ),
              if (!_lecture)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _confirmerValidation,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.check),
                        label: const Text('Valider l\'inventaire'),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _ligneTile(LigneInventaire l) {
    final ecart = _ecarts[l.id] ?? 0;
    final couleur = ecart == 0
        ? Colors.grey
        : (ecart > 0 ? Colors.green.shade700 : Colors.red.shade700);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.produitNom ?? 'Produit',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                Text('Théorique : ${l.theorique}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _ctrls[l.id],
              enabled: !_lecture,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Compté', isDense: true),
              onChanged: (v) {
                final c = int.tryParse(v.trim());
                setState(() {
                  _ecarts[l.id] = (c == null) ? 0 : c - l.theorique;
                });
              },
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              ecart == 0 ? '—' : (ecart > 0 ? '+$ecart' : '$ecart'),
              textAlign: TextAlign.right,
              style: TextStyle(color: couleur, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
