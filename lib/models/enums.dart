/// Closed vocabularies used across the analysis and evidence layers.
///
/// These are serialized into evidence records, so the wire names are fixed.
/// Never rename a wire name without bumping the canonical format version.
library;

/// The presumptive outcome of a field test.
///
/// There is deliberately no "probable" or "likely" tier: the system either
/// reports a presumptive outcome or declines to (master spec section 56).
enum TestResult {
  presumptivePositive('POSITIVE'),
  presumptiveNegative('NEGATIVE'),
  inconclusive('INCONCLUSIVE');

  const TestResult(this.wireName);
  final String wireName;

  String get displayLabel => switch (this) {
        TestResult.presumptivePositive => 'PRESUMPTIVE POSITIVE',
        TestResult.presumptiveNegative => 'PRESUMPTIVE NEGATIVE',
        TestResult.inconclusive => 'INCONCLUSIVE',
      };

  static TestResult fromWire(String value) => TestResult.values.firstWhere(
        (TestResult r) => r.wireName == value,
        orElse: () => TestResult.inconclusive,
      );
}

/// Transparent capture/analysis status. Intentionally a three-state indicator
/// rather than a percentage: no validation data exists to justify a numeric
/// "reliability score" (master spec section 26).
enum ReliabilityStatus {
  pass('PASS'),
  review('REVIEW'),
  recaptureRequired('RECAPTURE_REQUIRED');

  const ReliabilityStatus(this.wireName);
  final String wireName;

  String get displayLabel => switch (this) {
        ReliabilityStatus.pass => 'PASS',
        ReliabilityStatus.review => 'REVIEW REQUIRED',
        ReliabilityStatus.recaptureRequired => 'RECAPTURE REQUIRED',
      };

  static ReliabilityStatus fromWire(String value) =>
      ReliabilityStatus.values.firstWhere(
        (ReliabilityStatus s) => s.wireName == value,
        orElse: () => ReliabilityStatus.review,
      );
}

/// Machine-readable anomaly codes (master spec section 27).
enum AnomalyCode {
  referenceCardMissing('ANOMALY_REFERENCE_CARD_MISSING'),
  referenceCardOccluded('ANOMALY_REFERENCE_CARD_OCCLUDED'),
  calibrationFailed('ANOMALY_CALIBRATION_FAILED'),
  excessiveGlare('ANOMALY_EXCESSIVE_GLARE'),
  excessiveBlur('ANOMALY_EXCESSIVE_BLUR'),
  underexposed('ANOMALY_UNDEREXPOSED'),
  overexposed('ANOMALY_OVEREXPOSED'),
  unusualLighting('ANOMALY_UNUSUAL_LIGHTING'),
  testRegionNotDetected('ANOMALY_TEST_REGION_NOT_DETECTED'),
  testRegionLowConfidence('ANOMALY_TEST_REGION_LOW_CONFIDENCE'),
  incorrectFraming('ANOMALY_INCORRECT_FRAMING'),
  reactionUnstable('ANOMALY_REACTION_UNSTABLE'),
  reactionTrajectoryUnexpected('ANOMALY_REACTION_TRAJECTORY_UNEXPECTED'),
  spatialInconsistency('ANOMALY_SPATIAL_INCONSISTENCY'),
  unsupportedKitProfile('ANOMALY_UNSUPPORTED_KIT_PROFILE'),
  unsupportedCondition('ANOMALY_UNSUPPORTED_CONDITION'),
  modelOutOfDistribution('ANOMALY_MODEL_OUT_OF_DISTRIBUTION'),
  modelUnavailable('ANOMALY_MODEL_UNAVAILABLE'),
  locationIntegrity('ANOMALY_LOCATION_INTEGRITY'),
  locationUnavailable('ANOMALY_LOCATION_UNAVAILABLE'),
  timestampInconsistent('ANOMALY_TIMESTAMP_INCONSISTENT');

  const AnomalyCode(this.wireName);
  final String wireName;

  static AnomalyCode? fromWire(String value) {
    for (final AnomalyCode c in AnomalyCode.values) {
      if (c.wireName == value) return c;
    }
    return null;
  }
}

/// Severity drives the reliability engine's decision, not the UI colour alone.
enum AnomalySeverity {
  /// Recorded for traceability; does not by itself change the outcome.
  informational('INFO'),

  /// Forces human review.
  review('REVIEW'),

  /// Forces recapture; no result is produced.
  blocking('BLOCKING');

  const AnomalySeverity(this.wireName);
  final String wireName;
}

/// Whether the analysed region was found automatically or corrected by the
/// operator. Recorded because it changes how the result should be weighed
/// (master spec section 15).
enum RegionSelectionMode {
  automatic('AUTOMATIC'),
  manuallyCorrected('MANUALLY_CORRECTED'),
  manual('MANUAL');

  const RegionSelectionMode(this.wireName);
  final String wireName;

  static RegionSelectionMode fromWire(String value) =>
      RegionSelectionMode.values.firstWhere(
        (RegionSelectionMode m) => m.wireName == value,
        orElse: () => RegionSelectionMode.manual,
      );
}

/// Operator role. The prototype uses local roles only; institutional identity
/// integration is an explicit future extension (master spec section 8).
enum OperatorRole {
  fieldOperator('FIELD_OPERATOR'),
  reviewer('REVIEWER'),
  administrator('ADMINISTRATOR');

  const OperatorRole(this.wireName);
  final String wireName;

  static OperatorRole fromWire(String value) =>
      OperatorRole.values.firstWhere(
        (OperatorRole r) => r.wireName == value,
        orElse: () => OperatorRole.fieldOperator,
      );
}

/// Result of verifying a stored evidence record.
enum ChainStatus {
  valid('VALID'),
  broken('BROKEN'),
  unverified('UNVERIFIED');

  const ChainStatus(this.wireName);
  final String wireName;

  static ChainStatus fromWire(String value) => ChainStatus.values.firstWhere(
        (ChainStatus s) => s.wireName == value,
        orElse: () => ChainStatus.unverified,
      );
}
