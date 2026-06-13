import 'package:flutter/material.dart';
import '../app_session.dart';
import '../data/repositories/reparation_repository.dart';
import '../data/repositories/appareil_repository.dart';
import '../data/repositories/client_repository.dart';
import '../data/repositories/produit_repository.dart';
import '../data/repositories/caisse_repository.dart';
import '../data/repositories/photo_repository.dart';
import '../data/repositories/catalogue_repository.dart';
import '../models/reparation.dart';
import '../models/client.dart';
import '../models/appareil.dart';
import '../util/format.dart';
import 'reparation_detail_page.dart';
import 'widgets/recherche_dialog.dart';

/// Onglet Réparations (§5.2) : liste filtrable par statut + création.
class ReparationsPage extends StatefulWidget {
  final ReparationRepository reparationRepo;
  final AppareilRepository appareilRepo;
  final ClientRepository clientRepo;
  final ProduitRepository produitRepo;
  final CaisseRepository caisseRepo;
  final PhotoRepository photoRepo;
  final CatalogueRepository catalogueRepo;
  final AppSession session;

  const ReparationsPage({
    super.key,
    required this.reparationRepo,
    required this.appareilRepo,
    required this.clientRepo,
    required this.produitRepo,
    required this.caisseRepo,
    required this.photoRepo,
    required this.catalogueRepo,
    required this.session,
  });

  @override
  State<ReparationsPage> createState() => _ReparationsPageState();
}

class _ReparationsPageState extends State<ReparationsPage> {
  String? _filtre; // statut filtré, null = toutes

  static Color statutColor(String statut) {
    switch (statut) {
      case StatutReparation.recu:
        return Colors.blueGrey;
      case StatutReparation.diagnostic:
      case StatutReparation.attenteValidation:
        return Colors.orange;
      case StatutReparation.attentePiece:
        return Colors.deepOrange;
      case StatutReparation.enReparation:
        return Colors.blue;
      case StatutReparation.pret:
        return Colors.green;
      case StatutReparation.livre:
        return Colors.teal;
      case StatutReparation.annule:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                _chip('Toutes', null),
                ...StatutReparation.ordre.map(
                    (s) => _chip(StatutReparation.libelle(s), s)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<ReparationListItem>>(
              stream:
                  widget.reparationRepo.watch(widget.session.magasinId, statut: _filtre),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return const Center(
                      child: Text('Aucune réparation. Créez-en une (+).'));
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _tile(items[i]),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nouvelleReparation,
        icon: const Icon(Icons.add),
        label: const Text('Réparation'),
      ),
    );
  }

  Widget _chip(String label, String? statut) {
    final selected = _filtre == statut;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _filtre = statut),
      ),
    );
  }

  Widget _tile(ReparationListItem it) {
    final r = it.reparation;
    return ListTile(
      title: Text(it.appareilLibelle.isEmpty ? 'Appareil' : it.appareilLibelle),
      subtitle: Text([
        if (it.clientNom != null) it.clientNom!,
        if (it.imei != null) 'IMEI ${it.imei}',
        fcfa(r.total),
      ].join('  •  ')),
      trailing: Chip(
        label: Text(StatutReparation.libelle(r.statut),
            style: const TextStyle(color: Colors.white, fontSize: 12)),
        backgroundColor: statutColor(r.statut),
        visualDensity: VisualDensity.compact,
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReparationDetailPage(
          reparationId: r.id,
          reparationRepo: widget.reparationRepo,
          produitRepo: widget.produitRepo,
          caisseRepo: widget.caisseRepo,
          photoRepo: widget.photoRepo,
          session: widget.session,
        ),
      )),
    );
  }

  Future<void> _nouvelleReparation() async {
    final clients = await widget.clientRepo.listAll();
    if (!mounted) return;
    if (clients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Créez d\'abord un client (onglet Clients).')));
      return;
    }
    await showDialog(
      context: context,
      builder: (_) => _NouvelleReparationDialog(
        clients: clients,
        appareilRepo: widget.appareilRepo,
        reparationRepo: widget.reparationRepo,
        catalogueRepo: widget.catalogueRepo,
        session: widget.session,
      ),
    );
  }
}

class _NouvelleReparationDialog extends StatefulWidget {
  final List<Client> clients;
  final AppareilRepository appareilRepo;
  final ReparationRepository reparationRepo;
  final CatalogueRepository catalogueRepo;
  final AppSession session;

  const _NouvelleReparationDialog({
    required this.clients,
    required this.appareilRepo,
    required this.reparationRepo,
    required this.catalogueRepo,
    required this.session,
  });

