/// Deterministic, profile-driven interpretation of a calibrated colour
/// (master spec sections 25, 62).
///
/// Runs independently of any model, so there is always an auditable path from
/// a measured Lab value to an outcome that a reviewer can check by hand.
library;

import '../cv/colour_space.dart';
import '../models/analysis_result.dart';
import '../models/enums.dart';
import '../models/kit_profile.dart';

class RuleInterpreter {
  const RuleInterpreter();

  /// Assigns the measured colour to the nearest decision region by CIEDE2000.
  ///
  /// Returns INCONCLUSIVE when the colour is outside every region's radius:
  /// an unrecognised colour is not evidence of a negative result, it is
  /// evidence that the kit profile does not describe what was observed.
  RuleOutcome interpret(Lab measured, KitProfile profile) {
    if (profile.decisionRegions.isEmpty) {
      return const RuleOutcome(
        result: TestResult.inconclusive,
        matchedRegionLabel: null,
        distanceToMatchedRegion: null,
        borderline: false,
        distanceToNearestOtherRegion: null,
      );
    }

    ColourDecisionRegion? nearest;
    double nearestDistance = double.infinity;
    double secondDistance = double.infinity;

    for (final ColourDecisionRegion region in profile.decisionRegions) {
      final double d = ColourSpace.deltaE2000(
        measured,
        Lab(region.centreLab[0], region.centreLab[1], region.centreLab[2]),
      );
      if (d < nearestDistance) {
        secondDistance = nearestDistance;
        nearestDistance = d;
        nearest = region;
      } else if (d < secondDistance) {
        secondDistance = d;
      }
    }

    if (nearest == null || nearestDistance > nearest.radiusDeltaE) {
      return RuleOutcome(
        result: TestResult.inconclusive,
        matchedRegionLabel: null,
        distanceToMatchedRegion:
            nearestDistance.isFinite ? nearestDistance : null,
        borderline: false,
        distanceToNearestOtherRegion:
            secondDistance.isFinite ? secondDistance : null,
      );
    }

    // Borderline in either of two senses: close to the outer edge of its own
    // region, or nearly as close to a different region. Both mean the colour
    // does not separate the outcomes cleanly.
    final double marginToEdge = nearest.radiusDeltaE - nearestDistance;
    final double separation = secondDistance - nearestDistance;
    final bool borderline = marginToEdge < nearest.borderlineMarginDeltaE ||
        (secondDistance.isFinite &&
            separation < nearest.borderlineMarginDeltaE);

    return RuleOutcome(
      result: TestResult.fromWire(nearest.label),
      matchedRegionLabel: nearest.label,
      distanceToMatchedRegion: nearestDistance,
      borderline: borderline,
      distanceToNearestOtherRegion:
          secondDistance.isFinite ? secondDistance : null,
    );
  }
}
