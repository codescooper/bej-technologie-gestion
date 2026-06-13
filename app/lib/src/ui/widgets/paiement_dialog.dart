import 'package:flutter/material.dart';
import '../../models/vente.dart';
import '../../util/format.dart';

/// Dialogue de saisie du paiement — un ou plusieurs moyens (paiement mixte,
/// §5.4). Partagé entre la vente comptoir et l'encaissement réparation.
///
/// Renvoie une `List<PaiementInput>` (ou null si annulé).
class PaiementDialog extends StatefulWidget {
  final num total;
  const PaiementDialog({super.key, required this.total});

  @override
  State<PaiementDialog> createState() => _PaiementDialogState();
}

class _PaiementDialogState extends State<PaiementDialog> {
  static const _methodes = {
    'cash': 'Espèces',
    'wave': 'Wave',
    'orange_money': 'Orange Money',
    'mtn_momo': 'MTN MoMo',
  };
  late final Map<String, TextEditingController> _ctrls = {
    for (final k in _methodes.keys) k: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _ctrls['cash']!.text = widget.total.round().toString(); // défaut tout cash
  }

  num get _saisi => _ctrls.values
      .fold<num>(0, (s, c) => s + (num.tryParse(c.text.trim()) ?? 0));

  @override
  Widget build(BuildContext context) {
    final reste = widget.total - _saisi;
    return AlertDialog(
      title: Text('Paiement — ${fcfa(widget.total)}'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._methodes.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: TextField(
                    controller: _ctrls[e.key],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: e.value),
                    onChanged: (_) => setState(() {}),
                  ),
                )),
            const SizedBox(height: 8),
            Text(
              reste == 0
                  ? 'Compte juste ✓'
                  : (reste > 0
                      ? 'Reste ${fcfa(reste)}'
                      : 'Surplus ${fcfa(-reste)}'),
              style: TextStyle(
                  color: reste == 0
                      ? Colors.green.shade700
                      : Colors.orange.shade800),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            final list = <PaiementInput>[];
            for (final e in _ctrls.entries) {
              final v = num.tryParse(e.value.text.trim()) ?? 0;
              if (v > 0) list.add(PaiementInput(e.key, v));
            }
            if (list.isEmpty) return;
            Navigator.pop(context, list);
          },
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
