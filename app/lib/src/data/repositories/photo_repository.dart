import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

/// Photo d'appareil rattachée à une réparation (§5.3).
class PhotoAppareil {
  final String id;
  final String reparationId;
  final String? typePhoto;
  final String? fichierLocal; // data URL (base64) en Phase 1
  final String statutSync;

  PhotoAppareil({
    required this.id,
    required this.reparationId,
    this.typePhoto,
    this.fichierLocal,
    this.statutSync = 'local',
  });

  factory PhotoAppareil.fromRow(Map<String, dynamic> r) => PhotoAppareil(
        id: r['id'] as String,
        reparationId: r['reparation_id'] as String,
        typePhoto: r['type_photo'] as String?,
        fichierLocal: r['fichier_local'] as String?,
        statutSync: (r['statut_sync'] as String?) ?? 'local',
      );
}

/// Stockage des photos (§5.3). En Phase 1 web, l'image est stockée en data URL
/// base64 (compressée à la capture). En production : object storage + url_sync.
class PhotoRepository {
  final PowerSyncDatabase db;
  final _uuid = const Uuid();

  PhotoRepository(this.db);

  Stream<List<PhotoAppareil>> watch(String reparationId) {
    return db
        .watch(
            'SELECT * FROM photos_appareil WHERE reparation_id = ? '
            'ORDER BY date_creation',
            parameters: [reparationId])
        .map((rs) => rs.map((r) => PhotoAppareil.fromRow(r)).toList());
  }

  Future<void> ajouter({
    required String reparationId,
    String? typePhoto,
    required String dataUrl,
  }) async {
    if (!dataUrl.startsWith('data:image/')) {
      throw ArgumentError('Le fichier doit être une image (data:image/…).');
    }
    // ~5 Mo base64 ≈ 3,75 Mo image compressée — suffit pour intake photo
    if (dataUrl.length > 6 * 1024 * 1024) {
      throw ArgumentError('Image trop volumineuse (max 5 Mo).');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await db.execute(
      'INSERT INTO photos_appareil(id, reparation_id, type_photo, '
      'fichier_local, statut_sync, date_creation) VALUES(?,?,?,?,?,?)',
      [_uuid.v4(), reparationId, typePhoto, dataUrl, 'local', now],
    );
  }
}
