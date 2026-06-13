import 'package:flutter/material.dart';
import '../data/demo_controller.dart';

/// Écran **Mode Démo** : joue tout le parcours de l'app en direct (présentation
/// live + smoke-test autonome). Chaque étape exécute une vraie opération et
/// affiche son résultat ; on peut mettre en pause, régler la vitesse, rejouer.
class DemoPage extends StatefulWidget {
  final DemoController controller;
  const DemoPage({super.key, required this.controller});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _scroll = ScrollController();
  final _activeKey = GlobalKey();

  DemoController get c => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.3, duration: const Duration(milliseconds: 350));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mode démo — présentation live')),
      body: AnimatedBuilder(
        animation: c,
        builder: (context, _) {
          _autoScroll();
          return Column(
            children: [
              _panneauControle(context),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: c.steps.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (context, i) => _tuile(context, i),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _panneauControle(BuildContext context) {
    final total = c.steps.length;
    final faits = c.resultats.where((r) => r != null).length;
    final progress = total == 0 ? 0.0 : faits / total;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statutChip(),
                const Spacer(),
                Text('$faits / $total étapes',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 6),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _boutonPrincipal(context),
                const SizedBox(width: 8),
                if (c.enCours)
                  OutlinedButton.icon(
                    onPressed: c.arreter,
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Arrêter'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.speed, size: 18),
                const SizedBox(width: 8),
                Text('Vitesse ×${c.vitesse.toStringAsFixed(1)}'),
                Expanded(
                  child: Slider(
                    value: c.vitesse,
                    min: 0.5,
                    max: 3.0,
                    divisions: 5,
                    label: '×${c.vitesse.toStringAsFixed(1)}',
                    onChanged: c.setVitesse,
                  ),
                ),
              ],
            ),
            if (c.erreur != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('⚠ ${c.erreur}',
                    style: TextStyle(color: Colors.red.shade800)),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'La démo crée de vraies données (préfixées « DÉMO ») et les '
                  'synchronise. Idéale pour présenter l\'app ou vérifier que tout '
                  'fonctionne.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statutChip() {
    final (texte, couleur) = switch (c.statut) {
      DemoStatut.pret => ('Prêt', Colors.blueGrey),
      DemoStatut.enCours => ('En cours…', Colors.blue),
      DemoStatut.enPause => ('En pause', Colors.orange),
      DemoStatut.termine => ('Terminé ✓', Colors.green),
      DemoStatut.erreur => ('Erreur', Colors.red),
    };
    return Chip(
      label: Text(texte, style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: couleur,
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }

  Widget _boutonPrincipal(BuildContext context) {
    if (c.statut == DemoStatut.enCours) {
      return FilledButton.icon(
        onPressed: c.pause,
        icon: const Icon(Icons.pause, size: 18),
        label: const Text('Pause'),
      );
    }
    if (c.statut == DemoStatut.enPause) {
      return FilledButton.icon(
        onPressed: c.reprendre,
        icon: const Icon(Icons.play_arrow, size: 18),
        label: const Text('Reprendre'),
      );
    }
    final rejouer = c.statut == DemoStatut.termine || c.statut == DemoStatut.erreur;
    return FilledButton.icon(
      onPressed: () => c.demarrer(),
      icon: Icon(rejouer ? Icons.replay : Icons.play_arrow, size: 18),
      label: Text(rejouer ? 'Rejouer la démo' : 'Démarrer la démo'),
    );
  }

  Widget _tuile(BuildContext context, int i) {
    final step = c.steps[i];
    final res = c.resultat(i);
    final err = res != null && res.startsWith('ERREUR');
    final done = res != null && !err;
    final current = i == c.index && c.enCours;

    final Color couleur;
    final Widget avatarChild;
    if (err) {
      couleur = Colors.red.shade600;
      avatarChild = const Icon(Icons.error_outline, color: Colors.white, size: 20);
    } else if (done) {
      couleur = Colors.green.shade600;
      avatarChild = const Icon(Icons.check, color: Colors.white, size: 20);
    } else if (current) {
      couleur = Theme.of(context).colorScheme.primary;
      avatarChild = Icon(step.icon, color: Colors.white, size: 20);
    } else {
      couleur = Colors.grey.shade400;
      avatarChild = Icon(step.icon, color: Colors.white, size: 20);
    }

    return Container(
      key: current ? _activeKey : null,
      color: current
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.06)
          : null,
      child: ListTile(
        leading: CircleAvatar(backgroundColor: couleur, child: avatarChild),
        title: Text('${i + 1}. ${step.titre}',
            style: TextStyle(
                fontWeight:
                    current || done ? FontWeight.bold : FontWeight.normal)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(step.narration,
                style: Theme.of(context).textTheme.bodySmall),
            if (current && res == null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            if (res != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(err ? Icons.close : Icons.arrow_right,
                        size: 18,
                        color: err ? Colors.red.shade700 : Colors.green.shade700),
                    Expanded(
                      child: Text(
                        err ? res.substring('ERREUR : '.length) : res,
                        style: TextStyle(
                          color:
                              err ? Colors.red.shade700 : Colors.green.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
