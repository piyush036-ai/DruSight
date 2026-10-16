/// Adaptive colour calibration against a reference card (master spec 12).
///
/// The camera does not measure colour: it measures scene radiance filtered
/// through an unknown illuminant, an unknown white balance and an unknown
/// tone curve. The reference card gives us a set of colours whose true values
/// we know, so we can estimate that combined transform and invert it.
///
/// Method: fit a 3x4 affine transform (3x3 mixing matrix plus per-channel
/// bias) in LINEAR RGB from observed patch colours to known patch colours.
/// Linear light is the right domain for this: illumination scaling and sensor
/// cross-talk are linear there, and are not linear in gamma-encoded sRGB.
///
/// The fit's residual, expressed as mean CIEDE2000 across the patches, is the
/// calibration-quality figure. If it exceeds the kit profile's threshold the
/// pipeline must report INCONCLUSIVE / RECAPTURE rather than analysing an
/// image it cannot trust.
library;

import 'colour_space.dart';
import 'linear_algebra.dart';

/// A single reference patch: what we expected, and what the camera saw.
class PatchObservation {
  const PatchObservation({
    required this.patchId,
    required this.expected,
    required this.observed,
  });

  final String patchId;

  /// Known sRGB value of the printed patch, from the reference-card spec.
  final Rgb expected;

  /// Mean sRGB value measured inside the detected patch in this frame.
  final Rgb observed;
}

/// Outcome of a calibration attempt. Either [transform] is non-null and the
/// residuals are meaningful, or [failureReason] explains why no usable
/// transform could be estimated.
class CalibrationResult {
  const CalibrationResult({
    required this.succeeded,
    required this.calibrationVersion,
    this.transform,
    this.meanResidualDeltaE = double.nan,
    this.maxResidualDeltaE = double.nan,
    this.perPatchResidualDeltaE = const <String, double>{},
    this.patchCount = 0,
    this.failureReason,
  });

  factory CalibrationResult.failed(String reason, String version) =>
      CalibrationResult(
        succeeded: false,
        calibrationVersion: version,
        failureReason: reason,
      );

  final bool succeeded;
  final String calibrationVersion;

  /// Row-major 3x4 matrix in linear RGB: [r; g; b] = M * [r, g, b, 1]^T.
  final List<List<double>>? transform;

  /// Mean CIEDE2000 between corrected patches and their known values.
  /// This is a residual of the fit, not an accuracy claim about the test
  /// region itself.
  final double meanResidualDeltaE;
  final double maxResidualDeltaE;
  final Map<String, double> perPatchResidualDeltaE;
  final int patchCount;
  final String? failureReason;

  /// Applies the fitted transform to a measured sRGB colour.
  ///
  /// Throws [StateError] if calibration failed - callers must check
  /// [succeeded] first rather than silently analysing uncalibrated colour.
  Rgb apply(Rgb measured) {
    final List<List<double>>? m = transform;
    if (!succeeded || m == null) {
      throw StateError(
        'Cannot apply a failed calibration. Reason: '
        '${failureReason ?? "unknown"}',
      );
    }

    final double lr = ColourSpace.srgbToLinear(measured.r);
    final double lg = ColourSpace.srgbToLinear(measured.g);
    final double lb = ColourSpace.srgbToLinear(measured.b);

    final double outR = m[0][0] * lr + m[0][1] * lg + m[0][2] * lb + m[0][3];
    final double outG = m[1][0] * lr + m[1][1] * lg + m[1][2] * lb + m[1][3];
    final double outB = m[2][0] * lr + m[2][1] * lg + m[2][2] * lb + m[2][3];

    return Rgb(
      ColourSpace.linearToSrgb(outR),
      ColourSpace.linearToSrgb(outG),
      ColourSpace.linearToSrgb(outB),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'succeeded': succeeded,
        'calibrationVersion': calibrationVersion,
        'patchCount': patchCount,
        'meanResidualDeltaE': meanResidualDeltaE.isNaN
            ? null
            : double.parse(meanResidualDeltaE.toStringAsFixed(4)),
        'maxResidualDeltaE': maxResidualDeltaE.isNaN
            ? null
            : double.parse(maxResidualDeltaE.toStringAsFixed(4)),
        'failureReason': failureReason,
      };
}

class ColourCalibrator {
  const ColourCalibrator({required this.calibrationVersion});

  final String calibrationVersion;

  /// Minimum patches needed to fit 4 coefficients per channel. Four is the
  /// bare algebraic minimum; a real card should provide considerably more so
  /// the residual means something.
  static const int minimumPatches = 4;

  /// Estimates the colour transform from observed reference patches.
  CalibrationResult fit(List<PatchObservation> patches) {
    if (patches.length < minimumPatches) {
      return CalibrationResult.failed(
        'Only ${patches.length} reference patches detected; at least '
        '$minimumPatches are required.',
        calibrationVersion,
      );
    }

    // Design matrix in linear RGB with a bias column.
    final List<List<double>> design = <List<double>>[];
    final List<double> targetR = <double>[];
    final List<double> targetG = <double>[];
    final List<double> targetB = <double>[];

    for (final PatchObservation p in patches) {
      design.add(<double>[
        ColourSpace.srgbToLinear(p.observed.r),
        ColourSpace.srgbToLinear(p.observed.g),
        ColourSpace.srgbToLinear(p.observed.b),
        1.0,
      ]);
      targetR.add(ColourSpace.srgbToLinear(p.expected.r));
      targetG.add(ColourSpace.srgbToLinear(p.expected.g));
      targetB.add(ColourSpace.srgbToLinear(p.expected.b));
    }

    final List<double>? rowR = LinearAlgebra.leastSquares(design, targetR);
    final List<double>? rowG = LinearAlgebra.leastSquares(design, targetG);
    final List<double>? rowB = LinearAlgebra.leastSquares(design, targetB);

    if (rowR == null || rowG == null || rowB == null) {
      return CalibrationResult.failed(
        'Colour transform could not be estimated; reference patches are '
        'degenerate or insufficiently distinct.',
        calibrationVersion,
      );
    }

    final List<List<double>> transform = <List<double>>[rowR, rowG, rowB];

    // Residuals: apply the fit back to the observations and measure how far
    // each corrected patch sits from its known value.
    final CalibrationResult provisional = CalibrationResult(
      succeeded: true,
      calibrationVersion: calibrationVersion,
      transform: transform,
      patchCount: patches.length,
    );

    final Map<String, double> perPatch = <String, double>{};
    final List<double> residuals = <double>[];
    for (final PatchObservation p in patches) {
      final Rgb corrected = provisional.apply(p.observed);
      final double dE = ColourSpace.deltaE2000(
        ColourSpace.rgbToLab(corrected),
        ColourSpace.rgbToLab(p.expected),
      );
      perPatch[p.patchId] = dE;
      residuals.add(dE);
    }

    return CalibrationResult(
      succeeded: true,
      calibrationVersion: calibrationVersion,
      transform: transform,
      meanResidualDeltaE: LinearAlgebra.mean(residuals),
      maxResidualDeltaE: residuals.reduce((double a, double b) => a > b ? a : b),
      perPatchResidualDeltaE: perPatch,
      patchCount: patches.length,
    );
  }
}
