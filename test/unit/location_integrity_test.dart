/// Location-integrity tests (master spec section 28).
///
/// The behaviour under test is deliberately conservative: the checker should
/// stay silent whenever a benign explanation is available, and speak only when
/// the numbers are genuinely implausible.
library;

import 'package:drusight/location/location_integrity.dart';
import 'package:drusight/models/location_fix.dart';
import 'package:flutter_test/flutter_test.dart';

LocationFix fix(
  double lat,
  double lon, {
  double accuracy = 5,
  required DateTime at,
}) =>
    LocationFix(
      latitude: lat,
      longitude: lon,
      accuracyMetres: accuracy,
      acquiredAtUtc: at,
      provider: 'test',
    );

void main() {
  const LocationIntegrityChecker checker = LocationIntegrityChecker();
  final DateTime t0 = DateTime.utc(2026, 9, 25, 7, 38);

  group('haversine distance', () {
    test('zero for identical points', () {
      final LocationFix a = fix(18.5204, 73.8567, at: t0);
      expect(LocationIntegrityChecker.haversineMetres(a, a), closeTo(0, 1e-6));
    });

    test('one degree of latitude is about 111 km', () {
      final double d = LocationIntegrityChecker.haversineMetres(
        fix(0, 0, at: t0),
        fix(1, 0, at: t0),
      );
      expect(d, closeTo(111195, 200));
    });

    test('matches a known city-pair distance', () {
      // Pune to Mumbai, roughly 120 km great-circle.
      final double d = LocationIntegrityChecker.haversineMetres(
        fix(18.5204, 73.8567, at: t0),
        fix(19.0760, 72.8777, at: t0),
      );
      expect(d, closeTo(119000, 4000));
    });

    test('is symmetric', () {
      final LocationFix a = fix(18.5204, 73.8567, at: t0);
      final LocationFix b = fix(19.0760, 72.8777, at: t0);
      expect(
        LocationIntegrityChecker.haversineMetres(a, b),
        closeTo(LocationIntegrityChecker.haversineMetres(b, a), 1e-6),
      );
    });
  });

  group('plausible cases stay silent', () {
    test('two tests at the same place minutes apart', () {
      final LocationIntegrityAssessment r = checker.assess(
        previous: fix(18.5204, 73.8567, at: t0),
        current: fix(18.5204, 73.8567,
            at: t0.add(const Duration(minutes: 7))),
      );
      expect(r.evaluated, isTrue);
      expect(r.plausible, isTrue);
    });

    test('ordinary vehicle travel', () {
      // ~10 km in 15 minutes, about 40 km/h.
      final LocationIntegrityAssessment r = checker.assess(
        previous: fix(18.5204, 73.8567, at: t0),
        current: fix(18.6100, 73.8567,
            at: t0.add(const Duration(minutes: 15))),
      );
      expect(r.plausible, isTrue);
      expect(r.impliedSpeedMps, lessThan(30));
    });

    test('GPS jitter at a stationary location does not trigger', () {
      // Two fixes 20 m apart, 2 seconds apart, each with 30 m accuracy. The
      // apparent 10 m/s is entirely within the combined uncertainty.
      final LocationIntegrityAssessment r = checker.assess(
        previous: fix(18.520400, 73.856700, accuracy: 30, at: t0),
        current: fix(18.520580, 73.856700,
            accuracy: 30, at: t0.add(const Duration(seconds: 2))),
      );
      expect(r.plausible, isTrue,
          reason: 'uncertainty must be subtracted before computing speed');
    });
  });

  group('implausible cases are flagged', () {
    test('a large jump in a short time', () {
      // Pune to Mumbai in 7 minutes: ~283 m/s.
      final LocationIntegrityAssessment r = checker.assess(
        previous: fix(18.5204, 73.8567, at: t0),
        current: fix(19.0760, 72.8777,
            at: t0.add(const Duration(minutes: 7))),
      );
      expect(r.evaluated, isTrue);
      expect(r.plausible, isFalse);
      expect(r.impliedSpeedMps, greaterThan(200));
      expect(r.distanceMetres, greaterThan(100000));
    });

    test('non-increasing time between records is itself flagged', () {
      final LocationIntegrityAssessment r = checker.assess(
        previous: fix(18.5204, 73.8567,
            at: t0.add(const Duration(minutes: 5))),
        current: fix(18.5210, 73.8570, at: t0),
      );
      expect(r.evaluated, isTrue);
      expect(r.plausible, isFalse);
      expect(r.impliedSpeedMps, isNull);
    });
  });

  group('declines to judge when it cannot', () {
    test('no previous fix', () {
      final LocationIntegrityAssessment r =
          checker.assess(previous: null, current: fix(18.5, 73.8, at: t0));
      expect(r.evaluated, isFalse);
      expect(r.plausible, isTrue);
      expect(r.skipReason, isNotNull);
    });

    test('no current fix', () {
      final LocationIntegrityAssessment r =
          checker.assess(previous: fix(18.5, 73.8, at: t0), current: null);
      expect(r.evaluated, isFalse);
    });

    test('a low-accuracy fix is not used for a speed argument', () {
      final LocationIntegrityAssessment r = checker.assess(
        previous: fix(18.5204, 73.8567, accuracy: 500, at: t0),
        current: fix(19.0760, 72.8777,
            accuracy: 5, at: t0.add(const Duration(minutes: 7))),
      );
      expect(r.evaluated, isFalse);
      expect(r.skipReason, contains('accuracy'));
    });
  });

  test('the explanation list leads with benign causes', () {
    // The app must never accuse an operator. Manipulation is listed, but last.
    const List<String> reasons =
        LocationIntegrityAssessment.possibleExplanations;
    expect(reasons.first.toLowerCase(), contains('gps'));
    expect(reasons.last.toLowerCase(), contains('manipulation'));
    expect(reasons.length, greaterThan(4));
  });
}
