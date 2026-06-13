import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Hachage de code PIN (durcissement §6).
///
/// PBKDF2-HMAC-SHA256, avec **sel = identifiant utilisateur** (unique et stable).
/// Le sel n'est donc pas stocké séparément : il vaut l'`id` de l'utilisateur,
/// déjà connu. Sortie : 32 octets en hexadécimal (64 caractères).
///
/// Adapté à un code PIN de point de vente local. Pour un usage exposé sur
/// Internet, compléter par Argon2id/bcrypt et un verrouillage après N essais.
class PinHash {
  /// Nombre de tours d'étirement (ralentit une attaque par force brute).
  static const int iterations = 50000;

  /// Hache [pin] avec le sel [salt] (l'id utilisateur). Renvoie 64 car. hex.
  static String hash(String pin, String salt) {
    final hmac = Hmac(sha256, utf8.encode(pin)); // clé = PIN
    // PBKDF2, un seul bloc (longueur de clé dérivée = 32 = taille de SHA-256).
    final bloc = <int>[...utf8.encode(salt), 0, 0, 0, 1]; // salt || INT_32_BE(1)
    var u = hmac.convert(bloc).bytes;
    final acc = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < acc.length; j++) {
        acc[j] ^= u[j];
      }
    }
    final sb = StringBuffer();
    for (final b in acc) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// Vérifie [pin] contre la valeur stockée [stored] pour le sel [salt].
  /// Comparaison à temps constant. Repli doux : si [stored] n'est pas une
  /// empreinte (ancien PIN en clair), compare directement — migration sans
  /// casse tant que toutes les empreintes ne sont pas regénérées.
  static bool verify(String pin, String salt, String stored) {
    if (stored.isEmpty) return false;
    final computed = hash(pin, salt);
    if (computed.length != stored.length) {
      return _constEq(pin, stored); // ancien format en clair
    }
    return _constEq(computed, stored);
  }

  static bool _constEq(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
