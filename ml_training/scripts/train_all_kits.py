#!/usr/bin/env python3
"""Train, evaluate, and export ONNX models for all four real forensic reagent kits.

This is the single command that goes from raw CSVs to deployed app assets:

    python scripts/train_all_kits.py

It runs the full pipeline for each kit:
  1. prepare_dataset  (validate + dedupe)
  2. split_dataset    (group-aware, no leakage)
  3. train            (grouped CV, model selection)
  4. evaluate         (held-out metrics)
  5. export_model     (ONNX + manifest)
  6. copies ONNX to assets/models/ and prints the kit profile update needed

All outputs go to per-kit subdirectories under experiments/.

Usage:
    cd ml_training
    python scripts/train_all_kits.py
    python scripts/train_all_kits.py --kit MARQUIS-001
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

KITS = {
    "MARQUIS-001":    {"csv_glob": "marquis*_literature.csv",   "model_id": "marquis-001-clf",    "version": "1.0.0"},
    "SCOTT-001":      {"csv_glob": "scott*_literature.csv",     "model_id": "scott-001-clf",      "version": "1.0.0"},
    "DUQUENOIS-001":  {"csv_glob": "duquenois*_literature.csv", "model_id": "duquenois-001-clf",  "version": "1.0.0"},
    "MECKE-001":      {"csv_glob": "mecke*_literature.csv",     "model_id": "mecke-001-clf",      "version": "1.0.0"},
}

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"
RAW_DIR = ROOT / "data" / "raw"
EXPERIMENTS_DIR = ROOT / "experiments"
ASSETS_MODELS = ROOT.parent / "assets" / "models"


def run(cmd: list[str], cwd: Path) -> int:
    print(f"\n>>> {' '.join(str(c) for c in cmd)}")
    result = subprocess.run(cmd, cwd=cwd)
    return result.returncode


def train_kit(kit_id: str, meta: dict, python: str) -> bool:
    print(f"\n{'='*60}")
    print(f"  Training kit: {kit_id}")
    print(f"{'='*60}")

    exp_dir = EXPERIMENTS_DIR / kit_id
    raw_dir = exp_dir / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)

    # Copy matching raw CSV(s) into per-kit raw dir
    matches = list(RAW_DIR.glob(meta["csv_glob"]))
    if not matches:
        print(f"[{kit_id}] ERROR: No CSV matching {meta['csv_glob']} in {RAW_DIR}")
        print(f"  Run: python scripts/make_literature_data.py")
        return False
    for src in matches:
        shutil.copy(src, raw_dir / src.name)
        print(f"[{kit_id}] Using data: {src.name} ({src.stat().st_size // 1024} KB)")

    # 1. prepare
    rc = run([python, str(SCRIPTS / "prepare_dataset.py"),
              "--raw-dir", str(raw_dir),
              "--out-dir", str(exp_dir / "processed"),
              "--report-dir", str(exp_dir / "reports")], cwd=ROOT)
    if rc != 0:
        print(f"[{kit_id}] prepare_dataset FAILED"); return False

    # 2. split
    rc = run([python, str(SCRIPTS / "split_dataset.py"),
              "--dataset", str(exp_dir / "processed" / "dataset.csv"),
              "--out-dir", str(exp_dir / "splits"),
              "--report-dir", str(exp_dir / "reports")], cwd=ROOT)
    if rc != 0:
        print(f"[{kit_id}] split_dataset FAILED"); return False

    # 3. train
    rc = run([python, str(SCRIPTS / "train.py"),
              "--splits-dir", str(exp_dir / "splits"),
              "--out-dir", str(exp_dir / "models"),
              "--report-dir", str(exp_dir / "reports")], cwd=ROOT)
    if rc != 0:
        print(f"[{kit_id}] train FAILED"); return False

    # 4. evaluate — find the best model
    model_files = list((exp_dir / "models").glob("*.joblib"))
    if not model_files:
        print(f"[{kit_id}] No model produced by train.py"); return False
    model_path = model_files[0]

    rc = run([python, str(SCRIPTS / "evaluate.py"),
              "--model", str(model_path),
              "--report-dir", str(exp_dir / "reports")], cwd=ROOT)
    if rc != 0:
        print(f"[{kit_id}] evaluate FAILED (non-fatal, continuing export)")

    # 5. export ONNX (needs skl2onnx — install if missing)
    try:
        import skl2onnx  # noqa: F401
    except ImportError:
        print(f"[{kit_id}] Installing skl2onnx for ONNX export...")
        subprocess.run([python, "-m", "pip", "install", "skl2onnx", "onnx", "--quiet"])

    rc = run([python, str(SCRIPTS / "export_model.py"),
              "--model", str(model_path),
              "--model-id", meta["model_id"],
              "--model-version", meta["version"],
              "--kit-id", kit_id,
              "--out-dir", str(exp_dir / "onnx"),
              "--validation-status",
              "Literature-derived training data (UNODC ST/NAR/42 + SWGDRUG). "
              "Not validated on physical samples. For prototype demonstration only."],
             cwd=ROOT)
    if rc != 0:
        print(f"[{kit_id}] export_model FAILED"); return False

    # 6. copy ONNX to Flutter assets
    onnx_files = list((exp_dir / "onnx").glob("*.onnx"))
    manifest_files = list((exp_dir / "onnx").glob("*.manifest.json"))
    if not onnx_files:
        print(f"[{kit_id}] No ONNX file found after export"); return False

    ASSETS_MODELS.mkdir(parents=True, exist_ok=True)
    onnx_dest = ASSETS_MODELS / onnx_files[0].name
    shutil.copy(onnx_files[0], onnx_dest)
    if manifest_files:
        shutil.copy(manifest_files[0], ASSETS_MODELS / manifest_files[0].name)

    # Compute hash for model_versions table
    sha256 = hashlib.sha256(onnx_dest.read_bytes()).hexdigest()

    print(f"\n[{kit_id}] SUCCESS")
    print(f"  ONNX model: {onnx_dest}")
    print(f"  SHA-256:    {sha256}")
    print(f"\n  Kit profile (modelId/modelVersion already set):")
    print(f'    "modelId": "{meta["model_id"]}",')
    print(f'    "modelVersion": "{meta["version"]}",')
    print(f"  asset_path=assets/models/{onnx_files[0].name}")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kit", default=None, choices=list(KITS.keys()),
                        help="Train only this kit; default trains all.")
    parser.add_argument("--python", default=sys.executable,
                        help="Python interpreter (default: current env).")
    args = parser.parse_args()

    kits_to_train = {args.kit: KITS[args.kit]} if args.kit else KITS

    print(f"DruSight ML pipeline — training {len(kits_to_train)} kit(s)")
    print(f"Python: {args.python}")
    print(f"Raw data: {RAW_DIR}")
    print(f"Assets output: {ASSETS_MODELS}")

    results = {}
    for kit_id, meta in kits_to_train.items():
        results[kit_id] = train_kit(kit_id, meta, args.python)

    print(f"\n{'='*60}")
    print("  SUMMARY")
    print(f"{'='*60}")
    all_ok = True
    for kit_id, ok in results.items():
        status = "OK" if ok else "FAILED"
        print(f"  {kit_id}: {status}")
        if not ok:
            all_ok = False

    if all_ok:
        print(f"\nAll models exported to {ASSETS_MODELS}")
        print("Next step: run the app — OnnxClassifierService will auto-load models.")
    else:
        print("\nSome kits failed. Check errors above.")

    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
