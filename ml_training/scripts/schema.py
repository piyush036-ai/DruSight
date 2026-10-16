"""Shared schema definitions for the DruSight ML pipeline.

The feature order here IS the contract with the mobile app. It must match
`ColourFeatures.featureNames` in lib/models/colour_features.dart exactly. A
mismatch would feed a deployed model a differently-shaped vector, which
produces confident nonsense rather than an error - so both sides declare a
schema version and the app refuses to run a model whose version differs.
"""

from __future__ import annotations

FEATURE_SCHEMA_VERSION = "features-0.1.0"

#: Ordered feature names. Order is the schema.
FEATURE_NAMES: list[str] = [
    "mean_r",
    "mean_g",
    "mean_b",
    "median_r",
    "median_g",
    "median_b",
    "std_r",
    "std_g",
    "std_b",
    "hue_circular_mean",
    "hue_std",
    "saturation_mean",
    "value_mean",
    "lab_l",
    "lab_a",
    "lab_b",
    "delta_e_from_reference",
    "spatial_uniformity",
    "edge_density",
    "p05_luminance",
    "p95_luminance",
]

#: Label vocabulary. Must match TestResult wire names in the app.
LABELS: list[str] = ["POSITIVE", "NEGATIVE", "INCONCLUSIVE"]

#: Columns every ingested sample must carry. Missing any of these makes the
#: sample unusable for supervised training, and the ingester reports it rather
#: than quietly dropping it.
REQUIRED_METADATA: list[str] = [
    "sample_id",        # physical sample / test - the grouping key for splits
    "session_id",       # capture session
    "kit_id",
    "kit_profile_version",
    "device_model",
    "lighting_condition",
    "captured_at_utc",
    "label",            # ground truth
    "ground_truth_source",  # how the label was established
]

#: Optional but recorded when present.
OPTIONAL_METADATA: list[str] = [
    "reaction_offset_seconds",
    "operator_id",
    "quality_label",
    "calibration_residual_delta_e",
    "provenance_note",
]

#: Quality labels used for robustness slicing.
QUALITY_LABELS: list[str] = [
    "good",
    "blur",
    "glare",
    "poor_lighting",
    "overexposed",
    "underexposed",
    "missing_card",
    "incorrect_framing",
    "unstable_reaction",
]
