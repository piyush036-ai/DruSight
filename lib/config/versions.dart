/// Version constants recorded into every evidence record.
///
/// These exist so that a record created today can never be mistaken for one
/// produced by a future model or algorithm (master spec section 51).
/// Bump the relevant constant whenever the corresponding logic changes.
library;

class Versions {
  const Versions._();

  /// Version of the deterministic analysis pipeline (CV + feature extraction
  /// + reliability rules). Bump on any change that can alter a result for the
  /// same input image.
  static const String algorithm = 'algo-0.1.0';

  /// Version of the feature vector layout handed to the classifier.
  /// Must match the `feature_schema_version` emitted by ml_training.
  static const String featureSchema = 'features-0.1.0';

  /// Version of the colour-calibration method (reference-card model + solver).
  static const String calibration = 'calib-0.1.0';

  /// Canonical-serialization format version. Changing this changes every
  /// record hash, so it is versioned independently and must never be changed
  /// silently.
  static const String canonicalFormat = 'canon-1';

  /// Hash-chain genesis value used as `previous_record_hash` for the first
  /// record on a device.
  static const String chainGenesis =
      '0000000000000000000000000000000000000000000000000000000000000000';
}
