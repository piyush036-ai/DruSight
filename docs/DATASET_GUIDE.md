# Dataset guide

## Legal and ethical position

This project does not obtain, synthesise, manufacture, extract or handle
controlled substances. Data must come from an authorised holder operating under
their own legal framework — a forensic laboratory, a law-enforcement training
programme, or an equivalent authorised body — with ground truth established by
confirmatory instrumental analysis.

Where authorised samples are unavailable, the pipeline can be exercised with
controlled safe test materials (pH indicators, food-colouring dilutions,
printed colour targets). Data from such materials characterises **the
measurement system**, not the chemistry, and must be labelled as such.

**Never fabricate ground truth.**

## Input format

`ml_training/data/raw/*.csv`, one row per captured frame. Columns are defined
in `ml_training/scripts/schema.py`.

### Required metadata

| Column | Meaning |
|---|---|
| `sample_id` | The physical sample/test. **The grouping key for splitting.** Every frame of one physical test shares it. |
| `session_id` | Capture session. |
| `kit_id` | Kit profile identifier, e.g. `DS-DEMO-001`. |
| `kit_profile_version` | Exact profile version used. |
| `device_model` | Handset. Needed for cross-device robustness. |
| `lighting_condition` | Controlled vocabulary, e.g. `daylight_diffuse`, `indoor_fluorescent`, `low_light`. |
| `captured_at_utc` | ISO 8601 UTC. |
| `label` | `POSITIVE`, `NEGATIVE` or `INCONCLUSIVE`. |
| `ground_truth_source` | How the label was established, e.g. `GC-MS confirmed, lab ref 1234`. Free text, but must be specific. A row whose provenance cannot be stated should not be in the dataset. |

### Optional metadata

`reaction_offset_seconds`, `operator_id`, `quality_label`,
`calibration_residual_delta_e`, `provenance_note`.

`quality_label` uses: `good`, `blur`, `glare`, `poor_lighting`, `overexposed`,
`underexposed`, `missing_card`, `incorrect_framing`, `unstable_reaction`. These
drive the robustness slices in `evaluate.py`.

### Features

The 21 feature columns, in the exact order given by `FEATURE_NAMES`:

```
mean_r, mean_g, mean_b,
median_r, median_g, median_b,
std_r, std_g, std_b,
hue_circular_mean, hue_std,
saturation_mean, value_mean,
lab_l, lab_a, lab_b,
delta_e_from_reference,
spatial_uniformity, edge_density,
p05_luminance, p95_luminance
```

This order **is** the schema. It must match `ColourFeatures.featureNames` in
`lib/models/colour_features.dart`. Both declare `features-0.1.0`; changing
either requires bumping both.

All feature values must be extracted from **calibrated** pixels, using the same
`FeatureExtractor` the app uses. Extracting them any other way produces a
training distribution the deployed extractor will never reproduce.

`delta_e_from_reference` is `-1.0` when the kit profile defines no baseline —
an impossible CIEDE2000 value, so the model can distinguish "no baseline" from
"zero distance".

## What the pipeline does with it

`prepare_dataset.py`:
- rejects rows with missing required metadata, non-numeric features, or an
  unknown label;
- removes exact duplicates by fingerprint over `sample_id` + features;
- **never silently drops anything** — every rejection is counted, categorised,
  and written to `data/processed/rejected.csv`;
- reports class balance, sample/session/device/lighting counts, and warns when
  the dataset is too small or too narrow to support any claim.

`split_dataset.py`:
- splits by `sample_id`, never by row. Several photographs of one physical test
  are near-identical; a row-level split would put some in train and some in
  test, and the resulting score would measure memorisation;
- supports `--hold-out-device` for an explicit unseen-device evaluation;
- fails with a `LEAKAGE` error if any group lands on both sides;
- records its methodology in `reports/split_summary.json`.

## Collection guidance

To support any claim about robustness, vary deliberately:

- **Devices** — at least 3, ideally 5+, across sensor generations and
  manufacturers.
- **Lighting** — daylight diffuse, daylight direct, indoor warm, indoor
  fluorescent, low light. At least 3.
- **Angle and distance** — within the range the capture guide permits.
- **Operators** — to capture handling variation.
- **Deliberate bad captures** — labelled with `quality_label`. The quality
  gates need negative examples as much as the classifier needs positive ones.

Record **multiple frames per physical sample** and give them the same
`sample_id`. That is what makes the grouped split meaningful.

## Directory layout

```
ml_training/data/
  raw/         input CSVs, provenance-controlled, gitignored
  processed/   dataset.csv + rejected.csv
  features/    intermediate feature files
  splits/      train.csv, validation.csv, test.csv
```

Nothing under `data/` is committed. Datasets are provenance-controlled and
version them outside the source repository.
