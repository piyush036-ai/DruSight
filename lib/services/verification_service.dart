/// Local verification of stored records (master spec sections 34, 35).
///
/// Everything here runs offline. No network call is made or required.
library;

import 'dart:io';

import '../models/evidence_record.dart';
import '../security/hash_chain.dart';
import '../security/hashing.dart';
import '../security/signer.dart';

class VerificationService {
  VerificationService(this._signer);

  final EvidenceSigner _signer;

  /// Verifies one record in isolation: its own hash, its signature and,
  /// when [imageFile] is supplied, the stored image.
  ///
  /// Link validity cannot be checked from a single record, so [linkValid] is
  /// reported as true here and re-evaluated by [verifyChain].
  Future<RecordVerification> verifyRecord(
    EvidenceRecord record, {
    File? imageFile,
    bool linkValid = true,
  }) async {
    final bool hashOk = HashChain.recordHashMatches(record);

    final bool signatureOk = await _signer.verify(
      record.toSignedPayload(),
      signatureBase64: record.signature,
      publicKeyBase64: record.publicKeyBase64,
    );

    bool? imageOk;
    final List<String> notes = <String>[];
    if (imageFile != null) {
      if (await imageFile.exists()) {
        final String actual = await Hashing.sha256OfFile(imageFile);
        imageOk = Hashing.constantTimeEquals(actual, record.imageHash);
        if (!imageOk) {
          notes.add(
            'Stored image no longer hashes to the value recorded at capture.',
          );
        }
      } else {
        imageOk = false;
        notes.add('Original evidence image is missing from storage.');
      }
    }

    if (!hashOk) {
      notes.add(
        'Record hash does not match a recomputation from the stored fields; '
        'the record has been modified since signing.',
      );
    }
    if (!signatureOk) {
      notes.add(
        'Ed25519 signature does not verify against the public key stored '
        'with this record.',
      );
    }

    return RecordVerification(
      testId: record.testId,
      sequenceNumber: record.sequenceNumber,
      recordHashValid: hashOk,
      linkValid: linkValid,
      signatureValid: signatureOk,
      imageHashValid: imageOk,
      notes: notes,
    );
  }

  /// Verifies a whole device chain.
  ///
  /// [records] must be ordered ascending by sequence number.
  Future<ChainVerification> verifyChain(
    List<EvidenceRecord> records, {
    Future<File?> Function(String testId)? imageResolver,
  }) async {
    final List<bool> links = HashChain.verifyLinks(records);
    final List<RecordVerification> perRecord = <RecordVerification>[];
    int? firstBreak;

    for (int i = 0; i < records.length; i++) {
      final File? image = imageResolver == null
          ? null
          : await imageResolver(records[i].testId);
      final RecordVerification v = await verifyRecord(
        records[i],
        imageFile: image,
        linkValid: links[i],
      );
      perRecord.add(v);
      if (!v.intact && firstBreak == null) {
        firstBreak = records[i].sequenceNumber;
      }
    }

    return ChainVerification(
      intact: firstBreak == null,
      recordsChecked: records.length,
      perRecord: perRecord,
      firstBreakSequence: firstBreak,
    );
  }
}
