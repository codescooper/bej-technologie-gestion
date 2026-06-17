import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Ouvre une modale caméra pour scanner un QR / code-barres. Renvoie le premier
/// code décodé (`rawValue`) ou `null` si l'utilisateur ferme la modale ou si la
/// caméra est indisponible. La douchette et la saisie manuelle restent le repli.
///
/// Web : la caméra requiert un contexte sécurisé (https ou localhost) + une
/// autorisation du navigateur ; sinon `errorBuilder` s'affiche et l'utilisateur
/// ferme la modale pour revenir au champ de scan.
Future<String?> scannerCameraQr(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _ScanCameraDialog(),
  );
}

class _ScanCameraDialog extends StatefulWidget {
  const _ScanCameraDialog();

  @override
  State<_ScanCameraDialog> createState() => _ScanCameraDialogState();
}

class _ScanCameraDialogState extends State<_ScanCameraDialog> {
  // Sans contrôleur explicite, MobileScanner gère start/stop/dispose lui-même.
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue?.trim();
      if (v != null && v.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 340,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Scanner un QR',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: MobileScanner(
                  onDetect: _onDetect,
                  errorBuilder: _erreurCamera,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text(
                'Visez le QR. Sans caméra : utilisez la douchette ou '
                'saisissez le code en clair sous le QR.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _erreurCamera(BuildContext context, MobileScannerException error) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, color: Colors.white, size: 40),
              const SizedBox(height: 12),
              const Text('Caméra indisponible',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text(
                'Autorisez la caméra dans le navigateur, ou utilisez la '
                'douchette / la saisie manuelle du code.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fermer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
