/// Time-resolved reaction measurements (master spec section 17).
///
/// A reaction fingerprint is an ADDITIONAL evidence feature. It describes how
/// a colour evolved; it is not by itself a chemical identification.
library;

import '../cv/colour_space.dart';

/// One frame in the timed sequence.
class ReactionSample {
  const ReactionSample({
    required this.offsetSeconds,
    required this.capturedAtUtc,
    required this.calibratedLab,
    required this.calibratedHsv,
    required this.imageHash,
  });

  final int offsetSeconds;
  final DateTime capturedAtUtc;
  final Lab calibratedLab;
  final Hsv calibratedHsv;

  /// Each frame in the sequence is hashed independently so the whole series is
  /// tamper-evident, not just the final frame.
  final String imageHash;

  Map<String, Object?> toJson() => <String, Object?>{
        'offsetSeconds': offsetSeconds,
        'capturedAtUtc': capturedAtUtc.toUtc().toIso8601String(),
        'lab': calibratedLab.toJson(),
        'hsv': calibratedHsv.toJson(),
        'imageHash': imageHash,
      };
}

/// Derived description of the trajectory across the sequence.
class ReactionTrajectory {
  const ReactionTrajectory({
    required this.samples,
    required this.totalDeltaE,
    required this.netHueShiftDegrees,
    required this.netSaturationChange,
    required this.netBrightnessChange,
    required this.maxStepDeltaE,
    required this.stabilised,
    required this.stabilisedAtOffsetSeconds,
    required this.monotonicHue,
  });

  /// Empty when the kit profile does not define a timed window.
  final List<ReactionSample> samples;

  /// CIEDE2000 between the first and last sample.
  final double totalDeltaE;

  final double netHueShiftDegrees;
  final double netSaturationChange;
  final double netBrightnessChange;

  /// Largest CIEDE2000 between consecutive samples. A large final step means
  /// the reaction was still moving when observation ended.
  final double maxStepDeltaE;

  /// True when the last consecutive step fell below the profile's stability
  /// threshold.
  final bool stabilised;
  final int? stabilisedAtOffsetSeconds;

  /// Whether hue moved consistently in one direction. Oscillating hue usually
  /// indicates a lighting or framing problem rather than chemistry.
  final bool monotonicHue;

  bool get isEmpty => samples.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'samples': samples.map((ReactionSample s) => s.toJson()).toList(),
        'totalDeltaE': totalDeltaE,
        'netHueShiftDegrees': netHueShiftDegrees,
        'netSaturationChange': netSaturationChange,
        'netBrightnessChange': netBrightnessChange,
        'maxStepDeltaE': maxStepDeltaE,
        'stabilised': stabilised,
        'stabilisedAtOffsetSeconds': stabilisedAtOffsetSeconds,
        'monotonicHue': monotonicHue,
      };

  static const ReactionTrajectory none = ReactionTrajectory(
    samples: <ReactionSample>[],
    totalDeltaE: 0,
    netHueShiftDegrees: 0,
    netSaturationChange: 0,
    netBrightnessChange: 0,
    maxStepDeltaE: 0,
    stabilised: false,
    stabilisedAtOffsetSeconds: null,
    monotonicHue: false,
  );
}
