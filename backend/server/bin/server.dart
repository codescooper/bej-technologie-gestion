import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

/// Backend de synchronisation BEJ.
///
/// Endpoints :
///   GET  /health   → sonde de disponibilité
///   POST /upload   → applique un lot { batch: [ {op, table, id, data}, … ] }
///
/// Configuration (variables d'environnement) :
///   PGPASSWORD        Mot de passe PostgreSQL     — obligatoire en prod
///   DB_HOST           Hôte PostgreSQL              (défaut : localhost)
///   DB_PORT           Port PostgreSQL               (défaut : 5432)
///   DB_NAME           Nom de la base               (défaut : bej)
///   DB_USER           Utilisateur PostgreSQL        (défaut : postgres)
///   HOST              Adresse d'écoute du serveur  (défaut : localhost)
///   PORT              Port d'écoute du serveur     (défaut : 8080)
///   BEJ_CORS_ORIGIN   Origine CORS autorisée       (défaut : http://localhost:5000)
///   BEJ_UPLOAD_TOKEN  Token Bearer pour /upload    (absent → pas d'auth, mode dev)

late Pool _db;

/// table -> { colonne -> type de cast Postgres }, chargé au démarrage.
final Map<String, Map<String, String>> _schemaCache = {};

// ─── Helpers configuration ────────────────────────────────────────────────────

/// Lit une variable d'environnement ; retourne [fallback] si absente ou vide.
String _env(String key, String fallback) {
  final v = Platform.environment[key];
  return (v != null && v.isNotEmpty) ? v : fallback;
}

/// Retourne la valeur de la variable ou null si absente/vide.
String? _envOpt(String key) {
  final v = Platform.environment[key];
  return (v != null && v.isNotEmpty) ? v : null;
}

// ─── Middlewares ──────────────────────────────────────────────────────────────

/// CORS restreint à l'origine déclarée (BEJ_CORS_ORIGIN).
Middleware _cors() => (handler) => (req) async {
      final origin = _env('BEJ_CORS_ORIGIN', 'http://localhost:5000');
      final corsH = {
        'Access-Control-Allow-Origin': origin,
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers':
            'Origin, Content-Type, Accept, Authorization',
      };
      if (req.method == 'OPTIONS') return Response.ok('', headers: corsH);
      final res = await handler(req);
      return res.change(headers: {...res.headers, ...corsH});
    };

/// Headers de sécurité HTTP de base (X-Content-Type-Options, X-Frame-Options…).
Middleware _securityHeaders() => (handler) => (req) async {
      final res = await handler(req);
      return res.change(headers: {
        ...res.headers,
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY',
        'X-XSS-Protection': '1; mode=block',
      });
    };

// ─── Helpers SQL ──────────────────────────────────────────────────────────────

/// Mappe le type natif Postgres (udt_name) vers un type de cast textuel.
String _castType(String udt) {
  switch (udt) {
    case 'uuid':
      return 'uuid';
    case 'timestamptz':
      return 'timestamptz';
    case 'timestamp':
      return 'timestamp';
    case 'date':
      return 'date';
    case 'numeric':
      return 'numeric';
    case 'int2':
    case 'int4':
    case 'int8':
      return 'int8';
    case 'float4':
    case 'float8':
      return 'float8';
    case 'bool':
      return 'boolean';
    case 'jsonb':
      return 'jsonb';
    case 'json':
      return 'json';
    default:
      return 'text';
  }
}

Future<void> _loadSchema() async {
  final rows = await _db.execute(
    "SELECT table_name, column_name, udt_name "
    "FROM information_schema.columns "
    "WHERE table_schema = 'public' ORDER BY table_name",
  );
  for (final r in rows) {
    final t = r[0] as String;
    final c = r[1] as String;
    final udt = r[2] as String;
    (_schemaCache[t] ??= {})[c] = _castType(udt);
  }
}

