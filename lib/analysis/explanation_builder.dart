/// Builds the evidence-based explanation shown on the result page
/// (master spec section 25).
///
/// Hard rule: every line must restate something that was measured. No
/// generated prose, no inferred chemistry, no confidence language that the
/// data does not support.
library;

import '../cv/calibration.dart';
import '../cv/region_detector.dart';
import '../models/analysis_result.dart';
import '../models/anomaly.dart';
import '../models/capture_quality.dart';
import '../models/enums.dart';
import '../models/colour_features.dart';
import '../models/kit_profile.dart';
import '../models/reaction_series.dart';

class ExplanationBuilder {
  const ExplanationBuilder();

  List<ExplanationItem> build({
    required KitProfile profile,
    required CaptureQuality quality,
    required CalibrationResult calibration,
    required RegionDetection regionDetection,
    required ColourFeatures? features,
    required ReactionTrajectory trajectory,
    required RuleOutcome? ruleOutcome,
    required ClassifierOutput classifier,
    required List<Anomaly> anomalies,
    required ReliabilityStatus status,
  }) {
    final List<ExplanationItem> items = <ExplanationItem>[];

    // --- Capture ------------------------------------------------------------
    items.add(
      ExplanationItem(
        statement: quality.referenceCardDetected
            ? 'Reference card detected and validated'
            : 'Reference card not detected',
        supportsResult: quality.referenceCardDetected,
        measurement: quality.referenceCardDetected
            ? '${(quality.cardCoverageFraction * 100).toStringAsFixed(1)}% of frame'
            : null,
      ),
    );

    items.add(
      ExplanationItem(
        statement: 'Image sharpness (variance of Laplacian)',
        supportsResult:
            quality.blurVariance >= profile.qualityThresholds.minBlurVariance,
        measurement: '${quality.blurVariance.toStringAsFixed(1)} '
            '(threshold ${profile.qualityThresholds.minBlurVariance.toStringAsFixed(1)})',
      ),
    );

    items.add(
      ExplanationItem(
        statement: 'Specular glare coverage',
        supportsResult: quality.glare.glareFraction <=
            profile.qualityThresholds.maxGlareFraction,
        measurement:
            '${(quality.glare.glareFraction * 100).toStringAsFixed(2)}% '
            '(limit ${(profile.qualityThresholds.maxGlareFraction * 100).toStringAsFixed(2)}%)',
      ),
    );

    // --- Calibration --------------------------------------------------------
    if (calibration.succeeded) {
      items.add(
        ExplanationItem(
          statement: 'Colour calibration fitted from '
              '${calibration.patchCount} reference patches',
          supportsResult: calibration.meanResidualDeltaE <=
              profile.qualityThresholds.maxCalibrationResidualDeltaE,
          measurement: 'mean residual dE2000 '
              '${calibration.meanResidualDeltaE.toStringAsFixed(2)} '
              '(limit ${profile.qualityThresholds.maxCalibrationResidualDeltaE.toStringAsFixed(2)})',
        ),
      );
    } else {
      items.add(
        ExplanationItem(
          statement: 'Colour calibration failed',
          supportsResult: false,
          measurement: calibration.failureReason,
        ),
      );
    }

    // --- Region -------------------------------------------------------------
    if (regionDetection.detected) {
      final String mode =
          regionDetection.region!.selectionMode == RegionSelectionMode.automatic
              ? 'automatically detected'
              : 'operator-selected';
      items.add(
        ExplanationItem(
          statement: 'Test region $mode',
          supportsResult: regionDetection.region!.confidence >=
              profile.qualityThresholds.minRegionConfidence,
          measurement: 'region quality '
              '${regionDetection.region!.confidence.toStringAsFixed(2)} '
              '(threshold ${profile.qualityThresholds.minRegionConfidence.toStringAsFixed(2)})',
        ),
      );
    }

    // --- Measured colour ----------------------------------------------------
    if (features != null) {
      items.add(
        ExplanationItem(
          statement: 'Calibrated region colour',
          supportsResult: true,
          measurement: 'Lab ${features.meanLab} / '
              'hue ${features.hueCircularMean.toStringAsFixed(1)} deg / '
              'sat ${features.meanHsv.s.toStringAsFixed(3)}',
        ),
      );
      items.add(
        ExplanationItem(
          statement: 'Spatial consistency across the region',
          supportsResult: features.spatialUniformity <= 12.0,
          measurement: 'mean tile deviation dE2000 '
              '${features.spatialUniformity.toStringAsFixed(2)}',
        ),
      );
    }

    // --- Reaction -----------------------------------------------------------
    if (!trajectory.isEmpty) {
      items.add(
        ExplanationItem(
          statement: trajectory.stabilised
              ? 'Reaction stabilised within the observation window'
              : 'Reaction had not stabilised when observation ended',
          supportsResult: trajectory.stabilised,
          measurement: 'total dE2000 '
              '${trajectory.totalDeltaE.toStringAsFixed(2)}, '
              'final step ${trajectory.maxStepDeltaE.toStringAsFixed(2)}'
              '${trajectory.stabilisedAtOffsetSeconds != null ? ", stable from ${trajectory.stabilisedAtOffsetSeconds}s" : ""}',
        ),
      );
      items.add(
        ExplanationItem(
          statement: trajectory.monotonicHue
              ? 'Hue moved consistently in one direction'
              : 'Hue direction was inconsistent across the sequence',
          supportsResult: trajectory.monotonicHue,
          measurement:
              'net shift ${trajectory.netHueShiftDegrees.toStringAsFixed(1)} deg',
        ),
      );
    }

    // --- Interpretation -----------------------------------------------------
    if (ruleOutcome != null) {
      if (ruleOutcome.matchedRegionLabel != null) {
        items.add(
          ExplanationItem(
            statement: 'Calibrated colour matched the kit profile '
                '"${ruleOutcome.matchedRegionLabel}" interpretation region',
            supportsResult: !ruleOutcome.borderline,
            measurement: 'dE2000 to region centre '
                '${ruleOutcome.distanceToMatchedRegion!.toStringAsFixed(2)}'
                '${ruleOutcome.distanceToNearestOtherRegion != null ? ", nearest other region ${ruleOutcome.distanceToNearestOtherRegion!.toStringAsFixed(2)}" : ""}',
          ),
        );
      } else {
        items.add(
          ExplanationItem(
            statement: 'Calibrated colour did not fall inside any '
                'interpretation region defined by this kit profile',
            supportsResult: false,
            measurement: ruleOutcome.distanceToMatchedRegion == null
                ? null
                : 'nearest region dE2000 '
                    '${ruleOutcome.distanceToMatchedRegion!.toStringAsFixed(2)}',
          ),
        );
      }
      if (ruleOutcome.borderline) {
        items.add(
          const ExplanationItem(
            statement: 'Result is treated as inconclusive because the '
                'calibrated colour is near the configured decision boundary',
            supportsResult: false,
          ),
        );
      }
    }

    // --- Model --------------------------------------------------------------
    if (classifier.available) {
      items.add(
        ExplanationItem(
          statement: 'Local model classification: '
              '${classifier.predicted.wireName}',
          supportsResult: ruleOutcome == null ||
              classifier.predicted == ruleOutcome.result,
          measurement: '${classifier.modelId} ${classifier.modelVersion}',
        ),
      );
    } else {
      items.add(
        ExplanationItem(
          statement: 'No local model contributed to this result',
          supportsResult: false,
          measurement: classifier.unavailableReason,
        ),
      );
    }

    // --- Anomalies ----------------------------------------------------------
    for (final Anomaly a in anomalies) {
      items.add(
        ExplanationItem(
          statement: '${a.code.wireName}: ${a.detail}',
          supportsResult: false,
          measurement: a.measuredValue == null
              ? null
              : 'measured ${a.measuredValue!.toStringAsFixed(4)}'
                  '${a.thresholdValue != null ? " vs threshold ${a.thresholdValue!.toStringAsFixed(4)}" : ""}',
        ),
      );
    }

    return items;
  }
}
