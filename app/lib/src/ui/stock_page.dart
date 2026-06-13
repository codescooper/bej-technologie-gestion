import 'package:flutter/material.dart';
import '../app_session.dart';
import '../data/repositories/produit_repository.dart';
import '../data/repositories/transfert_repository.dart';
import '../data/repositories/inventaire_repository.dart';
import '../models/produit.dart';
import '../util/format.dart';
import 'reappro_page.dart';
import 'inventaire_page.dart';

/// Onglet Stock (§5.7) : catalogue + quantité disponible du magasin courant.
/// Donne aussi accès au réapprovisionnement et à l'inventaire (Finitions Phase 2+).
class StockPage extends StatelessWidget {
  final ProduitRepository produitRepo;
  final TransfertRepository transfertRepo;
  final InventaireRepository inventaireRepo;
  final AppSession session;
  const StockPage({
    super.key,
    required this.produitRepo,
    required this.transfertRepo,
    required this.inventaireRepo,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<ProduitStock>>(
        stream: produitRepo.watchCatalogue(session.magasinId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          final Widget liste = items.isEmpty
              ? const Center(child: Text('Aucun produit. Ajoutez-en un (+).'))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final ps = items[i];
                    return ListTile(
                      title: Text(ps.produit.nom),
                      subtitle: Text(
                          '${ps.produit.categorie ?? ''}  •  ${fcfa(ps.produit.prixVente)}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${ps.quantiteDispo}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color:
                                    ps.stockBas ? Colors.red.shade700 : null,
                              )),
                          if (ps.stockBas)
                            Text('stock bas',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.red.shade700)),
                        ],
                      ),
                      onTap: session.peutAjusterStock
                          ? () => _ajuster(context, ps)
                          : null,
                    );
                  },
                );
          return Column(
            children: [
              if (session.peutAjusterStock) _barreActions(context, items),
              Expanded(child: liste),
            ],
          );
        },
      ),
      floatingActionButton: session.peutAjusterStock
          ? FloatingActionButton.extended(
              onPressed: () => _ajouterProduit(context),
              icon: const Icon(Icons.add_box),
              label: const Text('Produit'),
            )
          : null,
    );
  }

  Widget _barreActions(BuildContext context, List<ProduitStock> items) {
    final nbBas = items.where((p) => p.stockBas).length;
    return Material(
      color: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ReapproPage(
                    produitRepo: produitRepo,
                    transfertRepo: transfertRepo,
                    session: session,
                  ),
                )),
                icon: Badge(
                  isLabelVisible: nbBas > 0,
                  label: Text('$nbBas'),
                  child: const Icon(Icons.move_to_inbox, size: 20),
                ),
                label: const Text('Réappro'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => InventairePage(
                    inventaireRepo: inventaireRepo,
                    session: session,
                  ),
                )),
                icon: const Icon(Icons.fact_check, size: 20),
                label: const Text('Inventaire'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _ajuster(BuildContext context, ProduitStock ps) async {
    final ctrl = TextEditingController();
    final motif = TextEditingController();
    final delta = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Ajuster : ${ps.produit.nom}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Stock actuel : ${ps.quantiteDispo}'),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Variation (+ entrée / - sortie)', hintText: 'ex : 5 ou -2'),
          ),
          TextField(
            controller: motif,
            decoration: const InputDecoration(labelText: 'Motif'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(ctrl.text.trim())),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (delta != null && delta != 0) {
      await produitRepo.ajusterStock(
        produitId: ps.produit.id,
        magasinId: session.magasinId,
        delta: delta,
        motif: motif.text.trim().isEmpty ? 'Ajustement' : motif.text.trim(),
        utilisateurId: session.userId,
      );
    }
  }

  Future<void> _ajouterProduit(BuildContext context) async {
    final nom = TextEditingController();
    final prix = TextEditingController();
    final stock = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouveau produit'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: nom,
              decoration: const InputDecoration(labelText: 'Nom *')),
          TextField(
              controller: prix,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Prix de vente (FCFA) *')),
          TextField(
              controller: stock,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Stock initial')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Créer')),
        ],
      ),
    );
    if (ok == true && nom.text.trim().isNotEmpty) {
      await produitRepo.creerProduit(
        nom: nom.text.trim(),
        prixVente: num.tryParse(prix.text.trim()) ?? 0,
        prixAchat: 0,
        magasinId: session.magasinId,
        stockInitial: int.tryParse(stock.text.trim()) ?? 0,
      );
    }
  }
}
