# Limitations

The single most important document in this repository. Everything here is a
real constraint, not a disclaimer for form's sake.

---

## 1. Scientific

**No validation has been performed.** No accuracy, sensitivity, specificity,
precision, recall or confidence figure is claimed for DruSight anywhere. Where
such a number would normally appear, the application shows the reason it is
absent instead.

**No trained model exists.** The classifier interface is wired and the training
pipeline runs, but no model has been trained on characterised samples. Results
currently come from the deterministic colour rules in a kit profile, and the
app says so on every result.

**The bundled kit profiles are unvalidated.** Their colour regions, radii and
thresholds are illustrative values chosen to exercise the pipeline. They are
not derived from characterised samples and must not be used to interpret a
real field test. Each profile carries a `validationStatus` string saying this,
displayed verbatim in the UI.

**Presumptive means presumptive.** A colour change consistent with a reagent
reaction narrows possibilities. It does not identify a substance. Measuring
that colour precisely does not change what it means — it only removes observer
variability from the reading. Precision is not accuracy.

**Cross-reactivity is unchanged.** If a kit's reagent reacts with compounds
other than the target, DruSight reports the same colour just as confidently.
Nothing in this system detects a false positive arising from the chemistry.

---

## 2. Measurement

**Calibration corrects an affine distortion, and nothing else.** The solver
fits gain and offset per channel in linear light. It cannot undo clipping: once
a pixel saturates to 0 or 255, the information is gone. This is visible in the
calibration residual, which rises under clipping and is then rejected by the
kit profile's limit — correct behaviour, but it means some captures are simply
unmeasurable.

**Calibration quality is a fit residual, not an accuracy claim.** The reported
mean ΔE2000 says how well the fitted transform reproduces the card's own
patches. It does not bound the error on the test region, which is a different
colour under possibly different local illumination.

**The reference card must be characterised.** Every measurement inherits the
card's accuracy. A card printed on the wrong stock, faded, dirty, or printed at
the wrong scale silently degrades everything downstream. The app cannot detect
a systematically wrong card that is internally consistent.

**Single-illuminant assumption.** The fit assumes the card and the reaction
area are under the same light. Mixed lighting — window plus fluorescent, or a
shadow falling across one but not the other — violates this, and the residual
will not always catch it.

**Card detection is operator-guided, not automatic.** The shipped detector
relies on the operator aligning the card inside an on-screen guide, then
validates what it sampled (patch uniformity, and correlation between expected
and observed patch ordering). Full homography-based automatic detection is not
implemented; `HomographyCardDetector` reports unavailability rather than
returning a guessed quadrilateral, because a wrong card location produces a
plausible-looking but wrong calibration.

**Region "confidence" is a quality score, not a probability.** It is a
weighted combination of uniformity, surround contrast and clipping. It is not
the probability that the region was correctly identified, and the UI does not
present it as one.

**Perspective is not corrected.** A tilted capture makes the card's patches
trapezoidal while the sampler reads axis-aligned rectangles. The uniformity
check catches gross cases; moderate tilt introduces error that is not measured.

---

## 3. Machine learning

**The pipeline is complete; the data is not.** Ingestion, validation,
deduplication, group-aware splitting, training, evaluation and export all run.
They are waiting on authorised, characterised data.

**Synthetic demo data is not data.** `make_synthetic_demo_data.py` emits
numbers from a random number generator, tagged
`ground_truth_source=SYNTHETIC_NOT_REAL`. Metrics computed from it describe the
RNG. They must never appear in a presentation.

**Out-of-distribution detection is an interface, not an implementation.** The
`outOfDistribution` flag exists on `ClassifierOutput` and is honoured by the
anomaly engine, but nothing currently sets it. A real OOD strategy (e.g.
Mahalanobis distance to the training feature distribution) is future work.

**Probabilities are withheld by design.** `classProbabilities` stays null
unless a deployed model is genuinely probabilistic AND its calibration has been
assessed on an independent set. An uncalibrated softmax output shown as a
confidence would be a fabricated number.

