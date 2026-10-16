/// Ed25519 signing and verification of canonical evidence records
/// (master spec section 33).
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'canonical_json.dart';
import 'key_store.dart';

class SignatureBundle {
  const SignatureBundle({
    required this.signatureBase64,
    required this.publicKeyId,
    required this.publicKeyBase64,
    required this.keyVersion,
    required this.scheme,
  });

  final String signatureBase64;
  final String publicKeyId;
  final String publicKeyBase64;
  final int keyVersion;
  final String scheme;

  Map<String, Object?> toJson() => <String, Object?>{
        'signature': signatureBase64,
        'publicKeyId': publicKeyId,
        'publicKey': publicKeyBase64,
        'keyVersion': keyVersion,
        'scheme': scheme,
      };
}

class EvidenceSigner {
  EvidenceSigner(this._keyStore);

  final SigningKeyStore _keyStore;
  final Ed25519 _algorithm = Ed25519();

  static const String scheme = 'Ed25519';

  /// Ed25519 signature and public-key sizes, per RFC 8032.
  static const int signatureLengthBytes = 64;
  static const int publicKeyLengthBytes = 32;

  /// Signs the canonical bytes of [payload].
  ///
  /// The caller passes the record MAP, not a pre-serialized string, so that
  /// signing and verification can never disagree about serialization.
  Future<SignatureBundle> sign(Map<String, Object?> payload) async {
    final List<int> message = CanonicalJson.encodeToBytes(payload);
    final SimpleKeyPair pair = await _keyStore.loadOrCreateKeyPair();
    final Signature signature =
        await _algorithm.sign(message, keyPair: pair);

    return SignatureBundle(
      signatureBase64: base64.encode(signature.bytes),
      publicKeyId: await _keyStore.publicKeyId(),
      publicKeyBase64: await _keyStore.publicKeyBase64(),
      keyVersion: await _keyStore.keyVersion(),
      scheme: scheme,
    );
  }

  /// Verifies a signature against the public key recorded WITH the record.
  ///
  /// Note on what this proves: it proves the payload has not changed since it
  /// was signed by the holder of that private key. It does not, on its own,
  /// prove the key belongs to a particular institution - that requires an
  /// external key registry, which is out of scope for the offline prototype
  /// and documented as such.
  Future<bool> verify(
    Map<String, Object?> payload, {
    required String signatureBase64,
    required String publicKeyBase64,
  }) async {
    try {
      final List<int> message = CanonicalJson.encodeToBytes(payload);

      final List<int> signatureBytes = base64.decode(signatureBase64);
      final List<int> publicKeyBytes =
          base64Url.decode(_restorePadding(publicKeyBase64));

      // Length-check before handing anything to the library. A wrong-length
      // signature or key is a failed verification, and the library treats it
      // as a programming error and throws.
      if (signatureBytes.length != signatureLengthBytes ||
          publicKeyBytes.length != publicKeyLengthBytes) {
        return false;
      }

      final Signature signature = Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          publicKeyBytes,
          type: KeyPairType.ed25519,
        ),
      );
      return await _algorithm.verify(message, signature: signature);
    } on FormatException {
      // Malformed base64 in a stored or scanned record.
      return false;
    } on ArgumentError {
      return false;
    } on StateError {
      // Belt and braces: the cryptography package raises StateError for
      // malformed inputs the length checks above do not anticipate. Every
      // path through this method must end in a boolean, because the caller is
      // a verification screen, not a debugger.
      return false;
    }
  }

  static String _restorePadding(String value) {
    final int remainder = value.length % 4;
    if (remainder == 0) return value;
    return value + '=' * (4 - remainder);
  }
}
