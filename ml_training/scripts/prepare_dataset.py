#!/usr/bin/env python3
"""Ingest and validate a raw DruSight dataset.

Reads every CSV in data/raw/, validates required metadata, deduplicates,
and writes a single processed table plus a data-quality report.

Hard rule from the master spec (section 18): never silently discard data.
Every row that is dropped is counted, categorised, and written to
data/processed/rejected.csv so the loss is visible and auditable.

Usage:
    python scripts/prepare_dataset.py
    python scripts/prepare_dataset.py --raw-dir data/raw --out-dir data/processed
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from schema import (  # noqa: E402
    FEATURE_NAMES,
    LABELS,
    OPTIONAL_METADATA,
    REQUIRED_METADATA,
)


def row_fingerprint(row: pd.Series) -> str:
    """Stable hash over the feature values plus sample identity.

    Used for deduplication. Two rows from the same physical sample with
    bit-identical features are the same observation recorded twice, which
    would otherwise inflate the apparent dataset size and leak across splits.
    """
    parts = [str(row.get("sample_id", ""))]
    parts += [f"{float(row[name]):.6f}" for name in FEATURE_NAMES if name in row]
    return hashlib.sha256("|".join(parts).encode()).hexdigest()


def load_raw(raw_dir: Path) -> tuple[pd.DataFrame, list[str]]:
    files = sorted(raw_dir.glob("*.csv"))
    if not files:
        return pd.DataFrame(), []

    frames = []
    for path in files:
        frame = pd.read_csv(path)
        frame["_source_file"] = path.name
        frames.append(frame)
    return pd.concat(frames, ignore_index=True), [f.name for f in files]


def validate(frame: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    """Split into accepted and rejected rows, tagging each rejection reason."""
    if frame.empty:
        return frame, frame

    rejected = []

    missing_cols = [c for c in REQUIRED_METADATA + FEATURE_NAMES
                    if c not in frame.columns]
    if missing_cols:
        raise SystemExit(
            "Raw data is missing required columns: "
            + ", ".join(missing_cols)
            + "\nSee ml_training/README.md for the expected CSV layout."
        )

    work = frame.copy()
    work["_reject_reason"] = ""

    # Missing required metadata.
    for column in REQUIRED_METADATA:
        blank = work[column].isna() | (work[column].astype(str).str.strip() == "")
        work.loc[blank & (work["_reject_reason"] == ""), "_reject_reason"] = (
            f"missing_{column}"
        )

    # Non-finite or missing feature values.
    numeric = work[FEATURE_NAMES].apply(pd.to_numeric, errors="coerce")
    bad_features = ~numeric.notna().all(axis=1)
    work.loc[bad_features & (work["_reject_reason"] == ""), "_reject_reason"] = (
        "non_numeric_feature"
    )

    # Unknown label.
    unknown_label = ~work["label"].astype(str).str.upper().isin(LABELS)
    work.loc[unknown_label & (work["_reject_reason"] == ""), "_reject_reason"] = (
        "unknown_label"
    )

    rejected_frame = work[work["_reject_reason"] != ""].copy()
    accepted = work[work["_reject_reason"] == ""].copy()
    accepted = accepted.drop(columns=["_reject_reason"])
    accepted[FEATURE_NAMES] = numeric.loc[accepted.index]
    accepted["label"] = accepted["label"].astype(str).str.upper()

    rejected.append(rejected_frame)
    return accepted, pd.concat(rejected, ignore_index=True)


def deduplicate(frame: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    if frame.empty:
        return frame, frame
    frame = frame.copy()
    frame["_fingerprint"] = frame.apply(row_fingerprint, axis=1)
    duplicated = frame.duplicated(subset="_fingerprint", keep="first")
    dupes = frame[duplicated].copy()
    dupes["_reject_reason"] = "exact_duplicate"
    kept = frame[~duplicated].drop(columns=["_fingerprint"])
    return kept, dupes


def quality_report(
    accepted: pd.DataFrame,
    rejected: pd.DataFrame,
    duplicates: pd.DataFrame,
    source_files: list[str],
) -> dict:
    report: dict = {
        "sourceFiles": source_files,
        "rowsAccepted": int(len(accepted)),
        "rowsRejected": int(len(rejected)),
        "rowsDuplicate": int(len(duplicates)),
    }

    if not rejected.empty:
        report["rejectionReasons"] = (
            rejected["_reject_reason"].value_counts().to_dict()
        )

    if accepted.empty:
        report["warning"] = (
            "No usable rows. Nothing downstream can be trained or evaluated."
        )
        return report

    report["labelCounts"] = accepted["label"].value_counts().to_dict()
    report["uniqueSamples"] = int(accepted["sample_id"].nunique())
    report["uniqueSessions"] = int(accepted["session_id"].nunique())
    report["uniqueDevices"] = int(accepted["device_model"].nunique())
    report["uniqueLightingConditions"] = int(
        accepted["lighting_condition"].nunique()
    )
    report["kitProfiles"] = (
        accepted.groupby(["kit_id", "kit_profile_version"])
        .size()
        .reset_index(name="count")
        .to_dict(orient="records")
    )

    # Class balance is reported rather than corrected. Rebalancing a tiny
    # dataset by resampling would make the evaluation look better without
    # making the model better.
    counts = accepted["label"].value_counts()
    report["classImbalanceRatio"] = (
        round(float(counts.max() / counts.min()), 3) if counts.min() > 0 else None
    )

    if "quality_label" in accepted.columns:
        report["qualityLabelCounts"] = (
            accepted["quality_label"].fillna("unlabelled").value_counts().to_dict()
        )

    # Warn where the dataset is too small or too narrow to support a claim.
    warnings = []
    if report["uniqueSamples"] < 30:
        warnings.append(
            f"Only {report['uniqueSamples']} distinct physical samples. Any "
            "performance figure from this dataset describes these samples, "
            "not the method."
        )
    if report["uniqueDevices"] < 3:
        warnings.append(
            f"Only {report['uniqueDevices']} device model(s) represented. "
            "Cross-device robustness cannot be assessed."
        )
    if report["uniqueLightingConditions"] < 3:
        warnings.append(
            f"Only {report['uniqueLightingConditions']} lighting condition(s). "
            "Illumination robustness cannot be assessed."
        )
    if warnings:
        report["warnings"] = warnings

    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", default="data/raw", type=Path)
    parser.add_argument("--out-dir", default="data/processed", type=Path)
    parser.add_argument("--report-dir", default="reports", type=Path)
    args = parser.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    args.report_dir.mkdir(parents=True, exist_ok=True)

    raw, source_files = load_raw(args.raw_dir)
    if raw.empty:
        report = {
            "sourceFiles": [],
            "rowsAccepted": 0,
            "status": "NO_DATA",
            "message": (
                "No CSV files found in "
                f"{args.raw_dir}. The pipeline is complete and runnable; it "
                "is waiting on authorised, characterised data. See "
                "docs/DATASET_GUIDE.md."
            ),
        }
        (args.report_dir / "data_quality.json").write_text(
            json.dumps(report, indent=2)
        )
        print(json.dumps(report, indent=2))
        return 0

    accepted, rejected = validate(raw)
    accepted, duplicates = deduplicate(accepted)

    accepted.to_csv(args.out_dir / "dataset.csv", index=False)
    if not rejected.empty or not duplicates.empty:
        all_rejected = pd.concat(
            [r for r in (rejected, duplicates) if not r.empty],
            ignore_index=True,
        )
        all_rejected.to_csv(args.out_dir / "rejected.csv", index=False)

    report = quality_report(accepted, rejected, duplicates, source_files)
    (args.report_dir / "data_quality.json").write_text(json.dumps(report, indent=2))

    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
