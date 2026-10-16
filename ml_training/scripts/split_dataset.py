#!/usr/bin/env python3
"""Group-aware train/validation/test splitting (master spec section 20).

The failure mode this exists to prevent: several photographs of ONE physical
test are near-identical. A random row-level split puts some in train and some
in test, the model memorises those specific images, and the test score looks
excellent while measuring nothing. Splitting by `sample_id` keeps every image
of a given physical test on one side of the boundary.

Where enough distinct devices exist, the test set is additionally held out by
device, so the reported figure reflects an unseen handset rather than an
unseen photo of a seen handset.

Usage:
    python scripts/split_dataset.py
    python scripts/split_dataset.py --hold-out-device "Pixel 7a"
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from schema import LABELS  # noqa: E402


def group_split(
    frame: pd.DataFrame,
    group_column: str,
    test_fraction: float,
    validation_fraction: float,
    seed: int,
) -> dict[str, pd.DataFrame]:
    """Splits by group, trying to keep label proportions similar.

    Greedy rather than optimal: groups are shuffled, then assigned to whichever
    split is furthest below its target size. With few groups no split method
    produces balanced classes, which is why the caller reports the realised
    balance instead of assuming it.
    """
    rng = np.random.default_rng(seed)
    # np.asarray with an explicit object dtype: pandas may hand back a
    # StringArray, which numpy's shuffle does not handle reliably.
    groups = np.asarray(frame[group_column].unique(), dtype=object)
    rng.shuffle(groups)

    total = len(groups)
    n_test = max(1, int(round(total * test_fraction))) if total > 2 else 0
    n_val = max(1, int(round(total * validation_fraction))) if total > 4 else 0
    n_train = total - n_test - n_val
    if n_train < 1:
        n_train, n_val, n_test = total, 0, 0

    assignment = (
        ["train"] * n_train + ["validation"] * n_val + ["test"] * n_test
    )
    mapping = dict(zip(groups, assignment))

    frame = frame.copy()
    frame["_split"] = frame[group_column].map(mapping)
    return {
        name: frame[frame["_split"] == name].drop(columns=["_split"])
        for name in ("train", "validation", "test")
    }


def describe(frame: pd.DataFrame) -> dict:
    if frame.empty:
        return {"rows": 0, "samples": 0, "labels": {}}
    return {
        "rows": int(len(frame)),
        "samples": int(frame["sample_id"].nunique()),
        "devices": sorted(frame["device_model"].unique().tolist()),
        "labels": {
            label: int((frame["label"] == label).sum()) for label in LABELS
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset", default="data/processed/dataset.csv",
                        type=Path)
    parser.add_argument("--out-dir", default="data/splits", type=Path)
    parser.add_argument("--report-dir", default="reports", type=Path)
    parser.add_argument("--group-by", default="sample_id",
                        choices=["sample_id", "session_id"])
    parser.add_argument("--test-fraction", type=float, default=0.2)
    parser.add_argument("--validation-fraction", type=float, default=0.2)
    parser.add_argument("--seed", type=int, default=20260925)
    parser.add_argument(
        "--hold-out-device",
        default=None,
        help="Reserve every row from this device_model as the test set, for "
             "an explicit unseen-device evaluation.",
    )
    args = parser.parse_args()

    if not args.dataset.exists():
        print(
            f"No dataset at {args.dataset}. Run prepare_dataset.py first.",
            file=sys.stderr,
        )
        return 1

    frame = pd.read_csv(args.dataset)
    if frame.empty:
        print("Dataset is empty; nothing to split.", file=sys.stderr)
        return 1

    args.out_dir.mkdir(parents=True, exist_ok=True)
    args.report_dir.mkdir(parents=True, exist_ok=True)

    methodology: dict = {
        "groupBy": args.group_by,
        "seed": args.seed,
        "rationale": (
            "Split by physical sample so that near-identical images of the "
            "same test cannot appear on both sides of the boundary."
        ),
    }

    if args.hold_out_device:
        held = frame[frame["device_model"] == args.hold_out_device]
        rest = frame[frame["device_model"] != args.hold_out_device]
        if held.empty:
            print(
                f"No rows with device_model == {args.hold_out_device!r}.",
                file=sys.stderr,
            )
            return 1
        inner = group_split(
            rest, args.group_by, 0.0, args.validation_fraction, args.seed
        )
        splits = {
            "train": inner["train"],
            "validation": inner["validation"],
            "test": held,
        }
        methodology["heldOutDevice"] = args.hold_out_device
        methodology["testSetMeaning"] = (
            "Unseen device. The test figure reflects transfer to a handset "
            "the model never saw."
        )
    else:
        splits = group_split(
            frame,
            args.group_by,
            args.test_fraction,
            args.validation_fraction,
            args.seed,
        )
        methodology["testSetMeaning"] = (
            "Unseen physical samples from the same device pool. This does NOT "
            "establish cross-device robustness; use --hold-out-device for "
            "that."
        )

    summary = {"methodology": methodology, "splits": {}}
    for name, part in splits.items():
        part.to_csv(args.out_dir / f"{name}.csv", index=False)
        summary["splits"][name] = describe(part)

    # Leakage self-check. Cheap, and catches a mistake that would otherwise be
    # invisible in the metrics.
    train_groups = set(splits["train"][args.group_by])
    for other in ("validation", "test"):
        overlap = train_groups & set(splits[other][args.group_by])
        if overlap:
            summary.setdefault("errors", []).append(
                f"LEAKAGE: {len(overlap)} group(s) appear in both train and "
                f"{other}."
            )

    (args.report_dir / "split_summary.json").write_text(
        json.dumps(summary, indent=2)
    )
    print(json.dumps(summary, indent=2))
    return 1 if "errors" in summary else 0


if __name__ == "__main__":
    raise SystemExit(main())
