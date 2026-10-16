/// Reliability engine (master spec section 26).
///
/// Deliberately a transparent three-state rule set, not a score. There is no
/// validation data behind this system, so any percentage it printed would be
/// a number with no referent. The rules are:
///
///   RECAPTURE_REQUIRED  any BLOCKING anomaly, or calibration failed.
///   REVIEW              any REVIEW-severity anomaly, or the deterministic
///                       rules landed on a borderline colour, or rules and
///                       model disagree, or no model was available.
///   PASS                everything measured is within the profile's limits.
///
/// Result selection follows from status: a RECAPTURE or REVIEW outcome never
/// reports POSITIVE or NEGATIVE. Preferring INCONCLUSIVE over a possibly
/// misleading classification is the core safety principle (section 56).
library;

import '../models/analysis_result.dart';
import '../models/anomaly.dart';
import '../models/enums.dart';

class ReliabilityDecision {
  const ReliabilityDecision({
    required this.status,
    required this.result,
    required this.reasons,
  });

  final ReliabilityStatus status;
  final TestResult result;

  /// Plain-language reasons for the status, each traceable to a measurement.
  final List<String> reasons;
}

class ReliabilityEngine {
  const ReliabilityEngine();

  ReliabilityDecision decide({
    required List<Anomaly> anomalies,
    required RuleOutcome? ruleOutcome,
    required ClassifierOutput classifier,
  }) {
    final List<String> reasons = <String>[];

    final bool hasBlocking = anomalies
        .any((Anomaly a) => a.severity == AnomalySeverity.blocking);
    if (hasBlocking) {
      for (final Anomaly a in anomalies
          .where((Anomaly a) => a.severity == AnomalySeverity.blocking)) {
        reasons.add(a.detail);
      }
      return ReliabilityDecision(
        status: ReliabilityStatus.recaptureRequired,
        result: TestResult.inconclusive,
        reasons: reasons,
      );
    }

    if (ruleOutcome == null) {
      return const ReliabilityDecision(
        status: ReliabilityStatus.recaptureRequired,
        result: TestResult.inconclusive,
        reasons: <String>[
          'No interpretation could be applied to the measured colour.',
        ],
      );
    }

    bool needsReview = false;

    for (final Anomaly a
        in anomalies.where((Anomaly a) => a.severity == AnomalySeverity.review)) {
      needsReview = true;
      reasons.add(a.detail);
    }

    if (ruleOutcome.borderline) {
      needsReview = true;
      reasons.add(
        'Calibrated colour is near the configured decision boundary for this '
        'kit, so the outcome is not separated clearly enough to report.',
      );
    }

    if (ruleOutcome.result == TestResult.inconclusive) {
      needsReview = true;
      reasons.add(
        'Calibrated colour did not fall within any interpretation region '
        'defined by the kit profile.',
      );
    }

    if (classifier.available && classifier.predicted != ruleOutcome.result) {
      needsReview = true;
      reasons.add(
        'The local model (${classifier.predicted.wireName}) and the kit '
        'profile colour rules (${ruleOutcome.result.wireName}) disagree.',
      );
    }

    if (needsReview) {
      return ReliabilityDecision(
        status: ReliabilityStatus.review,
        result: TestResult.inconclusive,
        reasons: reasons,
      );
    }

    reasons.add(
      'All capture-quality, calibration and interpretation checks defined by '
      'the kit profile were satisfied.',
    );
    return ReliabilityDecision(
      status: ReliabilityStatus.pass,
      result: ruleOutcome.result,
      reasons: reasons,
    );
  }
}
