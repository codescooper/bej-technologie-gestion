import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

/// Backend de synchronisation BEJ — Phase 0.
///
/// Reçoit les lots d'opérations CRUD poussés par l'app (file PowerSync) et les
/// applique au PostgreSQL serveur. C'est le « côté serveur » du critère Phase 0.
///
/// Endpoints :
///   GET  /health   -> sonde de disponibilité (indicateur online/offline app)
///   POST /upload   -> applique un lot { batch: [ {op, table, id, data}, ... ] }
///
/// Connexion Postgres (dev local, voir backend/scripts/db.ps1).
const _pgEndpoint = (
  host: 'localhost',
  port: 5432,
  database: 'bej',
  username: 'postgres',
);

late Connection _db;

/// table -> { colonne -> type de cast Postgres }, chargé au démarrage.
final Map<String, Map<String, String>> _schemaCache = {};

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept',
};

Middleware _cors() => (handler) => (req) async {
      if (req.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final res = await handler(req);
      return res.change(headers: {...res.headers, ..._corsHeaders});
    };

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

Future<Response> _upload(Request req) async {
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
        //          par la dédup, ex. vente/réparation d'un client/caisse en
        //          doublon). Dans les deux cas on journalise pour le responsable
        //          (§9) et on POURSUIT : la synchro n'est JAMAIS bloquée. La
        //          réconciliation (fusion + réaffectation) est un traitement
        //          serveur de consolidation à venir.
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
          rethrow; // erreur réelle -> échec du batch
        }
      }
    }
    return Response.ok(
      jsonEncode({'applied': applied, 'skipped': skipped}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e, st) {
    stderr.writeln('upload error: $e\n$st');
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

/// Variante de _applyOp opérant sur une session de transaction (TxSession).
Future<void> _applyOpOnSession(Session s, Map<String, dynamic> op) async {
  final table = op['table'] as String;
  final id = op['id'] as String;
  final kind = (op['op'] as String).toLowerCase();
  final data = (op['data'] as Map?)?.cast<String, dynamic>() ?? {};
  final cols = _schemaCache[table];
  if (cols == null) throw Exception('Table inconnue: $table');

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
  // Mot de passe Postgres via l'environnement (PGPASSWORD ; cf. les scripts et
  // backend/scripts/local.env.ps1, non versionné). Défaut conventionnel sinon.
  final pgPassword = Platform.environment['PGPASSWORD'] ?? 'postgres';
  _db = await Connection.open(
    Endpoint(
      host: _pgEndpoint.host,
      port: _pgEndpoint.port,
      database: _pgEndpoint.database,
      username: _pgEndpoint.username,
      password: pgPassword,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  await _loadSchema();
  stdout.writeln('Schéma chargé : ${_schemaCache.length} tables.');

  final router = Router()
    ..get('/health', (Request r) => Response.ok(
          jsonEncode({'status': 'ok', 'tables': _schemaCache.length}),
          headers: {'Content-Type': 'application/json'},
        ))
    ..post('/upload', _upload);

  final handler =
      const Pipeline().addMiddleware(_cors()).addHandler(router.call);

  final server = await io.serve(handler, 'localhost', 8080);
  stdout.writeln('Backend BEJ à l\'écoute sur http://${server.address.host}:${server.port}');
}
