/// Tamper demonstration for the SIH presentation (master spec section 35).
///
/// SAFETY DESIGN: this service never modifies stored evidence. It operates on
/// an in-memory COPY of a record, shows that verification then fails, and
/// discards the copy. The real row in `evidence_records` is untouched, which
/// is why "restore valid record" in the demo script is simply re-verifying the
/// original - there is nothing to undo.
///
/// Every invocation writes an audit event, so even the demonstration is
/// accountable.
library;

import 'dart:convert';

import '../config/app_config.dart';
import '../models/enums.dart';
import '../models/evidence_record.dart';
import '../repositories/audit_repository.dart';
import '../security/hash_chain.dart';
import 'verification_service.dart';

enum TamperScenario {
  /// Change the reported result. Breaks the record hash and the signature.
  alterResult('Change the recorded result'),

  /// Change the image hash. Simulates image substitution.
  alterImageHash('Substitute the evidence image'),

  /// Change the previous-record hash. Simulates removing a record from the
  /// middle of the chain.
  breakChainLink('Remove a preceding record from the chain'),

  /// Keep the payload but replace the signature.
  forgeSignature('Replace the digital signature');

  const TamperScenario(this.label);
  final String label;
}

class TamperDemoOutcome {
  const TamperDemoOutcome({
    required this.scenario,
    required this.originalVerification,
    required this.tamperedVerification,
    required this.fieldChanged,
    required this.before,
    required this.after,
  });

  final TamperScenario scenario;
  final RecordVerification originalVerification;
  final RecordVerification tamperedVerification;
  final String fieldChanged;
  final String before;
  final String after;

  /// Headline shown in the demo.
  List<String> get failures {
    final List<String> out = <String>[];
    if (!tamperedVerification.recordHashValid) out.add('HASH MISMATCH');
    if (!tamperedVerification.signatureValid) out.add('SIGNATURE INVALID');
    if (!tamperedVerification.linkValid) out.add('CHAIN BROKEN');
    return out;
  }
}

class DemoTamperService {
  DemoTamperService(this._verification, this._audit);

  final VerificationService _verification;
  final AuditRepository _audit;

  bool get enabled => AppConfig.demoModeCompiledIn;

  /// Runs a scenario against an in-memory copy of [record].
  Future<TamperDemoOutcome> demonstrate(
    EvidenceRecord record,
    TamperScenario scenario, {
    String? actorId,
  }) async {
    if (!enabled) {
      throw StateError(
        'Tamper demonstration is not available in this build. Rebuild with '
        '--dart-define=DRUSIGHT_DEMO=true to enable the demonstration '
        'environment.',
      );
    }

    final RecordVerification original =
        await _verification.verifyRecord(record);

    late final Map<String, Object?> mutated;
    late final String field;
    late final String before;
    late final String after;

    final Map<String, Object?> json =
        jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>;

    switch (scenario) {
      case TamperScenario.alterResult:
        field = 'result';
        before = json['result']! as String;
        after = before == 'POSITIVE' ? 'NEGATIVE' : 'POSITIVE';
        json['result'] = after;
        mutated = json;
      case TamperScenario.alterImageHash:
        field = 'imageHash';
        before = json['imageHash']! as String;
        after = _flipLastHexDigit(before);
        json['imageHash'] = after;
        mutated = json;
      case TamperScenario.breakChainLink:
        field = 'previousRecordHash';
        before = json['previousRecordHash']! as String;
        after = _flipLastHexDigit(before);
        json['previousRecordHash'] = after;
        mutated = json;
      case TamperScenario.forgeSignature:
        field = 'signature';
        before = json['signature']! as String;
        after = _flipLastBase64Char(before);
        json['signature'] = after;
        mutated = json;
    }

    final EvidenceRecord tampered = _rebuild(record, mutated);

    // Link validity is evaluated against the untouched original's stored
    // previous hash, which is what a real chain walk would compare.
    final bool linkValid = scenario != TamperScenario.breakChainLink &&
        tampered.previousRecordHash == record.previousRecordHash;

    final RecordVerification tamperedVerification = await _verification
        .verifyRecord(tampered, linkValid: linkValid);

    await _audit.append(
      action: AuditAction.demoTamperSimulated,
      actorId: actorId,
      subjectType: 'EVIDENCE_RECORD',
      subjectId: record.testId,
      detail: <String, Object?>{
        'scenario': scenario.name,
        'field': field,
        'storedRecordModified': false,
        'note': 'Simulation performed on an in-memory copy. The stored '
            'evidence record was not modified.',
      },
    );

    return TamperDemoOutcome(
      scenario: scenario,
      originalVerification: original,
      tamperedVerification: tamperedVerification,
      fieldChanged: field,
      before: before,
      after: after,
    );
  }

