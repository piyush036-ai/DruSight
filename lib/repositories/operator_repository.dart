/// Operator persistence. All queries use bound parameters.
library;

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/enums.dart';
import '../models/operator.dart';

class OperatorRepository {
  OperatorRepository(this._database);

  final AppDatabase _database;

  Future<void> insert(OperatorAccount account, int iterations) async {
    await _database.db.insert(
      'operators',
      <String, Object?>{
        'operator_id': account.operatorId,
        'officer_id': account.officerId,
        'display_name': account.displayName,
        'role': account.role.wireName,
        'passphrase_hash': account.passphraseHash,
        'passphrase_salt': account.passphraseSalt,
        'pbkdf2_iterations': iterations,
        'created_at_utc': account.createdAtUtc.toIso8601String(),
        'active': account.active ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<OperatorAccount?> findByOfficerId(String officerId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'operators',
      where: 'officer_id = ?',
      whereArgs: <Object?>[officerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<OperatorAccount?> findById(String operatorId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'operators',
      where: 'operator_id = ?',
      whereArgs: <Object?>[operatorId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<int?> iterationsFor(String operatorId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'operators',
      columns: <String>['pbkdf2_iterations'],
      where: 'operator_id = ?',
      whereArgs: <Object?>[operatorId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['pbkdf2_iterations'] as int?;
  }

  /// Deactivates all operator accounts (sets active = 0) instead of deleting
  /// them. This preserves referential integrity with the tests table
  /// (FOREIGN KEY operator_id → operators) while blocking every existing
  /// account from logging in. The user can then re-register a fresh account
  /// as if it were first run.
  Future<void> deactivateAll() async {
    await _database.db
        .execute('UPDATE operators SET active = 0');
  }

  /// Returns the number of **active** operator accounts. Zero means first-run
  /// (or after a passphrase reset), which triggers the registration form.
  Future<int> count() async {
    final List<Map<String, Object?>> rows = await _database.db
        .rawQuery('SELECT COUNT(*) AS c FROM operators WHERE active = 1');
    return (rows.first['c']! as num).toInt();
  }

  Future<List<OperatorAccount>> listAll() async {
    final List<Map<String, Object?>> rows =
        await _database.db.query('operators', orderBy: 'display_name ASC');
    return rows.map(_fromRow).toList(growable: false);
  }

  static OperatorAccount _fromRow(Map<String, Object?> row) => OperatorAccount(
        operatorId: row['operator_id']! as String,
        officerId: row['officer_id']! as String,
        displayName: row['display_name']! as String,
        role: OperatorRole.fromWire(row['role']! as String),
        passphraseHash: row['passphrase_hash']! as String,
        passphraseSalt: row['passphrase_salt']! as String,
        createdAtUtc: DateTime.parse(row['created_at_utc']! as String),
        active: (row['active']! as int) == 1,
      );
}
