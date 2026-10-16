/// SHA-256 helpers for image and record hashing (master spec sections 31, 32).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'canonical_json.dart';

class Hashing {
  const Hashing._();

  static const String algorithm = 'SHA-256';

  /// Hex-encoded SHA-256 of raw bytes.
  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  /// Hex-encoded SHA-256 of a UTF-8 string.
  static String sha256OfString(String value) =>
      sha256Hex(utf8.encode(value));

  /// Hashes a file by streaming it, so a large original evidence image is
  /// never fully materialised in memory.
  static Future<String> sha256OfFile(File file) async {
    final _DigestCollector collector = _DigestCollector();
    final ByteConversionSink sink = sha256.startChunkedConversion(collector);
    await for (final List<int> chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();

    final Digest? digest = collector.digest;
    if (digest == null) {
      throw StateError('Hashing produced no digest for ${file.path}');
    }
    return digest.toString();
  }

  /// Hash of a canonically-serialized object.
  static String sha256OfCanonical(Object? value) =>
      sha256Hex(CanonicalJson.encodeToBytes(value));

  /// Constant-time comparison of two hex digests.
  ///
  /// Verification results can be observed by an attacker, so comparisons on
  /// integrity values do not short-circuit on the first differing byte.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Convenience for hashing an in-memory image buffer.
  static String sha256OfImageBytes(Uint8List bytes) => sha256Hex(bytes);
}

class _DigestCollector implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
