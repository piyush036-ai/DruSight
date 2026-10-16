# Security

## What the evidence layer proves

1. **Integrity of a record.** `recordHash` is recomputed from the stored fields
   on every open. Any modification breaks it.
2. **Integrity of an image.** The original capture is hashed with SHA-256 as it
   is written. Re-hashing the file detects substitution or corruption.
3. **Authenticity relative to a key.** The Ed25519 signature verifies against
   the public key stored with the record.
4. **Ordering and completeness of a device's chain.** Each record commits to
   its predecessor's hash. Modifying or removing a record breaks the chain from
   that point on.
5. **Integrity of the audit trail.** Audit events are themselves hash-chained.

## What it does not prove

| Claim | Reality |
|---|---|
| "The record was created at time T" | Signing establishes a record has not changed. A manipulated device clock yields a perfectly valid signature over a false timestamp. |
| "The key belongs to Agency X" | Verification checks the key stored *with* the record. Nothing ties it to an institution. That needs a key registry. |
| "Nobody tampered with this" | Correct only against an attacker *without* the private key. A key holder can rebuild a consistent chain. |
| "The GPS coordinates are genuine" | Spoofing is not detected. See `LIMITATIONS.md` §5. |
| "This is legally admissible" | No such claim is made anywhere. |

## Threat model

**In scope**

- Post-hoc editing of a stored record — detected by hash mismatch.
- Substituting the evidence image — detected by image-hash mismatch.
- Deleting a record from the middle of the chain — detected by link break.
- Forging or replaying a signature — detected by signature failure. The
  signature binds the record hash, so it cannot be moved between positions.
- Malformed input (corrupt QR, bad base64, truncated record) — returns a failed
  verification, never a crash.
- SQL injection — every query uses bound parameters. The one `LIKE` pattern
  escapes user wildcards; sort order comes from a fixed enum, never user text.

**Out of scope**

- An attacker holding the unlocked device and the private key.
- A rooted or compromised OS.
- Physical substitution of the sample before capture.
- Denial of service (deleting the whole app or its storage).
- Coercion of the operator.

## Cryptographic choices

| Purpose | Algorithm | Why |
|---|---|---|
| Hashing | SHA-256 | Standard, widely reviewed, available natively |
| Signing | Ed25519 | Deterministic (no nonce-reuse failure mode), small keys and signatures, fast on mobile, no curve-parameter choices to get wrong |
| Passphrase derivation | PBKDF2-HMAC-SHA256, 210k iterations, 16-byte random salt | OWASP-aligned for mobile; available in the `cryptography` package without a native dependency |
| Canonicalisation | Project-defined, versioned | See `ARCHITECTURE.md` |

No cryptographic primitive is implemented in this project. All come from
`package:crypto` and `package:cryptography`.

## Key handling

- Generated on device at first use. Never transmitted.
- Stored via `flutter_secure_storage` (Android Keystore–backed
  `EncryptedSharedPreferences`; iOS Keychain).
- Never logged, never written to the database, never placed in a QR payload.
- No private key, credential or secret appears in source. `.gitignore` excludes
  `*.pem`, `*.key`, `*.jks`, `*.keystore`, `android/key.properties`.

**Known weakness.** `flutter_secure_storage` protects key *material*; it does
not make the key non-extractable inside a secure element. Hardware-bound keys
would require a platform channel using Keystore-generated keys with
`setUserAuthenticationRequired`. This is the highest-value hardening step
available and is not done.

## Timing attacks

Hash and digest comparisons use `Hashing.constantTimeEquals`, and passphrase
comparison uses an equivalent. Verification outcomes are observable, so these
do not short-circuit on the first differing byte.

## Privacy

- Device identity is a locally-generated random installation ID. No hardware
  serial, IMEI, advertising ID or account identifier is collected.
- QR payloads carry integrity values and version metadata only — no officer
  identity, no location, no substance information, no image.
- Location is best-effort and absent when unavailable. It is never estimated.
- Release builds must not log evidence contents, keys or personal data;
  developer logging is debug-only.

## Demonstration mode

Tamper simulation is compiled out unless built with
`--dart-define=DRUSIGHT_DEMO=true`. When enabled it operates on an **in-memory
copy** of a record; the stored row is never modified, and every invocation
writes an audit event recording that a simulation was run.

## Not yet done

- Database encryption at rest (SQLCipher).
- Hardware-bound signing keys.
- External chain anchoring for trusted timestamping.
- A public-key registry for cross-device key attribution.
- Account lockout / rate limiting on the login screen.
- An independent security review. **None has been performed.**
