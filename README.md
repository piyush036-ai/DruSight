# DruSight

**See the reaction. Understand the test. Verify the evidence.**

A digital companion for presumptive field drug testing.
SIH problem statement **SIH26231 — Digital Companion for Field Drug Testing**.

---

## What this is

DruSight does **not** replace a physical field-test kit and does **not**
identify substances. It adds a measurement, quality-control, explainability
and evidence layer around a kit you already use:

> DruSight converts a subjective visual field-test workflow into a calibrated,
> measurable, explainable and tamper-evident digital workflow while preserving
> the role of confirmatory laboratory analysis.

Every result the app produces carries this, undismissable:

> **Presumptive field-test result. Confirmatory laboratory testing is
> required.**

## What this is not

- Not a confirmatory identification system.
- Not a validated diagnostic instrument. **No accuracy, sensitivity or
  specificity figure is claimed anywhere in this application or repository.**
- Not a legal-admissibility tool. The evidence layer establishes that a record
  has not changed since it was signed. It does not establish the wall-clock
  time of capture, and it does not establish which institution a signing key
  belongs to.

`docs/LIMITATIONS.md` is the full, blunt list. Read it before demonstrating
this to anyone.

---

## Current status

| Layer | State |
|---|---|
| Colour science (sRGB/HSV/Lab, CIEDE2000) | Implemented, verified against the Sharma–Wu–Dalal test vectors |
| Reference-card calibration | Implemented (3x4 affine fit in linear light), verified on synthetic distortions |
| Capture quality gates | Implemented (blur, exposure, glare, framing, resolution) |
| Card / region detection | Guided-alignment detector with automatic validation. Automatic homography detection is an unimplemented integration point that reports unavailability rather than guessing |
| Feature extraction | Implemented, 21 features, schema `features-0.1.0` |
| Reaction fingerprint | Implemented |
| Local classifier | **No trained model exists.** `MockClassifierService` reports unavailability; `OnnxClassifierService` is the wired integration point |
| Reliability + anomaly engines | Implemented |
| Evidence: SHA-256, canonical JSON, Ed25519, hash chain, audit trail | Implemented |
| QR generation + offline verification | Implemented |
| SQLite + searchable history | Implemented |
| ML training pipeline (Python) | Implemented and runnable end to end |
| Kit profiles | Two **clearly-labelled unvalidated demonstration profiles** |

---

## Offline-first

No core function requires a network. There is no API key, no cloud inference
and no mandatory server. Authentication, capture, calibration, analysis,
classification, GPS, hashing, signing, storage, search, reporting, QR
generation and QR verification all run on the handset.

Optional synchronisation to an institutional server is designed for as an
interface only, and is not implemented.

---

## Build

Requires **Flutter 3.29+ / Dart 3.3+**. `CardThemeData` and `Color.withValues`
are used, which need Flutter 3.27+; 3.29 is the version the theme was written
against.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Release build:

```bash
flutter build apk --split-per-abi --release
```

Full instructions, signing, and size measurement: `docs/MOBILE_BUILD.md`.

The demonstration environment (tamper simulation) is compiled out by default:

```bash
flutter run --dart-define=DRUSIGHT_DEMO=true
```

---

## ML pipeline

```bash
cd ml_training
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

python scripts/prepare_dataset.py        # ingest + validate + dedupe
python scripts/split_dataset.py          # group-aware split, no leakage
python scripts/train.py                  # baselines + grouped CV selection
python scripts/evaluate.py --model models/<selected>.joblib
python scripts/export_model.py ...       # ONNX + manifest
```

See `ml_training/README.md` and `docs/MODEL_TRAINING.md`.

---

## Repository layout

```
lib/
  app/           shell, theme, composition root
  config/        versioned constants and thresholds
  models/        domain types (no logic)
  cv/            colour science, calibration, detection, features
  analysis/      capture guard, rules, anomalies, reliability, pipeline
  ml/            classifier interface + mock + ONNX integration point
  security/      canonical JSON, hashing, keys, signing, hash chain
  location/      acquisition + integrity checking
  database/      SQLite schema and connection
  repositories/  data access
  services/      orchestration (workflow, evidence, QR, reports, demo)
  screens/       UI
  widgets/       shared UI components
assets/
  kits/          versioned kit profiles
  knowledge/     offline knowledge base
  tutorials/     offline learning content
ml_training/     Python training pipeline
test/            unit, security, integration tests
docs/            architecture, dataset, security, validation, limitations
```

---

## Documentation

| Document | Contents |
|---|---|
| `docs/ARCHITECTURE.md` | Module map, data flow, key decisions |
| `docs/DATASET_GUIDE.md` | Required data, column meanings, provenance |
| `docs/MODEL_TRAINING.md` | Training procedure and reproducibility |
| `docs/MODEL_EVALUATION.md` | What is measured and how it must be reported |
| `docs/MOBILE_BUILD.md` | Build, sign, measure APK size |
| `docs/SECURITY.md` | Threat model and what the crypto does and does not prove |
| `docs/DATABASE.md` | Schema and migrations |
| `docs/TESTING.md` | Test strategy and coverage |
| `docs/DEMO_GUIDE.md` | The 24-step demonstration script |
| `docs/LIMITATIONS.md` | Everything this system cannot do |
| `docs/VALIDATION_PLAN.md` | What validation would require |

---

## Research context

These informed the architecture. **None of them validates DruSight.**

- Krauss et al. (2016), *Objective Method for Presumptive Field-Testing of
  Illicit Drug Possession Using Centrifugal Microdevices and Smartphone
  Analysis*, Anal. Chem. DOI 10.1021/acs.analchem.6b01982, PMID 27525468 —
  evidence that quantitative smartphone colour analysis is technically
  plausible. DruSight deliberately does **not** copy its custom hardware,
  because it must work with existing kits.
- NIST, *Forensic Seized Drug Analysis: Current Challenges and Emerging
  Analytical Solutions* — background on real analytical challenges and
  validation requirements.
- NIST, *Characterized Authentic Drug Samples (CADS)* — an architectural model
  for what serious algorithm validation requires. CADS physical samples are
  **not** assumed to be available to this project.

---

## Safety and scope

This project does not obtain, synthesise, manufacture, extract or handle
controlled substances, and contains no information about doing so. The
knowledge base covers presumptive test methodology and safety only.

---

## Verification status

**Verified by execution on this machine** (Flutter 3.47.5 / Dart 3.13.4):

- `flutter pub get` — all 100 dependencies resolve.
- `flutter analyze` — **No issues found.** Zero errors, zero warnings, zero
  lints across 82 source files.
- `flutter test` — **98/98 passing**, first run to last.
- CIEDE2000 and sRGB to Lab checked against all 30 Sharma-Wu-Dalal published
  vectors (max deviation 5e-5).
- The calibration solver: residual ~2e-6 for affine distortions, rising
  monotonically under highlight clipping.
- The Python ML pipeline, end to end, including the empty-input and
  unseen-device paths.
- The printable reference card: PDF geometry checked patch-by-patch against
  the kit profile, and both PDFs render.

