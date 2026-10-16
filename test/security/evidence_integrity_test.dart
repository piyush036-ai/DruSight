/// End-to-end integrity tests: hashing, signing, chaining, and the tamper
/// detections the whole evidence claim rests on (master spec section 53).
library;

import 'dart:convert';

import 'package:drusight/config/versions.dart';
import 'package:drusight/models/enums.dart';
import 'package:drusight/models/evidence_record.dart';
import 'package:drusight/models/location_fix.dart';
import 'package:drusight/security/hash_chain.dart';
import 'package:drusight/security/hashing.dart';
import 'package:drusight/security/key_store.dart';
import 'package:drusight/security/signer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a record with a correctly computed hash and signature.
Future<EvidenceRecord> buildRecord(
  EvidenceSigner signer, {
  required int sequence,
  required String previousHash,
  String testId = 'DS-TEST-0001',
  TestResult result = TestResult.presumptiveNegative,
  String imageHash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  LocationFix? location,
}) async {
  final EvidenceRecord draft = EvidenceRecord(
    testId: testId,
    officerId: 'OFF-1',
    operatorId: 'OP-1',
    sessionId: 'SESS-1',
    role: OperatorRole.fieldOperator,
    deviceId: 'DEV-1',
    deviceModel: 'Test Device',
    osVersion: 'Test OS 1',
    appVersion: '0.1.0+1',
    kitId: 'DS-DEMO-001',
    kitProfileVersion: '1.0.0',
    createdAtLocalIso: '2026-09-25T10:00:00.000',
    createdAtUtcIso: '2026-09-25T04:30:00.000Z',
    deviceTimeZoneOffsetMinutes: 330,
    captureAtUtcIso: '2026-09-25T04:29:50.000Z',
    location: location,
    result: result,
    reliabilityStatus: ReliabilityStatus.pass,
    anomalyCodes: const <String>[],
    imageHash: imageHash,
    previousRecordHash: previousHash,
    recordHash: '',
    analysisDigest:
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    modelId: null,
    modelVersion: null,
    calibrationVersion: Versions.calibration,
    algorithmVersion: Versions.algorithm,
    featureSchemaVersion: Versions.featureSchema,
    canonicalFormatVersion: Versions.canonicalFormat,
    signature: '',
    publicKeyId: '',
    publicKeyBase64: '',
    keyVersion: 0,
    signatureScheme: EvidenceSigner.scheme,
    sequenceNumber: sequence,
  );

  final Map<String, Object?> core = draft.toCoreMap();
  final String recordHash = EvidenceRecord.computeRecordHashFrom(
    core: core,
    imageHash: imageHash,
    previousRecordHash: previousHash,
  );
  final SignatureBundle sig = await signer.sign(<String, Object?>{
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
    signature: sig.signatureBase64,
    publicKeyId: sig.publicKeyId,
    publicKeyBase64: sig.publicKeyBase64,
    keyVersion: sig.keyVersion,
    signatureScheme: sig.scheme,
    sequenceNumber: sequence,
  );
}

/// Returns a copy with one field altered, keeping the ORIGINAL hash and
/// signature - which is exactly what a tampered stored record looks like.
EvidenceRecord tamper(
  EvidenceRecord r, {
  TestResult? result,
  String? imageHash,
  String? previousRecordHash,
  String? signature,
}) =>
    EvidenceRecord(
      testId: r.testId,
      officerId: r.officerId,
      operatorId: r.operatorId,
      sessionId: r.sessionId,
      role: r.role,
      deviceId: r.deviceId,
      deviceModel: r.deviceModel,
      osVersion: r.osVersion,
      appVersion: r.appVersion,
      kitId: r.kitId,
      kitProfileVersion: r.kitProfileVersion,
      createdAtLocalIso: r.createdAtLocalIso,
      createdAtUtcIso: r.createdAtUtcIso,
      deviceTimeZoneOffsetMinutes: r.deviceTimeZoneOffsetMinutes,
      captureAtUtcIso: r.captureAtUtcIso,
      location: r.location,
      result: result ?? r.result,
      reliabilityStatus: r.reliabilityStatus,
      anomalyCodes: r.anomalyCodes,
      imageHash: imageHash ?? r.imageHash,
      previousRecordHash: previousRecordHash ?? r.previousRecordHash,
      recordHash: r.recordHash,
      analysisDigest: r.analysisDigest,
      modelId: r.modelId,
      modelVersion: r.modelVersion,
      calibrationVersion: r.calibrationVersion,
      algorithmVersion: r.algorithmVersion,
      featureSchemaVersion: r.featureSchemaVersion,
      canonicalFormatVersion: r.canonicalFormatVersion,
      signature: signature ?? r.signature,
      publicKeyId: r.publicKeyId,
      publicKeyBase64: r.publicKeyBase64,
      keyVersion: r.keyVersion,
      signatureScheme: r.signatureScheme,
      sequenceNumber: r.sequenceNumber,
    );

void main() {
  late EvidenceSigner signer;

  setUp(() {
    signer = EvidenceSigner(InMemoryKeyStore(seed: 42));
  });

  group('SHA-256', () {
    test('matches the known digest of the empty string', () {
      expect(
        Hashing.sha256OfString(''),
        equals(
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        ),
      );
    });

    test('matches the known digest of "abc"', () {
      expect(
        Hashing.sha256OfString('abc'),
        equals(
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
        ),
      );
    });

    test('constant-time comparison behaves like equality', () {
      const String a =
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
      expect(Hashing.constantTimeEquals(a, a), isTrue);
      expect(Hashing.constantTimeEquals(a, a.substring(0, 63)), isFalse);
      expect(
        Hashing.constantTimeEquals(a, '${a.substring(0, 63)}e'),
        isFalse,
      );
    });
  });

  group('record hashing', () {
    test('a freshly built record verifies its own hash', () async {
      final EvidenceRecord r = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      expect(HashChain.recordHashMatches(r), isTrue);
    });

    test('changing the result breaks the record hash', () async {
      final EvidenceRecord r = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      final EvidenceRecord bad =
          tamper(r, result: TestResult.presumptivePositive);
      expect(HashChain.recordHashMatches(bad), isFalse);
    });

    test('changing the image hash breaks the record hash', () async {
      final EvidenceRecord r = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      final EvidenceRecord bad = tamper(
        r,
        imageHash:
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
      );
      expect(HashChain.recordHashMatches(bad), isFalse);
    });

    test('the hash depends on the previous hash', () async {
      final EvidenceRecord a = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      final EvidenceRecord b = await buildRecord(
        signer,
        sequence: 0,
        previousHash:
            '1111111111111111111111111111111111111111111111111111111111111111',
      );
      expect(a.recordHash, isNot(equals(b.recordHash)));
    });

    test('recomputation is stable across repeated calls', () async {
      final EvidenceRecord r = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      final String first = r.computeRecordHash();
      for (int i = 0; i < 10; i++) {
        expect(r.computeRecordHash(), equals(first));
      }
    });

    test('an optional field set to null hashes as if absent', () async {
      final EvidenceRecord withNull = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      expect(withNull.toCoreMap()['location'], isNull);
      expect(HashChain.recordHashMatches(withNull), isTrue);
    });
  });

  group('Ed25519 signatures', () {
    test('a valid signature verifies', () async {
      final EvidenceRecord r = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      expect(
        await signer.verify(
          r.toSignedPayload(),
          signatureBase64: r.signature,
          publicKeyBase64: r.publicKeyBase64,
        ),
        isTrue,
      );
    });

    test('a modified payload fails verification', () async {
      final EvidenceRecord r = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      final EvidenceRecord bad =
          tamper(r, result: TestResult.presumptivePositive);
      expect(
        await signer.verify(
          bad.toSignedPayload(),
          signatureBase64: bad.signature,
          publicKeyBase64: bad.publicKeyBase64,
        ),
        isFalse,
      );
    });

    test('a forged signature of the correct length fails verification',
        () async {
      final EvidenceRecord r = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      // Flip one base64 character inside the payload, keeping the decoded
      // length at 64 bytes.
      final List<int> bytes = base64.decode(r.signature);
      bytes[0] = bytes[0] ^ 0x01;
      expect(bytes.length, EvidenceSigner.signatureLengthBytes);

      expect(
        await signer.verify(
          r.toSignedPayload(),
          signatureBase64: base64.encode(bytes),
          publicKeyBase64: r.publicKeyBase64,
        ),
        isFalse,
      );
    });

    test('a wrong-length signature fails rather than throwing', () async {
      // Regression test. package:cryptography raises a StateError for a
      // signature that is not exactly 64 bytes, which would have crashed the
      // verification screen instead of reporting an invalid signature - the
      // precise failure mode SECURITY.md claims cannot happen.
      final EvidenceRecord r = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );

      for (final String broken in <String>[
        base64.encode(base64.decode(r.signature).sublist(0, 32)), // short
        base64.encode(<int>[...base64.decode(r.signature), 0, 0]), // long
        base64.encode(<int>[]), // empty
      ]) {
        expect(
          await signer.verify(
            r.toSignedPayload(),
            signatureBase64: broken,
            publicKeyBase64: r.publicKeyBase64,
          ),
          isFalse,
          reason: 'a malformed signature must be a failed verification, '
              'never an exception',
        );
      }
    });

    test('a wrong-length public key fails rather than throwing', () async {
      final EvidenceRecord r = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      expect(
        await signer.verify(
          r.toSignedPayload(),
          signatureBase64: r.signature,
          publicKeyBase64: base64Url.encode(<int>[1, 2, 3]),
        ),
        isFalse,
      );
    });

    test('a different key fails verification', () async {
      final EvidenceRecord r = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      final EvidenceSigner other =
          EvidenceSigner(InMemoryKeyStore(seed: 99));
      final EvidenceRecord otherRecord = await buildRecord(
        other,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      expect(
        await signer.verify(
          r.toSignedPayload(),
          signatureBase64: r.signature,
          publicKeyBase64: otherRecord.publicKeyBase64,
        ),
        isFalse,
      );
    });

    test('malformed base64 fails rather than throwing', () async {
      final EvidenceRecord r = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      expect(
        await signer.verify(
          r.toSignedPayload(),
          signatureBase64: 'not valid base64 !!!',
          publicKeyBase64: r.publicKeyBase64,
        ),
        isFalse,
      );
    });

    test('the signature binds the record hash, not just the core', () async {
      // A signature must not be liftable from one chain position to another.
      final EvidenceRecord r = await buildRecord(
        signer,
        sequence: 0,
        previousHash: EvidenceRecord.genesisHash,
      );
      final Map<String, Object?> payload = r.toSignedPayload();
      payload['recordHash'] =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      expect(
        await signer.verify(
          payload,
          signatureBase64: r.signature,
          publicKeyBase64: r.publicKeyBase64,
        ),
        isFalse,
      );
    });
  });

  group('hash chain', () {
    Future<List<EvidenceRecord>> buildChain(int length) async {
      final List<EvidenceRecord> chain = <EvidenceRecord>[];
      String previous = EvidenceRecord.genesisHash;
      for (int i = 0; i < length; i++) {
        final EvidenceRecord r = await buildRecord(
          signer,
          sequence: i,
          previousHash: previous,
          testId: 'DS-TEST-${i.toString().padLeft(4, '0')}',
        );
        chain.add(r);
        previous = r.recordHash;
      }
      return chain;
    }

    test('an intact chain verifies end to end', () async {
      final List<EvidenceRecord> chain = await buildChain(5);
      expect(HashChain.verifyLinks(chain), everyElement(isTrue));
      for (final EvidenceRecord r in chain) {
        expect(HashChain.recordHashMatches(r), isTrue);
      }
    });

    test('the first record links to the genesis value', () async {
      final List<EvidenceRecord> chain = await buildChain(1);
      expect(chain.first.previousRecordHash,
          equals(EvidenceRecord.genesisHash));
      expect(HashChain.verifyLinks(chain).first, isTrue);
    });

    test('removing a middle record breaks every link after it', () async {
      final List<EvidenceRecord> chain = await buildChain(5);
      final List<EvidenceRecord> gapped = <EvidenceRecord>[
        ...chain.sublist(0, 2),
        ...chain.sublist(3),
      ];
      final List<bool> links = HashChain.verifyLinks(gapped);
      expect(links[0], isTrue);
      expect(links[1], isTrue);
      // Record 3 now sits at index 2 and points at record 2's hash, not
      // record 1's, so both the link and the sequence number are wrong.
      expect(links.sublist(2), everyElement(isFalse));
    });

    test('altering a historical record is detected at that record', () async {
      final List<EvidenceRecord> chain = await buildChain(4);
      chain[1] = tamper(chain[1], result: TestResult.presumptivePositive);

      expect(HashChain.recordHashMatches(chain[0]), isTrue);
      expect(HashChain.recordHashMatches(chain[1]), isFalse);
      // Links still hold because the tampered record kept its stored hash -
      // which is precisely why link checking alone is not sufficient and the
      // verifier checks both.
      expect(HashChain.verifyLinks(chain), everyElement(isTrue));
    });

    test('re-pointing a record breaks its link', () async {
      final List<EvidenceRecord> chain = await buildChain(3);
      chain[2] = tamper(
        chain[2],
        previousRecordHash:
            '2222222222222222222222222222222222222222222222222222222222222222',
      );
      final List<bool> links = HashChain.verifyLinks(chain);
      expect(links[0], isTrue);
      expect(links[1], isTrue);
      expect(links[2], isFalse);
    });

    test('an out-of-order sequence number is rejected', () async {
      final List<EvidenceRecord> chain = await buildChain(3);
      final List<EvidenceRecord> reordered = <EvidenceRecord>[
        chain[1],
        chain[0],
        chain[2],
      ];
      expect(HashChain.verifyLinks(reordered), contains(isFalse));
    });
  });
}
