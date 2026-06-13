import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';
import '../../models/catalogue.dart';

/// Catalogues recherchables et enrichissables : modèles d'appareils et pannes.
///
/// La recherche est faite côté Dart avec normalisation (minuscules + accents
/// retirés) car SQLite `lower()` est ASCII seulement — ainsi « ecran » trouve
/// « Écran cassé ». Les catalogues étant petits, on charge tout puis on filtre.
class CatalogueRepository {
  final PowerSyncDatabase db;
  final _uuid = const Uuid();
  CatalogueRepository(this.db);

  static String _norm(String s) {
    s = s.toLowerCase().trim();
    const from = 'àâäáãéèêëíìîïóòôöõúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }

  // ---- Modèles d'appareils ----

  Future<List<ModeleAppareil>> rechercheModeles(String query) async {
    final rs = await db.getAll('SELECT * FROM modeles_appareil');
    final modeles = rs.map((r) => ModeleAppareil.fromRow(r)).toList()
      ..sort((a, b) => _norm(a.libelle).compareTo(_norm(b.libelle)));
    final q = _norm(query);
    if (q.isEmpty) return modeles.take(50).toList();
    return modeles
        .where((m) => _norm(m.libelle).contains(q))
        .take(50)
        .toList();
  }

  /// Ajoute un modèle s'il n'existe pas (insensible casse/accents) et le renvoie.
  Future<ModeleAppareil> ajouterModele(String marque, String modele,
      {String? type}) async {
    final rs = await db.getAll('SELECT * FROM modeles_appareil');
    final cible = '${_norm(marque)} ${_norm(modele)}';
    for (final r in rs) {
      final m = ModeleAppareil.fromRow(r);
      if ('${_norm(m.marque)} ${_norm(m.modele)}' == cible) return m;
    }
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'INSERT INTO modeles_appareil(id, marque, modele, type, date_creation) '
      'VALUES(?,?,?,?,?)',
      [id, marque.trim(), modele.trim(), type, now],
    );
    return ModeleAppareil(
        id: id, marque: marque.trim(), modele: modele.trim(), type: type);
  }

  // ---- Pannes ----

  Future<List<String>> recherchePannes(String query) async {
    final rs = await db.getAll('SELECT libelle FROM pannes');
    final pannes = rs.map((r) => r['libelle'] as String).toList()
      ..sort((a, b) => _norm(a).compareTo(_norm(b)));
    final q = _norm(query);
    if (q.isEmpty) return pannes.take(50).toList();
    return pannes.where((l) => _norm(l).contains(q)).take(50).toList();
  }

  /// Ajoute une panne si absente (insensible casse/accents) et renvoie le libellé.
  Future<String> ajouterPanne(String libelle) async {
    final l = libelle.trim();
    final rs = await db.getAll('SELECT libelle FROM pannes');
    final cible = _norm(l);
    for (final r in rs) {
      final existant = r['libelle'] as String;
      if (_norm(existant) == cible) return existant;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'INSERT INTO pannes(id, libelle, date_creation) VALUES(?,?,?)',
      [_uuid.v4(), l, now],
    );
    return l;
  }
}
