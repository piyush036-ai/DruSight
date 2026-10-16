/// Persistence for tests, images, analyses, anomalies and evidence records,
/// plus the mandatory searchable history (master spec sections 36, 46).
///
/// The write path runs in a single transaction and allocates the chain slot
/// inside it, so two tests completing at once cannot take the same sequence
/// number or branch the chain.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/analysis_result.dart';
import '../models/anomaly.dart';
import '../models/enums.dart';
import '../models/evidence_record.dart';
import '../models/reaction_series.dart';

/// A stored image reference.
class StoredImage {
  const StoredImage({
    required this.imageId,
    required this.role,
    required this.filePath,
    required this.imageHash,
    required this.widthPx,
    required this.heightPx,
    required this.byteSize,
    required this.capturedAtUtc,
    required this.isOriginal,
    this.offsetSeconds,
    this.derivedFrom,
  });

  final String imageId;

  /// "ORIGINAL", "SEQUENCE", "THUMBNAIL", "ANNOTATED".
  final String role;
  final String filePath;
  final String imageHash;
  final int widthPx;
  final int heightPx;
  final int byteSize;
  final DateTime capturedAtUtc;

  /// True only for the untouched capture. Derived artefacts never overwrite it
  /// (master spec section 31).
  final bool isOriginal;

  final int? offsetSeconds;
  final String? derivedFrom;
}

/// One row of the history list.
class TestSummary {
  const TestSummary({
    required this.testId,
    required this.startedAtUtc,
    required this.completedAtUtc,
    required this.officerId,
    required this.operatorId,
    required this.kitId,
    required this.result,
    required this.reliabilityStatus,
    required this.anomalyCount,
    required this.hasLocation,
  });

  final String testId;
  final DateTime startedAtUtc;
  final DateTime? completedAtUtc;
  final String officerId;
  final String operatorId;
  final String kitId;
  final TestResult? result;
  final ReliabilityStatus? reliabilityStatus;
  final int anomalyCount;
  final bool hasLocation;
}

/// Filter set for the history screen (master spec section 36).
class HistoryQuery {
  const HistoryQuery({
    this.testIdContains,
    this.from,
    this.to,
    this.operatorId,
    this.officerId,
    this.kitId,
    this.result,
    this.reliabilityStatus,
    this.anomalyCode,
    this.deviceId,
    this.sort = HistorySort.newest,
    this.limit = 100,
    this.offset = 0,
  });

  final String? testIdContains;
  final DateTime? from;
  final DateTime? to;
  final String? operatorId;
  final String? officerId;
  final String? kitId;
  final TestResult? result;
  final ReliabilityStatus? reliabilityStatus;
  final AnomalyCode? anomalyCode;
  final String? deviceId;
  final HistorySort sort;
  final int limit;
  final int offset;
}

enum HistorySort {
  newest('t.started_at_utc DESC'),
  oldest('t.started_at_utc ASC'),
  byResult('t.result ASC, t.started_at_utc DESC'),
  byAnomaly('anomaly_count DESC, t.started_at_utc DESC'),
  byOperator('t.officer_id ASC, t.started_at_utc DESC');

  const HistorySort(this.orderBy);

  /// Fixed SQL fragment. Never built from user input - this is why the enum
  /// exists rather than a free-text sort parameter.
  final String orderBy;
}

class TestRepository {
  TestRepository(this._database);

  final AppDatabase _database;