  @override
  State<_NouvelleReparationDialog> createState() =>
      _NouvelleReparationDialogState();
}

class _NouvelleReparationDialogState extends State<_NouvelleReparationDialog> {
  String? _clientId;
  String? _marque;
  String? _modele;
  String? _probleme;
  final _imei = TextEditingController();
  final _etat = TextEditingController();
  final _devis = TextEditingController(text: '0');
  bool _saving = false;

  // Suivi par appareil : appareils déjà connus du client + nb de réparations.
  List<Appareil> _appareils = [];
  Map<String, int> _nbRepar = {};
  String? _appareilExistantId; // appareil connu choisi ; null = nouvel appareil
  bool _chargementAppareils = false;
  String? _garantieDate; // date d'une panne identique récente sur l'appareil

  /// Si l'appareil choisi a déjà eu la même panne récemment, on le signale
  /// (possible reprise sous garantie) — décision commerciale au comptoir.
  Future<void> _verifierGarantie() async {
    if (_appareilExistantId == null || (_probleme ?? '').trim().isEmpty) {
      if (_garantieDate != null) setState(() => _garantieDate = null);
      return;
    }
    final d = await widget.reparationRepo.garantieRecente(
        appareilId: _appareilExistantId!, probleme: _probleme!.trim());
    if (mounted) setState(() => _garantieDate = d);
  }

  static String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  // Pannes fréquentes pour le modèle courant (suggestions data-driven).
  List<String> _pannesSuggerees = [];

  String? _modeleCourantStr() {
    if (_appareilExistantId != null) {
      final a = _appareils.where((x) => x.id == _appareilExistantId);
      return a.isEmpty ? null : a.first.modele;
    }
    return _modele;
  }

  Future<void> _chargerPannesFrequentes() async {
    final modele = _modeleCourantStr();
    if (modele == null || modele.trim().isEmpty) {
      if (_pannesSuggerees.isNotEmpty) setState(() => _pannesSuggerees = []);
      return;
    }
    final f = await widget.reparationRepo.pannesFrequentes(modele: modele);
    if (mounted) setState(() => _pannesSuggerees = f);
  }

  String? get _modeleLibelle =>
      (_marque == null && _modele == null) ? null : '$_marque $_modele'.trim();

  /// Charge les appareils déjà enregistrés pour ce client + le nombre de
  /// réparations passées par appareil. Présélectionne le 1er (client qui revient).
  Future<void> _chargerAppareils(String clientId) async {
    setState(() => _chargementAppareils = true);
    final apps = await widget.appareilRepo.parClient(clientId);
    final reps = await widget.reparationRepo.parClient(clientId);
    final counts = <String, int>{};
    for (final r in reps) {
      final aid = r.reparation.appareilId;
      counts[aid] = (counts[aid] ?? 0) + 1;
    }
    if (!mounted) return;
    setState(() {
      _appareils = apps;
      _nbRepar = counts;
      _appareilExistantId = apps.isNotEmpty ? apps.first.id : null;
      _chargementAppareils = false;
    });
    _verifierGarantie();
    _chargerPannesFrequentes();
  }

  String _libelleAppareil(Appareil a) {
    final s = [a.marque, a.modele]
        .where((x) => x != null && x.isNotEmpty)
        .join(' ')
        .trim();
    return s.isEmpty ? (a.type ?? 'Appareil') : s;
  }

  Future<void> _pickModele() async {
    final m = await choisirModele(context, widget.catalogueRepo);
    if (m != null) {
      setState(() {
        _marque = m.marque;
        _modele = m.modele;
      });
      _chargerPannesFrequentes();
    }
  }

  Future<void> _pickPanne() async {
    final p = await choisirPanne(context, widget.catalogueRepo);
    if (p != null) {
      setState(() => _probleme = p);
      _verifierGarantie();
    }
  }

