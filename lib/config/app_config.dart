/// Application-wide configuration.
///
/// Thresholds that affect analysis live in versioned kit profiles
/// (assets/kits/*.json), NOT here. Only cross-cutting, kit-independent
/// settings belong in this file (master spec section 62).
library;

class AppConfig {
  const AppConfig._();

  static const String appName = 'DruSight';
  static const String tagline =
      'See the reaction. Understand the test. Verify the evidence.';

  /// Shown on every result surface. Non-negotiable (master spec section 1).
  static const String presumptiveDisclaimer =
      'Presumptive field-test result. Confirmatory laboratory testing is '
      'required.';

  /// Database file name and schema version.
  static const String databaseName = 'drusight.db';
  static const int databaseSchemaVersion = 1;

  /// Identifier of the signing key pair held in secure storage.
  static const String signingKeyAlias = 'drusight.evidence.ed25519';

  /// Maximum plausible ground travel speed, in metres per second, used by the
  /// location-integrity check. 90 m/s (~324 km/h) is deliberately generous:
  /// the intent is to flag physically implausible jumps, not ordinary travel
  /// (master spec section 28).
  static const double maxPlausibleSpeedMps = 90.0;

  /// Location fixes worse than this (metres) are treated as low-confidence
  /// and excluded from travel-speed reasoning.
  static const double locationAccuracyCeilingMetres = 100.0;

  /// Set true only in the clearly-labelled demonstration environment.
  /// Never enabled in a release build by default (master spec section 35).
  static const bool demoModeCompiledIn = bool.fromEnvironment(
    'DRUSIGHT_DEMO',
    defaultValue: false,
  );

  /// Optional NewsAPI.org free-tier key for live drug intelligence news.
  /// Set via --dart-define=NEWSAPI_KEY=your_key_here at build time.
  /// When empty, the NewsAPI source is skipped; UNODC RSS still works.
  static const String newsApiKey = String.fromEnvironment(
    'NEWSAPI_KEY',
    defaultValue: '',
  );
}