---

## 4. Evidence and cryptography

**Signing proves integrity, not time.** An Ed25519 signature shows a record has
not changed since it was signed. It says nothing about when the signing
happened in the real world. A device with a manipulated clock produces a
perfectly valid signature over a false timestamp. External anchoring —
publishing chain head hashes to an institutional server — would be needed, and
is not implemented.

**The chain does not defend against a compromised key.** An attacker who
extracts the private key can rebuild an entirely consistent chain. The chain
detects modification of stored records by someone *without* the key. It is not
a defence against a determined holder of the device.

**Key storage is platform-protected, not hardware-bound.**
`flutter_secure_storage` stores key material protected by Android Keystore /
iOS Keychain. It does not make the key non-extractable inside a secure element.
Truly hardware-bound keys require a platform-channel implementation using
Keystore-generated keys with `setUserAuthenticationRequired`. Documented as a
hardening step in `SECURITY.md`; not done.

**Key ownership is not established.** Verification confirms a signature against
the public key stored *with the record*. Nothing ties that key to an
institution. A public-key registry would be required, and would need a network,
which the offline-first design deliberately avoids for core functions.

**Chains are per-device.** Records are created offline on independent handsets,
so there is no global ordering. Two devices produce two independent chains.

**QR verification off-device is limited.** A scanned payload can be checked for
internal consistency, but the original image and the chain position cannot be
verified on a device that does not hold the record.

**Deletion of the whole database is not detected.** The chain detects
modification and removal of individual records. Wholesale destruction of local
storage leaves nothing to detect it with.

---

## 5. Location and time

**GPS spoofing is not detected.** The location-integrity check compares two
consecutive fixes and reports whether the implied travel speed is physically
plausible. A spoofed location that moves slowly is indistinguishable from a
real one. A genuine fix after a flight looks implausible. The output is an
inconsistency flag for a human, and the UI lists benign causes first and
"possible manipulation" last, because the system cannot tell them apart.

**`position.isMocked` is reported, not relied on.** It is recorded as the
provider string where the platform supplies it. It is trivially defeated.

**Absent location stays absent.** If no fix is available the record says so. No
cached or default coordinate is ever substituted.

---

## 6. Authentication and identity

**Local passphrase authentication only.** PBKDF2-HMAC-SHA256 with a per-user
salt, stored locally. There is no federation, no directory, no revocation, and
no verification of the officer ID against any registry — an operator types
whatever they type. Institutional identity integration is an architectural
allowance, not a feature.

**No account lockout or rate limiting.** An attacker with the unlocked device
can attempt passphrases without restriction.

---

## 7. Application

**No APK has been built.** The Dart analyses clean (`flutter analyze`: no
issues) and all 98 tests pass on Flutter 3.47.5, and the Android manifest and
Gradle config are in place. But the machine this was developed on has no
Android SDK and no JDK, so the Gradle build has never run. R8 behaviour,
plugin native linkage and the real APK size are all unconfirmed.

**Nothing has run on a device.** The camera, GPS and Android Keystore paths are
exercised only by analysis, not by execution. Anything hardware-dependent —
autofocus behaviour, exposure locking, real Keystore semantics, permission
flows — is untested.

**Timed reaction capture is modelled, not driven.** The data model, analyser,
storage and graph for a timed sequence are implemented, and a kit profile can
declare offsets. The capture screen currently performs a single capture; the
automated timed-sequence capture loop is not wired.

**Android-first.** iOS is architecturally compatible but untested.

**Single portrait orientation.** The mapping from overlay guides to image
coordinates assumes it.

**No accessibility audit.** Type is large and status is never colour-only, but
screen-reader labelling and contrast have not been formally checked.

---

## 8. Data protection

**The database is not encrypted at rest.** Evidence records and images sit in
app-private storage, protected by OS sandboxing and device encryption only.
SQLCipher would be the next step and is not integrated.

**Evidence images may contain more than intended.** A capture frames whatever
was in front of the lens. There is no redaction.
