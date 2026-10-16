# Model training

Full command reference: `ml_training/README.md`.

## Status

No trained model exists. The pipeline runs end to end and is waiting on
authorised, characterised data (`docs/DATASET_GUIDE.md`).

## Why classical models

The feature vector is 21 tabular values derived from calibrated colour. On that
input, a gradient-boosted tree or a regularised linear model is at least as
accurate as a neural network and is inspectable: you can look at which features
drove a decision and check whether it is chemically sensible. In a forensic
context an unexplainable model is the wrong tool, and "it's a neural network"
is not an answer a reviewer should have to accept.

Candidates trained: logistic regression, random forest, RBF SVM, gradient
boosting. All wrapped in a `StandardScaler` so the exported artefacts are
interchangeable (the feature vector mixes 0-255 channel values, 0-360 degrees
and 0-1 saturation).

## Selection

Grouped cross-validation on the **training split only**, scored by balanced
accuracy, grouped by `sample_id`. The test split is never touched during
training; `evaluate.py` consumes it once.

If there are fewer than two distinct sample groups, `train.py` says so and
records that no model-selection evidence exists, rather than fabricating a
fold. If the training split has only one class, it refuses to train.

## Reproducibility

- Seeds are explicit (`--seed`, default `20260925`) and recorded in
  `reports/training_summary.json`.
- Split methodology and its rationale are recorded in
  `reports/split_summary.json`.
- Every report carries `featureSchemaVersion`.
- Old models are never overwritten; each export is `<id>_<version>.onnx`.

## Export and deployment

```bash
python scripts/export_model.py \
  --model models/random_forest.joblib \
  --model-id ds-demo-001-clf \
  --model-version 0.1.0 \
  --kit-id DS-DEMO-001
```

Emits the ONNX file plus a manifest with the feature schema, class order, input
shape and SHA-256. Then:

1. Copy the `.onnx` into `drusight/assets/models/`.
2. Insert a `model_versions` row with the SHA-256. The app verifies the asset
   hash before use, so a swapped or corrupted model fails loudly.
3. Set `modelId` and `modelVersion` in the kit profile JSON.
4. Implement `_runInference` in `lib/ml/onnx_classifier_service.dart`.
5. Register `OnnxClassifierService` in `lib/app/service_locator.dart` in place
   of `MockClassifierService`.

The app refuses to run a model whose `featureSchemaVersion` differs from the
extractor's. A differently-shaped vector produces confident nonsense rather
than an error, so this is a hard stop rather than a warning.

## Rules

- Never train on the test split.
- Never tune thresholds against the test split, then reuse it.
- Never describe cross-validation figures as validation.
- Never ship a model without recording its version, schema and asset hash.
