/// Append-only audit trail (master spec section 49).
///
/// Audit events are themselves hash-chained, so deleting or editing one is
/// detectable. Events are never updated or removed by application code.
library;

import 'dart:convert';
import 'dart:math';

import '../database/app_database.dart';
import '../config/versions.dart';
import '../security/canonical_json.dart';
import '../security/hashing.dart';

class AuditEvent {
  const AuditEvent({
    required this.eventId,
    required this.occurredAtUtc,
    required this.actorId,
    required this.action,
    required this.subjectType,
    required this.subjectId,
    required this.detail,
    required this.previousEventHash,
    required this.eventHash,
  });

  final String eventId;
  final DateTime occurredAtUtc;
  final String? actorId;
  final String action;
  final String? subjectType;
  final String? subjectId;
  final Map<String, Object?> detail;
  final String previousEventHash;
  final String eventHash;
}

/// Actions worth auditing. A closed set keeps the log queryable.
class AuditAction {
  const AuditAction._();

  static const String authenticated = 'AUTH_SUCCESS';
  static const String authenticationFailed = 'AUTH_FAILURE';
  static const String signedOut = 'AUTH_SIGN_OUT';
  static const String testStarted = 'TEST_STARTED';
  static const String imageCaptured = 'IMAGE_CAPTURED';
  static const String imageRejected = 'IMAGE_REJECTED';
  static const String analysisStarted = 'ANALYSIS_STARTED';
  static const String resultGenerated = 'RESULT_GENERATED';
  static const String evidenceCreated = 'EVIDENCE_RECORD_CREATED';
  static const String signatureGenerated = 'SIGNATURE_GENERATED';
  static const String verificationPerformed = 'VERIFICATION_PERFORMED';
  static const String reviewPerformed = 'REVIEW_PERFORMED';
  static const String exportPerformed = 'EXPORT_PERFORMED';
  static const String demoTamperSimulated = 'DEMO_TAMPER_SIMULATED';
}

class AuditRepository {
  AuditRepository(this._database);

  final AppDatabase _database;

  Future<AuditEvent> append({
    required String action,
    String? actorId,
    String? subjectType,
    String? subjectId,
    Map<String, Object?> detail = const <String, Object?>{},
  }) async {
    final String previousHash = await _headHash();
    final DateTime now = DateTime.now().toUtc();
    final String eventId = _randomId();

    final Map<String, Object?> core = <String, Object?>{
      'eventId': eventId,
      'occurredAtUtc': now.toIso8601String(),
      'actorId': actorId,
      'action': action,
      'subjectType': subjectType,
      'subjectId': subjectId,
      'detail': detail,
      'previousEventHash': previousHash,
    };
    final String eventHash =
        Hashing.sha256Hex(CanonicalJson.encodeToBytes(core));

    await _database.db.insert('audit_events', <String, Object?>{
      'event_id': eventId,
      'occurred_at_utc': now.toIso8601String(),
      'actor_id': actorId,
      'action': action,
      'subject_type': subjectType,
      'subject_id': subjectId,
      'detail_json': jsonEncode(detail),
      'previous_event_hash': previousHash,
      'event_hash': eventHash,
    });

    return AuditEvent(
      eventId: eventId,
      occurredAtUtc: now,
      actorId: actorId,
      action: action,
      subjectType: subjectType,
      subjectId: subjectId,
      detail: detail,
      previousEventHash: previousHash,
      eventHash: eventHash,
    );
  }

  Future<List<AuditEvent>> recent({int limit = 200}) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'audit_events',
      orderBy: 'occurred_at_utc DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  /// Verifies the audit chain end to end.
  Future<bool> verifyChain() async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'audit_events',
      orderBy: 'occurred_at_utc ASC, event_id ASC',
    );

    String expectedPrevious = Versions.chainGenesis;
    for (final Map<String, Object?> row in rows) {
      final AuditEvent e = _fromRow(row);
      if (!Hashing.constantTimeEquals(e.previousEventHash, expectedPrevious)) {
        return false;
      }
      final String recomputed = Hashing.sha256Hex(
        CanonicalJson.encodeToBytes(<String, Object?>{
          'eventId': e.eventId,
          'occurredAtUtc': e.occurredAtUtc.toIso8601String(),
          'actorId': e.actorId,
          'action': e.action,
          'subjectType': e.subjectType,
          'subjectId': e.subjectId,
          'detail': e.detail,
          'previousEventHash': e.previousEventHash,
        }),
      );
      if (!Hashing.constantTimeEquals(recomputed, e.eventHash)) return false;
      expectedPrevious = e.eventHash;
    }
    return true;
  }

  Future<String> _headHash() async {
    final List<Map<String, Object?>> rows = await _database.db.rawQuery('''
      SELECT event_hash FROM audit_events
      ORDER BY occurred_at_utc DESC, event_id DESC LIMIT 1
    ''');
    return rows.isEmpty
        ? Versions.chainGenesis
        : rows.first['event_hash']! as String;
  }

  static AuditEvent _fromRow(Map<String, Object?> row) => AuditEvent(
        eventId: row['event_id']! as String,
        occurredAtUtc: DateTime.parse(row['occurred_at_utc']! as String),
        actorId: row['actor_id'] as String?,
        action: row['action']! as String,
        subjectType: row['subject_type'] as String?,
        subjectId: row['subject_id'] as String?,
        detail: row['detail_json'] == null
            ? const <String, Object?>{}
            : jsonDecode(row['detail_json']! as String)
                as Map<String, Object?>,
        previousEventHash: row['previous_event_hash']! as String,
        eventHash: row['event_hash']! as String,
      );

  static String _randomId() {
    final Random rng = Random.secure();
    return List<int>.generate(16, (_) => rng.nextInt(256))
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
