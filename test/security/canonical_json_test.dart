/// Canonical-serialization tests.
///
/// These protect the property every hash in the system depends on: the same
/// logical record must always produce the same bytes. A regression here would
/// silently invalidate every stored record's hash.
library;

import 'package:drusight/security/canonical_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('determinism', () {
    test('key insertion order does not change the output', () {
      final String a = CanonicalJson.encode(<String, Object?>{
        'zebra': 1,
        'alpha': 2,
        'middle': 3,
      });
      final String b = CanonicalJson.encode(<String, Object?>{
        'middle': 3,
        'alpha': 2,
        'zebra': 1,
      });
      expect(a, equals(b));
      expect(a, equals('{"alpha":2,"middle":3,"zebra":1}'));
    });

    test('nested objects are sorted at every level', () {
      expect(
        CanonicalJson.encode(<String, Object?>{
          'outer': <String, Object?>{'z': 1, 'a': 2},
          'first': true,
        }),
        equals('{"first":true,"outer":{"a":2,"z":1}}'),
      );
    });

    test('array order is preserved', () {
      // Sorting arrays would destroy meaning; only object KEYS are sorted.
      expect(CanonicalJson.encode(<Object?>[3, 1, 2]), equals('[3,1,2]'));
    });

    test('repeated encoding is byte-identical', () {
      final Map<String, Object?> record = <String, Object?>{
        'result': 'POSITIVE',
        'measurements': <String, Object?>{
          'lab': <double>[52.13, -3.4, 18.9],
          'deltaE': 4.219,
        },
        'anomalies': <String>['A', 'B'],
      };
      final String first = CanonicalJson.encode(record);
      for (int i = 0; i < 20; i++) {
        expect(CanonicalJson.encode(record), equals(first));
      }
    });
  });

  group('null handling', () {
    test('null-valued keys are omitted', () {
      // Absent and null must hash identically, otherwise an optional field
      // being explicitly set to null would change a record hash.
      expect(
        CanonicalJson.encode(<String, Object?>{'a': 1, 'b': null}),
        equals('{"a":1}'),
      );
    });

    test('omitting a key and setting it null produce the same bytes', () {
      expect(
        CanonicalJson.encode(<String, Object?>{'x': 'v', 'optional': null}),
        equals(CanonicalJson.encode(<String, Object?>{'x': 'v'})),
      );
    });

    test('a null inside an array is preserved', () {
      // Dropping it would change the array's length and meaning.
      expect(CanonicalJson.encode(<Object?>[1, null, 2]), equals('[1,null,2]'));
    });
  });

  group('number formatting', () {
    test('integral doubles encode as integers', () {
      expect(
        CanonicalJson.encode(<String, Object?>{'v': 1.0}),
        equals('{"v":1}'),
      );
      expect(
        CanonicalJson.encode(<String, Object?>{'v': 1}),
        equals('{"v":1}'),
      );
    });

    test('1.0 and 1 hash identically', () {
      expect(
        CanonicalJson.encode(<String, Object?>{'v': 1.0}),
        equals(CanonicalJson.encode(<String, Object?>{'v': 1})),
      );
    });

    test('non-integral doubles are rounded to a fixed precision', () {
      // Floating-point noise in the last bits of a measurement must not
      // change a record hash across devices or architectures.
      expect(
        CanonicalJson.encode(<String, Object?>{'v': 0.1 + 0.2}),
        equals(CanonicalJson.encode(<String, Object?>{'v': 0.3})),
      );
    });

    test('negative zero normalises', () {
      expect(
        CanonicalJson.encode(<String, Object?>{'v': -0.0}),
        equals('{"v":0}'),
      );
    });

    test('trailing zeros are trimmed', () {
      expect(
        CanonicalJson.encode(<String, Object?>{'v': 2.50}),
        equals('{"v":2.5}'),
      );
    });

    test('NaN and infinity are rejected rather than encoded', () {
      // Substituting a placeholder would corrupt the evidence silently.
      expect(
        () => CanonicalJson.encode(<String, Object?>{'v': double.nan}),
        throwsA(isA<CanonicalJsonException>()),
      );
      expect(
        () => CanonicalJson.encode(<String, Object?>{'v': double.infinity}),
        throwsA(isA<CanonicalJsonException>()),
      );
    });
  });

  group('string escaping', () {
    test('quotes and backslashes are escaped', () {
      expect(
        CanonicalJson.encode(<String, Object?>{'k': 'a"b\\c'}),
        equals(r'{"k":"a\"b\\c"}'),
      );
    });

    test('control characters use a unicode escape', () {
      // The control character is built rather than written as a literal: a
      // raw 0x01 byte in this source file would make the test assert the
      // opposite of what JSON requires.
      final String encoded = CanonicalJson.encode(
        <String, Object?>{'k': 'a${String.fromCharCode(1)}b'},
      );
      expect(encoded, equals('{"k":"a\\u0001b"}'));
      // And the raw byte must not survive into the output.
      expect(encoded.contains(String.fromCharCode(1)), isFalse);
    });

    test('newlines and tabs use their short escapes', () {
      final String encoded = CanonicalJson.encode(
        <String, Object?>{'k': 'a${String.fromCharCode(10)}b'
            '${String.fromCharCode(9)}c'},
      );
      expect(encoded, equals('{"k":"a\\nb\\tc"}'));
    });

    test('non-ASCII characters survive intact', () {
      final String encoded =
          CanonicalJson.encode(<String, Object?>{'k': 'naive unicode'});
      expect(encoded, contains('naive unicode'));
    });

    test('keys are escaped the same way as values', () {
      expect(
        CanonicalJson.encode(<String, Object?>{'a"b': 1}),
        equals(r'{"a\"b":1}'),
      );
    });
  });

  group('rejections', () {
    test('non-string keys are rejected', () {
      expect(
        () => CanonicalJson.encode(<Object?, Object?>{1: 'a'}),
        throwsA(isA<CanonicalJsonException>()),
      );
    });

    test('unsupported types are rejected rather than stringified', () {
      expect(
        () => CanonicalJson.encode(<String, Object?>{'d': DateTime.now()}),
        throwsA(isA<CanonicalJsonException>()),
      );
    });
  });
}
