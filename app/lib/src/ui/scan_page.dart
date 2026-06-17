import 'package:flutter/material.dart';
import '../app_session.dart';
import '../data/repositories/etiquette_qr_repository.dart';
import '../data/repositories/produit_repository.dart';
import '../data/repositories/caisse_repository.dart';
import '../data/repositories/reparation_repository.dart';
import '../data/repositories/photo_repository.dart';
import '../models/reparation.dart';
import 'reparation_detail_page.dart';
import 'scan_camera.dart';

/// Scan universel (point d'entrée central) : un QR / code-barres est résolu vers
///  - un PRODUIT → on revient vers la Vente avec l'article (pop ProduitStock,
///    la coquille bascule sur l'onglet Vente et l'ajoute au panier) ;
///  - un APPAREIL → on ouvre sa fiche réparation (appareil + propriétaire +
///    actions) ;
///  - un sticker libre / code inconnu → message d'aide.
/// Douchette (clavier) par défaut + bouton caméra ; le code en clair imprimé
/// sous le QR peut être saisi à la main si rien ne le lit.
class ScanPage extends StatefulWidget {
  final EtiquetteQrRepository etiquetteRepo;
  final ProduitRepository produitRepo;
  final ReparationRepository reparationRepo;
  final CaisseRepository caisseRepo;
  final PhotoRepository photoRepo;
  final AppSession session;

  const ScanPage({
    super.key,
    required this.etiquetteRepo,
    required this.produitRepo,
    required this.reparationRepo,
    required this.caisseRepo,
    required this.photoRepo,
    required this.session,
  });

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _scanCamera() async {
    final code = await scannerCameraQr(context);
    if (!mounted) return;
    if (code != null && code.trim().isNotEmpty) {
      await _traiter(code.trim());
    } else {
      _focus.requestFocus();
    }
  }

  Future<void> _onSubmit(String code) async {
    final c = code.trim();
    _ctrl.clear();
    if (c.isEmpty) {
      _focus.requestFocus();
      return;
    }
    await _traiter(c);
  }

  Future<void> _traiter(String code) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final res = await widget.etiquetteRepo.resoudre(code);
      if (!mounted) return;
      if (res == null) {
        setState(() => _message = 'Code inconnu : $code');
        return;
      }
      switch (res.cible) {
        case CibleQr.produit:
          final ps = await widget.produitRepo
              .findById(widget.session.magasinId, res.produitId!);
          if (!mounted) return;
          if (ps == null) {
            setState(() => _message = 'Produit introuvable.');
            return;
          }
          // Retour vers la coquille : bascule sur Vente + ajout au panier.
          Navigator.of(context).pop(ps);
          return;
        case CibleQr.appareil:
          await _ouvrirAppareil(res.appareilId!);
          return;
        case CibleQr.etiquetteLibre:
          setState(() => _message =
              'Sticker libre (non encore affecté). Liez-le à un appareil '
              'lors d\'une nouvelle réparation.');
          return;
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Erreur : $e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _focus.requestFocus();
      }
    }
  }

  Future<void> _ouvrirAppareil(String appareilId) async {
    final reps = await widget.reparationRepo.parAppareil(appareilId);
    if (!mounted) return;
    if (reps.isEmpty) {
      setState(() =>
          _message = 'Appareil reconnu, mais aucune réparation enregistrée.');
      return;
    }
    // Réparation active en priorité (ni livrée ni annulée), sinon la plus récente.
    final actives = reps
        .where((r) =>
            r.reparation.statut != StatutReparation.livre &&
            r.reparation.statut != StatutReparation.annule)
        .toList();
    final cible = actives.isNotEmpty ? actives.first : reps.first;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReparationDetailPage(
        reparationId: cible.reparation.id,
        reparationRepo: widget.reparationRepo,
        produitRepo: widget.produitRepo,
        caisseRepo: widget.caisseRepo,
        photoRepo: widget.photoRepo,
        session: widget.session,
      ),
    ));
    if (mounted) _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.qr_code_scanner, size: 72, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'Scannez un QR (article ou appareil) avec la douchette ou la '
              'caméra, ou saisissez le code en clair imprimé sous le QR.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              focusNode: _focus,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.qr_code_scanner),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.photo_camera),
                  tooltip: 'Scanner avec la caméra',
                  onPressed: _busy ? null : _scanCamera,
                ),
                hintText: 'Scanner ou saisir un code',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: _busy ? null : _onSubmit,
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade900),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_message!,
                          style: TextStyle(color: Colors.orange.shade900)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
