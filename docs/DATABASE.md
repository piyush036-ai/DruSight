# Database

SQLite via `sqflite`. Schema version 1, defined in `lib/database/schema.dart`.

## Principles

- **Append-oriented evidence.** There is no UPDATE path for `evidence_records`
  or `audit_events`. A correction is a new record plus an audit event.
- **Bound parameters everywhere.** No SQL is built by interpolating user input.
  The single `LIKE` pattern escapes user wildcards, and sort order comes from a
  fixed enum (`HistorySort`), never from user text.
- **Foreign keys on.** `PRAGMA foreign_keys = ON` in `onConfigure`; SQLite
  defaults it off.
- **Transactional writes.** A test, its images, its analysis, its anomalies and
  its evidence record commit together or not at all — and the chain slot is
  allocated inside that same transaction, so concurrent tests cannot claim the
  same sequence number.

## Tables

| Table | Holds |
|---|---|
| `operators` | Local accounts. PBKDF2 digest + salt + iteration count. Never a plaintext passphrase. |
| `devices` | Device identity per installation. |
| `kit_profiles` | Installed profiles, keyed `(kit_id, profile_version)`. An installed version is immutable. |
| `tests` | One row per test, with denormalised result/reliability/location for fast history queries. |
| `test_images` | Every image. `is_original` marks the untouched capture; `derived_from` links derived artefacts to it. |
| `analysis_results` | Full analysis JSON plus its digest and all version identifiers. |
| `reaction_measurements` | Per-frame Lab/HSV for timed sequences. |
| `anomalies` | Code, severity, detail, measured value, threshold. |
| `evidence_records` | Signed record JSON plus indexed integrity columns. `sequence_number` and `record_hash` are UNIQUE. |
| `audit_events` | Hash-chained audit trail. |
| `model_versions` | Installed models with their asset SHA-256. |
| `calibration_versions` | Installed calibration methods. |
| `knowledge_base_entries` | Offline knowledge base. |
| `verification_events` | Every verification attempt and its outcome. |
| `reviews` | Human review notes. The machine result is stored alongside and is never overwritten. |

## Indices

Built for the mandatory searchable history (master spec §36): `started_at_utc`,
`operator_id`, `officer_id`, `kit_id`, `result`, `reliability_status`,
`device_id`, plus `anomalies(test_id)` and `anomalies(code)` for the anomaly
filter's `EXISTS` subquery, and `evidence_records(sequence_number)` for chain
verification.

## Migrations

`Schema.upgrades` maps a target version to its ordered statements;
`migrationsFrom` composes the path. Version 1 is the initial schema and has no
entry.

Rules when adding version 2:

1. Never modify `createStatements` for an existing version — that would leave
   new and upgraded installs with different schemas.
2. Add the statements under `upgrades[2]` and bump `Schema.version` and
   `AppConfig.databaseSchemaVersion` together.
3. Never alter a column that feeds a record hash. If the canonical record
   layout must change, bump `Versions.canonicalFormat` and verify old records
   under their own recorded format version.

## Not yet done

- No encryption at rest. SQLCipher is the next step.
- No automated migration tests (only v1 exists).
- No retention or purge policy.
