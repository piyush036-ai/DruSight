# Model evaluation

## Status

**No evaluation results exist.** No model has been trained on real data.
`VALIDATION PENDING`.

## What `evaluate.py` produces

- Confusion matrix, rows = true labels.
- Per-class precision, recall, F1, **with support**, and an `underpowered` flag
  when support is below 10.
- Balanced accuracy.
- False positives and false negatives for the POSITIVE class as raw counts.
- Probability calibration (Brier score) only when the model is genuinely
  binary-probabilistic; otherwise it records that calibration was not assessed
  and why.
- Robustness slices by device model, lighting condition and quality label.
- A warnings list that always includes the reminder that these are internal
  held-out figures, not validation.

## What it refuses to produce

- **Sensitivity and specificity** unless the problem is genuinely binary with
  an unambiguous positive class. Quoting them for a three-class problem is a
  category error that makes a system sound more medical than it is.
- **Any metric without its support.** A 100% recall over 3 samples is not a
  performance figure.
- **Confidence percentages in the app.** `classProbabilities` stays null unless
  calibration has been assessed on an independent set. An uncalibrated softmax
  presented as confidence is a fabricated number.

## Why false positives are broken out

In this domain a false presumptive positive is the consequential error: it can
lead to a detention that confirmatory testing later overturns. It is reported
as a raw count rather than a rate, because on a small evaluation set a rate
implies a precision the data does not support.

## Interpreting the four tiers

| Tier | What it means | May be called |
|---|---|---|
| Training CV | Grouped cross-validation on the training split | "training performance" |
| Internal held-out | The test split from the same collection | "internal evaluation" |
| External | Independent organisation, samples, devices, operators | "external validation" |
| Operational | Field use with laboratory confirmation on every case | "operational performance" |

Only the third permits the word *validated*, and only with its scope stated.
`docs/VALIDATION_PLAN.md` sets out what each requires.

## The synthetic-data trap

`make_synthetic_demo_data.py` produces two well-separated Gaussian clusters
from a random number generator. A classifier will score near-perfectly on it.
That number describes the RNG. It has appeared in no report here and must
appear in none.
