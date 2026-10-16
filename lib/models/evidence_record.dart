/// The tamper-evident digital evidence record (master spec sections 30-33).
///
/// Structure and integrity relationships:
///
///   core            = all substantive fields (identity, context, result,
///                     versions, image hash, previous record hash)
///   recordHash      = SHA256( canonical(core) || imageHash || prevHash )
///   signedPayload   = core + { recordHash }
///   signature       = Ed25519( canonical(signedPayload) )
///
/// Binding the signature to the record hash - rather than to `core` alone -
/// means a signature cannot be lifted from one position in the chain and
/// replayed at another.
library;

import 'dart:convert';

import '../config/versions.dart';
import '../security/canonical_json.dart';
import '../security/hashing.dart';
import 'enums.dart';
import 'location_fix.dart';

class EvidenceRecord {
  const EvidenceRecord({
    required this.testId,
    required this.officerId,
    required this.operatorId,
    required this.sessionId,
    required this.role,
    required this.deviceId,
    required this.deviceModel,
    required this.osVersion,
    required this.appVersion,
    required this.kitId,
    required this.kitProfileVersion,
    required this.createdAtLocalIso,
    required this.createdAtUtcIso,
    required this.deviceTimeZoneOffsetMinutes,
    required this.captureAtUtcIso,
    required this.location,
    required this.result,
    required this.reliabilityStatus,
    required this.anomalyCodes,
    required this.imageHash,
    required this.previousRecordHash,
    required this.recordHash,
    required this.modelId,
    required this.modelVersion,
    required this.calibrationVersion,
    required this.algorithmVersion,
    required this.featureSchemaVersion,
    required this.canonicalFormatVersion,
    required this.analysisDigest,
    required this.signature,
    required this.publicKeyId,
    required this.publicKeyBase64,
    required this.keyVersion,
    required this.signatureScheme,
    required this.sequenceNumber,
    this.chainStatus = ChainStatus.unverified,
  });

  // --- Identity and context -------------------------------------------------
  final String testId;
  final String officerId;
  final String operatorId;
  final String sessionId;
  final OperatorRole role;
  final String deviceId;
  final String deviceModel;
  final String osVersion;
  final String appVersion;
  final String kitId;
  final String kitProfileVersion;

  // --- Time (master spec section 29) ---------------------------------------
  final String createdAtLocalIso;
  final String createdAtUtcIso;
  final int deviceTimeZoneOffsetMinutes;
  final String captureAtUtcIso;

  // --- Location (master spec section 28) -----------------------------------
  final LocationFix? location;

  // --- Outcome --------------------------------------------------------------
  final TestResult result;
  final ReliabilityStatus reliabilityStatus;
  final List<String> anomalyCodes;

  // --- Integrity ------------------------------------------------------------
  final String imageHash;
  final String previousRecordHash;
  final String recordHash;

  /// SHA-256 of the canonical full analysis object. The complete analysis is
  /// stored alongside the record; this digest binds it to the signed record
  /// without bloating the signed payload.
  final String analysisDigest;

  // --- Versions (master spec section 51) ------------------------------------
  final String? modelId;
  final String? modelVersion;
  final String calibrationVersion;
  final String algorithmVersion;
  final String featureSchemaVersion;
  final String canonicalFormatVersion;

  // --- Signature ------------------------------------------------------------
  final String signature;
  final String publicKeyId;
  final String publicKeyBase64;
  final int keyVersion;
  final String signatureScheme;

  /// Position in this device's chain. Genesis record is 0.
  final int sequenceNumber;

  /// Transient: populated by verification, never part of the signed payload.
  final ChainStatus chainStatus;

