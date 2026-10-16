# Testing

## Running

```bash
flutter test                       # all
flutter test test/unit             # colour science, calibration, engines
flutter test test/security         # canonical JSON, hashing, signing, chain
```

**Status: 98/98 passing** on Flutter 3.47.5 / Dart 3.13.4, with
`flutter analyze` reporting no issues.

## What is tested

### `test/unit/colour_space_test.dart`

- sRGB transfer function: endpoints, the 128 → 0.2158 check that catches a
  linearised-by-mistake implementation, round-trips, and an explicit assertion
  that it is *not* linear.
- RGB→Lab against published values for white, black, and the sRGB primaries;
  neutral greys must have near-zero chroma.
- RGB→HSV: primaries, grey, the negative-hue branch, round-trip.
- **CIEDE2000 against all 30 Sharma–Wu–Dalal test vectors.** These are the
  standard check that the rotation term and the hue-difference branches are
  right; a naive implementation passes the easy pairs and fails the
  near-neutral and blue-region ones.
- A test that ΔE2000 and ΔE76 *disagree* in the blue region, which fails if the
  rotation term is ever dropped.
- Circular hue arithmetic: the mean of 350° and 10° must be 0°, not 180°.

### `test/unit/calibration_test.dart`

Synthesises a known distortion, applies it to the card patches, and checks the
solver undoes it — including for a colour that was never on the card, which is
the property that actually matters.

Also asserts the honest failure: highlight clipping is not affine, so the
residual must **rise** monotonically with clipping severity. A solver reporting
a low residual there would produce a confident, wrong calibration.

### `test/unit/reliability_engine_test.dart`

The core safety property: a blocking anomaly outranks an otherwise clean
positive, a borderline colour escalates, model/rule disagreement escalates, and
every decision carries a stated reason.

### `test/unit/location_integrity_test.dart`

Haversine against known distances; plausible cases stay silent (including GPS
jitter at a stationary location, where positional uncertainty must be
subtracted before computing speed); implausible cases are flagged; and the
checker declines to judge on low-accuracy fixes. Also asserts the explanation
list leads with benign causes and ends with manipulation.

### `test/security/canonical_json_test.dart`

Byte-level determinism: key ordering, null omission, fixed-precision doubles,
`1.0 == 1`, negative-zero normalisation, escaping, and rejection of NaN,
infinity, non-string keys and unsupported types.

### `test/security/evidence_integrity_test.dart`

SHA-256 against known digests; record hashing and every tamper case; Ed25519
valid/modified/forged/wrong-key/malformed; and the chain: intact verification,
genesis linkage, middle-record removal, historical alteration, re-pointing, and
out-of-order sequence numbers.

One test deserves note: *altering a historical record is detected at that
record* asserts that link checking alone is **not** sufficient — a tampered
record keeps its stored hash and still chains cleanly — which is why the
verifier checks both the record hash and the link.

## Not yet written

- Widget tests for the capture and result screens.
- Integration tests for the full camera → analysis → evidence → QR path
  (needs a device or a substantial camera fake).
- Database migration tests (only schema v1 exists).
- ML robustness tests against real data (no data).
- Performance benchmarks.

## What running them for the first time found

Two failures on the first run, both worth recording.

**A real production bug.** `EvidenceSigner.verify` threw
`StateError: Ed25519 signature must be 64 bytes` on a wrong-length signature
rather than returning `false`. In the app a corrupt or truncated signature
would have crashed the verification screen instead of reporting an invalid
signature — the precise failure mode `SECURITY.md` asserts cannot happen. Fixed
by length-checking the signature and public key before handing them to the
library, and catching `StateError` as a last resort. Regression tests now cover
short, long and empty signatures and a malformed public key.

This is the clearest argument for the tests existing: the bug was in the code
path whose entire job is to survive hostile input, and no amount of reading it
had caught it.

**A corrupted test file.** The `\u0001` in the control-character assertion had
been written to disk as a literal 0x01 byte, so the test asserted the opposite
of the JSON requirement. The production encoder was correct throughout. Both
that test and the newline/tab one now build their inputs with
`String.fromCharCode` so no literal control byte can reach the source again.

## Numerical verification done separately

Some properties are easier to check by running the identical algorithm outside
Dart, and were verified that way before the SDK was available:

- **CIEDE2000 and sRGB to Lab** — all 30 Sharma-Wu-Dalal vectors to within
  5e-5; Lab for white/black/red/green/blue to 0.01; `srgbToLinear(128) =
  0.215861`.
- **Calibration solver** — residual ~2e-6 for affine distortions; an unseen
  colour's error drops from 5.42 to 0.000002; residual rises monotonically
  (0.00 → 0.46 → 2.07 → 3.51) with increasing clipping.
- **Haversine** — 1 degree latitude = 111195.1 m; Pune-Mumbai = 120.2 km.
- **The Python ML pipeline** — executed end to end.
- **The reference-card PDF** — every patch checked against the kit profile,
  including the y-axis flip between image and PDF coordinate conventions.
