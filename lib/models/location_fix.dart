/// A location observation and the integrity assessment derived from it
/// (master spec section 28).
library;

class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
    required this.acquiredAtUtc,
    required this.provider,
  });

  factory LocationFix.fromJson(Map<String, Object?> json) => LocationFix(
        latitude: (json['latitude']! as num).toDouble(),
        longitude: (json['longitude']! as num).toDouble(),
        accuracyMetres: (json['accuracyMetres']! as num).toDouble(),
        acquiredAtUtc: DateTime.parse(json['acquiredAtUtc']! as String),
        provider: json['provider'] as String?,
      );

  final double latitude;
  final double longitude;
  final double accuracyMetres;
  final DateTime acquiredAtUtc;

  /// Provider name where the platform exposes one (e.g. "gps", "fused").
  final String? provider;

  Map<String, Object?> toJson() => <String, Object?>{
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMetres': accuracyMetres,
        'acquiredAtUtc': acquiredAtUtc.toUtc().toIso8601String(),
        'provider': provider,
      };
}

/// Result of comparing a new fix against the previous one from the same
/// device/operator.
///
/// This detects an INCONSISTENCY. It does not, and cannot, determine the
/// cause: poor fix, clock drift, device fault and genuine fast travel all
/// produce the same signal.
class LocationIntegrityAssessment {
  const LocationIntegrityAssessment({
    required this.evaluated,
    required this.plausible,
    this.distanceMetres,
    this.elapsedSeconds,
    this.impliedSpeedMps,
    this.skipReason,
  });

  factory LocationIntegrityAssessment.notEvaluated(String reason) =>
      LocationIntegrityAssessment(
        evaluated: false,
        plausible: true,
        skipReason: reason,
      );

  final bool evaluated;
  final bool plausible;
  final double? distanceMetres;
  final double? elapsedSeconds;
  final double? impliedSpeedMps;
  final String? skipReason;

  /// Neutral phrasing shown to the operator. Deliberately lists benign causes
  /// first: the app must not accuse anyone of manipulation.
  static const List<String> possibleExplanations = <String>[
    'Poor or degraded GPS fix',
    'Location acquired indoors or in an urban canyon',
    'Device clock adjustment between records',
    'Legitimate rapid travel (e.g. vehicle or aircraft)',
    'Device or sensor fault',
    'Record synchronisation ordering',
    'Possible manipulation - requires human review',
  ];

  Map<String, Object?> toJson() => <String, Object?>{
        'evaluated': evaluated,
        'plausible': plausible,
        'distanceMetres': distanceMetres,
        'elapsedSeconds': elapsedSeconds,
        'impliedSpeedMps': impliedSpeedMps,
        'skipReason': skipReason,
      };
}
