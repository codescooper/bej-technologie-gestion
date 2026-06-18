import 'package:flutter/material.dart';
import '../app_session.dart';
import '../data/repositories/phase3_repository.dart';

/// Paramètres Phase 3 : FNE/DGI, Notifications SMS/WhatsApp, Campagnes fidélité.
/// Accessible aux responsables/admins uniquement.
class ParametresPage extends StatefulWidget {
  final AppSession session;
  final Phase3Repository phase3Repo;

  const ParametresPage({
    super.key,
    required this.session,
    required this.phase3Repo,
  });

  @override
  State<ParametresPage> createState() => _ParametresPageState();
}

class _ParametresPageState extends State<ParametresPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long), text: 'FNE / DGI'),
            Tab(icon: Icon(Icons.message), text: 'Notifications'),
            Tab(icon: Icon(Icons.stars), text: 'Fidélité'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _FneTab(session: widget.session, repo: widget.phase3Repo),
          _NotifTab(session: widget.session, repo: widget.phase3Repo),
          _CampagnesTab(session: widget.session, repo: widget.phase3Repo),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet FNE / DGI
// ─────────────────────────────────────────────────────────────────────────────

class _FneTab extends StatefulWidget {
  final AppSession session;
  final Phase3Repository repo;
  const _FneTab({required this.session, required this.repo});
  @override
  State<_FneTab> createState() => _FneTabState();
}

class _FneTabState extends State<_FneTab> {
  final _endpoint = TextEditingController();
  final _merchantId = TextEditingController();
  final _apiKey = TextEditingController();
  final _numeroContrib = TextEditingController();
  bool _actif = false;
  bool _loading = true;
  bool _saving = false;
  bool _showApiKey = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _merchantId.dispose();
    _apiKey.dispose();
    _numeroContrib.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await widget.repo.configFne(widget.session.magasinId);
    if (!mounted) return;
    setState(() {
      _actif = (cfg?['actif'] as int? ?? 0) == 1;
      _endpoint.text = cfg?['endpoint_url'] as String? ?? '';
      _merchantId.text = cfg?['merchant_id'] as String? ?? '';
      _apiKey.text = cfg?['api_key'] as String? ?? '';
      _numeroContrib.text = cfg?['numero_contrib'] as String? ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.repo.sauvegarderConfigFne(
      magasinId: widget.session.magasinId,
      actif: _actif,
      endpointUrl: _endpoint.text.trim(),
      merchantId: _merchantId.text.trim(),
      apiKey: _apiKey.text.trim(),
      numeroContrib: _numeroContrib.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Configuration FNE enregistrée')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Facture Normalisée Électronique (DGI)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'L\'intégration FNE soumet chaque vente à la DGI Côte d\'Ivoire '
                  'pour obtenir un numéro de facture officiel et un QR fiscal. '
                  'Laissez "Inactif" jusqu\'à l\'obtention de vos accès DGI.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Activer la soumission FNE'),
          subtitle: Text(_actif
              ? 'Chaque vente sera transmise à la DGI'
              : 'Désactivé — les ventes ne sont pas transmises'),
          value: _actif,
          onChanged: (v) => setState(() => _actif = v),
        ),
        const Divider(),
        const SizedBox(height: 8),
        TextField(
          controller: _endpoint,
          decoration: const InputDecoration(
            labelText: 'URL de l\'API DGI',
            hintText: 'https://efacture.dgi.ci/api/v1',
            prefixIcon: Icon(Icons.link),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _merchantId,
          decoration: const InputDecoration(
            labelText: 'Identifiant marchand (Merchant ID)',
            prefixIcon: Icon(Icons.store),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _numeroContrib,
          decoration: const InputDecoration(
            labelText: 'Numéro de contribuable',
            hintText: 'Ex : CI-ABJ-XXXXX-XXXX',
            prefixIcon: Icon(Icons.numbers),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _apiKey,
          obscureText: !_showApiKey,
          decoration: InputDecoration(
            labelText: 'Clé API',
            prefixIcon: const Icon(Icons.key),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_showApiKey ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showApiKey = !_showApiKey),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            label: const Text('Enregistrer'),
          ),
        ),
        const SizedBox(height: 24),
        _HistoriqueFacturesFne(session: widget.session, repo: widget.repo),
      ],
    );
  }
}

class _HistoriqueFacturesFne extends StatelessWidget {
  final AppSession session;
  final Phase3Repository repo;
  const _HistoriqueFacturesFne({required this.session, required this.repo});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dernières factures émises',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: repo.watchFacturesFne(session.magasinId),
          builder: (context, snap) {
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return const Text('Aucune facture FNE émise.',
                  style: TextStyle(color: Colors.grey));
            }
            return Column(
              children: items.take(10).map((f) {
                final statut = f['statut'] as String;
                final color = statut == 'emise'
                    ? Colors.green
                    : statut == 'erreur'
                        ? Colors.red
                        : Colors.orange;
                return ListTile(
                  dense: true,
                  leading: Icon(Icons.receipt, color: color, size: 20),
                  title: Text(f['numero_facture'] as String? ?? f['transaction_id'] as String),
                  subtitle: Text(statut == 'erreur'
                      ? f['erreur'] as String? ?? ''
                      : statut),
                  trailing: Text(_dateC(f['date_emission'] as String?),
                      style: const TextStyle(fontSize: 11)),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  static String _dateC(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)} ${p(d.hour)}:${p(d.minute)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Notifications
// ─────────────────────────────────────────────────────────────────────────────

class _NotifTab extends StatefulWidget {
  final AppSession session;
  final Phase3Repository repo;
  const _NotifTab({required this.session, required this.repo});
  @override
  State<_NotifTab> createState() => _NotifTabState();
}

class _NotifTabState extends State<_NotifTab> {
  final _sid = TextEditingController();
  final _token = TextEditingController();
  final _from = TextEditingController();
  bool _actif = false;
  bool _whatsapp = false;
  bool _loading = true;
  bool _saving = false;
  bool _showToken = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _sid.dispose();
    _token.dispose();
    _from.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await widget.repo.configNotifications(widget.session.magasinId);
    if (!mounted) return;
    setState(() {
      _actif = (cfg?['actif'] as int? ?? 0) == 1;
      _whatsapp = (cfg?['utiliser_whatsapp'] as int? ?? 0) == 1;
      _sid.text = cfg?['account_sid'] as String? ?? '';
      _token.text = cfg?['auth_token'] as String? ?? '';
      _from.text = cfg?['from_number'] as String? ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.repo.sauvegarderConfigNotifications(
      magasinId: widget.session.magasinId,
      actif: _actif,
      accountSid: _sid.text.trim(),
      authToken: _token.text.trim(),
      fromNumber: _from.text.trim(),
      utiliserWhatsapp: _whatsapp,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Configuration notifications enregistrée')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SMS / WhatsApp via Twilio',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Envoie automatiquement un message au client lors de la '
                  'réception de son appareil, quand la réparation est prête, '
                  'et à la livraison. Nécessite un compte Twilio.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('Activer les notifications'),
          value: _actif,
          onChanged: (v) => setState(() => _actif = v),
        ),
        SwitchListTile(
          title: const Text('Utiliser WhatsApp'),
          subtitle: const Text('SMS si désactivé, WhatsApp si activé'),
          value: _whatsapp,
          onChanged: (v) => setState(() => _whatsapp = v),
        ),
        const Divider(),
        const SizedBox(height: 8),
        TextField(
          controller: _sid,
          decoration: const InputDecoration(
            labelText: 'Twilio Account SID',
            hintText: 'ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
            prefixIcon: Icon(Icons.account_circle),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _token,
          obscureText: !_showToken,
          decoration: InputDecoration(
            labelText: 'Auth Token',
            prefixIcon: const Icon(Icons.key),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showToken = !_showToken),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _from,
          decoration: InputDecoration(
            labelText: _whatsapp ? 'Numéro WhatsApp Twilio' : 'Numéro SMS Twilio',
            hintText: _whatsapp ? 'whatsapp:+14155238886' : '+14155238886',
            prefixIcon: Icon(_whatsapp ? Icons.chat_bubble_outline : Icons.sms),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            label: const Text('Enregistrer'),
          ),
        ),
        const SizedBox(height: 24),
        Text('Dernières notifications',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: widget.repo.watchNotificationsLog(widget.session.magasinId),
          builder: (context, snap) {
            final items = snap.data ?? [];
            if (items.isEmpty) {
              return const Text('Aucune notification envoyée.',
                  style: TextStyle(color: Colors.grey));
            }
            return Column(
              children: items.take(15).map((n) {
                final ok = n['statut'] == 'envoye';
                return ListTile(
                  dense: true,
                  leading: Icon(
                    n['canal'] == 'whatsapp' ? Icons.chat_bubble_outline : Icons.sms,
                    color: ok ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  title: Text(n['client_nom'] as String? ?? n['numero'] as String),
                  subtitle: Text(ok ? n['message'] as String : n['erreur'] as String? ?? ''),
                  trailing: Text(_dateC(n['date_envoi'] as String?),
                      style: const TextStyle(fontSize: 11)),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  static String _dateC(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)} ${p(d.hour)}:${p(d.minute)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Campagnes fidélité
// ─────────────────────────────────────────────────────────────────────────────

class _CampagnesTab extends StatelessWidget {
  final AppSession session;
  final Phase3Repository repo;
  const _CampagnesTab({required this.session, required this.repo});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<CampagneFidelite>>(
        stream: repo.watchCampagnes(session.magasinId),
        builder: (context, snap) {
          final items = snap.data ?? [];
          final now = DateTime.now().toUtc();
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Campagnes bonus jetons',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Pendant une campagne active, les clients gagnent le montant '
                        'normal × le multiplicateur. Ex : ×2 = 200 FCFA → 2 jetons.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aucune campagne.', style: TextStyle(color: Colors.grey)),
                )
              else
                ...items.map((c) {
                  final debut = DateTime.tryParse(c.dateDebut);
                  final fin = DateTime.tryParse(c.dateFin);
                  final enCours = debut != null && fin != null &&
                      now.isAfter(debut) && now.isBefore(fin) && c.actif;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: enCours ? Colors.amber : Colors.grey.shade200,
                        child: Text('×${c.multiplicateur.toStringAsFixed(1)}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: enCours ? Colors.white : Colors.grey)),
                      ),
                      title: Text(c.nom),
                      subtitle: Text(
                          '${_dateCourte(c.dateDebut)} → ${_dateCourte(c.dateFin)}'
                          '${enCours ? '  🟢 En cours' : ''}'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'toggle') {
                            await repo.toggleCampagne(c.id, !c.actif);
                          } else if (v == 'delete') {
                            await repo.supprimerCampagne(c.id);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(c.actif ? 'Désactiver' : 'Activer'),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Supprimer', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nouvelleCampagne(context),
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle campagne'),
      ),
    );
  }

  void _nouvelleCampagne(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _Nouvellecamp(session: session, repo: repo),
    );
  }

  static String _dateCourte(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year}';
  }
}

class _Nouvellecamp extends StatefulWidget {
  final AppSession session;
  final Phase3Repository repo;
  const _Nouvellecamp({required this.session, required this.repo});
  @override
  State<_Nouvellecamp> createState() => _Nouvellecamp_State();
}

class _Nouvellecamp_State extends State<_Nouvellecamp> {
  final _nom = TextEditingController();
  final _desc = TextEditingController();
  double _mult = 2.0;
  DateTimeRange? _periode;

  @override
  void dispose() {
    _nom.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickPeriode() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _periode,
    );
    if (r != null) setState(() => _periode = r);
  }

  Future<void> _save() async {
    if (_nom.text.trim().isEmpty || _periode == null) return;
    await widget.repo.creerCampagne(
      magasinId: widget.session.magasinId,
      nom: _nom.text.trim(),
      multiplicateur: _mult,
      dateDebut: _periode!.start,
      dateFin: _periode!.end,
      description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    String p(int n) => n.toString().padLeft(2, '0');
    final periodeLabel = _periode == null
        ? 'Choisir une période'
        : '${p(_periode!.start.day)}/${p(_periode!.start.month)} → '
            '${p(_periode!.end.day)}/${p(_periode!.end.month)}/${_periode!.end.year}';

    return AlertDialog(
      title: const Text('Nouvelle campagne fidélité'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nom,
              decoration: const InputDecoration(
                  labelText: 'Nom', border: OutlineInputBorder()),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Multiplicateur  ×'),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: _mult,
                    min: 1.5,
                    max: 5.0,
                    divisions: 7,
                    label: '×${_mult.toStringAsFixed(1)}',
                    onChanged: (v) => setState(() => _mult = v),
                  ),
                ),
                Text('${_mult.toStringAsFixed(1)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickPeriode,
              icon: const Icon(Icons.date_range),
              label: Text(periodeLabel),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(
                  labelText: 'Description (optionnel)',
                  border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(
            onPressed: _save,
            child: const Text('Créer')),
      ],
    );
  }
}
