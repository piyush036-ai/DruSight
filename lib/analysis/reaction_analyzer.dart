/// Reaction-fingerprint analysis (master spec section 17).
///
/// Consumes the per-frame calibrated colours from a timed capture sequence and
/// describes how they moved. The output is an additional evidence feature; it
/// is never treated as a chemical identification on its own.
library;

import 'dart:math' as math;

import '../cv/colour_space.dart';
import '../models/kit_profile.dart';
import '../models/reaction_series.dart';

class ReactionAnalyzer {
  const ReactionAnalyzer();

  ReactionTrajectory analyse(
    List<ReactionSample> samples,
    KitProfile profile,
  ) {
    if (samples.length < 2) return ReactionTrajectory.none;

    final List<ReactionSample> ordered = List<ReactionSample>.of(samples)
      ..sort((ReactionSample a, ReactionSample b) =>
          a.offsetSeconds.compareTo(b.offsetSeconds));

    final ReactionSample first = ordered.first;
    final ReactionSample last = ordered.last;

    final double totalDeltaE =
        ColourSpace.deltaE2000(first.calibratedLab, last.calibratedLab);

    // Step-wise deltas drive both stability and monotonicity.
    final List<double> stepDeltas = <double>[];
    final List<double> hueSteps = <double>[];
    for (int i = 1; i < ordered.length; i++) {
      stepDeltas.add(
        ColourSpace.deltaE2000(
          ordered[i - 1].calibratedLab,
          ordered[i].calibratedLab,
        ),
      );
      hueSteps.add(
        ColourSpace.hueDifference(
          ordered[i - 1].calibratedHsv.h,
          ordered[i].calibratedHsv.h,
        ),
      );
    }

    final double threshold = profile.reactionWindow.stabilityDeltaE;

    // Stabilised means the FINAL step was small. An early small step followed
    // by a large one is not stability, it is a pause.
    final bool stabilised = stepDeltas.last <= threshold;

    int? stabilisedAt;
    if (stabilised) {
      // Walk back to the earliest point from which every subsequent step
      // stayed under the threshold.
      int index = stepDeltas.length - 1;
      while (index > 0 && stepDeltas[index - 1] <= threshold) {
        index--;
      }
      stabilisedAt = ordered[index + 1].offsetSeconds;
    }

    // Monotonic hue: ignore steps too small to carry a reliable direction,
    // then require the remaining ones to agree in sign.
    const double hueNoiseFloor = 2.0;
    final List<double> significantHueSteps = hueSteps
        .where((double d) => d.abs() >= hueNoiseFloor)
        .toList(growable: false);
    final bool monotonicHue = significantHueSteps.isEmpty ||
        significantHueSteps.every((double d) => d > 0) ||
        significantHueSteps.every((double d) => d < 0);

    return ReactionTrajectory(
      samples: ordered,
      totalDeltaE: totalDeltaE,
      netHueShiftDegrees: ColourSpace.hueDifference(
        first.calibratedHsv.h,
        last.calibratedHsv.h,
      ),
      netSaturationChange: last.calibratedHsv.s - first.calibratedHsv.s,
      netBrightnessChange: last.calibratedHsv.v - first.calibratedHsv.v,
      maxStepDeltaE: stepDeltas.reduce(math.max),
      stabilised: stabilised,
      stabilisedAtOffsetSeconds: stabilisedAt,
      monotonicHue: monotonicHue,
    );
  }
}
