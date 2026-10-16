#!/usr/bin/env python3
"""Evaluate a trained model (master spec sections 23, 24).

Produces a confusion matrix, per-class precision/recall/F1, balanced accuracy,
probability calibration if the model is probabilistic, and error slices by
device, lighting and quality label.

What this script will NOT do:
  - print sensitivity or specificity unless the evaluation is binary AND the
    positive class is unambiguous;
  - describe any figure as validated;
  - report a metric whose support is too small to mean anything without
    printing the support alongside it.

Usage:
    python scripts/evaluate.py --model models/random_forest.joblib
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import (
    balanced_accuracy_score,
    brier_score_loss,
    classification_report,
    confusion_matrix,
)

sys.path.insert(0, str(Path(__file__).resolve().parent))
from schema import FEATURE_NAMES  # noqa: E402

#: Below this many rows a per-class metric is reported with an explicit
#: warning rather than presented as a performance figure.
MIN_SUPPORT_FOR_METRIC = 10


def slice_errors(
    frame: pd.DataFrame, predictions: np.ndarray, column: str
) -> list[dict]:
    if column not in frame.columns:
        return []
    out = []
    work = frame.copy()
    work["_predicted"] = predictions
    work["_correct"] = work["_predicted"] == work["label"]
    for value, group in work.groupby(column):
        out.append({
            column: str(value),
            "support": int(len(group)),
            "correct": int(group["_correct"].sum()),
            "accuracy": round(float(group["_correct"].mean()), 4),
            "underpowered": bool(len(group) < MIN_SUPPORT_FOR_METRIC),
        })
    return sorted(out, key=lambda r: -r["support"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--split", default="data/splits/test.csv", type=Path)
    parser.add_argument("--report-dir", default="reports", type=Path)
    args = parser.parse_args()

    if not args.model.exists():
        print(f"No model at {args.model}.", file=sys.stderr)
        return 1
    if not args.split.exists():
        print(f"No evaluation split at {args.split}.", file=sys.stderr)
        return 1

    frame = pd.read_csv(args.split)
    if frame.empty:
        report = {
            "status": "NO_TEST_DATA",
            "message": (
                "The evaluation split is empty, so no performance figure "
                "exists. VALIDATION PENDING."
            ),
        }
        args.report_dir.mkdir(parents=True, exist_ok=True)
        (args.report_dir / "evaluation.json").write_text(
            json.dumps(report, indent=2)
        )
        print(json.dumps(report, indent=2))
        return 0

    model = joblib.load(args.model)
    x = frame[FEATURE_NAMES].to_numpy(dtype=float)
    y = frame["label"].to_numpy()
    predictions = model.predict(x)

    labels = sorted(set(y.tolist()) | set(predictions.tolist()))
    matrix = confusion_matrix(y, predictions, labels=labels)

    per_class = classification_report(
        y, predictions, labels=labels, output_dict=True, zero_division=0
    )

    report: dict = {
        "model": str(args.model),
        "split": str(args.split),
        "rows": int(len(frame)),
        "distinctSamples": int(frame["sample_id"].nunique())
        if "sample_id" in frame.columns else None,
        "labels": labels,
        "confusionMatrix": {
            "order": labels,
            "rowsAreTrue": True,
            "matrix": matrix.tolist(),
        },
        "balancedAccuracy": round(
            float(balanced_accuracy_score(y, predictions)), 4
        ),
        "perClass": {
            label: {
                "precision": round(float(per_class[label]["precision"]), 4),
                "recall": round(float(per_class[label]["recall"]), 4),
                "f1": round(float(per_class[label]["f1-score"]), 4),
                "support": int(per_class[label]["support"]),
                "underpowered": bool(
                    per_class[label]["support"] < MIN_SUPPORT_FOR_METRIC
                ),
            }
            for label in labels if label in per_class
        },
    }

    # False positives and negatives, listed explicitly. In this domain a false
    # POSITIVE is the consequential error, so it is broken out.
    if "POSITIVE" in labels:
        false_positive = int(
            ((predictions == "POSITIVE") & (y != "POSITIVE")).sum()
        )
        false_negative = int(
            ((predictions != "POSITIVE") & (y == "POSITIVE")).sum()
        )
        report["positiveClassErrors"] = {
            "falsePositives": false_positive,
            "falseNegatives": false_negative,
            "note": (
                "A false presumptive positive is the consequential error in "
                "this domain. It is reported as a raw count, not a rate, "
                "because the support here is too small for a rate to be "
                "meaningful."
            ),
        }

    # Probability calibration, only where genuinely probabilistic.
    if hasattr(model, "predict_proba") and len(labels) == 2:
        probabilities = model.predict_proba(x)
        positive_index = (
            list(model.classes_).index("POSITIVE")
            if "POSITIVE" in list(model.classes_) else 1
        )
        report["calibration"] = {
            "brierScore": round(
                float(
                    brier_score_loss(
                        (y == model.classes_[positive_index]).astype(int),
                        probabilities[:, positive_index],
                    )
                ),
                4,
            ),
            "note": (
                "Brier score over the evaluation split. Probabilities are NOT "
                "surfaced in the application unless calibration has been "
                "assessed on an independent set."
            ),
        }
    else:
        report["calibration"] = {
            "assessed": False,
            "reason": (
                "Model is not binary-probabilistic, or probabilities were not "
                "requested. No confidence figure is exported to the app."
            ),
        }

    report["robustnessSlices"] = {
        "byDevice": slice_errors(frame, predictions, "device_model"),
        "byLighting": slice_errors(frame, predictions, "lighting_condition"),
        "byQualityLabel": slice_errors(frame, predictions, "quality_label"),
    }

    warnings = []
    if report["rows"] < 50:
        warnings.append(
            f"Evaluation set has {report['rows']} rows. Every figure above "
            "describes this specific small set and must not be presented as "
            "the performance of the method."
        )
    if report.get("distinctSamples") and report["distinctSamples"] < 20:
        warnings.append(
            f"Only {report['distinctSamples']} distinct physical samples in "
            "the evaluation set."
        )
    warnings.append(
        "These are INTERNAL evaluation figures on a held-out split. They are "
        "not external validation and not real-world validation. See "
        "docs/VALIDATION_PLAN.md."
    )
    report["warnings"] = warnings

    args.report_dir.mkdir(parents=True, exist_ok=True)
    (args.report_dir / "evaluation.json").write_text(
        json.dumps(report, indent=2)
    )
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
