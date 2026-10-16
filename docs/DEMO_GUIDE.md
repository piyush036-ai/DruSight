# Demonstration guide

## Before you start

Build with the demonstration environment enabled:

```bash
flutter run --dart-define=DRUSIGHT_DEMO=true
```

Put the device in **aeroplane mode** and leave it there. The entire
demonstration runs offline; showing that is part of the point.

Print `DS-CARD-A` on matte stock at 100% scale. Have a used field-test kit or a
safe colourimetric stand-in ready.

## What to say at the start

> DruSight does not replace the field-test kit and does not identify
> substances. It turns a subjective visual reading into a calibrated,
> measurable, explainable and tamper-evident one. The chemistry and its limits
> are unchanged.

If you say more than that, you are overclaiming.

## The 24 steps

| # | Step | What to point at |
|---|---|---|
| 1 | Sign in | Local authentication. Say plainly it is a prototype, not institutional identity. |
| 2 | Select the test kit | Two profiles, both labelled UNVALIDATED DEMONSTRATION PROFILE. Read that label out. |
| 3 | View kit instructions | Capture steps, safety notes, and the reference-card spec come from the profile, not from code. |
| 4 | Open the camera | Both guides visible: reference card and test region, in one frame. |
| 5 | Show the Smart Capture Guard | Deliberately shake the phone, then tap CHECK FRAME. It reports measured sharpness against the profile threshold, not a vibe. |
| 6 | Place the reference card | Align inside the guide. Tap CHECK FRAME again — the guide turns green. |
| 7 | Capture | Press CAPTURE. |
| 8 | Show calibration | On the result page: patches used, mean residual ΔE2000, and the profile's limit. Say the residual is a fit residual, not an accuracy claim. |
| 9 | Show colour analysis | Calibrated RGB, HSV, Lab, ΔE from baseline, spatial uniformity. |
| 10 | Show the reaction fingerprint | Only if the timed profile is selected. Say it is an additional evidence feature, not an identification. |
| 11 | Local model | It will say **no trained model is installed**. Do not skip this. Say: we did not train a model on data we do not have, and the app refuses to invent a prediction. |
| 12 | Show the result | PRESUMPTIVE POSITIVE / NEGATIVE / INCONCLUSIVE, with the disclaimer beneath it. |
| 13 | Show the explanation | Every line is a measurement with its threshold. Nothing is generated prose. |
| 14 | Show reliability status | PASS / REVIEW / RECAPTURE. Say it is deliberately a three-state indicator, not a percentage, because no validation data exists that would justify a number. |
| 15 | Show anomaly status | Machine-readable codes with the measured value and the threshold crossed. |
| 16 | Show the evidence record | Image hash, record hash, previous hash, chain position, key ID. |
| 17 | Show the QR | Integrity values only. No officer identity, no location, no substance. |
| 18 | Verify the QR | Dashboard → scan icon → scan it. CHAIN OF CUSTODY: VALID. Still in aeroplane mode. |
| 19 | Open test history | Search and filter by result, reliability, anomaly, date, kit. |
| 20 | Demonstrate tampering | Open a record → flask icon → pick a scenario. |
| 21 | Show the failure | HASH MISMATCH / SIGNATURE INVALID / CHAIN BROKEN. |
| 22 | Restore | Close the dialog and reopen the record: VALID. Explain why — the simulation ran on an in-memory copy and the stored record was never touched. That is the design, not a trick. |
| 23 | Show system integrity | Whole-chain verification plus the audit trail, including the audit event the tamper demo just wrote about itself. |
| 24 | Show offline mode | Dashboard offline card: kit profiles present, model absent and why, knowledge base present. Point at the aeroplane-mode indicator. |

## The three moments that matter

**Step 11 — the missing model.** The instinct is to hide it. Do the opposite.
An evaluator who has seen a dozen projects claim 97% accuracy on invented data
will notice a team that refused to. The line is: *the pipeline is built and
runs; we did not fabricate the data to feed it.*

**Step 14 — no percentage.** If asked "why not a confidence score?": because we
have no validation data, so any number would be decoration. A three-state
indicator is what the evidence supports.

**Step 22 — the demo cannot corrupt evidence.** Say explicitly that the tamper
scenario never touches stored data, and that it writes an audit event about
itself.

## Questions you will get

**"What's your accuracy?"**
> We don't have one, and we won't quote one. No trained model exists and no
> validation has been done. `docs/VALIDATION_PLAN.md` sets out the four phases
> that would be required, starting with measurement-system characterisation
> that needs no controlled substances at all.

**"Can this replace lab testing?"**
> No, and it is not designed to. Every result says confirmatory laboratory
> testing is required, and that text cannot be dismissed.

**"Can it detect GPS spoofing?"**
> No. It compares consecutive fixes and flags physically implausible travel
> speed. Poor GPS, a clock change and a genuine flight all produce the same
> signal, so the app lists benign causes first and never accuses the operator.

**"Is this legally admissible?"**
> We make no admissibility claim. The cryptography establishes that a record
> has not changed since signing. It does not establish the real-world time of
> capture, and it does not prove which institution the signing key belongs to.

**"Why no deep learning?"**
> On 21 tabular features it would add opacity and overfitting without adding
> signal, and an unexplainable model is the wrong tool for a forensic context.
> The pipeline trains interpretable baselines and selects on grouped
> cross-validation.

**"Why is the card detection manual?"**
> Automatic detection that is wrong is the most dangerous failure mode here: a
> misplaced card produces a confident, plausible, completely wrong calibration.
> Guided alignment with automatic validation fails visibly instead. The
> automatic detector is a wired integration point that reports unavailability
> rather than guessing.

## Do not

- Do not present synthetic demo data as results.
- Do not quote the Krauss et al. paper's performance as if it were DruSight's.
- Do not describe the calibration residual as accuracy.
- Do not let the phone come off aeroplane mode.
