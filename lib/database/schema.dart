/// SQLite schema definition (master spec section 46).
///
/// Design notes:
///   - Evidence tables are append-oriented. There is no UPDATE path for
///     `evidence_records`; a correction is a new record plus an audit event.
///   - Every statement in the app uses parameter binding. No SQL is ever
///     built by string interpolation of user input (master spec section 48).
///   - Migrations are explicit and versioned; [migrationsFrom] returns the
///     ordered statements needed to move an old database forward.
library;

class Schema {
  const Schema._();

  static const int version = 1;

  static const List<String> createStatements = <String>[
    '''
    CREATE TABLE operators (
      operator_id       TEXT PRIMARY KEY,
      officer_id        TEXT NOT NULL,
      display_name      TEXT NOT NULL,
      role              TEXT NOT NULL,
      passphrase_hash   TEXT NOT NULL,
      passphrase_salt   TEXT NOT NULL,
      pbkdf2_iterations INTEGER NOT NULL,
      created_at_utc    TEXT NOT NULL,
      active            INTEGER NOT NULL DEFAULT 1
    )
    ''',
    '''
    CREATE TABLE devices (
      device_id      TEXT PRIMARY KEY,
      device_model   TEXT NOT NULL,
      os_version     TEXT NOT NULL,
      app_version    TEXT NOT NULL,
      app_build      TEXT NOT NULL,
      first_seen_utc TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE kit_profiles (
      kit_id            TEXT NOT NULL,
      profile_version   TEXT NOT NULL,
      manufacturer      TEXT NOT NULL,
      test_name         TEXT NOT NULL,
      reagent_type      TEXT NOT NULL,
      validation_status TEXT NOT NULL,
      profile_json      TEXT NOT NULL,
      installed_at_utc  TEXT NOT NULL,
      PRIMARY KEY (kit_id, profile_version)
    )
    ''',
    '''
    CREATE TABLE tests (
      test_id            TEXT PRIMARY KEY,
      operator_id        TEXT NOT NULL,
      officer_id         TEXT NOT NULL,
      session_id         TEXT NOT NULL,
      device_id          TEXT NOT NULL,
      kit_id             TEXT NOT NULL,
      kit_profile_version TEXT NOT NULL,
      started_at_utc     TEXT NOT NULL,
      completed_at_utc   TEXT,
      result             TEXT,
      reliability_status TEXT,
      latitude           REAL,
      longitude          REAL,
      location_accuracy  REAL,
      location_time_utc  TEXT,
      FOREIGN KEY (operator_id) REFERENCES operators (operator_id)
    )
    ''',
    '''
    CREATE TABLE test_images (
      image_id        TEXT PRIMARY KEY,
      test_id         TEXT NOT NULL,
      role            TEXT NOT NULL,
      offset_seconds  INTEGER,
      file_path       TEXT NOT NULL,
      image_hash      TEXT NOT NULL,
      width_px        INTEGER NOT NULL,
      height_px       INTEGER NOT NULL,
      byte_size       INTEGER NOT NULL,
      captured_at_utc TEXT NOT NULL,
      is_original     INTEGER NOT NULL,
      derived_from    TEXT,
      FOREIGN KEY (test_id) REFERENCES tests (test_id)
    )
    ''',
    '''
    CREATE TABLE analysis_results (
      test_id              TEXT PRIMARY KEY,
      result               TEXT NOT NULL,
      reliability_status   TEXT NOT NULL,
      algorithm_version    TEXT NOT NULL,
      calibration_version  TEXT NOT NULL,
      feature_schema_version TEXT NOT NULL,
      model_id             TEXT,
      model_version        TEXT,
      analysis_json        TEXT NOT NULL,
      analysis_digest      TEXT NOT NULL,
      created_at_utc       TEXT NOT NULL,
      FOREIGN KEY (test_id) REFERENCES tests (test_id)
    )
    ''',
    '''
    CREATE TABLE reaction_measurements (
      measurement_id  TEXT PRIMARY KEY,
      test_id         TEXT NOT NULL,
      offset_seconds  INTEGER NOT NULL,
      captured_at_utc TEXT NOT NULL,
      lab_l           REAL NOT NULL,
      lab_a           REAL NOT NULL,
      lab_b           REAL NOT NULL,
      hsv_h           REAL NOT NULL,
      hsv_s           REAL NOT NULL,
      hsv_v           REAL NOT NULL,
      image_hash      TEXT NOT NULL,
      FOREIGN KEY (test_id) REFERENCES tests (test_id)
    )
    ''',
    '''
    CREATE TABLE anomalies (
      anomaly_id   TEXT PRIMARY KEY,
      test_id      TEXT NOT NULL,
      code         TEXT NOT NULL,
      severity     TEXT NOT NULL,
      detail       TEXT NOT NULL,
      measured_value REAL,
      threshold_value REAL,
      created_at_utc TEXT NOT NULL,
      FOREIGN KEY (test_id) REFERENCES tests (test_id)
    )
    ''',
    '''
    CREATE TABLE evidence_records (
      test_id               TEXT PRIMARY KEY,
      sequence_number       INTEGER NOT NULL UNIQUE,
      record_hash           TEXT NOT NULL UNIQUE,
      previous_record_hash  TEXT NOT NULL,
      image_hash            TEXT NOT NULL,
      analysis_digest       TEXT NOT NULL,
      signature             TEXT NOT NULL,
      public_key_id         TEXT NOT NULL,
      public_key            TEXT NOT NULL,
      key_version           INTEGER NOT NULL,
      signature_scheme      TEXT NOT NULL,
      canonical_format_version TEXT NOT NULL,
      record_json           TEXT NOT NULL,
      created_at_utc        TEXT NOT NULL,
      FOREIGN KEY (test_id) REFERENCES tests (test_id)
    )
    ''',
    '''
    CREATE TABLE audit_events (
      event_id       TEXT PRIMARY KEY,
      occurred_at_utc TEXT NOT NULL,
      actor_id       TEXT,
      action         TEXT NOT NULL,
      subject_type   TEXT,
      subject_id     TEXT,
      detail_json    TEXT,
      previous_event_hash TEXT NOT NULL,
      event_hash     TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE model_versions (
      model_id             TEXT NOT NULL,
      model_version        TEXT NOT NULL,
      kit_id               TEXT NOT NULL,
      feature_schema_version TEXT NOT NULL,
      asset_path           TEXT NOT NULL,
      asset_hash           TEXT NOT NULL,
      validation_status    TEXT NOT NULL,
      installed_at_utc     TEXT NOT NULL,
      PRIMARY KEY (model_id, model_version)
    )
    ''',
    '''
    CREATE TABLE calibration_versions (
      calibration_version TEXT PRIMARY KEY,
      description         TEXT NOT NULL,
      installed_at_utc    TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE knowledge_base_entries (
      entry_id          TEXT PRIMARY KEY,
      title             TEXT NOT NULL,
      aliases           TEXT,
      classification    TEXT,
      related_kit_ids   TEXT,
      content_json      TEXT NOT NULL,
      source            TEXT NOT NULL,
      source_version    TEXT NOT NULL,
      last_verified_date TEXT,
      installed_at_utc  TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE verification_events (
      verification_id  TEXT PRIMARY KEY,
      test_id          TEXT NOT NULL,
      verified_at_utc  TEXT NOT NULL,
      actor_id         TEXT,
      method           TEXT NOT NULL,
      record_hash_valid INTEGER NOT NULL,
      link_valid        INTEGER NOT NULL,
      signature_valid   INTEGER NOT NULL,
      image_hash_valid  INTEGER,
      notes             TEXT
    )
    ''',
    '''
    CREATE TABLE reviews (
      review_id       TEXT PRIMARY KEY,
      test_id         TEXT NOT NULL,
      reviewer_id     TEXT NOT NULL,
      reviewed_at_utc TEXT NOT NULL,
      machine_result  TEXT NOT NULL,
      reviewer_notes  TEXT NOT NULL,
      lab_confirmation_requested INTEGER NOT NULL,
      FOREIGN KEY (test_id) REFERENCES tests (test_id)
    )
    ''',
    // Indices for the mandatory searchable history (master spec section 36).
    'CREATE INDEX idx_tests_started ON tests (started_at_utc DESC)',
    'CREATE INDEX idx_tests_operator ON tests (operator_id)',
    'CREATE INDEX idx_tests_officer ON tests (officer_id)',
    'CREATE INDEX idx_tests_kit ON tests (kit_id)',
    'CREATE INDEX idx_tests_result ON tests (result)',
    'CREATE INDEX idx_tests_reliability ON tests (reliability_status)',
    'CREATE INDEX idx_tests_device ON tests (device_id)',
    'CREATE INDEX idx_anomalies_test ON anomalies (test_id)',
    'CREATE INDEX idx_anomalies_code ON anomalies (code)',
    'CREATE INDEX idx_images_test ON test_images (test_id)',
    'CREATE INDEX idx_reaction_test ON reaction_measurements (test_id)',
    'CREATE INDEX idx_evidence_sequence ON evidence_records (sequence_number)',
    'CREATE INDEX idx_audit_time ON audit_events (occurred_at_utc DESC)',
    'CREATE INDEX idx_verification_test ON verification_events (test_id)',
  ];

  /// Ordered upgrade statements keyed by the version they move the database
  /// TO. Version 1 is the initial schema and therefore has no entry.
  static const Map<int, List<String>> upgrades = <int, List<String>>{};

  static List<String> migrationsFrom(int oldVersion, int newVersion) {
    final List<String> statements = <String>[];
    for (int v = oldVersion + 1; v <= newVersion; v++) {
      statements.addAll(upgrades[v] ?? const <String>[]);
    }
    return statements;
  }
}