  /// Section de choix de l'appareil : liste des appareils connus du client
  /// (avec leur nb de réparations passées) + option « nouvel appareil ».
  Widget _sectionAppareil() {
    if (_chargementAppareils) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Chargement des appareils…',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 12, bottom: 2),
          child: Text('Appareil', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ..._appareils.map((a) {
          final n = _nbRepar[a.id] ?? 0;
          return RadioListTile<String?>(
            value: a.id,
            groupValue: _appareilExistantId,
            onChanged: (v) {
              setState(() => _appareilExistantId = v);
              _verifierGarantie();
              _chargerPannesFrequentes();
            },
            title: Text(_libelleAppareil(a)),
            subtitle: Text([
              if (a.imei != null && a.imei!.isNotEmpty) 'IMEI ${a.imei}',
              '$n réparation(s) précédente(s)',
            ].join('  •  ')),
            dense: true,
            contentPadding: EdgeInsets.zero,
          );
        }),
        RadioListTile<String?>(
          value: null,
          groupValue: _appareilExistantId,
          onChanged: (v) => setState(() => _appareilExistantId = v),
          title: const Text('➕ Nouvel appareil'),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_clientId == null || (_probleme ?? '').trim().isEmpty) {
      final manque = <String>[
        if (_clientId == null) 'un client',
        if ((_probleme ?? '').trim().isEmpty) 'un problème',
      ].join(' et ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Veuillez choisir $manque.')),
      );
      return;
    }
    setState(() => _saving = true);
    String appareilId;
    if (_appareilExistantId != null) {
      // Appareil déjà connu du client : on y rattache la réparation (suivi).
      appareilId = _appareilExistantId!;
    } else {
      final appareil = await widget.appareilRepo.creer(
        clientId: _clientId!,
        type: 'téléphone',
        marque: _marque,
        modele: _modele,
        imei: _imei.text.trim().isEmpty ? null : _imei.text.trim(),
      );
      appareilId = appareil.id;
    }
    await widget.reparationRepo.creer(
      appareilId: appareilId,
      magasinId: widget.session.magasinId,
      technicienId: widget.session.userId,
      probleme: _probleme!.trim(),
      etatVisuel: _etat.text.trim().isEmpty ? null : _etat.text.trim(),
      devis: num.tryParse(_devis.text.trim()) ?? 0,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle réparation'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _clientId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Client *'),
                items: widget.clients
                    .map((c) => DropdownMenuItem(
                        value: c.id, child: Text(c.nom)))
                    .toList(),
                onChanged: (v) {
                  setState(() {
                    _clientId = v;
                    _appareils = [];
                    _nbRepar = {};
                    _appareilExistantId = null;
                  });
                  if (v != null) _chargerAppareils(v);
                },
              ),
              // Appareil : réutiliser un appareil connu du client, ou en saisir un.
              if (_clientId != null) _sectionAppareil(),
              // Champs « nouvel appareil » (seulement si aucun appareil connu choisi).
              if (_clientId != null && _appareilExistantId == null) ...[
                _ChampSelection(
                  label: 'Modèle d\'appareil',
                  valeur: _modeleLibelle,
                  icone: Icons.smartphone,
                  onTap: _pickModele,
                ),
                TextField(
                    controller: _imei,
                    decoration: const InputDecoration(
                        labelText: 'IMEI / n° série')),
              ],
              // Pannes fréquentes pour ce modèle (data-driven, tap = sélection).
              if (_pannesSuggerees.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Pannes fréquentes pour ce modèle :',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: _pannesSuggerees
                      .map((p) => ActionChip(
                            label:
                                Text(p, style: const TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              setState(() => _probleme = p);
                              _verifierGarantie();
                            },
                          ))
                      .toList(),
                ),
              ],
              // Problème : sélecteur recherchable + ajout.
              _ChampSelection(
                label: 'Problème déclaré *',
                valeur: _probleme,
                icone: Icons.report_problem,
                onTap: _pickPanne,
              ),
              if (_garantieDate != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(children: [
                    Icon(Icons.verified_user,
                        color: Colors.orange.shade800, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Possible garantie : même panne sur cet appareil le '
                        '${_fmtDate(_garantieDate!)}.',
                        style: TextStyle(
                            color: Colors.orange.shade900, fontSize: 12),
                      ),
                    ),
                  ]),
                ),
              TextField(
                  controller: _etat,
                  decoration:
                      const InputDecoration(labelText: 'État visuel à la réception')),
              TextField(
                  controller: _devis,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Devis estimé (FCFA)')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
            onPressed: _saving ? null : _save, child: const Text('Créer')),
      ],
    );
  }
}

/// Champ tappable façon liste déroulante, ouvrant un sélecteur recherchable.
class _ChampSelection extends StatelessWidget {
  final String label;
  final String? valeur;
  final IconData icone;
  final VoidCallback onTap;
  const _ChampSelection({
    required this.label,
    required this.valeur,
    required this.icone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icone),
            suffixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          child: Text(
            valeur == null || valeur!.isEmpty ? 'Choisir…' : valeur!,
            style: TextStyle(
                color: valeur == null || valeur!.isEmpty ? Colors.grey : null),
          ),
        ),
      ),
    );
  }
}
