import 'package:powersync/powersync.dart';
import '../../models/utilisateur.dart';
import '../../util/pin_hash.dart';

/// Authentification locale (§6). Login par identifiant + code PIN.
///
/// Le PIN n'est jamais stocké en clair : `utilisateurs.mot_de_passe_hash`
/// contient une empreinte PBKDF2 (sel = id utilisateur, cf. [PinHash]). La
/// vérification recalcule l'empreinte et compare à temps constant.
class AuthRepository {
  final PowerSyncDatabase db;
  AuthRepository(this.db);

  static const _select =
      'SELECT u.id AS id, u.nom AS nom, u.login AS login, '
      'u.magasin_id AS magasin_id, r.code AS role_code '
      'FROM utilisateurs u JOIN roles r ON r.id = u.role_id ';

  /// Liste des comptes (pour l'écran de connexion).
  Future<List<Utilisateur>> comptes() async {
    final rs = await db
        .getAll('$_select WHERE COALESCE(u.actif,1) = 1 ORDER BY u.nom');
    return rs.map((r) => Utilisateur.fromRow(r)).toList();
  }

  /// Tentatives avant verrouillage et durée du verrou (anti-force-brute §6).
  static const maxTentatives = 5;
  static const verrouMinutes = 5;

  /// Vérifie le PIN d'un utilisateur. L'empreinte stockée est recalculée et
  /// comparée à temps constant (jamais d'égalité en clair en SQL). Gère le
  /// verrouillage : après [maxTentatives] échecs consécutifs, le compte est
  /// bloqué pendant [verrouMinutes]. Un succès réinitialise le compteur.
  Future<LoginResult> login(String userId, String pin) async {
    final rs = await db.getAll(
      'SELECT u.id AS id, u.nom AS nom, u.login AS login, '
      'u.magasin_id AS magasin_id, r.code AS role_code, '
      'u.mot_de_passe_hash AS pin_hash, '
      'u.tentatives_echouees AS tentatives, u.verrou_jusqu_a AS verrou '
      'FROM utilisateurs u JOIN roles r ON r.id = u.role_id '
      'WHERE u.id = ? AND COALESCE(u.actif,1) = 1',
      [userId],
    );
    if (rs.isEmpty) return LoginResult.echec();
    final row = rs.first;
    final now = DateTime.now().toUtc();

    // Verrou encore actif ?
    final verrouStr = row['verrou'] as String?;
    if (verrouStr != null && verrouStr.isNotEmpty) {
      final verrou = DateTime.tryParse(verrouStr);
      if (verrou != null && verrou.isAfter(now)) {
        return LoginResult.verrou(verrou.difference(now).inSeconds);
      }
    }

    final stored = (row['pin_hash'] as String?) ?? '';
    if (PinHash.verify(pin, userId, stored)) {
      await db.execute(
        'UPDATE utilisateurs SET tentatives_echouees = 0, '
        'verrou_jusqu_a = NULL WHERE id = ?',
        [userId],
      );
      return LoginResult.ok(Utilisateur.fromRow(row));
    }

    // Échec : incrémente le compteur, verrouille au seuil atteint.
    final tentatives = ((row['tentatives'] as num?) ?? 0).toInt() + 1;
    if (tentatives >= maxTentatives) {
      final verrou = now.add(const Duration(minutes: verrouMinutes));
      await db.execute(
        'UPDATE utilisateurs SET tentatives_echouees = 0, '
        'verrou_jusqu_a = ? WHERE id = ?',
        [verrou.toIso8601String(), userId],
      );
      return LoginResult.verrou(verrouMinutes * 60);
    }
    await db.execute(
      'UPDATE utilisateurs SET tentatives_echouees = ? WHERE id = ?',
      [tentatives, userId],
    );
    return LoginResult.echec(essaisRestants: maxTentatives - tentatives);
  }
}

/// Résultat d'une tentative de connexion (§6) : succès, mauvais PIN (avec
/// essais restants) ou compte verrouillé (avec délai en secondes).
class LoginResult {
  final Utilisateur? user;
  final bool verrouille;
  final int secondesVerrou;
  final int? essaisRestants;

  LoginResult.ok(this.user)
      : verrouille = false,
        secondesVerrou = 0,
        essaisRestants = null;
  LoginResult.echec({this.essaisRestants})
      : user = null,
        verrouille = false,
        secondesVerrou = 0;
  LoginResult.verrou(this.secondesVerrou)
      : user = null,
        verrouille = true,
        essaisRestants = null;

  bool get reussi => user != null;
}
