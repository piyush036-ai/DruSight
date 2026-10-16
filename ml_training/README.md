# DruSight ML training pipeline

Reproducible, offline training for the local classifier. Nothing here requires
a cloud service or a GPU.

## Status

**No trained model ships with this repository.** The pipeline is complete and
runnable; it is waiting on authorised, characterised data. Until such a model
exists the app runs `MockClassifierService`, which reports that no model is
available rather than inventing a prediction.

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## The pipeline

```bash
# 1. Validate and deduplicate raw data -> data/processed/dataset.csv
python scripts/prepare_dataset.py

# 2. Group-aware split -> data/splits/{train,validation,test}.csv
python scripts/split_dataset.py
# or, for an explicit unseen-device evaluation:
python scripts/split_dataset.py --hold-out-device "Pixel 7a"

# 3. Train candidates, select by grouped CV -> models/<name>.joblib
python scripts/train.py

# 4. Evaluate on the held-out split -> reports/evaluation.json
python scripts/evaluate.py --model models/random_forest.joblib

# 5. Export for the phone (needs skl2onnx)
python scripts/export_model.py \
  --model models/random_forest.joblib \
  --model-id ds-demo-001-clf --model-version 0.1.0 --kit-id DS-DEMO-001
```

Every script writes a JSON report to `reports/` and prints it to stdout.

## Input format

`data/raw/*.csv`, one row per captured frame. Required columns are listed in
`scripts/schema.py` (`REQUIRED_METADATA` + `FEATURE_NAMES`). See
`../docs/DATASET_GUIDE.md` for what each column means and how to produce it.

The feature column order in `schema.py` must stay identical to
`ColourFeatures.featureNames` in `lib/models/colour_features.dart`. Both
declare `features-0.1.0`; change either and you must bump both.

## Exercising the pipeline without real data

```bash
python scripts/make_synthetic_demo_data.py --samples 40
```

This writes numbers from a random number generator, tagged
`ground_truth_source=SYNTHETIC_NOT_REAL`. It exists so a developer can confirm
the plumbing works. Any metric computed from it describes the RNG. It must
never appear in a presentation or report as evidence of anything.

## What the scripts refuse to do

- `prepare_dataset.py` never silently drops a row. Rejections are counted,
  categorised, and written to `data/processed/rejected.csv`.
- `split_dataset.py` splits by physical sample, never by row, and fails with a
  `LEAKAGE` error if a group lands on both sides.
- `train.py` reports cross-validation figures as training-split figures and
  refuses to train on a single-class split.
- `evaluate.py` prints support alongside every metric, flags any metric with
  fewer than 10 supporting rows as `underpowered`, and does not emit
  sensitivity/specificity unless the problem is genuinely binary.
