/// QR payload construction and parsing (master spec sections 34, 47).
///
/// Privacy: the payload carries integrity values and version metadata only.
/// It does NOT carry the officer ID, operator name, GPS coordinates, image, or
/// any substance information. A QR code is a public-facing artefact - it can
/// be photographed by anyone who sees the evidence bag - so it contains the
/// minimum needed to verify, and nothing that identifies a person or place.
///
/// Verification model:
///   - On the issuing device, the test ID resolves to the full local record
///     and a complete verification runs.
///   - On another device, the payload alone still proves internal
///     consistency: the record hash and signature in the payload can be
///     checked against the public key in the payload. What it cannot do
///     offline is prove that public key belongs to a particular institution.
///     That requires a key registry and is documented as out of scope.
library;

import 'dart:convert';

import '../models/evidence_record.dart';

class QrPayload {
  const QrPayload({
    required this.version,
    required this.testId,
    required this.recordHash,
    required this.imageHash,
    required this.previousRecordHash,
    required this.sequenceNumber,
    required this.signature,
    required this.publicKeyId,
    required this.publicKey,
    required this.signatureScheme,
    required this.canonicalFormatVersion,
    required this.createdAtUtc,
  });

  factory QrPayload.fromRecord(EvidenceRecord record) => QrPayload(
        version: currentVersion,
        testId: record.testId,
        recordHash: record.recordHash,
        imageHash: record.imageHash,
        previousRecordHash: record.previousRecordHash,
        sequenceNumber: record.sequenceNumber,
        signature: record.signature,
        publicKeyId: record.publicKeyId,
        publicKey: record.publicKeyBase64,
        signatureScheme: record.signatureScheme,
        canonicalFormatVersion: record.canonicalFormatVersion,
        createdAtUtc: record.createdAtUtcIso,
      );

  static const String currentVersion = 'DRUSIGHT-QR-1';
  static const String uriScheme = 'drusight';

  final String version;
  final String testId;
  final String recordHash;
  final String imageHash;
  final String previousRecordHash;
  final int sequenceNumber;
  final String signature;
  final String publicKeyId;
  final String publicKey;
  final String signatureScheme;
  final String canonicalFormatVersion;
  final String createdAtUtc;

  Map<String, Object?> toJson() => <String, Object?>{
        'v': version,
        'id': testId,
        'rh': recordHash,
        'ih': imageHash,
        'ph': previousRecordHash,
        'sq': sequenceNumber,
        'sg': signature,
        'kid': publicKeyId,
        'pk': publicKey,
        'sch': signatureScheme,
        'cf': canonicalFormatVersion,
        'ts': createdAtUtc,
      };

  /// Compact single-line encoding placed in the QR code.
  String encode() => '$uriScheme:v1:${base64Url.encode(
        utf8.encode(jsonEncode(toJson())),
      )}';

  /// Parses a scanned payload. Returns null for anything that is not a
  /// well-formed DruSight payload - a malformed scan is a failed
  /// verification, never a crash (master spec section 53, security tests).
  static QrPayload? decode(String scanned) {
    try {
      final String trimmed = scanned.trim();
      const String prefix = '$uriScheme:v1:';
      if (!trimmed.startsWith(prefix)) return null;

      final String encoded = trimmed.substring(prefix.length);
      final Object? decoded =
          jsonDecode(utf8.decode(base64Url.decode(_pad(encoded))));
      if (decoded is! Map<String, Object?>) return null;

      final Object? version = decoded['v'];
      if (version != currentVersion) return null;

      return QrPayload(
        version: version! as String,
        testId: decoded['id']! as String,
        recordHash: decoded['rh']! as String,
        imageHash: decoded['ih']! as String,
        previousRecordHash: decoded['ph']! as String,
        sequenceNumber: (decoded['sq']! as num).toInt(),
        signature: decoded['sg']! as String,
        publicKeyId: decoded['kid']! as String,
        publicKey: decoded['pk']! as String,
        signatureScheme: decoded['sch']! as String,
        canonicalFormatVersion: decoded['cf']! as String,
        createdAtUtc: decoded['ts']! as String,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on StateError {
      return null;
    }
  }

  static String _pad(String value) {
    final int remainder = value.length % 4;
    return remainder == 0 ? value : value + '=' * (4 - remainder);
  }
}
