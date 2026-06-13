import 'package:flutter/material.dart';
import '../app_session.dart';
import '../data/repositories/caisse_repository.dart';
import '../models/caisse.dart';
import '../util/format.dart';

/// Onglet Caisse (§5.4) : ouverture / clôture, comptage et écart.
class CaissePage extends StatelessWidget {
  final CaisseRepository caisseRepo;
  final AppSession session;
  const CaissePage({super.key, required this.caisseRepo, required this.session});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Caisse?>(
      stream: caisseRepo.watchCaisseOuverte(session.magasinId),
      builder: (context, snap) {
        final caisse = snap.data;
        if (caisse == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_balance_wallet_outlined, size: 64),
                const SizedBox(height: 12),
                Text('Aucune caisse ouverte pour ${session.magasinNom}.'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: session.peutCaisse ? () => _ouvrir(context) : null,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Ouvrir la caisse'),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lock_open, color: Colors.green),
                  title: const Text('Caisse ouverte'),
                  subtitle: Text(
                      'Ouverte à ${_heure(caisse.ouverture)}\nFond initial : ${fcfa(caisse.fondInitial)}'),
                  isThreeLine: true,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700),
                  onPressed:
                      session.peutCaisse ? () => _cloturer(context, caisse) : null,
                  icon: const Icon(Icons.lock),
                  label: const Text('Clôturer la caisse'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _heure(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _ouvrir(BuildContext context) async {
    final fond = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ouvrir la caisse'),
        content: TextField(
          controller: fond,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Fond de caisse initial (FCFA)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ouvrir')),
        ],
      ),
    );
    if (ok == true) {
      await caisseRepo.ouvrir(
        magasinId: session.magasinId,
        utilisateurId: session.userId,
        fondInitial: num.tryParse(fond.text.trim()) ?? 0,
      );
    }
  }

  Future<void> _cloturer(BuildContext context, Caisse caisse) async {
    // Le dialogue s'affiche IMMÉDIATEMENT ; les totaux théoriques se chargent à
    // l'intérieur (FutureBuilder) — aucun await avant showDialog (fiabilité).
    final cash = TextEditingController();
    final mobile = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clôture de caisse'),
        content: SizedBox(
          width: 320,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FutureBuilder<({num cash, num mobile})>(
              future: caisseRepo.totauxTheoriques(caisse.id),
              builder: (ctx, snap) {
                final t = snap.data;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Théorique cash (fond + ventes) : ${t == null ? '…' : fcfa(caisse.fondInitial + t.cash)}'),
                    Text(
                        'Théorique mobile money : ${t == null ? '…' : fcfa(t.mobile)}'),
                  ],
                );
              },
            ),
            const Divider(),
            TextField(
                controller: cash,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Cash réel compté')),
            TextField(
                controller: mobile,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Mobile money réel')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clôturer')),
        ],
      ),
    );
    if (result == true) {
      final c = await caisseRepo.cloturer(
        caisseId: caisse.id,
        cashReel: num.tryParse(cash.text.trim()) ?? 0,
        mobileReel: num.tryParse(mobile.text.trim()) ?? 0,
      );
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Caisse clôturée'),
          content: Text(
              'Écart constaté : ${fcfa(c.ecart ?? 0)}\n\n${(c.ecart ?? 0) == 0 ? 'Caisse juste ✓' : 'Vérifier l\'écart.'}'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
    }
  }
}
