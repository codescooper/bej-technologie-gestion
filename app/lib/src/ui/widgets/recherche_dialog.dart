import 'package:flutter/material.dart';
import '../../data/repositories/catalogue_repository.dart';
import '../../models/catalogue.dart';

/// Ouvre un sélecteur recherchable de modèle d'appareil (avec ajout).
Future<ModeleAppareil?> choisirModele(
    BuildContext context, CatalogueRepository repo) {
  return showDialog<ModeleAppareil>(
    context: context,
    builder: (_) => _RechercheDialog<ModeleAppareil>(
      titre: 'Modèle d\'appareil',
      onSearch: repo.rechercheModeles,
      label: (m) => m.libelle,
      onAjouter: (query) => showDialog<ModeleAppareil>(
        context: context,
        builder: (_) => _AjoutModeleDialog(repo: repo, initialModele: query),
      ),
    ),
  );
}

/// Ouvre un sélecteur recherchable de panne (avec ajout).
Future<String?> choisirPanne(BuildContext context, CatalogueRepository repo) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RechercheDialog<String>(
      titre: 'Panne / problème',
      onSearch: repo.recherchePannes,
      label: (s) => s,
      onAjouter: (query) => repo.ajouterPanne(query),
    ),
  );
}

/// Dialogue générique : champ de recherche dynamique + liste filtrée +
/// option « Ajouter «query» » si l'élément cherché n'existe pas.
class _RechercheDialog<T> extends StatefulWidget {
  final String titre;
  final Future<List<T>> Function(String query) onSearch;
  final String Function(T item) label;
  final Future<T?> Function(String query) onAjouter;

  const _RechercheDialog({
    required this.titre,
    required this.onSearch,
    required this.label,
    required this.onAjouter,
  });

  @override
  State<_RechercheDialog<T>> createState() => _RechercheDialogState<T>();
}

class _RechercheDialogState<T> extends State<_RechercheDialog<T>> {
  final _ctrl = TextEditingController();
  List<T> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String q) async {
    final r = await widget.onSearch(q);
    if (!mounted) return;
    setState(() {
      _results = r;
      _loading = false;
    });
  }

  bool get _exactMatch {
    final t = _ctrl.text.trim().toLowerCase();
    return t.isNotEmpty &&
        _results.any((r) => widget.label(r).toLowerCase() == t);
  }

  @override
  Widget build(BuildContext context) {
    final query = _ctrl.text.trim();
    return AlertDialog(
      title: Text(widget.titre),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Rechercher…',
              ),
              onChanged: (q) {
                setState(() {}); // met à jour l'option "Ajouter"
                _search(q);
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        if (query.isNotEmpty && !_exactMatch)
                          Card(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            child: ListTile(
                              leading: const Icon(Icons.add),
                              title: Text('Ajouter « $query »'),
                              onTap: () async {
                                final created = await widget.onAjouter(query);
                                if (created != null && context.mounted) {
                                  Navigator.pop(context, created);
                                }
                              },
                            ),
                          ),
                        ..._results.map((r) => ListTile(
                              title: Text(widget.label(r)),
                              onTap: () => Navigator.pop(context, r),
                            )),
                        if (_results.isEmpty && query.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Tapez pour rechercher.',
                                style: TextStyle(color: Colors.grey)),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
      ],
    );
  }
}

/// Sous-formulaire d'ajout d'un modèle (marque + modèle).
class _AjoutModeleDialog extends StatefulWidget {
  final CatalogueRepository repo;
  final String initialModele;
  const _AjoutModeleDialog({required this.repo, required this.initialModele});

  @override
  State<_AjoutModeleDialog> createState() => _AjoutModeleDialogState();
}

class _AjoutModeleDialogState extends State<_AjoutModeleDialog> {
  final _marque = TextEditingController();
  late final _modele = TextEditingController(text: widget.initialModele);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouveau modèle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: _marque,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Marque *')),
          TextField(
              controller: _modele,
              decoration: const InputDecoration(labelText: 'Modèle *')),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: () async {
            if (_marque.text.trim().isEmpty || _modele.text.trim().isEmpty) {
              return;
            }
            final m = await widget.repo
                .ajouterModele(_marque.text.trim(), _modele.text.trim());
            if (context.mounted) Navigator.pop(context, m);
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}
