import 'package:powersync/powersync.dart';
import 'package:uuid/uuid.dart';

/// Nature de la cible résolue à partir d'un code scanné.
enum CibleQr { etiquetteLibre, appareil, produit }

/// Résultat de la résolution d'un code scanné (QR ou code-barres).
class ResolutionQr {
  final CibleQr cible;
  final String code;
  final String? appareilId; // si cible == appareil
  final String? produitId; // si cible == produit
  final String? etiquetteId; // si cible == etiquetteLibre (ou appareil via pool)
  ResolutionQr({
    required this.cible,
    required this.code,
    this.appareilId,
    this.produitId,
    this.etiquetteId,
  });
}

/// Une étiquette du pool (sticker QR pré-imprimé).
class EtiquetteQr {
  final String id;
  final String code;
  final String type; // reparation | vente
  final String statut; // libre | utilise
  final String? appareilId;
  EtiquetteQr({
    required this.id,
    required this.code,
    required this.type,
    required this.statut,
    this.appareilId,
  });

  factory EtiquetteQr.fromRow(Map<String, dynamic> r) => EtiquetteQr(
        id: r['id'] as String,
        code: r['code'] as String,
        type: (r['type'] as String?) ?? 'reparation',
        statut: (r['statut'] as String?) ?? 'libre',
        appareilId: r['appareil_id'] as String?,
      );
}

/// Étiquettes QR brandées BEJ : préparation en lot d'un pool de stickers
/// (réparation), affectation d'un sticker à un appareil, et résolution d'un
/// code scanné vers sa cible (produit pour la vente, appareil pour la fiche
/// réparation). La vente réutilise `produits.qr_code` (payload `BEJ-P-<id>`).
class EtiquetteQrRepository {
  final PowerSyncDatabase db;
  final _uuid = const Uuid();

  EtiquetteQrRepository(this.db);

  /// Code court et typeable pour un sticker réparation : `BEJ-R-<10 hex maj>`.
  String _genCodeReparation() =>
      'BEJ-R-${_uuid.v4().replaceAll('-', '').substring(0, 10).toUpperCase()}';

  /// Prépare un lot de [nombre] stickers réparation `libre` pour un magasin.
  /// Renvoie les codes générés (pour impression). Anti-collision local.
  Future<List<String>> preparerLotReparation({
    required String magasinId,
    required int nombre,
  }) async {
    if (nombre <= 0) return const [];
    final now = DateTime.now().toUtc().toIso8601String();
    final codes = <String>[];
    await db.writeTransaction((tx) async {
      for (var i = 0; i < nombre; i++) {
        String code;
        do {
          code = _genCodeReparation();
        } while ((await tx.getAll(
                'SELECT 1 FROM etiquettes_qr WHERE code = ? LIMIT 1', [code]))
            .isNotEmpty);
        await tx.execute(
          'INSERT INTO etiquettes_qr(id, code, type, statut, magasin_id, '
          'date_creation) VALUES(?,?,?,?,?,?)',
          [_uuid.v4(), code, 'reparation', 'libre', magasinId, now],
        );
        codes.add(code);
      }
    });
    return codes;
  }

  /// Stickers réparation encore `libre` d'un magasin (pour « piocher »).
  Future<List<EtiquetteQr>> codesLibresReparation(String magasinId) async {
    final rs = await db.getAll(
      "SELECT * FROM etiquettes_qr WHERE magasin_id = ? AND type = 'reparation' "
      "AND statut = 'libre' ORDER BY date_creation",
      [magasinId],
    );
    return rs.map((r) => EtiquetteQr.fromRow(r)).toList();
  }

  /// Flux des stickers réparation `libre` (rafraîchi à chaque changement).
  Stream<List<EtiquetteQr>> watchLibresReparation(String magasinId) {
    return db.watch(
      "SELECT * FROM etiquettes_qr WHERE magasin_id = ? AND type = 'reparation' "
      "AND statut = 'libre' ORDER BY date_creation",
      parameters: [magasinId],
    ).map((rs) => rs.map((r) => EtiquetteQr.fromRow(r)).toList());
  }

  /// Compteurs libres / utilisées (réparation) pour un magasin.
  Future<({int libres, int utilisees})> comptes(String magasinId) async {
    final rs = await db.getAll(
      "SELECT statut, count(*) AS c FROM etiquettes_qr "
      "WHERE magasin_id = ? AND type = 'reparation' GROUP BY statut",
      [magasinId],
    );
    var libres = 0, utilisees = 0;
    for (final r in rs) {
      final c = ((r['c'] as num?) ?? 0).toInt();
      if (r['statut'] == 'utilise') {
        utilisees = c;
      } else if (r['statut'] == 'libre') {
        libres = c;
      }
    }
    return (libres: libres, utilisees: utilisees);
  }

