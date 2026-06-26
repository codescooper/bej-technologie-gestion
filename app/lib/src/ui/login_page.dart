import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import '../app_session.dart';
import '../data/repositories/auth_repository.dart';
import '../models/utilisateur.dart';

/// Écran de connexion (§6) : choix du compte + code PIN.
class LoginPage extends StatefulWidget {
  final AuthRepository authRepo;
  final AppSession session;
  const LoginPage({super.key, required this.authRepo, required this.session});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  List<Utilisateur> _comptes = [];
  String? _selectedId;
  final _pin = TextEditingController();
  String? _erreur;
  bool _loading = true;
  bool _busy = false; // connexion en cours (vérification PIN)

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final c = await widget.authRepo.comptes();
    if (!mounted) return;
    setState(() {
      _comptes = c;
      _selectedId = c.isNotEmpty ? c.first.id : null;
      _loading = false;
    });
  }

  Future<void> _connexion() async {
    if (_selectedId == null || _busy) return;
    setState(() {
      _busy = true;
      _erreur = null;
    });
    final res = await widget.authRepo.login(_selectedId!, _pin.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.reussi) {
      widget.session.login(res.user!);
      return;
    }
    _pin.clear();
    if (res.verrouille) {
      final minutes = (res.secondesVerrou / 60).ceil();
      setState(() => _erreur =
          'Compte verrouillé (trop d\'essais). Réessayez dans $minutes min.');
    } else {
      setState(() => _erreur = res.essaisRestants != null
          ? 'Code PIN incorrect. ${res.essaisRestants} essai(s) restant(s).'
          : 'Code PIN incorrect.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      body: Center(
        child: SingleChildScrollView(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Container(
              width: 360,
              padding: const EdgeInsets.all(24),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator())
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.point_of_sale, size: 48, color: Color(0xFF1565C0)),
                        const SizedBox(height: 8),
                        Text('BEJ Technologie',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge),
                        const Text('Connexion',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 24),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Compte', border: OutlineInputBorder()),
                          items: _comptes
                              .map((u) => DropdownMenuItem(
                                    value: u.id,
                                    child: Text('${u.nom} — ${_role(u.roleCode)}'),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() {
                            _selectedId = v;
                            _erreur = null;
                          }),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pin,
                          decoration: const InputDecoration(
                              labelText: 'Code PIN',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.lock)),
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          onSubmitted: (_) => _connexion(),
                        ),
                        if (_erreur != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_erreur!,
                                style: TextStyle(color: Colors.red.shade700)),
                          ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _busy ? null : _connexion,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.login),
                          label: Text(_busy ? 'Connexion…' : 'Se connecter'),
                        ),
                        const SizedBox(height: 12),
                        if (kDebugMode)
                          const Text(
                            'PIN démo — admin 1111 · caissier 2222 · responsable 3333 · technicien 4444',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  String _role(String code) => const {
        'admin': 'Administrateur',
        'responsable': 'Responsable',
        'caissier': 'Caissier',
        'technicien': 'Technicien',
      }[code] ??
      code;
}
