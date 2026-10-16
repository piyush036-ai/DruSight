/// Orchestrates the complete New Test workflow (master spec section 45).
///
/// Steps 10-24 live here so the capture screen stays a camera UI and the
/// evidence path has exactly one implementation. Ordering is load-bearing:
/// the original image is written and hashed BEFORE analysis begins, so the
/// hash commits to the bytes as captured rather than to anything the analysis
/// might have touched.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../analysis/analysis_pipeline.dart';
import '../app/service_locator.dart';
import '../models/analysis_result.dart';
import '../models/device_identity.dart';
import '../models/enums.dart';
import '../models/evidence_record.dart';
import '../models/kit_profile.dart';
import '../models/location_fix.dart';
import '../models/operator.dart';
import '../models/reaction_series.dart';
import '../models/test_region.dart';
import '../repositories/audit_repository.dart';
import '../repositories/test_repository.dart';

class CompletedTest {
  const CompletedTest({
    required this.testId,
    required this.analysis,
    required this.record,
    required this.originalImagePath,
  });

  final String testId;
  final AnalysisResult analysis;
  final EvidenceRecord record;
  final String originalImagePath;
}

class TestWorkflowService {
  TestWorkflowService(this._services);

  final ServiceLocator _services;

  /// Runs steps 10-24 for a single capture.
  ///
  /// [regionGuideBox] is the overlay rectangle converted to image pixel
  /// coordinates. Calibration is handled automatically via the digital card.
  Future<CompletedTest> completeTest({
    required KitProfile profile,
    required Uint8List originalBytes,
    required img.Image decoded,
    required RegionBox regionGuideBox,
    required RegionSelectionMode regionMode,
    required DateTime startedAtUtc,
    required DateTime captureAtUtc,
    List<ReactionSample> reactionSamples = const <ReactionSample>[],
  }) async {
    final OperatorSession? session = _services.auth.currentSession;
    if (session == null) {
      throw StateError('No authenticated operator session.');
    }
    final DeviceIdentity device = await _services.deviceIdentity.current();
    final String testId = _generateTestId();

    await _services.audit.append(
      action: AuditAction.testStarted,
      actorId: session.account.operatorId,
      subjectType: 'TEST',
      subjectId: testId,
      detail: <String, Object?>{
        'kitId': profile.kitId,
        'kitProfileVersion': profile.profileVersion,
      },
    );

    // --- Steps 10-11: store and hash the original, before anything else ------
    final StoredImage original = await _services.imageStorage.saveOriginal(
      testId: testId,
      bytes: originalBytes,
      capturedAtUtc: captureAtUtc,
    );

    await _services.audit.append(
      action: AuditAction.imageCaptured,
      actorId: session.account.operatorId,
      subjectType: 'TEST',
      subjectId: testId,
      detail: <String, Object?>{'imageHash': original.imageHash},
    );

    // --- Step 11b: location, best effort -------------------------------------
    final LocationFix? location = await _services.location.currentFix();
    final LocationFix? previousLocation = await _previousLocation();
    final LocationIntegrityAssessment integrity =
        _services.locationIntegrity.assess(
      previous: previousLocation,
      current: location,
    );

    // --- Steps 12-18: analysis ------------------------------------------------
    await _services.audit.append(
      action: AuditAction.analysisStarted,
      actorId: session.account.operatorId,
      subjectType: 'TEST',
      subjectId: testId,
    );

    final AnalysisResult analysis = await _services.pipeline.run(
      AnalysisRequest(
        image: decoded,
        profile: profile,
        regionCandidate: regionGuideBox,
        regionSelectionMode: regionMode,
        reactionSamples: reactionSamples,
        locationIntegrity: integrity,
        locationAvailable: location != null,
      ),
    );

    await _services.audit.append(
      action: AuditAction.resultGenerated,
      actorId: session.account.operatorId,
      subjectType: 'TEST',
      subjectId: testId,
      detail: <String, Object?>{
        'result': analysis.result.wireName,
        'reliabilityStatus': analysis.reliabilityStatus.wireName,
        'anomalyCount': analysis.anomalies.length,
      },
    );

    // --- Steps 19-22: evidence record, hashed, signed, stored ----------------
    final EvidenceRecord record = await _services.tests.commitTest(
      testId: testId,
      operatorId: session.account.operatorId,
      officerId: session.account.officerId,
      sessionId: session.sessionId,
      deviceId: device.installationId,
      kitId: profile.kitId,
      kitProfileVersion: profile.profileVersion,
      startedAtUtc: startedAtUtc,
      analysis: analysis,
      images: <StoredImage>[original],
      reactionSamples: reactionSamples,
      latitude: location?.latitude,
      longitude: location?.longitude,
      locationAccuracy: location?.accuracyMetres,
      locationTimeUtc: location?.acquiredAtUtc,
      buildRecord: (String previousHash, int sequence) =>
          _services.evidenceService.createRecord(
        testId: testId,
        session: session,
        device: device,
        analysis: analysis,
        imageHash: original.imageHash,
        captureAtUtc: captureAtUtc,
        location: location,
        previousRecordHash: previousHash,
        sequenceNumber: sequence,
      ),
    );

    await _services.audit.append(
      action: AuditAction.evidenceCreated,
      actorId: session.account.operatorId,
      subjectType: 'EVIDENCE_RECORD',
      subjectId: testId,
      detail: <String, Object?>{
        'recordHash': record.recordHash,
        'sequenceNumber': record.sequenceNumber,
      },
    );
    await _services.audit.append(
      action: AuditAction.signatureGenerated,
      actorId: session.account.operatorId,
      subjectType: 'EVIDENCE_RECORD',
      subjectId: testId,
      detail: <String, Object?>{
        'publicKeyId': record.publicKeyId,
        'scheme': record.signatureScheme,
      },
    );

    return CompletedTest(
      testId: testId,
      analysis: analysis,
      record: record,
      originalImagePath: original.filePath,
    );
  }

  /// Most recent recorded location for this device, used by the
  /// location-integrity comparison.
  Future<LocationFix?> _previousLocation() async {
    final List<TestSummary> recent =
        await _services.tests.search(const HistoryQuery(limit: 1));
    if (recent.isEmpty) return null;

    final EvidenceRecord? record =
        await _services.evidence.findByTestId(recent.first.testId);
    return record?.location;
  }

  static String _generateTestId() {
    final DateTime now = DateTime.now().toUtc();
    final Random rng = Random.secure();
    final String suffix = List<int>.generate(4, (_) => rng.nextInt(256))
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    final String date = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return 'DS-$date-$suffix';
  }
}
