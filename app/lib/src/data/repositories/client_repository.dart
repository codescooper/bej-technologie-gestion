import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';
import '../../models/client.dart';

/// Accès aux clients, offline-first (§5.1). Les UUID sont générés localement
/// (clé locale) ; la déduplication serveur se fait sur `telephone_normalise`
/// au moment de la consolidation (§2.6).
class ClientRepository {
  final PowerSyncDatabase db;
  final _uuid = const Uuid();

  ClientRepository(this.db);

  /// Normalisation du téléphone (§2.6) : format international sans séparateurs.
  /// Côte d'Ivoire (+225) par défaut si l'indicatif est absent.
  static String? normalizePhone(String? raw) {
    if (raw == null) return null;
    var s = raw.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (s.isEmpty) return null;
    if (s.startsWith('+')) return s;
    if (s.startsWith('225')) return '+$s';
    return '+225$s';
  }

  /// Flux réactif de la liste des clients actifs (non fusionnés).
  Stream<List<Client>> watchAll() {
    return db
        .watch(
          'SELECT * FROM clients WHERE fusionne_vers IS NULL '
          'ORDER BY date_creation DESC',
        )
        .map((rs) => rs.map((r) => Client.fromRow(r)).toList());
  }

  /// Liste ponctuelle des clients actifs (pour un sélecteur).
  Future<List<Client>> listAll() async {
    final rs = await db.getAll(
      'SELECT * FROM clients WHERE fusionne_vers IS NULL ORDER BY nom',
    );
    return rs.map((r) => Client.fromRow(r)).toList();
  }

  Future<Client?> getById(String id) async {
    final rs = await db.getAll('SELECT * FROM clients WHERE id = ?', [id]);
    return rs.isEmpty ? null : Client.fromRow(rs.first);
  }

  /// Met à jour la fiche client (nom, téléphone, WhatsApp).
  Future<void> update({
    required String id,
    required String nom,
    String? telephone,
    String? whatsapp,
  }) async {
    await db.execute(
      'UPDATE clients SET nom = ?, telephone = ?, telephone_normalise = ?, '
      'whatsapp = ? WHERE id = ?',
      [nom, telephone, normalizePhone(telephone), whatsapp, id],
    );
  }

  /// Historique des transactions du client (ventes, réparations, retours).
  Future<List<Map<String, dynamic>>> transactions(String clientId) async {
    final rs = await db.getAll(
      'SELECT id, type, total, date FROM transactions '
      'WHERE client_id = ? ORDER BY date DESC LIMIT 100',
      [clientId],
    );
    return rs
        .map((r) => {
              'id': r['id'],
              'type': r['type'],
              'total': r['total'],
              'date': r['date'],
            })
        .toList();
  }

  /// Recherche un client existant par téléphone normalisé (proposition de
  /// fiche existante à la saisie, §5.1).
  Future<Client?> findByPhone(String? normalized) async {
    if (normalized == null) return null;
    final rs = await db.getAll(
      'SELECT * FROM clients WHERE telephone_normalise = ? '
      'AND fusionne_vers IS NULL LIMIT 1',
      [normalized],
    );
    if (rs.isEmpty) return null;
    return Client.fromRow(rs.first);
  }

  Future<Client> create({
    required String nom,
    String? telephone,
    String? whatsapp,
  }) async {
    final id = _uuid.v4();
    final norm = normalizePhone(telephone);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'INSERT INTO clients(id, nom, telephone, telephone_normalise, whatsapp, '
      'solde_jetons, date_creation) VALUES(?,?,?,?,?,?,?)',
      [id, nom, telephone, norm, whatsapp, 0, now],
    );
    return Client(
      id: id,
      nom: nom,
      telephone: telephone,
      telephoneNormalise: norm,
      whatsapp: whatsapp,
      soldeJetons: 0,
      dateCreation: now,
    );
  }
}
