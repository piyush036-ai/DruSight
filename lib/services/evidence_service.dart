/// Builds, hashes and signs evidence records (master spec sections 30-33).
///
/// This is the only place a record is created. Centralising it means the
/// hash-and-sign order can never diverge between code paths.
library;

import '../config/versions.dart';
import '../models/analysis_result.dart';
import '../models/device_identity.dart';
import '../models/enums.dart';
import '../models/evidence_record.dart';
import '../models/location_fix.dart';
import '../models/operator.dart';
import '../security/hashing.dart';
import '../security/signer.dart';

class EvidenceService {
  EvidenceService(this._signer);

  final EvidenceSigner _signer;

  /// Creates a signed record.
  ///
  /// [previousRecordHash] must be the stored record hash of the immediately
  /// preceding record for this device, or [EvidenceRecord.genesisHash] for the
  /// first. [sequenceNumber] must be that record's sequence plus one. Both are
  /// supplied by the repository inside the same transaction that writes the
  /// new record, so two concurrent tests cannot claim the same chain slot.
  Future<EvidenceRecord> createRecord({
    required String testId,
    required OperatorSession session,
    required DeviceIdentity device,
    required AnalysisResult analysis,
    required String imageHash,
    required DateTime captureAtUtc,
    required LocationFix? location,
    required String previousRecordHash,
    required int sequenceNumber,
  }) async {
    final DateTime nowLocal = DateTime.now();
    final DateTime nowUtc = nowLocal.toUtc();

    // The full analysis is bound to the record by digest rather than embedded,
    // so the signed payload stays small enough to reason about while the
    // analysis remains tamper-evident.
    final String analysisDigest =
        Hashing.sha256OfCanonical(analysis.toJson());

    final List<String> anomalyCodes = analysis.anomalies
        .map((a) => a.code.wireName)
        .toList(growable: false)
      ..sort(); // Stable ordering: the set matters, the order does not.

    // Build the core map via a throwaway record so the layout comes from the
    // single definition in EvidenceRecord.toCoreMap().
    final EvidenceRecord draft = EvidenceRecord(
      testId: testId,
      officerId: session.account.officerId,
      operatorId: session.account.operatorId,
      sessionId: session.sessionId,
      role: session.account.role,
      deviceId: device.installationId,
      deviceModel: device.deviceModel,
      osVersion: device.osVersion,
      appVersion: '${device.appVersion}+${device.appBuild}',
      kitId: analysis.kitId,
      kitProfileVersion: analysis.kitProfileVersion,
      createdAtLocalIso: nowLocal.toIso8601String(),
      createdAtUtcIso: nowUtc.toIso8601String(),
      deviceTimeZoneOffsetMinutes: nowLocal.timeZoneOffset.inMinutes,
      captureAtUtcIso: captureAtUtc.toUtc().toIso8601String(),
      location: location,
      result: analysis.result,
      reliabilityStatus: analysis.reliabilityStatus,
      anomalyCodes: anomalyCodes,
      imageHash: imageHash,
      previousRecordHash: previousRecordHash,
      recordHash: '', // filled below
      analysisDigest: analysisDigest,
      modelId: analysis.classifierOutput.modelId,
      modelVersion: analysis.classifierOutput.modelVersion,
      calibrationVersion: analysis.calibration.calibrationVersion,
      algorithmVersion: analysis.algorithmVersion,
      featureSchemaVersion:
          analysis.features?.schemaVersion ?? Versions.featureSchema,
      canonicalFormatVersion: Versions.canonicalFormat,
      signature: '',
      publicKeyId: '',
      publicKeyBase64: '',
      keyVersion: 0,
      signatureScheme: EvidenceSigner.scheme,
      sequenceNumber: sequenceNumber,
    );

    final Map<String, Object?> core = draft.toCoreMap();
    final String recordHash = EvidenceRecord.computeRecordHashFrom(
      core: core,
      imageHash: imageHash,
      previousRecordHash: previousRecordHash,
    );

    final SignatureBundle signature = await _signer.sign(<String, Object?>{
      ...core,
      'recordHash': recordHash,
    });

    return EvidenceRecord(
      testId: draft.testId,
      officerId: draft.officerId,
      operatorId: draft.operatorId,
      sessionId: draft.sessionId,
      role: draft.role,
      deviceId: draft.deviceId,
      deviceModel: draft.deviceModel,
      osVersion: draft.osVersion,
      appVersion: draft.appVersion,
      kitId: draft.kitId,
      kitProfileVersion: draft.kitProfileVersion,
      createdAtLocalIso: draft.createdAtLocalIso,
      createdAtUtcIso: draft.createdAtUtcIso,
      deviceTimeZoneOffsetMinutes: draft.deviceTimeZoneOffsetMinutes,
      captureAtUtcIso: draft.captureAtUtcIso,
      location: draft.location,
      result: draft.result,
      reliabilityStatus: draft.reliabilityStatus,
      anomalyCodes: draft.anomalyCodes,
      imageHash: draft.imageHash,
      previousRecordHash: draft.previousRecordHash,
      recordHash: recordHash,
      analysisDigest: draft.analysisDigest,
      modelId: draft.modelId,
      modelVersion: draft.modelVersion,
      calibrationVersion: draft.calibrationVersion,
      algorithmVersion: draft.algorithmVersion,
      featureSchemaVersion: draft.featureSchemaVersion,
      canonicalFormatVersion: draft.canonicalFormatVersion,
      signature: signature.signatureBase64,
      publicKeyId: signature.publicKeyId,
      publicKeyBase64: signature.publicKeyBase64,
      keyVersion: signature.keyVersion,
      signatureScheme: signature.scheme,
      sequenceNumber: sequenceNumber,
      chainStatus: ChainStatus.valid,
    );
  }
}
