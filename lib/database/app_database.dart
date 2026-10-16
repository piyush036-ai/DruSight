/// SQLite connection management and migration.
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import 'schema.dart';

class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static AppDatabase? _instance;

  static Future<AppDatabase> open({String? overridePath}) async {
    final AppDatabase? existing = _instance;
    if (existing != null) return existing;

    final String path = overridePath ??
        p.join(await getDatabasesPath(), AppConfig.databaseName);

    final Database database = await openDatabase(
      path,
      version: Schema.version,
      onConfigure: (Database d) async {
        // Referential integrity is off by default in SQLite.
        await d.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (Database d, int version) async {
        final Batch batch = d.batch();
        for (final String statement in Schema.createStatements) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);
      },
      onUpgrade: (Database d, int oldVersion, int newVersion) async {
        final List<String> statements =
            Schema.migrationsFrom(oldVersion, newVersion);
        final Batch batch = d.batch();
        for (final String statement in statements) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);
      },
    );

    final AppDatabase wrapper = AppDatabase._(database);
    _instance = wrapper;
    return wrapper;
  }

  static Future<void> closeInstance() async {
    await _instance?.db.close();
    _instance = null;
  }

  /// Runs [action] inside a transaction. Used for the evidence write path so
  /// a test, its images, its analysis and its evidence record are committed
  /// together or not at all.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) =>
      db.transaction<T>(action);
}
