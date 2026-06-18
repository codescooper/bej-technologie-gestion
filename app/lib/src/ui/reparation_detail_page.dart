import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../app_session.dart';
import '../data/repositories/reparation_repository.dart';
import '../data/repositories/produit_repository.dart';
import '../data/repositories/caisse_repository.dart';
import '../data/repositories/photo_repository.dart';
import '../models/reparation.dart';
import '../models/produit.dart';
import '../models/vente.dart';
import '../util/format.dart';
import '../services/notification_service.dart';
import 'widgets/paiement_dialog.dart';

/// Détail d'une réparation : statut, diagnostic, pièces, photos, encaissement.
class ReparationDetailPage extends StatefulWidget {
  final String reparationId;
  final ReparationRepository reparationRepo;
  final ProduitRepository produitRepo;
  final CaisseRepository caisseRepo;
  final PhotoRepository photoRepo;
  final AppSession session;
  final NotificationService? notifService;

  const ReparationDetailPage({
    super.key,
    required this.reparationId,
    required this.reparationRepo,
    required this.produitRepo,
    required this.caisseRepo,
    required this.photoRepo,
    required this.session,
    this.notifService,
  });

  @override
  State<ReparationDetailPage> createState() => _ReparationDetailPageState();
}

class _ReparationDetailPageState extends State<ReparationDetailPage> {
  late Future<ReparationListItem?> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = widget.reparationRepo.getById(widget.reparationId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réparation')),
      body: FutureBuilder<ReparationListItem?>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final it = snap.data!;
          final r = it.reparation;
          final encaissable =
              r.statut != StatutReparation.livre && r.statut != StatutReparation.annule;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                  it.appareilLibelle.isEmpty ? 'Appareil' : it.appareilLibelle,
                  style: Theme.of(context).textTheme.titleLarge),
              if (it.clientNom != null) Text('Client : ${it.clientNom}'),
              if (it.imei != null) Text('IMEI : ${it.imei}'),
              const SizedBox(height: 12),
              _statutSelector(r, it),
              const Divider(height: 24),
              if (r.probleme != null) _info('Problème', r.probleme!),
              if (r.etatVisuel != null) _info('État à la réception', r.etatVisuel!),
              if (r.diagnostic != null) _info('Diagnostic', r.diagnostic!),
              const SizedBox(height: 8),
              _info('Main-d\'œuvre', fcfa(r.montantMainOeuvre)),
              _info('Pièces', fcfa(r.montantPieces)),
              _info('TOTAL', fcfa(r.total), bold: true),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => _diagnostic(r),
                  icon: const Icon(Icons.medical_services, size: 18),
                  label: const Text('Diagnostic / main-d\'œuvre'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _ajouterPiece(r, it.modele),
                  icon: const Icon(Icons.build, size: 18),
                  label: const Text('Ajouter une pièce'),
                ),
              ]),
              const Divider(height: 24),
              _photos(r),
              const SizedBox(height: 16),
              _historiqueAppareil(r.appareilId, r.id),
              const SizedBox(height: 16),
              if (encaissable)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _encaisser(r),
                    icon: const Icon(Icons.payments),
                    label: Text('Encaisser au retrait — ${fcfa(r.total)}'),
                  ),
                ),
              if (r.statut == StatutReparation.livre)
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Réparation livrée et encaissée ✓',
                      style: TextStyle(color: Colors.teal)),
                )),
            ],
          );
        },
      ),
    );
  }

  /// Historique des réparations du MÊME appareil (suivi par appareil).
  Widget _historiqueAppareil(String appareilId, String currentId) {
    return FutureBuilder<List<ReparationListItem>>(
      future: widget.reparationRepo.parAppareil(appareilId),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final autres =
            snap.data!.where((x) => x.reparation.id != currentId).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 24),
            Text('Historique de cet appareil (${autres.length})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            if (autres.isEmpty)
              const Text('Premier passage de cet appareil.',
                  style: TextStyle(color: Colors.grey))
            else
              ...autres.map((x) {
                final rr = x.reparation;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.history, color: Colors.blueGrey),
                  title: Text(rr.probleme ?? 'Réparation'),
                  subtitle: Text(
                      '${_dateCourte(rr.dateCreation)}  •  ${StatutReparation.libelle(rr.statut)}  •  ${fcfa(rr.total)}'),
                );
              }),
          ],
        );
      },
    );
  }

  static String _dateCourte(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  Widget _info(String l, String v, {bool bold = false}) {
    final st = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l, style: st),
          Flexible(child: Text(v, style: st, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _statutSelector(Reparation r, ReparationListItem item) {
    final statuts = [...StatutReparation.ordre, StatutReparation.annule];
    return Row(
      children: [
        const Text('Statut : '),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: r.statut,
          items: statuts
              .map((s) => DropdownMenuItem(
                  value: s, child: Text(StatutReparation.libelle(s))))
              .toList(),
          onChanged: (s) async {
            if (s == null) return;
            await widget.reparationRepo.changerStatut(r.id, s);
            _reload();
            widget.notifService?.notifierChangementStatut(
              magasinId: widget.session.magasinId,
              magasinNom: widget.session.magasinNom,
              clientId: item.clientId,
              appareilLibelle: item.appareilLibelle.isEmpty
                  ? 'votre appareil'
                  : item.appareilLibelle,
              statut: s,
            );
          },
        ),
      ],
    );
  }

  Widget _photos(Reparation r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Photos (§5.3)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _prendrePhoto(r),
              icon: const Icon(Icons.add_a_photo, size: 18),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        StreamBuilder<List<PhotoAppareil>>(
          stream: widget.photoRepo.watch(r.id),
          builder: (context, snap) {
            final photos = snap.data ?? [];
            if (photos.isEmpty) {
              return const Text('Aucune photo.',
                  style: TextStyle(color: Colors.grey));
            }
            return SizedBox(
              height: 90,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: photos.map((p) {
                  final bytes = _decode(p.fichierLocal);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: bytes == null
                        ? const Icon(Icons.broken_image)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.memory(bytes,
                                width: 90, height: 90, fit: BoxFit.cover),
                          ),
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }

  static Uint8List? _decode(String? dataUrl) {
    if (dataUrl == null) return null;
    final i = dataUrl.indexOf(',');
    final b64 = i >= 0 ? dataUrl.substring(i + 1) : dataUrl;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Future<void> _prendrePhoto(Reparation r) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 1024, imageQuality: 50);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    await widget.photoRepo
        .ajouter(reparationId: r.id, typePhoto: 'reception', dataUrl: dataUrl);
  }

  Future<void> _diagnostic(Reparation r) async {
    final diag = TextEditingController(text: r.diagnostic ?? '');
    final mo = TextEditingController(text: r.montantMainOeuvre.round().toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Diagnostic'),
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: diag,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Diagnostic')),
            TextField(
                controller: mo,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Main-d\'œuvre (FCFA)')),
          ]),
        ),
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
    if (ok == true) {
      await widget.reparationRepo.majDiagnostic(r.id,
          diagnostic: diag.text.trim().isEmpty ? null : diag.text.trim(),
          montantMainOeuvre: num.tryParse(mo.text.trim()) ?? r.montantMainOeuvre);
      _reload();
    }
  }

  Future<void> _ajouterPiece(Reparation r, String? modeleRef) async {
    final produit = await showDialog<ProduitStock>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Choisir une pièce'),
        content: SizedBox(
          width: 340,
          height: 360,
          child: StreamBuilder<List<ProduitStock>>(
            stream: widget.produitRepo.watchCatalogue(widget.session.magasinId),
            builder: (context, snap) {
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return const Center(child: Text('Aucun produit.'));
              }
              ListTile tile(ProduitStock ps) => ListTile(
                    dense: true,
                    title: Text(ps.produit.nom),
                    subtitle: Text(
                        '${fcfa(ps.produit.prixVente)} • stock ${ps.quantiteDispo}'),
                    enabled: ps.quantiteDispo > 0,
                    onTap: () => Navigator.pop(context, ps),
                  );
              // Pièces compatibles : nom du produit contenant le modèle.
              final term = (modeleRef ?? '').toLowerCase().trim();
              final compat = term.isEmpty
                  ? <ProduitStock>[]
                  : items
                      .where((p) => p.produit.nom.toLowerCase().contains(term))
                      .toList();
              final autres = term.isEmpty
                  ? items
                  : items
                      .where((p) => !p.produit.nom.toLowerCase().contains(term))
                      .toList();
              return ListView(
                children: [
                  if (compat.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text('Pièces compatibles ($modeleRef)',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                    ...compat.map(tile),
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text('Autres produits',
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                  ],
                  ...autres.map(tile),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
        ],
      ),
    );
    if (produit != null) {
      await widget.reparationRepo.consommerPiece(
        reparationId: r.id,
        produitId: produit.produit.id,
        magasinId: widget.session.magasinId,
        prixUnitaire: produit.produit.prixVente,
        utilisateurId: widget.session.userId,
      );
      _reload();
    }
  }

  Future<void> _encaisser(Reparation r) async {
    final caisse = await widget.caisseRepo.caisseOuverte(widget.session.magasinId);
    if (!mounted) return;
    if (caisse == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ouvrez la caisse avant d\'encaisser (onglet Caisse).')));
      return;
    }
    final paiements = await showDialog<List<PaiementInput>>(
      context: context,
      builder: (_) => PaiementDialog(total: r.total),
    );
    if (paiements == null) return;
    final result = await widget.reparationRepo.encaisserRetrait(
      reparationId: r.id,
      magasinId: widget.session.magasinId,
      caisseId: caisse.id,
      utilisateurId: widget.session.userId,
      paiements: paiements,
    );
    _reload();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Réparation encaissée'),
        content: Text(
            'Total : ${fcfa(result.total)}\nRéf : ${result.transactionId}'
            '${result.jetonsGagnes > 0 ? '\n+ ${result.jetonsGagnes} jetons' : ''}'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Terminer')),
        ],
      ),
    );
  }
}
