import 'package:flutter/material.dart';
import '../app_session.dart';
import '../data/repositories/etiquette_qr_repository.dart';
import '../data/repositories/produit_repository.dart';
import '../models/produit.dart';
import '../util/format.dart';
import '../util/qr_labels_pdf.dart';

/// Préparation & impression des étiquettes QR brandées BEJ (orange) :
///  - Réparation : un POOL de stickers vierges (pioche + appose à la réception).
///  - Vente : un QR par produit (généré si absent), pour scanner l'article.
/// Le format d'impression est choisi par l'utilisateur selon son matériel.
class QrCodesPage extends StatefulWidget {
  final EtiquetteQrRepository etiquetteRepo;
  final ProduitRepository produitRepo;
  final AppSession session;

  const QrCodesPage({
    super.key,
    required this.etiquetteRepo,
    required this.produitRepo,
    required this.session,
  });

  @override
  State<QrCodesPage> createState() => _QrCodesPageState();
}

class _QrCodesPageState extends State<QrCodesPage> {
  FormatEtiquette _format = FormatEtiquette.plancheA4;
  final _nCtrl = TextEditingController(text: '24');
  final Set<String> _selVente = {};
  bool _busy = false;
  late Future<({int libres, int utilisees})> _comptesFuture;

  String get _mag => widget.session.magasinId;

  @override
  void initState() {
    super.initState();
    _comptesFuture = widget.etiquetteRepo.comptes(_mag);
  }

  @override
  void dispose() {
    _nCtrl.dispose();
    super.dispose();
  }

  void _refreshComptes() =>
      setState(() => _comptesFuture = widget.etiquetteRepo.comptes(_mag));

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _preparerReparation() async {
    final n = int.tryParse(_nCtrl.text.trim()) ?? 0;
    if (n <= 0) {
      _snack('Indiquez un nombre de stickers à préparer (> 0).');
      return;
    }
    if (n > 500) {
      _snack('Maximum 500 stickers à la fois.');
      return;
    }
    setState(() => _busy = true);
    try {
      final codes = await widget.etiquetteRepo
          .preparerLotReparation(magasinId: _mag, nombre: n);
      final labels =
          codes.map((c) => EtiquetteLabel.reparation(code: c)).toList();
      await imprimerEtiquettes(labels, _format);
      if (!mounted) return;
      _refreshComptes();
      _snack('${codes.length} sticker(s) préparé(s) et envoyé(s) à l\'impression.');
    } catch (e) {
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _imprimerVente() async {
    if (_selVente.isEmpty) {
      _snack('Sélectionnez au moins un produit.');
      return;
    }
    setState(() => _busy = true);
    try {
      final ids = _selVente.toList();
      final nGeneres = await widget.produitRepo.genererQrCodesManquants(ids);
      final rows = await widget.produitRepo.qrLabelsVente(ids);
      final labels = rows
          .map((r) => EtiquetteLabel.vente(
                payload: r['payload'] as String,
                codeBarres: r['code_barres'] as String?,
                nom: (r['nom'] as String?) ?? '',
                prix: (r['prix_vente'] as num?) ?? 0,
              ))
          .toList();
      await imprimerEtiquettes(labels, _format);
      if (!mounted) return;
      _snack('${labels.length} étiquette(s) envoyée(s) — $nGeneres QR généré(s).');
    } catch (e) {
      _snack('Erreur : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Étiquettes QR'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Réparation', icon: Icon(Icons.build)),
            Tab(text: 'Vente', icon: Icon(Icons.sell)),
          ]),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.print_outlined, size: 20),
                  const SizedBox(width: 8),
                  const Text('Format : '),
                  const SizedBox(width: 4),
                  Expanded(
                    child: DropdownButton<FormatEtiquette>(
                      isExpanded: true,
                      value: _format,
                      items: FormatEtiquette.values
                          .map((f) => DropdownMenuItem(
                              value: f, child: Text(formatEtiquetteLabel(f))))
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _format = v ?? _format),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 3,
              child: _busy ? const LinearProgressIndicator() : null,
            ),
            Expanded(
              child: TabBarView(children: [_tabReparation(), _tabVente()]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabReparation() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<({int libres, int utilisees})>(
            future: _comptesFuture,
            builder: (context, snap) {
              final c = snap.data;
              return Row(
                children: [
                  _carteCompteur('Libres', c?.libres, Colors.green.shade700),
                  const SizedBox(width: 12),
                  _carteCompteur(
                      'Utilisées', c?.utilisees, Colors.blueGrey.shade600),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Nombre de stickers à préparer',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _preparerReparation,
            icon: const Icon(Icons.print),
            label: const Text('Préparer & imprimer'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Imprimez une planche de stickers, collez-en un sur chaque appareil '
            'à la réception, puis scannez-le pour le lier à la réparation.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _carteCompteur(String label, int? val, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(val?.toString() ?? '—',
                  style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold, color: color)),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabVente() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<ProduitStock>>(
            stream: widget.produitRepo.watchCatalogue(_mag),
            builder: (context, snap) {
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return const Center(child: Text('Catalogue vide.'));
              }
              return ListView(
                children: items.map((ps) {
                  final id = ps.produit.id;
                  return CheckboxListTile(
                    value: _selVente.contains(id),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                              if (v == true) {
                                _selVente.add(id);
                              } else {
                                _selVente.remove(id);
                              }
                            }),
                    title: Text(ps.produit.nom),
                    subtitle: Text(fcfa(ps.produit.prixVente)),
                    dense: true,
                  );
                }).toList(),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: Text('${_selVente.length} sélectionné(s)')),
              FilledButton.icon(
                onPressed: _busy ? null : _imprimerVente,
                icon: const Icon(Icons.print),
                label: const Text('Générer QR & imprimer'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
