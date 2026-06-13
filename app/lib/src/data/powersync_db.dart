import 'package:powersync/powersync.dart';
import 'schema.dart';

/// Ouvre la base PowerSync locale (SQLite natif, ou WASM/OPFS sur le web).
///
/// Phase 0 : on N'APPELLE PAS `db.connect(...)` car il n'y a pas (encore) de
/// service PowerSync de streaming. La base fonctionne en local offline-first et
/// accumule les écritures dans sa file CRUD ; c'est notre `SyncService` qui
/// pousse cette file vers le backend (cf. sync_service.dart).
///
/// Pour passer en sync temps réel (Phase 1+), il suffira d'implémenter un
/// PowerSyncBackendConnector et d'appeler `db.connect(connector)` — le schéma
/// et les tables sont déjà prêts.
Future<PowerSyncDatabase> openDatabase() async {
  final db = PowerSyncDatabase(schema: schema, path: 'bej.sqlite');
  await db.initialize();
  return db;
}
