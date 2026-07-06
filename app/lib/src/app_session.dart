import 'package:flutter/foundation.dart';
import 'data/ref_ids.dart';
import 'models/utilisateur.dart';

/// Contexte de session : utilisateur connecté, son rôle (§6) et le magasin courant.
///
/// Par défaut (avant connexion réelle) : caissière Awa à Cocody — ce qui permet
/// aux tests et au mode démo de fonctionner. `main()` démarre déconnecté
/// (`logout()`) pour afficher l'écran de connexion ; `login()` fixe l'utilisateur.
class AppSession extends ChangeNotifier {
  String _magasinId = RefIds.magasinCocody;
  String _userId = RefIds.userAwaCaissiere;
  String _userNom = 'Awa (caissière Cocody)';
  String _roleCode = 'caissier';
  bool _authentifie = true;

  String get magasinId => _magasinId;
  String get userId => _userId;
  String get userNom => _userNom;
  String get roleCode => _roleCode;
  bool get authentifie => _authentifie;

  String get magasinNom =>
      magasinsRef.firstWhere((m) => m.id == _magasinId, orElse: () => magasinsRef.first).nom;

  String get roleLibelle => const {
        'admin': 'Administrateur',
        'responsable': 'Responsable',
        'caissier': 'Caissier',
        'technicien': 'Technicien',
      }[_roleCode] ??
      _roleCode;

  // ---- Permissions (matrice §6) ----
  bool get estAdmin => _roleCode == 'admin';
  bool get _estResp => _roleCode == 'admin' || _roleCode == 'responsable';
  bool get peutEncaisser => _roleCode != 'technicien';
  bool get peutCaisse => _roleCode != 'technicien';
  bool get peutAjusterStock => _estResp;
  bool get peutValiderRetour => _estResp;
  bool get peutDashboard => _estResp;
  bool get peutGererQrCodes => _estResp;
  // Écran Paramètres : le caissier peut configurer (notifications) ; FNE fiscal
  // et campagnes fidélité restent réservés au responsable/admin (avancé).
  bool get peutParametres => _roleCode != 'technicien';
  bool get peutParametresAvances => _estResp;
  bool get peutModifierDiagnostic => _roleCode != 'caissier';
  bool get peutChangerMagasin => _estResp;
  bool get peutDashboardGlobal => estAdmin;

  void login(Utilisateur u) {
    _userId = u.id;
    _userNom = u.nom;
    _roleCode = u.roleCode;
    _magasinId = u.magasinId ?? RefIds.magasinCocody;
    _authentifie = true;
    notifyListeners();
  }

  void logout() {
    _authentifie = false;
    notifyListeners();
  }

  void setMagasin(String id) {
    if (id == _magasinId) return;
    _magasinId = id;
    notifyListeners();
  }
}