  /// Résout un code scanné (QR ou code-barres). `code` est globalement unique.
  /// Ordre : pool d'étiquettes → appareil (qr_code) → produit (qr_code) →
  /// repli préfixe `BEJ-P-<id>` → repli code-barres legacy (scan comptoir §8).
  Future<ResolutionQr?> resoudre(String codeScanne) async {
    final code = codeScanne.trim();
    if (code.isEmpty) return null;

    // 1) Étiquette du pool (libre ou déjà affectée).
    final et = await db.getAll(
      'SELECT id, appareil_id FROM etiquettes_qr WHERE code = ? LIMIT 1',
      [code],
    );
    if (et.isNotEmpty) {
      final appareilId = et.first['appareil_id'] as String?;
      return ResolutionQr(
        cible: appareilId == null ? CibleQr.etiquetteLibre : CibleQr.appareil,
        code: code,
        etiquetteId: et.first['id'] as String?,
        appareilId: appareilId,
      );
    }

    // 2) Appareil portant ce QR (saisi à la main / étiquette pas encore lue).
    final ap = await db.getAll(
      'SELECT id FROM appareils WHERE qr_code = ? AND fusionne_vers IS NULL '
      'LIMIT 1',
      [code],
    );
    if (ap.isNotEmpty) {
      return ResolutionQr(
          cible: CibleQr.appareil, code: code, appareilId: ap.first['id'] as String?);
    }

    // 3) Produit par QR vente.
    final pq = await db.getAll(
      'SELECT id FROM produits WHERE qr_code = ? AND COALESCE(actif,1)=1 LIMIT 1',
      [code],
    );
    if (pq.isNotEmpty) {
      return ResolutionQr(
          cible: CibleQr.produit, code: code, produitId: pq.first['id'] as String?);
    }

    // 4) Repli : préfixe BEJ-P-<id> même si qr_code pas encore peuplé.
    if (code.startsWith('BEJ-P-')) {
      final pid = code.substring(6);
      final p = await db.getAll(
        'SELECT id FROM produits WHERE id = ? AND COALESCE(actif,1)=1 LIMIT 1',
        [pid],
      );
      if (p.isNotEmpty) {
        return ResolutionQr(cible: CibleQr.produit, code: code, produitId: pid);
      }
    }

    // 5) Repli legacy : code-barres brut.
    final pb = await db.getAll(
      'SELECT id FROM produits WHERE code_barres = ? AND COALESCE(actif,1)=1 '
      'LIMIT 1',
      [code],
    );
    if (pb.isNotEmpty) {
      return ResolutionQr(
          cible: CibleQr.produit, code: code, produitId: pb.first['id'] as String?);
    }
    return null;
  }

  /// Affecte un sticker à un appareil : étiquette → `utilise` + `appareils.qr_code`.
  /// Idempotent si le même sticker est re-scanné pour le même appareil ; lève si
  /// le sticker est déjà utilisé par un AUTRE appareil (évite un mauvais lien).
  Future<void> affecterAppareil({
    required String code,
    required String appareilId,
    required String magasinId,
  }) async {
    final c = code.trim();
    if (c.isEmpty) throw StateError('Code QR vide.');
    final now = DateTime.now().toUtc().toIso8601String();
    await db.writeTransaction((tx) async {
      final et = await tx.getAll(
        'SELECT statut, appareil_id FROM etiquettes_qr WHERE code = ? LIMIT 1',
        [c],
      );
      if (et.isEmpty) {
        throw StateError('Étiquette QR inconnue : $c');
      }
      final dejaLie = et.first['appareil_id'] as String?;
      if (dejaLie != null && dejaLie != appareilId) {
        throw StateError('Étiquette déjà affectée à un autre appareil.');
      }
      await tx.execute(
        "UPDATE etiquettes_qr SET statut='utilise', appareil_id=?, "
        'date_utilisation=?, magasin_id=COALESCE(magasin_id, ?) WHERE code=?',
        [appareilId, now, magasinId, c],
      );
      await tx.execute(
        'UPDATE appareils SET qr_code = ? WHERE id = ?',
        [c, appareilId],
      );
    });
  }

  /// Code QR déjà lié à un appareil (affichage en lecture seule), ou null.
  Future<String?> codeParAppareil(String appareilId) async {
    final rs = await db.getAll(
      'SELECT qr_code FROM appareils WHERE id = ? LIMIT 1',
      [appareilId],
    );
    if (rs.isEmpty) return null;
    final code = rs.first['qr_code'] as String?;
    return (code == null || code.isEmpty) ? null : code;
  }
}
