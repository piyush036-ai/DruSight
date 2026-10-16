#!/usr/bin/env python3
"""Export a trained model to ONNX for on-device inference (spec section 7).

Also emits a sidecar JSON manifest carrying the feature-schema version, the
class order and the model's SHA-256. The app verifies the hash before use, so
a swapped or corrupted model file fails loudly rather than producing silently
different results.

Requires skl2onnx and onnx, which are intentionally NOT in the default
requirements: training and evaluation must work without them.

Usage:
    python scripts/export_model.py --model models/random_forest.joblib \
        --model-id ds-demo-001-clf --model-version 0.1.0 --kit-id DS-DEMO-001
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import joblib

sys.path.insert(0, str(Path(__file__).resolve().parent))
from schema import FEATURE_NAMES, FEATURE_SCHEMA_VERSION  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, type=Path)
    parser.add_argument("--model-id", required=True)
    parser.add_argument("--model-version", required=True)
    parser.add_argument("--kit-id", required=True)
    parser.add_argument("--out-dir", default="models", type=Path)
    parser.add_argument(
        "--validation-status",
        default="VALIDATION PENDING - internal held-out evaluation only.",
        help="Copied verbatim into the manifest and shown in the app.",
    )
    args = parser.parse_args()

    try:
        from skl2onnx import to_onnx
    except ImportError:
        print(
            "skl2onnx is not installed. Install the export extras:\n"
            "  pip install skl2onnx onnx onnxruntime",
            file=sys.stderr,
        )
        return 1

    if not args.model.exists():
        print(f"No model at {args.model}.", file=sys.stderr)
        return 1

    import numpy as np

    model = joblib.load(args.model)
    sample = np.zeros((1, len(FEATURE_NAMES)), dtype=np.float32)
    onnx_model = to_onnx(model, sample, target_opset=15)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    onnx_path = args.out_dir / f"{args.model_id}_{args.model_version}.onnx"
    onnx_path.write_bytes(onnx_model.SerializeToString())

    digest = hashlib.sha256(onnx_path.read_bytes()).hexdigest()

    classes = getattr(model, "classes_", None)
    if classes is None and hasattr(model, "steps"):
        classes = getattr(model.steps[-1][1], "classes_", None)

    manifest = {
        "modelId": args.model_id,
        "modelVersion": args.model_version,
        "kitId": args.kit_id,
        "featureSchemaVersion": FEATURE_SCHEMA_VERSION,
        "featureNames": FEATURE_NAMES,
        "inputShape": [1, len(FEATURE_NAMES)],
        "inputDtype": "float32",
        "classOrder": list(classes) if classes is not None else None,
        "assetPath": f"assets/models/{onnx_path.name}",
        "sha256": digest,
        "validationStatus": args.validation_status,
        "deploymentChecklist": [
            f"Copy {onnx_path} to drusight/assets/models/",
            "Insert a row into the model_versions table with this sha256",
            f"Set modelId={args.model_id!r} and "
            f"modelVersion={args.model_version!r} in the kit profile JSON",
            "Register OnnxClassifierService in lib/app/service_locator.dart "
            "in place of MockClassifierService",
        ],
    }
    manifest_path = onnx_path.with_suffix(".manifest.json")
    manifest_path.write_text(json.dumps(manifest, indent=2))

    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
