#!/usr/bin/env python3
"""Train baseline classifiers (master spec section 22).

Starts with interpretable, low-variance models. Deep learning is deliberately
not used: with a small tabular feature set it would add opacity and
overfitting without adding signal, and an unexplainable model is the wrong
tool for a forensic context.

Model selection uses grouped cross-validation on the TRAINING split only. The
test split is not touched here - it is consumed once, by evaluate.py.

Usage:
    python scripts/train.py
    python scripts/train.py --model random_forest
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import GradientBoostingClassifier, RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GroupKFold, cross_val_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC

sys.path.insert(0, str(Path(__file__).resolve().parent))
from schema import FEATURE_NAMES, FEATURE_SCHEMA_VERSION  # noqa: E402


def build_models(seed: int) -> dict[str, Pipeline]:
    """Candidate models.

    All are wrapped in a scaler because the feature vector mixes units
    (0-255 channel values, 0-360 degrees, 0-1 saturation). Tree models do not
    need it, but keeping the pipeline shape identical makes the exported
    artefacts interchangeable.
    """
    return {
        "logistic_regression": Pipeline([
            ("scale", StandardScaler()),
            ("clf", LogisticRegression(
                max_iter=2000,
                class_weight="balanced",
                random_state=seed,
            )),
        ]),
        "random_forest": Pipeline([
            ("scale", StandardScaler()),
            ("clf", RandomForestClassifier(
                n_estimators=300,
                min_samples_leaf=2,
                class_weight="balanced",
                random_state=seed,
                n_jobs=-1,
            )),
        ]),
        "svm_rbf": Pipeline([
            ("scale", StandardScaler()),
            # No probability=True: it is deprecated in scikit-learn 1.9 and
            # removed in 1.11, and we do not use SVC probabilities. An
            # uncalibrated SVC probability would not be exported to the app
            # anyway (see docs/MODEL_EVALUATION.md), so asking for one would
            # cost a 5-fold internal refit to produce a number we discard.
            ("clf", SVC(
                kernel="rbf",
                class_weight="balanced",
                random_state=seed,
            )),
        ]),
        "gradient_boosting": Pipeline([
            ("scale", StandardScaler()),
            ("clf", GradientBoostingClassifier(random_state=seed)),
        ]),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--splits-dir", default="data/splits", type=Path)
    parser.add_argument("--out-dir", default="models", type=Path)
    parser.add_argument("--report-dir", default="reports", type=Path)
    parser.add_argument("--model", default=None,
                        help="Train only this model; default trains all and "
                             "selects by grouped CV.")
    parser.add_argument("--seed", type=int, default=20260925)
    args = parser.parse_args()

    train_path = args.splits_dir / "train.csv"
    if not train_path.exists():
        print(
            f"No training split at {train_path}. Run split_dataset.py first.",
            file=sys.stderr,
        )
        return 1

    frame = pd.read_csv(train_path)
    if frame.empty:
        print("Training split is empty.", file=sys.stderr)
        return 1

    x = frame[FEATURE_NAMES].to_numpy(dtype=float)
    y = frame["label"].to_numpy()
    groups = frame["sample_id"].to_numpy()

    distinct_classes = len(np.unique(y))
    if distinct_classes < 2:
        print(
            f"Training split contains only {distinct_classes} class. A "
            "classifier cannot be trained. This is a data problem, not a "
            "code problem.",
            file=sys.stderr,
        )
        return 1

    args.out_dir.mkdir(parents=True, exist_ok=True)
    args.report_dir.mkdir(parents=True, exist_ok=True)

    candidates = build_models(args.seed)
    if args.model:
        if args.model not in candidates:
            print(f"Unknown model {args.model!r}.", file=sys.stderr)
            return 1
        candidates = {args.model: candidates[args.model]}

    n_groups = len(np.unique(groups))
    n_splits = min(5, n_groups)
    results: dict[str, dict] = {}

    for name, pipeline in candidates.items():
        entry: dict = {}
        if n_splits >= 2:
            scores = cross_val_score(
                pipeline,
                x,
                y,
                groups=groups,
                cv=GroupKFold(n_splits=n_splits),
                scoring="balanced_accuracy",
            )
            entry["cvFolds"] = int(n_splits)
            entry["cvBalancedAccuracyMean"] = round(float(scores.mean()), 4)
            entry["cvBalancedAccuracyStd"] = round(float(scores.std()), 4)
            entry["cvScores"] = [round(float(s), 4) for s in scores]
        else:
            # Honest about it rather than fabricating a fold.
            entry["cvFolds"] = 0
            entry["cvBalancedAccuracyMean"] = None
            entry["note"] = (
                f"Only {n_groups} distinct sample group(s); grouped "
                "cross-validation is not possible. No model-selection "
                "evidence is available."
            )
        results[name] = entry

    scored = {
        k: v["cvBalancedAccuracyMean"]
        for k, v in results.items()
        if v.get("cvBalancedAccuracyMean") is not None
    }
    selected = (
        max(scored, key=lambda k: scored[k]) if scored
        else next(iter(candidates))
    )

    final = candidates[selected]
    final.fit(x, y)
    model_path = args.out_dir / f"{selected}.joblib"
    joblib.dump(final, model_path)

    summary = {
        "featureSchemaVersion": FEATURE_SCHEMA_VERSION,
        "featureNames": FEATURE_NAMES,
        "trainingRows": int(len(frame)),
        "trainingGroups": int(n_groups),
        "classes": sorted(np.unique(y).tolist()),
        "candidates": results,
        "selectedModel": selected,
        "selectionCriterion": (
            "highest mean balanced accuracy under grouped cross-validation"
            if scored else
            "no cross-validation evidence available; first candidate used"
        ),
        "modelPath": str(model_path),
        "seed": args.seed,
        "caveat": (
            "These are TRAINING-SPLIT cross-validation figures. They are not "
            "validation results and must never be presented as accuracy of "
            "the deployed system."
        ),
    }

    (args.report_dir / "training_summary.json").write_text(
        json.dumps(summary, indent=2)
    )
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
