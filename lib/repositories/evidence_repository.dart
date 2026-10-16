/// Read access to stored evidence records, for verification and the chain
/// integrity screen.
library;

import 'dart:convert';

import '../database/app_database.dart';
import '../models/enums.dart';
import '../models/evidence_record.dart';
import '../models/location_fix.dart';

class EvidenceRepository {
  EvidenceRepository(this._database);

  final AppDatabase _database;

  Future<EvidenceRecord?> findByTestId(String testId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'evidence_records',
      columns: <String>['record_json'],
      where: 'test_id = ?',
      whereArgs: <Object?>[testId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _decode(rows.first['record_json']! as String);
  }

  /// Whole chain in sequence order. Loaded eagerly because verification is
  /// inherently sequential - each record's validity depends on its
  /// predecessor's stored hash.
  Future<List<EvidenceRecord>> loadChain() async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'evidence_records',
      columns: <String>['record_json'],
      orderBy: 'sequence_number ASC',
    );
    return rows
        .map((Map<String, Object?> r) => _decode(r['record_json']! as String))
        .toList(growable: false);
  }

  Future<int> count() async {
    final List<Map<String, Object?>> rows = await _database.db
        .rawQuery('SELECT COUNT(*) AS c FROM evidence_records');
    return (rows.first['c']! as num).toInt();
  }

  Future<String> headHash() async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery('''
      SELECT record_hash FROM evidence_records
      ORDER BY sequence_number DESC LIMIT 1
    ''');
    return rows.isEmpty
        ? EvidenceRecord.genesisHash
        : rows.first['record_hash']! as String;
  }

  /// Records a verification attempt in the audit-adjacent verification log.
  Future<void> recordVerification({
    required String verificationId,
    required String testId,
    required String? actorId,
    required String method,
    required bool recordHashValid,
    required bool linkValid,
    required bool signatureValid,
    required bool? imageHashValid,
    String? notes,
  }) async {
    await _database.db.insert('verification_events', <String, Object?>{
      'verification_id': verificationId,
      'test_id': testId,
      'verified_at_utc': DateTime.now().toUtc().toIso8601String(),
      'actor_id': actorId,
      'method': method,
      'record_hash_valid': recordHashValid ? 1 : 0,
      'link_valid': linkValid ? 1 : 0,
      'signature_valid': signatureValid ? 1 : 0,
      'image_hash_valid': imageHashValid == null ? null : (imageHashValid ? 1 : 0),
      'notes': notes,
    });
  }

  static EvidenceRecord _decode(String json) {
    final Map<String, Object?> m =
        jsonDecode(json) as Map<String, Object?>;
    return EvidenceRecord(
      testId: m['testId']! as String,
      officerId: m['officerId']! as String,
      operatorId: m['operatorId']! as String,
      sessionId: m['sessionId']! as String,
      role: OperatorRole.fromWire(m['role']! as String),
      deviceId: m['deviceId']! as String,
      deviceModel: m['deviceModel']! as String,
      osVersion: m['osVersion']! as String,
      appVersion: m['appVersion']! as String,
      kitId: m['kitId']! as String,
      kitProfileVersion: m['kitProfileVersion']! as String,
      createdAtLocalIso: m['createdAtLocal']! as String,
      createdAtUtcIso: m['createdAtUtc']! as String,
      deviceTimeZoneOffsetMinutes: (m['tzOffsetMinutes']! as num).toInt(),
      captureAtUtcIso: m['captureAtUtc']! as String,
      location: m['location'] == null
          ? null
          : LocationFix.fromJson(m['location']! as Map<String, Object?>),
      result: TestResult.fromWire(m['result']! as String),
      reliabilityStatus:
          ReliabilityStatus.fromWire(m['reliabilityStatus']! as String),
      anomalyCodes: ((m['anomalyCodes'] ?? const <Object?>[]) as List<Object?>)
          .map((Object? c) => c! as String)
          .toList(growable: false),
      imageHash: m['imageHash']! as String,
      previousRecordHash: m['previousRecordHash']! as String,
      recordHash: m['recordHash']! as String,
      analysisDigest: m['analysisDigest']! as String,
      modelId: m['modelId'] as String?,
      modelVersion: m['modelVersion'] as String?,
      calibrationVersion: m['calibrationVersion']! as String,
      algorithmVersion: m['algorithmVersion']! as String,
      featureSchemaVersion: m['featureSchemaVersion']! as String,
      canonicalFormatVersion: m['canonicalFormatVersion']! as String,
      signature: m['signature']! as String,
      publicKeyId: m['publicKeyId']! as String,
      publicKeyBase64: m['publicKey']! as String,
      keyVersion: (m['keyVersion']! as num).toInt(),
      signatureScheme: m['signatureScheme']! as String,
      sequenceNumber: (m['sequenceNumber']! as num).toInt(),
    );
  }
}
