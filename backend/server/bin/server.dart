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

late Connection _db;

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
    var skipped = 0;
    // Chaque opération est appliquée en AUTO-COMMIT (sa propre micro-transaction).
    // Évite le piège du savepoint dans une transaction postgres marquée échouée :
    // un conflit n'« abîme » plus la transaction globale. Les upserts
    // ON CONFLICT (id) rendent toute reprise idempotente.
    for (final op in batch) {
      try {
        await _applyOpOnSession(_db, op);
        applied++;
      } catch (e) {
        final msg = e.toString();
        // 23505 = conflit de clé naturelle (doublon offline, §2.6).
        // 23503 = violation de clé étrangère (enfant dont le parent a été ignoré
        //          par la dédup). Dans les deux cas on journalise et on POURSUIT.
        final dedup = msg.contains('23505');
        final orphelin = msg.contains('23503');
        if (dedup || orphelin) {
          await _db.execute(
            Sql.named(
                'INSERT INTO journal_audit(action, entite, entite_id, details) '
                'VALUES(@a, @t, @eid::uuid, @d::jsonb)'),
            parameters: {
              'a': dedup ? 'conflit_sync_dedup' : 'conflit_sync_orphelin',
              't': op['table'],
              'eid': op['id'],
              'd': jsonEncode({'op': op['op'], 'erreur': msg}),
            },
          );
          skipped++;
        } else {
          rethrow;
        }
      }
    }
    return Response.ok(
      jsonEncode({'applied': applied, 'skipped': skipped}),
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

Future<void> main() async {
  // ─── Connexion PostgreSQL ────────────────────────────────────────────────
  final pgPassword = _envOpt('PGPASSWORD');
  if (pgPassword == null) {
    stderr.writeln(
        '[WARN] PGPASSWORD non définie — connexion sans mot de passe (dev uniquement).');
  }

  _db = await Connection.open(
    Endpoint(
      host: _env('DB_HOST', 'localhost'),
      port: int.tryParse(_env('DB_PORT', '5432')) ?? 5432,
      database: _env('DB_NAME', 'bej'),
      username: _env('DB_USER', 'postgres'),
      password: pgPassword ?? '',
    ),
    settings: const ConnectionSettings(
      sslMode: SslMode.disable,
      queryTimeout: Duration(seconds: 30),
    ),
  );
  await _loadSchema();
  stdout.writeln('[INFO] Schéma chargé : ${_schemaCache.length} tables.');

  // ─── Routeur ─────────────────────────────────────────────────────────────
  final router = Router()
    ..get('/health', (Request r) => Response.ok(
          jsonEncode({'status': 'ok', 'tables': _schemaCache.length}),
          headers: {'Content-Type': 'application/json'},
        ))
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
