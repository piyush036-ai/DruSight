# Architecture

## Layering

Dependencies point one way only. `models` and `cv` know nothing about Flutter,
SQLite or the camera, which is why the colour science and the evidence layer
are unit-testable without a device.

```
screens / widgets          Flutter UI
        |
services                   orchestration (workflow, evidence, QR, reports)
        |
repositories               data access, SQL
        |
database                   SQLite schema + connection
        ^
analysis                   capture guard, rules, anomalies, reliability
        |
cv  |  ml  |  security  |  location      pure logic, no Flutter
        |
models  |  config          types and versioned constants
```

`lib/app/service_locator.dart` is the composition root: everything is
constructed once, there. Screens read it from a `Provider`. This is what makes
`MockClassifierService` swappable for a real ONNX service in one line.

## Analysis pipeline

`lib/analysis/analysis_pipeline.dart`. Each stage can veto the next.

```
capture
  -> detect reference card        guided alignment + validation
  -> fit colour calibration       3x4 affine in linear light
       |  fails -> stop, no measurement is reported
  -> detect test region           guided + quality scoring
  -> capture-quality gate         blur, exposure, glare, framing
  -> extract features             21 values, on CALIBRATED pixels
  -> reaction trajectory          if the profile defines a timed window
  -> deterministic colour rules   nearest region by CIEDE2000
  -> local classifier             or reports unavailability
  -> anomaly engine               measurement vs versioned threshold
  -> reliability engine           PASS / REVIEW / RECAPTURE
  -> explanation builder          one line per measurement
```

Calibration deliberately runs **before** region analysis: if the colour
transform cannot be estimated, nothing measured downstream means anything, and
producing numbers that look valid would be worse than stopping.

Feature extraction runs on calibrated pixels, not on calibrated summary
statistics. The transform is affine in linear light and the statistics are not,
so the two are not equivalent.

## Evidence pipeline

`lib/services/evidence_service.dart`, `lib/security/`.

```
core            = all substantive fields
recordHash      = SHA256( canonical(core) || imageHash || previousHash )
signedPayload   = core + { recordHash }
signature       = Ed25519( canonical(signedPayload) )
```

Binding the signature to the record hash rather than to `core` alone means a
signature cannot be lifted from one chain position and replayed at another.

The core field layout is defined in exactly one place —
`EvidenceRecord.toCoreMap()` — and both creation and verification go through
it, so they cannot drift apart.

`CanonicalJson` pins byte-level determinism: sorted keys, null keys omitted,
fixed-precision doubles, non-finite values rejected. Any change to those rules
changes every record hash ever produced, which is why the format carries its
own version.

The chain slot (previous hash + sequence number) is allocated **inside** the
same SQLite transaction that writes the record, so two tests completing at once
cannot claim the same position or branch the chain.

## Why no OpenCV

Everything the CV layer needs — colour conversion, least squares on a 4x4
system, Laplacian variance, histograms — is a few hundred lines of arithmetic.
Pulling in OpenCV would add tens of megabytes to the APK for functions that
fit on one screen, and would make the numerical behaviour harder to test. The
`image` package supplies pixel access; the maths is ours and is unit-tested.

## Why guided detection instead of automatic

Automatic card detection that is *wrong* is the most dangerous failure mode in
this system: a misplaced quadrilateral produces a confident, plausible-looking,
completely wrong calibration, and nothing downstream can tell. Guided alignment
plus automatic validation is a real measurement protocol — it is how reference
targets are used in practice — and it fails visibly rather than silently.
`HomographyCardDetector` exists as the integration point and reports
unavailability rather than guessing.

## Why the classifier can be absent

`MockClassifierService` returns `ClassifierOutput.unavailable(...)` on every
call. It never invents a label. The absence flows through the anomaly engine as
a REVIEW-severity `ANOMALY_MODEL_UNAVAILABLE`, appears in the explanation, and
is recorded in the evidence record as a null `modelId`. A fabricated prediction
in a forensic tool is worse than an absent one, because the absence is visible.

## Versioning

Five versions are recorded with every record: algorithm, calibration, feature
schema, kit profile, and canonical format. A future model update therefore
cannot make an old record appear to have been produced by the new model. The
kit profile is stored in SQLite at its exact version, so re-opening a
historical record explains it under the rules it was actually judged by.

`Versions.featureSchema` must match `FEATURE_SCHEMA_VERSION` in
`ml_training/scripts/schema.py`. The app refuses to run a model whose schema
version differs from the extractor's, because a differently-shaped vector
produces confident nonsense rather than an error.

## Threading

Analysis runs on the platform thread today. Feature extraction over a
full-resolution region is the expensive step; moving `AnalysisPipeline.run` to
an `Isolate` is the obvious next step and is contained to one call site because
`img.Image` and the feature types are plain data.
