/// Location-integrity anomaly detection (master spec section 28).
///
/// Scope statement, because this is easy to overclaim: this module compares
/// two consecutive location fixes from the same device and reports whether the
/// implied travel speed is physically plausible. It does NOT detect GPS
/// spoofing. A spoofed fix that moves slowly is indistinguishable from a real
/// one here, and a genuine fix after a flight will look implausible. The
/// output is an inconsistency flag for a human to consider, nothing more.
library;

import 'dart:math' as math;

import '../config/app_config.dart';
import '../models/location_fix.dart';

class LocationIntegrityChecker {
  const LocationIntegrityChecker({
    this.maxSpeedMps = AppConfig.maxPlausibleSpeedMps,
    this.accuracyCeilingMetres = AppConfig.locationAccuracyCeilingMetres,
  });

  final double maxSpeedMps;
  final double accuracyCeilingMetres;

  /// Mean Earth radius in metres.
  static const double _earthRadiusM = 6371008.8;

  LocationIntegrityAssessment assess({
    required LocationFix? previous,
    required LocationFix? current,
  }) {
    if (previous == null || current == null) {
      return LocationIntegrityAssessment.notEvaluated(
        'No previous or current location fix available for comparison.',
      );
    }

    // A fix with large reported error cannot support a speed argument: the
    // apparent movement may be entirely measurement uncertainty.
    if (previous.accuracyMetres > accuracyCeilingMetres ||
        current.accuracyMetres > accuracyCeilingMetres) {
      return LocationIntegrityAssessment.notEvaluated(
        'One or both fixes have accuracy worse than '
        '${accuracyCeilingMetres.toStringAsFixed(0)} m; travel speed cannot '
        'be assessed meaningfully.',
      );
    }

    final double elapsed = current.acquiredAtUtc
        .difference(previous.acquiredAtUtc)
        .inMilliseconds /
        1000.0;

    if (elapsed <= 0) {
      // Non-increasing time between consecutive records is itself the
      // anomaly, and no speed can be computed from it.
      return LocationIntegrityAssessment(
        evaluated: true,
        plausible: false,
        distanceMetres: haversineMetres(previous, current),
        elapsedSeconds: elapsed,
        impliedSpeedMps: null,
      );
    }

    final double distance = haversineMetres(previous, current);

    // Subtract the combined positional uncertainty before computing speed, so
    // two noisy fixes at the same place do not read as movement.
    final double uncertainty =
        previous.accuracyMetres + current.accuracyMetres;
    final double effectiveDistance = math.max(0.0, distance - uncertainty);
    final double speed = effectiveDistance / elapsed;

    return LocationIntegrityAssessment(
      evaluated: true,
      plausible: speed <= maxSpeedMps,
      distanceMetres: distance,
      elapsedSeconds: elapsed,
      impliedSpeedMps: speed,
    );
  }

  /// Great-circle distance in metres between two fixes.
  static double haversineMetres(LocationFix a, LocationFix b) {
    final double lat1 = _radians(a.latitude);
    final double lat2 = _radians(b.latitude);
    final double dLat = lat2 - lat1;
    final double dLon = _radians(b.longitude - a.longitude);

    final double h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(h)));
  }

  static double _radians(double degrees) => degrees * math.pi / 180.0;
}
