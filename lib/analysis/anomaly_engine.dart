/// Anomaly detection (master spec section 27).
///
/// Every anomaly is derived from a measurement compared against a versioned
/// threshold. Nothing here infers intent, and nothing here guesses a cause.
library;

import '../cv/calibration.dart';
import '../cv/region_detector.dart';
import '../models/analysis_result.dart';
import '../models/anomaly.dart';
import '../models/capture_quality.dart';
import '../models/enums.dart';
import '../models/kit_profile.dart';
import '../models/location_fix.dart';
import '../models/reaction_series.dart';

class AnomalyEngine {
  const AnomalyEngine();

  List<Anomaly> evaluate({
    required KitProfile profile,
    required CaptureQuality quality,
    required RegionDetection regionDetection,
    required CalibrationResult calibration,
    required ReactionTrajectory trajectory,
    required ClassifierOutput classifier,
    required LocationIntegrityAssessment locationIntegrity,
    required bool locationAvailable,
  }) {
    final QualityThresholds t = profile.qualityThresholds;
    final List<Anomaly> found = <Anomaly>[];

    // Note: reference card anomalies are not applicable — calibration is
    // always performed using the built-in digital card displayed on screen.

    // --- Calibration --------------------------------------------------------
    if (!calibration.succeeded) {
      found.add(
        Anomaly(
          code: AnomalyCode.calibrationFailed,
          severity: AnomalySeverity.blocking,
          detail: calibration.failureReason ??
              'Colour calibration could not be estimated.',
        ),
      );
    } else if (calibration.meanResidualDeltaE >
        t.maxCalibrationResidualDeltaE) {
      found.add(
        Anomaly(
          code: AnomalyCode.calibrationFailed,
          severity: AnomalySeverity.blocking,
          detail: 'Calibration residual exceeds the profile limit; measured '
              'colour cannot be trusted.',
          measuredValue: calibration.meanResidualDeltaE,
          thresholdValue: t.maxCalibrationResidualDeltaE,
        ),
      );
    }

    // --- Exposure / focus / glare -------------------------------------------
    if (quality.blurVariance < t.minBlurVariance) {
      found.add(
        Anomaly(
          code: AnomalyCode.excessiveBlur,
          severity: AnomalySeverity.blocking,
          detail: 'Image sharpness is below the profile threshold.',
          measuredValue: quality.blurVariance,
          thresholdValue: t.minBlurVariance,
        ),
      );
    }
    if (quality.glare.glareFraction > t.maxGlareFraction) {
      found.add(
        Anomaly(
          code: AnomalyCode.excessiveGlare,
          severity: AnomalySeverity.blocking,
          detail: 'Specular glare covers part of the measured area.',
          measuredValue: quality.glare.glareFraction,
          thresholdValue: t.maxGlareFraction,
        ),
      );
    }
    if (quality.exposure.shadowClippedFraction >
        t.maxShadowClippedFraction) {
      found.add(
        Anomaly(
          code: AnomalyCode.underexposed,
          severity: AnomalySeverity.blocking,
          detail: 'A significant fraction of pixels is clipped to black and '
              'carries no colour information.',
          measuredValue: quality.exposure.shadowClippedFraction,
          thresholdValue: t.maxShadowClippedFraction,
        ),
      );
    }
    if (quality.exposure.highlightClippedFraction >
        t.maxHighlightClippedFraction) {
      found.add(
        Anomaly(
          code: AnomalyCode.overexposed,
          severity: AnomalySeverity.blocking,
          detail: 'A significant fraction of pixels is clipped to white and '
              'carries no colour information.',
          measuredValue: quality.exposure.highlightClippedFraction,
          thresholdValue: t.maxHighlightClippedFraction,
        ),
      );
    }
    if (quality.exposure.dynamicRange < t.minDynamicRange) {
      found.add(
        Anomaly(
          code: AnomalyCode.unusualLighting,
          severity: AnomalySeverity.review,
          detail: 'Luminance spread is unusually narrow for this kit.',
          measuredValue: quality.exposure.dynamicRange,
          thresholdValue: t.minDynamicRange,
        ),
      );
    }

    // --- Test region --------------------------------------------------------
    if (!regionDetection.detected) {
      found.add(
        Anomaly(
          code: AnomalyCode.testRegionNotDetected,
          severity: AnomalySeverity.blocking,
          detail: regionDetection.failureReason ??
              'No usable test region was identified.',
        ),
      );
    } else {
      final double confidence = regionDetection.region!.confidence;
      if (confidence < t.minRegionConfidence) {
        found.add(
          Anomaly(
            code: AnomalyCode.testRegionLowConfidence,
            severity: AnomalySeverity.review,
            detail: 'Test-region quality score is below the profile '
                'threshold.',
            measuredValue: confidence,
            thresholdValue: t.minRegionConfidence,
          ),
        );
      }
      if (!regionDetection.uniformityDeltaE.isNaN &&
          regionDetection.uniformityDeltaE > 12.0) {
        found.add(
          Anomaly(
            code: AnomalyCode.spatialInconsistency,
            severity: AnomalySeverity.review,
            detail: 'Colour varies substantially across the test region, '
                'which may indicate incomplete mixing, a shadow, or a region '
                'boundary that includes non-reagent material.',
            measuredValue: regionDetection.uniformityDeltaE,
            thresholdValue: 12.0,
          ),
        );
      }
    }

    // --- Reaction trajectory -------------------------------------------------
    if (profile.reactionWindow.enabled && !trajectory.isEmpty) {
      if (!trajectory.stabilised) {
        found.add(
          Anomaly(
            code: AnomalyCode.reactionUnstable,
            severity: AnomalySeverity.review,
            detail: 'The reaction had not stabilised by the end of the '
                'configured observation window.',
            measuredValue: trajectory.maxStepDeltaE,
            thresholdValue: profile.reactionWindow.stabilityDeltaE,
          ),
        );
      }
      if (!trajectory.monotonicHue && trajectory.samples.length >= 3) {
        found.add(
          const Anomaly(
            code: AnomalyCode.reactionTrajectoryUnexpected,
            severity: AnomalySeverity.review,
            detail: 'Hue moved in inconsistent directions across the '
                'sequence, which more often reflects changing lighting or '
                'framing than reaction chemistry.',
          ),
        );
      }
    }

    // --- Model --------------------------------------------------------------
    if (!classifier.available) {
      found.add(
        Anomaly(
          code: AnomalyCode.modelUnavailable,
          severity: AnomalySeverity.review,
          detail: classifier.unavailableReason ??
              'No local model was available for this analysis.',
        ),
      );
    } else if (classifier.outOfDistribution) {
      found.add(
        const Anomaly(
          code: AnomalyCode.modelOutOfDistribution,
          severity: AnomalySeverity.blocking,
          detail: 'Input falls outside the conditions the model was trained '
              'and evaluated on.',
        ),
      );
    }

    // --- Kit profile support -------------------------------------------------
    if (profile.decisionRegions.isEmpty) {
      found.add(
        Anomaly(
          code: AnomalyCode.unsupportedKitProfile,
          severity: AnomalySeverity.blocking,
          detail: 'Kit profile ${profile.kitId} defines no interpretation '
              'rules, so no result can be produced.',
        ),
      );
    }

    // --- Location -------------------------------------------------------------
    if (!locationAvailable) {
      found.add(
        const Anomaly(
          code: AnomalyCode.locationUnavailable,
          severity: AnomalySeverity.informational,
          detail: 'No location fix was available when this record was '
              'created. The record is still valid; location is absent rather '
              'than estimated.',
        ),
      );
    }
    if (locationIntegrity.evaluated && !locationIntegrity.plausible) {
      found.add(
        Anomaly(
          code: AnomalyCode.locationIntegrity,
          severity: AnomalySeverity.review,
          detail: 'Distance and elapsed time between this record and the '
              'previous one imply an unusual travel speed. This is an '
              'inconsistency flag only; several benign causes are possible.',
          measuredValue: locationIntegrity.impliedSpeedMps,
        ),
      );
    }

    return found;
  }
}
