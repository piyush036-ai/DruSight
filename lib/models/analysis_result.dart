/// The complete outcome of analysing one test (master spec sections 37, 57).
library;

import 'anomaly.dart';
import 'colour_features.dart';
import 'enums.dart';
import 'reaction_series.dart';
import 'test_region.dart';
import '../cv/calibration.dart';
import 'capture_quality.dart';

/// Output of the local classifier.
class ClassifierOutput {
  const ClassifierOutput({
    required this.predicted,
    required this.modelId,
    required this.modelVersion,
    required this.featureSchemaVersion,
    required this.available,
    this.classProbabilities,
    this.outOfDistribution = false,
    this.unavailableReason,
  });

  factory ClassifierOutput.unavailable(String reason) => ClassifierOutput(
        predicted: TestResult.inconclusive,
        modelId: null,
        modelVersion: null,
        featureSchemaVersion: null,
        available: false,
        unavailableReason: reason,
      );

  final TestResult predicted;
  final String? modelId;
  final String? modelVersion;
  final String? featureSchemaVersion;

  /// False when no trained model exists for this kit, or the model could not
  /// be loaded. The pipeline then relies on deterministic colour rules alone
  /// and says so, rather than inventing a prediction.
  final bool available;

  /// Only populated when the deployed model is genuinely probabilistic AND its
  /// calibration has been assessed. Null otherwise - an uncalibrated softmax
  /// output presented as a confidence would be a fabricated number.
  final Map<String, double>? classProbabilities;

  final bool outOfDistribution;
  final String? unavailableReason;

  Map<String, Object?> toJson() => <String, Object?>{
        'predicted': predicted.wireName,
        'modelId': modelId,
        'modelVersion': modelVersion,
        'featureSchemaVersion': featureSchemaVersion,
        'available': available,
        'classProbabilities': classProbabilities,
        'outOfDistribution': outOfDistribution,
        'unavailableReason': unavailableReason,
      };
}

/// Outcome of the deterministic, profile-driven colour rules. Runs
/// independently of the model so there is always an auditable, explainable
/// path from measured colour to outcome.
class RuleOutcome {
  const RuleOutcome({
    required this.result,
    required this.matchedRegionLabel,
    required this.distanceToMatchedRegion,
    required this.borderline,
    required this.distanceToNearestOtherRegion,
  });

  final TestResult result;
  final String? matchedRegionLabel;
  final double? distanceToMatchedRegion;

  /// True when the calibrated colour sits within the configured margin of a
  /// decision boundary. Borderline always escalates (master spec section 56).
  final bool borderline;
  final double? distanceToNearestOtherRegion;

  Map<String, Object?> toJson() => <String, Object?>{
        'result': result.wireName,
        'matchedRegionLabel': matchedRegionLabel,
        'distanceToMatchedRegion': distanceToMatchedRegion,
        'borderline': borderline,
        'distanceToNearestOtherRegion': distanceToNearestOtherRegion,
      };
}

/// One line of the evidence-based explanation shown on the result page.
/// Every entry must correspond to something actually measured
/// (master spec section 25).
class ExplanationItem {
  const ExplanationItem({
    required this.statement,
    required this.supportsResult,
    this.measurement,
  });

  final String statement;

  /// True if this observation supported the outcome, false if it counted
  /// against it or reduced confidence.
  final bool supportsResult;

  /// The measured value behind the statement, formatted for display.
  final String? measurement;

  Map<String, Object?> toJson() => <String, Object?>{
        'statement': statement,
        'supportsResult': supportsResult,
        'measurement': measurement,
      };
}

class AnalysisResult {
  const AnalysisResult({
    required this.result,
    required this.reliabilityStatus,
    required this.anomalies,
    required this.quality,
    required this.calibration,
    required this.region,
    required this.features,
    required this.trajectory,
    required this.ruleOutcome,
    required this.classifierOutput,
    required this.explanation,
    required this.algorithmVersion,
    required this.kitId,
    required this.kitProfileVersion,
  });

  final TestResult result;
  final ReliabilityStatus reliabilityStatus;
  final List<Anomaly> anomalies;
  final CaptureQuality quality;
  final CalibrationResult calibration;
  final TestRegion? region;
  final ColourFeatures? features;
  final ReactionTrajectory trajectory;
  final RuleOutcome? ruleOutcome;
  final ClassifierOutput classifierOutput;
  final List<ExplanationItem> explanation;
  final String algorithmVersion;
  final String kitId;
  final String kitProfileVersion;

  bool get requiresHumanReview =>
      reliabilityStatus == ReliabilityStatus.review ||
      result == TestResult.inconclusive;

  Map<String, Object?> toJson() => <String, Object?>{
        'result': result.wireName,
        'reliabilityStatus': reliabilityStatus.wireName,
        'anomalies': anomalies.map((Anomaly a) => a.toJson()).toList(),
        'quality': quality.toJson(),
        'calibration': calibration.toJson(),
        'region': region?.toJson(),
        'features': features?.toJson(),
        'trajectory': trajectory.isEmpty ? null : trajectory.toJson(),
        'ruleOutcome': ruleOutcome?.toJson(),
        'classifier': classifierOutput.toJson(),
        'explanation':
            explanation.map((ExplanationItem e) => e.toJson()).toList(),
        'algorithmVersion': algorithmVersion,
        'kitId': kitId,
        'kitProfileVersion': kitProfileVersion,
      };
}
