/// Reliability-engine tests (master spec sections 26, 56).
///
/// The property under test is the core safety principle: the system must
/// prefer INCONCLUSIVE over a possibly misleading classification.
library;

import 'package:drusight/analysis/reliability_engine.dart';
import 'package:drusight/models/analysis_result.dart';
import 'package:drusight/models/anomaly.dart';
import 'package:drusight/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

const RuleOutcome _cleanPositive = RuleOutcome(
  result: TestResult.presumptivePositive,
  matchedRegionLabel: 'POSITIVE',
  distanceToMatchedRegion: 3.0,
  borderline: false,
  distanceToNearestOtherRegion: 40.0,
);

const RuleOutcome _borderlinePositive = RuleOutcome(
  result: TestResult.presumptivePositive,
  matchedRegionLabel: 'POSITIVE',
  distanceToMatchedRegion: 14.2,
  borderline: true,
  distanceToNearestOtherRegion: 16.0,
);

Anomaly anomaly(AnomalyCode code, AnomalySeverity severity) =>
    Anomaly(code: code, severity: severity, detail: 'test detail');

void main() {
  const ReliabilityEngine engine = ReliabilityEngine();

  test('a clean analysis passes and reports the rule outcome', () {
    final ReliabilityDecision d = engine.decide(
      anomalies: const <Anomaly>[],
      ruleOutcome: _cleanPositive,
      classifier: const ClassifierOutput(
        predicted: TestResult.presumptivePositive,
        modelId: 'm',
        modelVersion: '1',
        featureSchemaVersion: 'features-0.1.0',
        available: true,
      ),
    );
    expect(d.status, ReliabilityStatus.pass);
    expect(d.result, TestResult.presumptivePositive);
  });

  test('a blocking anomaly forces recapture and inconclusive', () {
    final ReliabilityDecision d = engine.decide(
      anomalies: <Anomaly>[
        anomaly(AnomalyCode.calibrationFailed, AnomalySeverity.blocking),
      ],
      ruleOutcome: _cleanPositive,
      classifier: ClassifierOutput.unavailable('none'),
    );
    expect(d.status, ReliabilityStatus.recaptureRequired);
    expect(d.result, TestResult.inconclusive);
    expect(d.reasons, isNotEmpty);
  });

  test('a blocking anomaly outranks an otherwise clean positive', () {
    // The most important single assertion in this file: a poor capture can
    // never become a presumptive positive.
    final ReliabilityDecision d = engine.decide(
      anomalies: <Anomaly>[
        anomaly(AnomalyCode.excessiveGlare, AnomalySeverity.blocking),
      ],
      ruleOutcome: _cleanPositive,
      classifier: const ClassifierOutput(
        predicted: TestResult.presumptivePositive,
        modelId: 'm',
        modelVersion: '1',
        featureSchemaVersion: 'features-0.1.0',
        available: true,
      ),
    );
    expect(d.result, isNot(TestResult.presumptivePositive));
    expect(d.result, TestResult.inconclusive);
  });

  test('a review anomaly escalates to review and withholds the outcome', () {
    final ReliabilityDecision d = engine.decide(
      anomalies: <Anomaly>[
        anomaly(AnomalyCode.spatialInconsistency, AnomalySeverity.review),
      ],
      ruleOutcome: _cleanPositive,
      classifier: ClassifierOutput.unavailable('none'),
    );
    expect(d.status, ReliabilityStatus.review);
    expect(d.result, TestResult.inconclusive);
  });

  test('an informational anomaly alone does not block a pass', () {
    final ReliabilityDecision d = engine.decide(
      anomalies: <Anomaly>[
        anomaly(AnomalyCode.locationUnavailable,
            AnomalySeverity.informational),
      ],
      ruleOutcome: _cleanPositive,
      classifier: const ClassifierOutput(
        predicted: TestResult.presumptivePositive,
        modelId: 'm',
        modelVersion: '1',
        featureSchemaVersion: 'features-0.1.0',
        available: true,
      ),
    );
    expect(d.status, ReliabilityStatus.pass);
  });

  test('a borderline colour escalates even with no anomalies', () {
    final ReliabilityDecision d = engine.decide(
      anomalies: const <Anomaly>[],
      ruleOutcome: _borderlinePositive,
      classifier: const ClassifierOutput(
        predicted: TestResult.presumptivePositive,
        modelId: 'm',
        modelVersion: '1',
        featureSchemaVersion: 'features-0.1.0',
        available: true,
      ),
    );
    expect(d.status, ReliabilityStatus.review);
    expect(d.result, TestResult.inconclusive);
    expect(
      d.reasons.join(' ').toLowerCase(),
      contains('decision boundary'),
    );
  });

  test('model and rules disagreeing escalates to review', () {
    final ReliabilityDecision d = engine.decide(
      anomalies: const <Anomaly>[],
      ruleOutcome: _cleanPositive,
      classifier: const ClassifierOutput(
        predicted: TestResult.presumptiveNegative,
        modelId: 'm',
        modelVersion: '1',
        featureSchemaVersion: 'features-0.1.0',
        available: true,
      ),
    );
    expect(d.status, ReliabilityStatus.review);
    expect(d.result, TestResult.inconclusive);
    expect(d.reasons.join(' '), contains('disagree'));
  });

  test('a missing model does not block, because the anomaly engine reports '
      'it separately', () {
    // MockClassifierService returns unavailable, and the anomaly engine emits
    // a REVIEW-severity modelUnavailable anomaly. The reliability engine must
    // not double-count it.
    final ReliabilityDecision d = engine.decide(
      anomalies: const <Anomaly>[],
      ruleOutcome: _cleanPositive,
      classifier: ClassifierOutput.unavailable('no model installed'),
    );
    expect(d.status, ReliabilityStatus.pass);
  });

  test('a null rule outcome forces recapture', () {
    final ReliabilityDecision d = engine.decide(
      anomalies: const <Anomaly>[],
      ruleOutcome: null,
      classifier: ClassifierOutput.unavailable('none'),
    );
    expect(d.status, ReliabilityStatus.recaptureRequired);
    expect(d.result, TestResult.inconclusive);
  });

  test('an inconclusive rule outcome escalates rather than passing', () {
    const RuleOutcome unmatched = RuleOutcome(
      result: TestResult.inconclusive,
      matchedRegionLabel: null,
      distanceToMatchedRegion: 38.0,
      borderline: false,
      distanceToNearestOtherRegion: 41.0,
    );
    final ReliabilityDecision d = engine.decide(
      anomalies: const <Anomaly>[],
      ruleOutcome: unmatched,
      classifier: ClassifierOutput.unavailable('none'),
    );
    expect(d.status, ReliabilityStatus.review);
    expect(d.result, TestResult.inconclusive);
  });

  test('every decision carries at least one stated reason', () {
    for (final ReliabilityDecision d in <ReliabilityDecision>[
      engine.decide(
        anomalies: const <Anomaly>[],
        ruleOutcome: _cleanPositive,
        classifier: ClassifierOutput.unavailable('none'),
      ),
      engine.decide(
        anomalies: <Anomaly>[
          anomaly(AnomalyCode.excessiveBlur, AnomalySeverity.blocking),
        ],
        ruleOutcome: _cleanPositive,
        classifier: ClassifierOutput.unavailable('none'),
      ),
      engine.decide(
        anomalies: const <Anomaly>[],
        ruleOutcome: _borderlinePositive,
        classifier: ClassifierOutput.unavailable('none'),
      ),
    ]) {
      expect(d.reasons, isNotEmpty);
    }
  });
}
