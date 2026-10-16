/// Canonical JSON serialization (master spec sections 32, 48).
///
/// A hash is only meaningful if the same logical record always produces the
/// same bytes. Dart's `jsonEncode` does not guarantee that: map iteration
/// order depends on insertion order, and double formatting varies. This module
/// pins both.
///
/// Rules (format version [Versions.canonicalFormat]):
///   1. Object keys are sorted by UTF-16 code unit, ascending.
///   2. Keys whose value is null are OMITTED. Absent and null are the same
///      thing, so they must not hash differently.
///   3. No insignificant whitespace.
///   4. Integers serialize without a decimal point.
///   5. Non-integral doubles serialize with exactly [_doubleDecimals] decimal
///      places. Floating-point noise in the last bits of a measurement must
///      not change a record hash; rounding to a fixed precision makes the
///      encoding reproducible across devices and architectures.
///   6. Non-finite doubles are rejected: NaN has no canonical form, and
///      silently substituting one would corrupt the evidence.
///   7. Strings use standard JSON escaping with \uXXXX for control characters.
///
/// Changing ANY of these rules changes every record hash ever produced, so the
/// format version must be bumped and old records verified under their own
/// recorded version.
library;

import 'dart:convert';

import '../config/versions.dart';

class CanonicalJsonException implements Exception {
  CanonicalJsonException(this.message);
  final String message;
  @override
  String toString() => 'CanonicalJsonException: $message';
}

class CanonicalJson {
  const CanonicalJson._();

  /// Decimal places used for non-integral doubles. Six places is far finer
  /// than any measurement this system produces, while staying clear of
  /// double-precision representation noise.
  static const int _doubleDecimals = 6;

  static String get formatVersion => Versions.canonicalFormat;

  /// Encodes [value] to its canonical string form.
  static String encode(Object? value) {
    final StringBuffer buffer = StringBuffer();
    _write(value, buffer);
    return buffer.toString();
  }

  /// Canonical UTF-8 bytes, which is what actually gets hashed and signed.
  static List<int> encodeToBytes(Object? value) => utf8.encode(encode(value));

  static void _write(Object? value, StringBuffer out) {
    if (value == null) {
      out.write('null');
    } else if (value is bool) {
      out.write(value ? 'true' : 'false');
    } else if (value is int) {
      out.write(value.toString());
    } else if (value is double) {
      out.write(_formatDouble(value));
    } else if (value is String) {
      _writeString(value, out);
    } else if (value is List<Object?>) {
      out.write('[');
      for (int i = 0; i < value.length; i++) {
        if (i > 0) out.write(',');
        _write(value[i], out);
      }
      out.write(']');
    } else if (value is Map) {
      _writeMap(value, out);
    } else {
      throw CanonicalJsonException(
        'Unsupported type in canonical record: ${value.runtimeType}. '
        'Convert it to a primitive, List or Map before serialization.',
      );
    }
  }

  static void _writeMap(Map<Object?, Object?> map, StringBuffer out) {
    final List<String> keys = <String>[];
    for (final Object? k in map.keys) {
      if (k is! String) {
        throw CanonicalJsonException(
          'Canonical objects require String keys; found ${k.runtimeType}.',
        );
      }
      // Rule 2: drop null-valued keys entirely.
      if (map[k] == null) continue;
      keys.add(k);
    }
    keys.sort();

    out.write('{');
    for (int i = 0; i < keys.length; i++) {
      if (i > 0) out.write(',');
      _writeString(keys[i], out);
      out.write(':');
      _write(map[keys[i]], out);
    }
    out.write('}');
  }

  static String _formatDouble(double value) {
    if (value.isNaN || value.isInfinite) {
      throw CanonicalJsonException(
        'Non-finite number ($value) cannot be canonically encoded. The '
        'producing code must emit null or omit the field instead.',
      );
    }
    // Integral doubles encode as integers so 1.0 and 1 hash identically.
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    String s = value.toStringAsFixed(_doubleDecimals);
    // Normalise "-0.000000" to "0".
    if (double.parse(s) == 0) return '0';
    // Trim trailing zeros but keep at least one decimal digit.
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  static void _writeString(String value, StringBuffer out) {
    out.write('"');
    for (final int rune in value.runes) {
      switch (rune) {
        case 0x22:
          out.write(r'\"');
        case 0x5C:
          out.write(r'\\');
        case 0x08:
          out.write(r'\b');
        case 0x0C:
          out.write(r'\f');
        case 0x0A:
          out.write(r'\n');
        case 0x0D:
          out.write(r'\r');
        case 0x09:
          out.write(r'\t');
        default:
          if (rune < 0x20) {
            out.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
          } else {
            out.writeCharCode(rune);
          }
      }
    }
    out.write('"');
  }
}
