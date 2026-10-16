/// The deterministic analysis pipeline (master spec sections 7, 45).
///
/// Order is fixed and each stage can veto the next:
///
///   calibrate (screen card) -> detect region -> quality gate ->
///   extract features -> reaction analysis -> classify -> anomalies ->
///   reliability -> explain
///
/// Calibration now uses the built-in digital reference card displayed on
/// the device screen. Since the screen emits known sRGB values, calibration
/// always succeeds without requiring any physical printed card.
library;

import 'package:image/image.dart' as img;

import '../config/versions.dart';
import '../cv/calibration.dart';
import '../cv/colour_space.dart';
import '../cv/feature_extractor.dart';
import '../cv/region_detector.dart';
import '../cv/screen_card_calibrator.dart';
import '../ml/classifier_service.dart';
import '../models/analysis_result.dart';
import '../models/anomaly.dart';
import '../models/capture_quality.dart';
import '../models/colour_features.dart';
import '../models/enums.dart';
import '../models/kit_profile.dart';
import '../models/location_fix.dart';
import '../models/reaction_series.dart';
import '../models/test_region.dart';
import 'anomaly_engine.dart';
import 'capture_guard.dart';
import 'explanation_builder.dart';
import 'reaction_analyzer.dart';
import 'reliability_engine.dart';
import 'rule_interpreter.dart';

/// Everything the pipeline needs for one analysis.
class AnalysisRequest {
  const AnalysisRequest({
    required this.image,
    required this.profile,
    required this.regionCandidate,
    required this.regionSelectionMode,
    this.reactionSamples = const <ReactionSample>[],
    this.locationIntegrity,
    this.locationAvailable = false,
  });

  final img.Image image;
  final KitProfile profile;

  /// Where the operator placed the test-region guide, in image pixels.
  final RegionBox regionCandidate;

  final RegionSelectionMode regionSelectionMode;
  final List<ReactionSample> reactionSamples;
  final LocationIntegrityAssessment? locationIntegrity;
  final bool locationAvailable;
}

class AnalysisPipeline {
  AnalysisPipeline({
    required ClassifierService classifier,
    TestRegionDetector? regionDetector,
  })  : _classifier = classifier,
        _regionDetector = regionDetector ?? const GuidedRegionDetector();

  final ClassifierService _classifier;
  final TestRegionDetector _regionDetector;

  final CaptureGuard _guard = const CaptureGuard();
  final AnomalyEngine _anomalyEngine = const AnomalyEngine();
  final ReliabilityEngine _reliabilityEngine = const ReliabilityEngine();
  final RuleInterpreter _ruleInterpreter = const RuleInterpreter();
  final ReactionAnalyzer _reactionAnalyzer = const ReactionAnalyzer();
  final ExplanationBuilder _explanationBuilder = const ExplanationBuilder();

  Future<AnalysisResult> run(AnalysisRequest request) async {
    final KitProfile profile = request.profile;

    // --- 1. Calibration (screen card — always succeeds) ----------------------
    final ScreenCardCalibrator screenCalibrator =
        ScreenCardCalibrator(calibrationVersion: profile.calibrationVersion);
    final CalibrationResult calibration =
        screenCalibrator.calibrate(profile.referenceCard);

    // --- 2. Test region ------------------------------------------------------
    final RegionDetection region = _regionDetector.detect(
      request.image,
      candidate: request.regionCandidate,
      mode: request.regionSelectionMode,
    );

    // --- 3. Capture quality --------------------------------------------------
    final CaptureQuality quality = _guard.evaluate(
      request.image,
      profile: profile,
      regionDetection: region,
    );

    // --- 4. Features (only if region was detected) ---------------------------
    // Calibration always succeeds with the screen card, so only check region.
    ColourFeatures? features;
    if (region.detected) {
      final FeatureExtractor extractor = FeatureExtractor(
        schemaVersion: profile.featureSchemaVersion,
      );
      features = extractor.extract(
        request.image,
        region: region.region!,
        calibration: calibration,
        baselineLab: _baselineLabFor(profile),
      );
    }

    // --- 5. Reaction trajectory ----------------------------------------------
    final ReactionTrajectory trajectory =
        profile.reactionWindow.enabled && request.reactionSamples.length >= 2
            ? _reactionAnalyzer.analyse(request.reactionSamples, profile)
            : ReactionTrajectory.none;

    // --- 6. Deterministic rules ----------------------------------------------
    final RuleOutcome? ruleOutcome = features == null
        ? null
        : _ruleInterpreter.interpret(features.meanLab, profile);

    // --- 7. Model ------------------------------------------------------------
    ClassifierOutput classifier;
    if (features == null) {
      classifier = ClassifierOutput.unavailable(
        'Classification not attempted: no calibrated features were produced.',
      );
    } else {
      await _classifier.load(profile);
      classifier = await _classifier.classify(features, profile: profile);
    }

    // --- 8. Anomalies --------------------------------------------------------
    final List<Anomaly> anomalies = _anomalyEngine.evaluate(
      profile: profile,
      quality: quality,
      regionDetection: region,
      calibration: calibration,
      trajectory: trajectory,
      classifier: classifier,
      locationIntegrity: request.locationIntegrity ??
          LocationIntegrityAssessment.notEvaluated(
            'No previous record available for comparison.',
          ),
      locationAvailable: request.locationAvailable,
    );

    // --- 9. Reliability -------------------------------------------------------
    final ReliabilityDecision decision = _reliabilityEngine.decide(
      anomalies: anomalies,
      ruleOutcome: ruleOutcome,
      classifier: classifier,
    );

    // --- 10. Explanation -------------------------------------------------------
    final List<ExplanationItem> explanation = _explanationBuilder.build(
      profile: profile,
      quality: quality,
      calibration: calibration,
      regionDetection: region,
      features: features,
      trajectory: trajectory,
      ruleOutcome: ruleOutcome,
      classifier: classifier,
      anomalies: anomalies,
      status: decision.status,
    );


    return AnalysisResult(
      result: decision.result,
      reliabilityStatus: decision.status,
      anomalies: anomalies,
      quality: quality,
      calibration: calibration,
      region: region.region,
      features: features,
      trajectory: trajectory,
      ruleOutcome: ruleOutcome,
      classifierOutput: classifier,
      explanation: explanation,
      algorithmVersion: Versions.algorithm,
      kitId: profile.kitId,
      kitProfileVersion: profile.profileVersion,
    );
  }

  /// The profile's NEGATIVE region centre serves as the baseline colour for
  /// the delta-E feature. Null when the profile defines no negative region.
  static Lab? _baselineLabFor(KitProfile profile) {
    for (final ColourDecisionRegion r in profile.decisionRegions) {
      if (r.label == TestResult.presumptiveNegative.wireName) {
        return Lab(r.centreLab[0], r.centreLab[1], r.centreLab[2]);
      }
    }
    return null;
  }
}