/// Charge le schéma en ré-essayant : PostgreSQL peut démarrer lentement
/// (recovery ~30 s après un crash) — on attend plutôt que d'abandonner.
Future<void> _loadSchemaAvecReessais({int maxTentatives = 15}) async {
  for (var tentative = 1;; tentative++) {
    try {
      await _loadSchema();
      return;
    } catch (e) {
      if (tentative >= maxTentatives) {
        stderr.writeln(
            '[ERROR] Schéma illisible après $maxTentatives tentatives : $e');
        rethrow;
      }
      stderr.writeln(
          '[WARN] PostgreSQL indisponible (tentative $tentative/$maxTentatives) — nouvel essai dans 3 s…');
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }
}

/// Convertit une valeur JSON en représentation texte acceptée par le cast SQL.
String _stringify(Object value) {
  if (value is Map || value is List) return jsonEncode(value);
  if (value is bool) return value ? 'true' : 'false';
  return value.toString();
}

// ─── Handlers ─────────────────────────────────────────────────────────────────

Future<Response> _upload(Request req) async {
  // Auth par token Bearer — activée uniquement si BEJ_UPLOAD_TOKEN est défini.
  final token = _envOpt('BEJ_UPLOAD_TOKEN');
  if (token != null) {
    final auth = req.headers['authorization'] ?? '';
    if (auth != 'Bearer $token') {
      return Response.forbidden(
        jsonEncode({'error': 'Non autorisé'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  try {
    final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
    final batch = (body['batch'] as List).cast<Map<String, dynamic>>();
    var applied = 0;
    var skipped = 0; // conflits bénins attendus (doublon/orphelin de la dédup)
    var failed = 0; // rejets réels (CHECK/cast/bug) — mis en quarantaine, à investiguer
    // Chaque opération est appliquée en AUTO-COMMIT (sa propre micro-transaction)
    // sur le pool. AUCUN échec d'op ne doit figer le lot : sinon le client ne
    // valide pas sa transaction CRUD et PowerSync la rejoue en boucle → toute la
    // file de sync se bloque en silence (l'appli croit être « hors ligne »).
    // On MET DONC TOUTE ERREUR EN QUARANTAINE (journalisée) et on POURSUIT.
    // Les upserts ON CONFLICT (id) rendent toute reprise idempotente.
    for (final op in batch) {
      try {
        await _applyOpOnSession(_db, op);
        applied++;
      } catch (e) {
        final msg = e.toString();
        // 23505 = doublon de clé naturelle (offline, §2.6) ; 23503 = orphelin FK.
        // Ces deux-là sont des conflits de convergence ATTENDUS (bénins).
        if (msg.contains('23505') || msg.contains('23503')) {
          await _quarantaine(
              msg.contains('23505')
                  ? 'conflit_sync_dedup'
                  : 'conflit_sync_orphelin',
              op,
              msg);
          skipped++;
        } else {
          // Rejet réel (CHECK 23514, NOT NULL 23502, cast 22P02, table inconnue…).
          await _quarantaine('rejet_sync', op, msg);
          failed++;
          stderr.writeln(
              '[WARN] op rejetée (quarantaine) : ${op['op']} ${op['table']}/${op['id']} — $msg');
        }
      }
    }
    return Response.ok(
      jsonEncode({'applied': applied, 'skipped': skipped, 'failed': failed}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, st) {
    stderr.writeln('[ERROR] upload: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Erreur interne du serveur'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

/// Journalise une opération rejetée SANS jamais échouer elle-même : `entite_id`
/// est laissé NULL (l'id peut ne pas être un UUID valide selon l'erreur), et
/// toute erreur de journalisation est avalée — une quarantaine ne doit jamais
/// re-déclencher le blocage qu'elle est censée éviter.
Future<void> _quarantaine(
    String action, Map<String, dynamic> op, String msg) async {
  try {
    await _db.execute(
      Sql.named('INSERT INTO journal_audit(action, entite, details) '
          'VALUES(@a, @t, @d::jsonb)'),
      parameters: {
        'a': action,
        't': op['table'],
        'd': jsonEncode({'id': op['id'], 'op': op['op'], 'erreur': msg}),
      },
    );
  } catch (e2) {
    stderr.writeln('[WARN] journal quarantaine échoué ($action) : $e2');
  }
}

/// Applique une opération CRUD sur la session fournie.
Future<void> _applyOpOnSession(Session s, Map<String, dynamic> op) async {
  final table = op['table'] as String;
  final id = op['id'] as String;
  final kind = (op['op'] as String).toLowerCase();
  final data = (op['data'] as Map?)?.cast<String, dynamic>() ?? {};
  final cols = _schemaCache[table];
  if (cols == null) throw Exception('Table inconnue');

  if (kind == 'delete') {
    await s.execute(Sql.named('DELETE FROM "$table" WHERE id = @id::uuid'),
        parameters: {'id': id});
    return;
  }

  final payload = <String, dynamic>{'id': id, ...data};
  final entries = payload.entries.where((e) => cols.containsKey(e.key)).toList();
  final colNames = <String>[];
  final valueExprs = <String>[];
  final params = <String, dynamic>{};
  var i = 0;
  for (final e in entries) {
    colNames.add('"${e.key}"');
    if (e.value == null) {
      valueExprs.add('NULL');
    } else {
      valueExprs.add('@p$i::${cols[e.key]}');
      params['p$i'] = _stringify(e.value as Object);
      i++;
    }
  }

  if (kind == 'put') {
    final updates = entries
        .where((e) => e.key != 'id')
        .map((e) => '"${e.key}" = EXCLUDED."${e.key}"')
        .join(', ');
    final conflict = updates.isEmpty ? ' DO NOTHING' : ' DO UPDATE SET $updates';
    final sql = 'INSERT INTO "$table" (${colNames.join(', ')}) '
        'VALUES (${valueExprs.join(', ')}) ON CONFLICT (id)$conflict';
    await s.execute(Sql.named(sql), parameters: params);
  } else {
    final sets = <String>[];
    final patchParams = <String, dynamic>{};
    var j = 0;
    for (final e in entries.where((e) => e.key != 'id')) {
      if (e.value == null) {
        sets.add('"${e.key}" = NULL');
      } else {
        sets.add('"${e.key}" = @q$j::${cols[e.key]}');
        patchParams['q$j'] = _stringify(e.value as Object);
        j++;
      }
    }
    if (sets.isEmpty) return;
    patchParams['wid'] = id;
    await s.execute(
        Sql.named('UPDATE "$table" SET ${sets.join(', ')} WHERE id = @wid::uuid'),
        parameters: patchParams);
  }
}

/// Sonde de disponibilité : teste RÉELLEMENT la base (SELECT 1). Renvoie 503 si
/// PostgreSQL est injoignable, pour que le client bascule en offline au lieu de
/// croire le backend sain alors qu'aucune écriture n'est possible.
Future<Response> _health(Request req) async {
  try {
    await _db.execute('SELECT 1').timeout(const Duration(seconds: 3));
    return Response.ok(
      jsonEncode({'status': 'ok', 'tables': _schemaCache.length}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (_) {
    return Response(
      503,
      body: jsonEncode({'status': 'db_indisponible'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<void> main() async {
  // ─── Connexion PostgreSQL ────────────────────────────────────────────────
  final pgPassword = _envOpt('PGPASSWORD');
  if (pgPassword == null) {
    stderr.writeln(
        '[WARN] PGPASSWORD non définie — connexion sans mot de passe (dev uniquement).');
  }

  // Pool plutôt qu'une connexion unique : gère la concurrence ET rouvre
  // automatiquement une connexion après une coupure PostgreSQL (le cluster
  // portable de la boutique retombe/redémarre — cf. risques connus).
  _db = Pool.withEndpoints(
    [
      Endpoint(
        host: _env('DB_HOST', 'localhost'),
        port: int.tryParse(_env('DB_PORT', '5432')) ?? 5432,
        database: _env('DB_NAME', 'bej'),
        username: _env('DB_USER', 'postgres'),
        password: pgPassword ?? '',
      ),
    ],
    settings: const PoolSettings(
      sslMode: SslMode.disable,
      queryTimeout: Duration(seconds: 30),
      connectTimeout: Duration(seconds: 10),
      maxConnectionCount: 8,
    ),
  );

  // Chargement du schéma avec ré-essais (PostgreSQL peut démarrer lentement).
  try {
    await _loadSchemaAvecReessais();
  } catch (_) {
    stderr.writeln(
        '[FATAL] PostgreSQL injoignable au démarrage — backend arrêté. '
        'Vérifiez que le cluster est lancé (restart-stack.ps1).');
    exit(1);
  }
  stdout.writeln('[INFO] Schéma chargé : ${_schemaCache.length} tables.');

  // ─── Routeur ─────────────────────────────────────────────────────────────
  final router = Router()
    ..get('/health', _health)
    ..post('/upload', _upload);

  final handler = const Pipeline()
      .addMiddleware(_cors())
      .addMiddleware(_securityHeaders())
      .addHandler(router.call);

  final host = _env('HOST', 'localhost');
  final port = int.tryParse(_env('PORT', '8080')) ?? 8080;
  final server = await io.serve(handler, host, port);
  stdout.writeln(
      '[INFO] Backend BEJ sur http://${server.address.host}:${server.port}');
  stdout
      .writeln('[INFO] CORS origin : ${_env('BEJ_CORS_ORIGIN', 'http://localhost:5000')}');
  stdout.writeln(
      '[INFO] Auth /upload : ${_envOpt('BEJ_UPLOAD_TOKEN') != null ? 'activée (token Bearer)' : 'désactivée (dev)'}');
}
