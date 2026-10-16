/// Append-only hash chain over evidence records (master spec section 32).
///
/// Each record commits to its predecessor's hash, so altering any historical
/// record invalidates that record's own hash AND every hash after it. The
/// chain is per-device: records are created offline on independent devices,
/// so a single global ordering cannot be assumed.
///
/// What this does and does not prove:
///   - It DOES detect any modification to a stored record after signing.
///   - It DOES detect deletion of a record from the middle of the chain.
///   - It does NOT prove the wall-clock time at which a record was created,
///     and it does NOT prevent an attacker who holds the private key from
///     rebuilding a whole consistent chain. External anchoring (e.g.
///     periodic publication of the head hash to an institutional server)
///     would be needed for that, and is a documented future step.
library;

import '../models/evidence_record.dart';
import 'hashing.dart';

/// One record's verification outcome.
class RecordVerification {
  const RecordVerification({
    required this.testId,
    required this.sequenceNumber,
    required this.recordHashValid,
    required this.linkValid,
    required this.signatureValid,
    required this.imageHashValid,
    this.notes = const <String>[],
  });

  final String testId;
  final int sequenceNumber;

  /// The stored record hash matches a recomputation from the stored fields.
  final bool recordHashValid;

  /// previousRecordHash matches the actual predecessor's record hash.
  final bool linkValid;

  final bool signatureValid;

  /// The stored image file still hashes to the recorded image hash. Null when
  /// the image was not available to check (e.g. verifying a scanned QR).
  final bool? imageHashValid;

  final List<String> notes;

  bool get intact =>
      recordHashValid &&
      linkValid &&
      signatureValid &&
      (imageHashValid ?? true);
}

/// Verification outcome for a whole chain.
class ChainVerification {
  const ChainVerification({
    required this.intact,
    required this.recordsChecked,
    required this.perRecord,
    required this.firstBreakSequence,
  });

  final bool intact;
  final int recordsChecked;
  final List<RecordVerification> perRecord;

  /// Sequence number of the earliest broken record, or null when intact.
  final int? firstBreakSequence;
}

class HashChain {
  const HashChain._();

  /// Computes the hash for the next record in the chain.
  static String nextRecordHash({
    required Map<String, Object?> core,
    required String imageHash,
    required String previousRecordHash,
  }) =>
      EvidenceRecord.computeRecordHashFrom(
        core: core,
        imageHash: imageHash,
        previousRecordHash: previousRecordHash,
      );

  /// Checks a record's own hash without reference to its neighbours.
  static bool recordHashMatches(EvidenceRecord record) =>
      Hashing.constantTimeEquals(
        record.computeRecordHash(),
        record.recordHash,
      );

  /// Checks link continuity across an ordered list of records.
  ///
  /// [records] must be sorted ascending by sequence number and belong to one
  /// device. Returns per-record link validity in the same order.
  static List<bool> verifyLinks(List<EvidenceRecord> records) {
    final List<bool> results = <bool>[];
    String expectedPrevious = EvidenceRecord.genesisHash;

    for (int i = 0; i < records.length; i++) {
      final EvidenceRecord r = records[i];
      final bool linkOk =
          Hashing.constantTimeEquals(r.previousRecordHash, expectedPrevious);
      final bool sequenceOk = r.sequenceNumber == i;
      results.add(linkOk && sequenceOk);
      // Continue from the record's OWN stored hash. Using the recomputed hash
      // would mask a break: a tampered record would still chain cleanly to its
      // successors under the recomputed value.
      expectedPrevious = r.recordHash;
    }
    return results;
  }
}
