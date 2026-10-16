/// Location acquisition (master spec section 28).
///
/// Location is best-effort: a test with no fix is a valid test with an absent
/// location, recorded as such. The app never substitutes a cached, estimated
/// or default coordinate, because a fabricated location in an evidence record
/// is worse than a missing one.
library;

import 'package:geolocator/geolocator.dart';

import '../models/location_fix.dart';

abstract class LocationService {
  /// Returns a fix, or null if permission is denied, services are off, or the
  /// fix times out.
  Future<LocationFix?> currentFix({Duration timeout});
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationFix?> currentFix({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: timeout,
      );

      return LocationFix(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMetres: position.accuracy,
        acquiredAtUtc: position.timestamp.toUtc(),
        provider: position.isMocked ? 'mocked' : null,
      );
    } on Exception {
      // Timeouts and platform errors mean "no fix", not "crash the test".
      return null;
    }
  }
}
