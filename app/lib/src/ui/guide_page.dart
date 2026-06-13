import 'package:flutter/material.dart';

/// Tutoriel d'utilisation intégré à l'application (accessible via l'icône ?
/// de la barre du haut). Pensé pour un usage terrain : étapes claires, langage
/// simple, parcours d'une journée type.
class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guide d\'utilisation')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          _Intro(),
          SizedBox(height: 8),
          _JourneeType(),
          SizedBox(height: 8),
          _Section(
            icon: Icons.sync,
            titre: 'La barre du haut',
            points: [
              'Magasin : choisissez le magasin actif. Le stock et la caisse '
                  'affichés sont ceux de CE magasin (chaque magasin gère son stock).',
              'Voyant vert « Serveur en ligne » / orange « Hors ligne » : indique '
                  'si le serveur est joignable. Vous pouvez travailler hors ligne.',
              'Bouton nuage ⬆ : envoie au serveur tout ce qui a été saisi en local. '
                  'Le chiffre sur le bouton = nombre d\'opérations en attente.',
              'Icône graphique 📊 : ouvre le tableau de bord du magasin '
                  '(chiffre d\'affaires du jour, réparations en cours, stock bas, caisse).',
            ],
          ),
          _Section(
            icon: Icons.slideshow,
            titre: 'Mode démo (présentation live)',
            points: [
              'Icône ▶ en haut (responsable/admin) : lance une démonstration '
                  'automatique de TOUT le parcours de l\'app.',
              'Chaque étape s\'exécute réellement (client, vente, réparation, '
                  'transfert, réappro, inventaire, retour, clôture, synchro) et '
                  'affiche son résultat en direct.',
              'Boutons Pause / Reprendre / Arrêter et réglage de la vitesse ; '
                  '« Rejouer » relance depuis le début.',
              'Pratique pour présenter l\'app ou vérifier que tout fonctionne '
                  '(si une étape échoue, elle passe en rouge). Les données créées '
                  'sont préfixées « DÉMO ».',
            ],
          ),
          _Section(
            icon: Icons.people,
            titre: 'Onglet Clients',
            points: [
              'Bouton « Client » : créer une fiche (nom obligatoire, téléphone, WhatsApp).',
              'Anti-doublon : si le téléphone existe déjà, un avertissement s\'affiche '
                  'pour éviter de créer deux fois le même client.',
              'Le solde de jetons de fidélité de chaque client est affiché.',
            ],
          ),
          _Section(
            icon: Icons.inventory_2,
            titre: 'Onglet Stock',
            points: [
              'Liste des produits du magasin avec la quantité disponible.',
              'En rouge « stock bas » : la quantité a atteint le seuil d\'alerte.',
              'Bouton « Produit » : ajouter un nouveau produit (nom, prix, stock initial).',
              'Toucher un produit : ajuster le stock (+ entrée / - sortie) avec un motif.',
              'Bouton « Réappro » (responsable/admin) : liste les produits sous le '
                  'seuil d\'alerte et les magasins capables de fournir ; créez un '
                  'transfert en un geste.',
              'Bouton « Inventaire » (responsable/admin) : comptez physiquement le '
                  'stock ; à la validation, le stock est aligné sur le comptage et '
                  'chaque écart est tracé (mouvement « inventaire »).',
            ],
          ),
          _Section(
            icon: Icons.account_balance_wallet,
            titre: 'Onglet Caisse',
            points: [
              'Ouvrir la caisse en début de journée avec le fond de caisse initial.',
              'Une seule caisse ouverte à la fois par magasin.',
              'Clôturer en fin de journée : saisissez le cash et le mobile money réels '
                  'comptés. L\'application calcule l\'écart avec le théorique.',
            ],
          ),
          _Section(
            icon: Icons.point_of_sale,
            titre: 'Onglet Vente',
            points: [
              'La caisse doit être ouverte pour vendre.',
              'À gauche : touchez les produits pour les ajouter au panier (le stock '
                  'restant est indiqué). À droite : le panier, avec + / - par ligne.',
              'Champ de scan (en haut à gauche) : un lecteur de code-barres USB '
                  'ajoute le produit au panier automatiquement ; sinon tapez le '
                  'code-barres puis Entrée.',
              'Client : optionnel (sinon « client de passage », sans jetons).',
              'Remise : remise globale sur le total. Jetons : si un client est choisi, '
                  'utilisez ses jetons en réduction.',
              'Encaisser : répartissez le montant entre Espèces / Wave / Orange Money / '
                  'MTN MoMo. Vous pouvez combiner plusieurs moyens (paiement mixte).',
              'Un reçu interne avec QR s\'affiche. Le stock est décrémenté et les '
                  'jetons gagnés (100 FCFA = 1 jeton) sont crédités au client.',
              'Bouton « Imprimer » sur le reçu : édite un ticket (format reçu '
                  '57 mm) via l\'imprimante du navigateur.',
              'Retour / Avoir : bouton en haut du panier. Choisissez la vente, les '
                  'articles à rendre (partiel ou tout), validez → un AVOIR est créé '
                  'pour le client (le stock revient, les jetons sont annulés).',
              'Payer avec un avoir : si le client a un avoir, un bouton « Appliquer » '
                  'apparaît et déduit le crédit du total.',
            ],
          ),
          _Section(
            icon: Icons.build,
            titre: 'Onglet Réparations',
            points: [
              'Bouton « Réparation » : choisir le client, puis le MODÈLE et le '
                  'PROBLÈME via des listes recherchables (tapez pour filtrer ; si '
                  'l\'élément manque, « Ajouter » l\'enregistre pour la prochaine fois).',
              'Suivi par appareil : après avoir choisi le client, ses APPAREILS '
                  'déjà connus s\'affichent (avec le nombre de réparations passées). '
                  'Sélectionnez-en un pour y rattacher la réparation, ou '
                  '« ➕ Nouvel appareil » pour en saisir un (modèle + IMEI).',
              'Historique & garantie : la fiche réparation montre « Historique de '
                  'cet appareil » (tous ses passages). À la création, si la MÊME '
                  'panne revient sous 30 jours sur le même appareil, un avertissement '
                  '« possible garantie » s\'affiche.',
              'Aide à la saisie : les PANNES fréquentes du modèle sont proposées en '
                  'un tap ; à l\'ajout d\'une pièce, les PIÈCES compatibles avec '
                  'l\'appareil apparaissent en tête (calculé sur l\'historique).',
              'Ouvrez une fiche pour faire évoluer le STATUT (reçu → … → prêt → livré), '
                  'saisir le diagnostic et la main-d\'œuvre.',
              'Ajouter une pièce : prélève du stock et l\'ajoute au total de la réparation.',
              'Ajouter des photos à la réception (preuve en cas de litige).',
              'Encaisser au retrait : génère l\'encaissement en caisse et passe la '
                  'réparation à « livré ».',
            ],
          ),
          _Section(
            icon: Icons.account_circle,
            titre: 'Connexion & rôles',
            points: [
              'Chaque personne se connecte avec son compte et son code PIN.',
              'Les droits dépendent du rôle (§6) : le technicien ne fait pas '
                  'd\'encaissement ; l\'ajustement de stock, la validation des retours '
                  'et le tableau de bord sont réservés au responsable / administrateur.',
              'Menu compte (icône en haut à droite) : voir qui est connecté et se '
                  'déconnecter.',
            ],
          ),
          _Section(
            icon: Icons.swap_horiz,
            titre: 'Transferts inter-magasins',
            points: [
              'Réservé au responsable / administrateur (icône ⇄ en haut).',
              'Envoyer : choisissez le produit, la quantité et le magasin '
                  'destinataire → le stock part « en transit » (il quitte votre magasin).',
              'Le magasin destinataire voit le transfert en « entrant » et '
                  '« Confirme la réception » → le stock est ajouté chez lui.',
              'Annuler : tant qu\'un envoi est « en transit », le magasin émetteur '
                  'peut l\'annuler — le stock lui revient aussitôt.',
              'Tant que ce n\'est pas confirmé, le stock reste en transit : aucun '
                  'magasin ne modifie directement le stock d\'un autre.',
              'Administrateur : le tableau de bord propose une vue '
                  '« reporting consolidé » de tous les magasins, avec le '
                  'rapprochement de caisse (écarts de clôture par magasin).',
            ],
          ),
          _Section(
            icon: Icons.wifi_off,
            titre: 'Travailler hors ligne',
            points: [
              'Tout fonctionne sans internet : clients, stock, caisse, ventes.',
              'Les opérations s\'accumulent en local (compteur « en attente »).',
              'Dès que le serveur est joignable, touchez le bouton nuage ⬆ pour '
                  'tout synchroniser. Rien n\'est perdu en cas de coupure.',
            ],
          ),
          SizedBox(height: 24),
          Center(
            child: Text('BEJ Technologie — application de gestion',
                style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bienvenue 👋',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(
                'Cette application gère vos clients, votre stock, votre caisse et '
                'vos ventes — même sans connexion internet. Naviguez avec les 4 '
                'onglets en bas de l\'écran.'),
          ],
        ),
      ),
    );
  }
}

class _JourneeType extends StatelessWidget {
  const _JourneeType();
  @override
  Widget build(BuildContext context) {
    const etapes = [
      'Choisir votre magasin (barre du haut).',
      'Onglet Caisse → Ouvrir la caisse (fond initial).',
      'Onglet Vente → composer le panier, choisir le client, Encaisser.',
      'Synchroniser (bouton nuage) quand internet est disponible.',
      'Onglet Caisse → Clôturer en fin de journée (comptage + écart).',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: const [
              Icon(Icons.wb_sunny, color: Colors.orange),
              SizedBox(width: 8),
              Text('Une journée type',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            ...List.generate(etapes.length, (i) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      child: Text('${i + 1}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(etapes[i])),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String titre;
  final List<String> points;
  const _Section(
      {required this.icon, required this.titre, required this.points});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: Icon(icon),
        title: Text(titre,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: points
            .map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(child: Text(p)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}