  /// Persists a completed test atomically and returns the signed record.
  ///
  /// [buildRecord] receives the chain position allocated inside the
  /// transaction and must produce the signed record for it.
  Future<EvidenceRecord> commitTest({
    required String testId,
    required String operatorId,
    required String officerId,
    required String sessionId,
    required String deviceId,
    required String kitId,
    required String kitProfileVersion,
    required DateTime startedAtUtc,
    required AnalysisResult analysis,
    required List<StoredImage> images,
    required List<ReactionSample> reactionSamples,
    required double? latitude,
    required double? longitude,
    required double? locationAccuracy,
    required DateTime? locationTimeUtc,
    required Future<EvidenceRecord> Function(
      String previousRecordHash,
      int sequenceNumber,
    ) buildRecord,
  }) async {
    return _database.transaction<EvidenceRecord>((Transaction txn) async {
      // Allocate the chain slot inside the transaction.
      final List<Map<String, Object?>> head = await txn.rawQuery('''
        SELECT record_hash, sequence_number
        FROM evidence_records
        ORDER BY sequence_number DESC
        LIMIT 1
      ''');
      final String previousHash = head.isEmpty
          ? EvidenceRecord.genesisHash
          : head.first['record_hash']! as String;
      final int sequence = head.isEmpty
          ? 0
          : (head.first['sequence_number']! as num).toInt() + 1;

      final EvidenceRecord record = await buildRecord(previousHash, sequence);

      final String nowUtc = DateTime.now().toUtc().toIso8601String();

      await txn.insert('tests', <String, Object?>{
        'test_id': testId,
        'operator_id': operatorId,
        'officer_id': officerId,
        'session_id': sessionId,
        'device_id': deviceId,
        'kit_id': kitId,
        'kit_profile_version': kitProfileVersion,
        'started_at_utc': startedAtUtc.toUtc().toIso8601String(),
        'completed_at_utc': nowUtc,
        'result': analysis.result.wireName,
        'reliability_status': analysis.reliabilityStatus.wireName,
        'latitude': latitude,
        'longitude': longitude,
        'location_accuracy': locationAccuracy,
        'location_time_utc': locationTimeUtc?.toUtc().toIso8601String(),
      });

      for (final StoredImage image in images) {
        await txn.insert('test_images', <String, Object?>{
          'image_id': image.imageId,
          'test_id': testId,
          'role': image.role,
          'offset_seconds': image.offsetSeconds,
          'file_path': image.filePath,
          'image_hash': image.imageHash,
          'width_px': image.widthPx,
          'height_px': image.heightPx,
          'byte_size': image.byteSize,
          'captured_at_utc': image.capturedAtUtc.toUtc().toIso8601String(),
          'is_original': image.isOriginal ? 1 : 0,
          'derived_from': image.derivedFrom,
        });
      }

      await txn.insert('analysis_results', <String, Object?>{
        'test_id': testId,
        'result': analysis.result.wireName,
        'reliability_status': analysis.reliabilityStatus.wireName,
        'algorithm_version': analysis.algorithmVersion,
        'calibration_version': analysis.calibration.calibrationVersion,
        'feature_schema_version': record.featureSchemaVersion,
        'model_id': analysis.classifierOutput.modelId,
        'model_version': analysis.classifierOutput.modelVersion,
        'analysis_json': jsonEncode(analysis.toJson()),
        'analysis_digest': record.analysisDigest,
        'created_at_utc': nowUtc,
      });

      for (int i = 0; i < reactionSamples.length; i++) {
        final ReactionSample s = reactionSamples[i];
        await txn.insert('reaction_measurements', <String, Object?>{
          'measurement_id': '$testId-r$i',
          'test_id': testId,
          'offset_seconds': s.offsetSeconds,
          'captured_at_utc': s.capturedAtUtc.toUtc().toIso8601String(),
          'lab_l': s.calibratedLab.l,
          'lab_a': s.calibratedLab.a,
          'lab_b': s.calibratedLab.b,
          'hsv_h': s.calibratedHsv.h,
          'hsv_s': s.calibratedHsv.s,
          'hsv_v': s.calibratedHsv.v,
          'image_hash': s.imageHash,
        });
      }

      for (int i = 0; i < analysis.anomalies.length; i++) {
        final Anomaly a = analysis.anomalies[i];
        await txn.insert('anomalies', <String, Object?>{
          'anomaly_id': '$testId-a$i',
          'test_id': testId,
          'code': a.code.wireName,
          'severity': a.severity.wireName,
          'detail': a.detail,
          'measured_value': a.measuredValue,
          'threshold_value': a.thresholdValue,
          'created_at_utc': nowUtc,
        });
      }

      await txn.insert('evidence_records', <String, Object?>{
        'test_id': testId,
        'sequence_number': record.sequenceNumber,
        'record_hash': record.recordHash,
        'previous_record_hash': record.previousRecordHash,
        'image_hash': record.imageHash,
        'analysis_digest': record.analysisDigest,
        'signature': record.signature,
        'public_key_id': record.publicKeyId,
        'public_key': record.publicKeyBase64,
        'key_version': record.keyVersion,
        'signature_scheme': record.signatureScheme,
        'canonical_format_version': record.canonicalFormatVersion,
        'record_json': jsonEncode(record.toJson()),
        'created_at_utc': nowUtc,
      });

      return record;
    });
  }

