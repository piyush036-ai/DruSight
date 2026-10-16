# Validation plan

**Nothing in this plan has been executed. DruSight is unvalidated.**

This describes what validation would require, informed by the principles that
serious forensic data infrastructures such as NIST CADS demonstrate:
characterised samples, associated analytical data, multiple techniques,
realistic mixtures, traceability and reproducibility.

## Phase 0 — Measurement-system characterisation

Does not require controlled substances, and should be done first because it
bounds everything after it.

Using printed colour targets and safe colourimetric materials of known value:

| Question | Method | Success criterion |
|---|---|---|
| Does calibration reduce inter-device variation? | Same targets, N devices, M lighting conditions. Compare ΔE2000 spread before and after calibration. | Post-calibration spread materially lower, with the reduction quantified. |
| Is measurement repeatable? | 10 captures of one target, same device, same light. | Report the standard deviation of ΔE2000. State it; do not set an arbitrary target in advance. |
| Is it reproducible across operators? | Same target, N operators. | Report between-operator variance. |
| Do the quality gates catch bad captures? | Deliberately blurred, glared, under/overexposed captures. | Report the gate's true/false positive counts against human labels. |
| Where does calibration break? | Progressive clipping, mixed illuminants, tilt, distance. | Characterise the failure boundary and set the profile thresholds from it. |

Phase 0 output is a **measurement-system report**. It says nothing about drug
detection, and must not be presented as if it does.

## Phase 1 — Internal validation with characterised samples

Requires an authorised partner.

- Characterised samples with ground truth from confirmatory instrumental
  analysis.
- Multiple kit types.
- Realistic mixtures and adulterants where legally and ethically available.
- ≥5 device models, ≥5 lighting conditions.
- Deliberate negative and blank controls.
- Grouped splits by physical sample; a held-out unseen-device test set.

Reported: confusion matrix, per-class precision/recall/F1 with support,
balanced accuracy, false-positive and false-negative analysis, inconclusive
rate, probability calibration if probabilities are used, and error slices by
device, lighting and quality label.

**Label this internal validation.** It is not external validation.

## Phase 2 — Blinded evaluation

- Operators do not know the ground truth.
- Test set sealed before any model or threshold is touched.
- The set is used **once**. Any subsequent tuning invalidates it and requires a
  fresh set.

## Phase 3 — External validation

- An independent organisation, its own samples, its own devices, its own
  operators.
- DruSight is used as shipped; no tuning to their data.
- Pre-registered protocol and analysis plan.

Only after Phase 3 may a performance figure be described as validated, and only
with its scope stated: which kits, which substances, which devices, which
conditions.

## Phase 4 — Operational evaluation

Field use alongside existing procedure, with laboratory confirmation on every
case, measuring: inconclusive rate in real conditions, recapture rate, time per
test, operator-reported failure modes, and agreement with laboratory
confirmation.

## Reproducibility requirements

Throughout:

- Version-controlled datasets with recorded provenance per sample.
- Pinned dependency versions and recorded random seeds.
- Every analysis reproducible from the original image plus the recorded
  algorithm, calibration, feature-schema, model and kit-profile versions.
- Old models retained, never overwritten.
- Raw and processed data both retained.

## Reporting rules

These apply to every artefact this project produces, including slides.

1. Never state a performance figure without its support count.
2. Never present training or cross-validation figures as validation.
3. Always name the phase: measurement-system / internal / blinded / external /
   operational.
4. Always state scope: kits, substances, devices, conditions.
5. Where a figure does not exist, write `VALIDATION PENDING` or
   `DATA NOT AVAILABLE`. Do not estimate, do not extrapolate, do not cite
   another system's numbers as if they were ours.