  /// The substantive fields, excluding derived integrity values.
  ///
  /// This is the ONLY place the core layout is defined. Both creation and
  /// verification go through it, so they cannot drift apart.
  Map<String, Object?> toCoreMap() => <String, Object?>{
        'testId': testId,
        'officerId': officerId,
        'operatorId': operatorId,
        'sessionId': sessionId,
        'role': role.wireName,
        'deviceId': deviceId,
        'deviceModel': deviceModel,
        'osVersion': osVersion,
        'appVersion': appVersion,
        'kitId': kitId,
        'kitProfileVersion': kitProfileVersion,
        'createdAtLocal': createdAtLocalIso,
        'createdAtUtc': createdAtUtcIso,
        'tzOffsetMinutes': deviceTimeZoneOffsetMinutes,
        'captureAtUtc': captureAtUtcIso,
        'location': location?.toJson(),
        'result': result.wireName,
        'reliabilityStatus': reliabilityStatus.wireName,
        'anomalyCodes': anomalyCodes,
        'imageHash': imageHash,
        'previousRecordHash': previousRecordHash,
        'analysisDigest': analysisDigest,
        'modelId': modelId,
        'modelVersion': modelVersion,
        'calibrationVersion': calibrationVersion,
        'algorithmVersion': algorithmVersion,
        'featureSchemaVersion': featureSchemaVersion,
        'canonicalFormatVersion': canonicalFormatVersion,
        'sequenceNumber': sequenceNumber,
      };

  /// The exact payload that was signed.
  Map<String, Object?> toSignedPayload() => <String, Object?>{
        ...toCoreMap(),
        'recordHash': recordHash,
      };

  /// Full serialization including signature, for export and QR verification.
  Map<String, Object?> toJson() => <String, Object?>{
        ...toSignedPayload(),
        'signature': signature,
        'publicKeyId': publicKeyId,
        'publicKey': publicKeyBase64,
        'keyVersion': keyVersion,
        'signatureScheme': signatureScheme,
      };

  EvidenceRecord copyWith({ChainStatus? chainStatus}) => EvidenceRecord(
        testId: testId,
        officerId: officerId,
        operatorId: operatorId,
        sessionId: sessionId,
        role: role,
        deviceId: deviceId,
        deviceModel: deviceModel,
        osVersion: osVersion,
        appVersion: appVersion,
        kitId: kitId,
        kitProfileVersion: kitProfileVersion,
        createdAtLocalIso: createdAtLocalIso,
        createdAtUtcIso: createdAtUtcIso,
        deviceTimeZoneOffsetMinutes: deviceTimeZoneOffsetMinutes,
        captureAtUtcIso: captureAtUtcIso,
        location: location,
        result: result,
        reliabilityStatus: reliabilityStatus,
        anomalyCodes: anomalyCodes,
        imageHash: imageHash,
        previousRecordHash: previousRecordHash,
        recordHash: recordHash,
        analysisDigest: analysisDigest,
        modelId: modelId,
        modelVersion: modelVersion,
        calibrationVersion: calibrationVersion,
        algorithmVersion: algorithmVersion,
        featureSchemaVersion: featureSchemaVersion,
        canonicalFormatVersion: canonicalFormatVersion,
        signature: signature,
        publicKeyId: publicKeyId,
        publicKeyBase64: publicKeyBase64,
        keyVersion: keyVersion,
        signatureScheme: signatureScheme,
        sequenceNumber: sequenceNumber,
        chainStatus: chainStatus ?? this.chainStatus,
      );

  /// Recomputes the record hash from the core fields.
  ///
  /// Concatenation order is fixed and must match [EvidenceRecordBuilder]:
  /// canonical(core) bytes, then the image-hash ASCII, then the previous-hash
  /// ASCII (master spec section 32).
  String computeRecordHash() => computeRecordHashFrom(
        core: toCoreMap(),
        imageHash: imageHash,
        previousRecordHash: previousRecordHash,
      );

  static String computeRecordHashFrom({
    required Map<String, Object?> core,
    required String imageHash,
    required String previousRecordHash,
  }) {
    final List<int> bytes = <int>[
      ...CanonicalJson.encodeToBytes(core),
      ...utf8.encode(imageHash),
      ...utf8.encode(previousRecordHash),
    ];
    return Hashing.sha256Hex(bytes);
  }

  static String get genesisHash => Versions.chainGenesis;
}