  /// Searchable history (master spec section 36).
  Future<List<TestSummary>> search(HistoryQuery query) async {
    final List<String> clauses = <String>[];
    final List<Object?> args = <Object?>[];

    void add(String clause, Object? value) {
      clauses.add(clause);
      args.add(value);
    }

    if (query.testIdContains != null && query.testIdContains!.isNotEmpty) {
      // The LIKE pattern is bound, not interpolated, and wildcards in the
      // user's text are escaped so searching for "%" does not match every row.
      // SQLite does not process backslash escapes inside string literals, so
      // the ESCAPE argument must be the single character backslash.
      clauses.add(r"t.test_id LIKE ? ESCAPE '\'");
      args.add('%${_escapeLike(query.testIdContains!)}%');
    }
    if (query.from != null) {
      add('t.started_at_utc >= ?', query.from!.toUtc().toIso8601String());
    }
    if (query.to != null) {
      add('t.started_at_utc <= ?', query.to!.toUtc().toIso8601String());
    }
    if (query.operatorId != null) add('t.operator_id = ?', query.operatorId);
    if (query.officerId != null) add('t.officer_id = ?', query.officerId);
    if (query.kitId != null) add('t.kit_id = ?', query.kitId);
    if (query.result != null) add('t.result = ?', query.result!.wireName);
    if (query.reliabilityStatus != null) {
      add('t.reliability_status = ?', query.reliabilityStatus!.wireName);
    }
    if (query.deviceId != null) add('t.device_id = ?', query.deviceId);
    if (query.anomalyCode != null) {
      clauses.add(
        'EXISTS (SELECT 1 FROM anomalies a2 WHERE a2.test_id = t.test_id '
        'AND a2.code = ?)',
      );
      args.add(query.anomalyCode!.wireName);
    }

    final String where =
        clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';

    final List<Map<String, Object?>> rows = await _database.db.rawQuery(
      '''
      SELECT
        t.test_id, t.started_at_utc, t.completed_at_utc, t.officer_id,
        t.operator_id, t.kit_id, t.result, t.reliability_status, t.latitude,
        (SELECT COUNT(*) FROM anomalies a WHERE a.test_id = t.test_id)
          AS anomaly_count
      FROM tests t
      $where
      ORDER BY ${query.sort.orderBy}
      LIMIT ? OFFSET ?
      ''',
      <Object?>[...args, query.limit, query.offset],
    );

    return rows
        .map(
          (Map<String, Object?> r) => TestSummary(
            testId: r['test_id']! as String,
            startedAtUtc: DateTime.parse(r['started_at_utc']! as String),
            completedAtUtc: r['completed_at_utc'] == null
                ? null
                : DateTime.parse(r['completed_at_utc']! as String),
            officerId: r['officer_id']! as String,
            operatorId: r['operator_id']! as String,
            kitId: r['kit_id']! as String,
            result: r['result'] == null
                ? null
                : TestResult.fromWire(r['result']! as String),
            reliabilityStatus: r['reliability_status'] == null
                ? null
                : ReliabilityStatus.fromWire(
                    r['reliability_status']! as String),
            anomalyCount: (r['anomaly_count']! as num).toInt(),
            hasLocation: r['latitude'] != null,
          ),
        )
        .toList(growable: false);
  }

  /// Full analysis JSON for one test.
  Future<Map<String, Object?>?> loadAnalysisJson(String testId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'analysis_results',
      columns: <String>['analysis_json'],
      where: 'test_id = ?',
      whereArgs: <Object?>[testId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['analysis_json']! as String)
        as Map<String, Object?>;
  }

  Future<List<StoredImage>> imagesFor(String testId) async {
    final List<Map<String, Object?>> rows = await _database.db.query(
      'test_images',
      where: 'test_id = ?',
      whereArgs: <Object?>[testId],
      orderBy: 'is_original DESC, offset_seconds ASC',
    );
    return rows
        .map(
          (Map<String, Object?> r) => StoredImage(
            imageId: r['image_id']! as String,
            role: r['role']! as String,
            filePath: r['file_path']! as String,
            imageHash: r['image_hash']! as String,
            widthPx: (r['width_px']! as num).toInt(),
            heightPx: (r['height_px']! as num).toInt(),
            byteSize: (r['byte_size']! as num).toInt(),
            capturedAtUtc: DateTime.parse(r['captured_at_utc']! as String),
            isOriginal: (r['is_original']! as int) == 1,
            offsetSeconds: (r['offset_seconds'] as num?)?.toInt(),
            derivedFrom: r['derived_from'] as String?,
          ),
        )
        .toList(growable: false);
  }

  static String _escapeLike(String input) => input
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