  /// Reconstructs a record from a mutated JSON map, keeping the ORIGINAL
  /// record hash and signature so the mismatch is detectable.
  static EvidenceRecord _rebuild(
    EvidenceRecord original,
    Map<String, Object?> mutated,
  ) =>
      EvidenceRecord(
        testId: mutated['testId']! as String,
        officerId: mutated['officerId']! as String,
        operatorId: mutated['operatorId']! as String,
        sessionId: mutated['sessionId']! as String,
        role: original.role,
        deviceId: mutated['deviceId']! as String,
        deviceModel: mutated['deviceModel']! as String,
        osVersion: mutated['osVersion']! as String,
        appVersion: mutated['appVersion']! as String,
        kitId: mutated['kitId']! as String,
        kitProfileVersion: mutated['kitProfileVersion']! as String,
        createdAtLocalIso: mutated['createdAtLocal']! as String,
        createdAtUtcIso: mutated['createdAtUtc']! as String,
        deviceTimeZoneOffsetMinutes:
            (mutated['tzOffsetMinutes']! as num).toInt(),
        captureAtUtcIso: mutated['captureAtUtc']! as String,
        location: original.location,
        result: TestResult.fromWire(mutated['result']! as String),
        reliabilityStatus: original.reliabilityStatus,
        anomalyCodes: original.anomalyCodes,
        imageHash: mutated['imageHash']! as String,
        previousRecordHash: mutated['previousRecordHash']! as String,
        recordHash: mutated['recordHash']! as String,
        analysisDigest: mutated['analysisDigest']! as String,
        modelId: mutated['modelId'] as String?,
        modelVersion: mutated['modelVersion'] as String?,
        calibrationVersion: mutated['calibrationVersion']! as String,
        algorithmVersion: mutated['algorithmVersion']! as String,
        featureSchemaVersion: mutated['featureSchemaVersion']! as String,
        canonicalFormatVersion: mutated['canonicalFormatVersion']! as String,
        signature: mutated['signature']! as String,
        publicKeyId: mutated['publicKeyId']! as String,
        publicKeyBase64: mutated['publicKey']! as String,
        keyVersion: (mutated['keyVersion']! as num).toInt(),
        signatureScheme: mutated['signatureScheme']! as String,
        sequenceNumber: (mutated['sequenceNumber']! as num).toInt(),
      );


  static String _flipLastHexDigit(String hex) {
    if (hex.isEmpty) return hex;
    final String last = hex[hex.length - 1];
    final int value = int.parse(last, radix: 16);
    return hex.substring(0, hex.length - 1) +
        ((value + 1) % 16).toRadixString(16);
  }

  static String _flipLastBase64Char(String value) {
    if (value.isEmpty) return value;
    const String alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final String trimmed = value.replaceAll('=', '');
    if (trimmed.isEmpty) return value;
    final String last = trimmed[trimmed.length - 1];
    final int index = alphabet.indexOf(last);
    final String replacement =
        alphabet[(index < 0 ? 0 : index + 1) % alphabet.length];
    return trimmed.substring(0, trimmed.length - 1) + replacement;
  }
}

