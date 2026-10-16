/// Signing-key management (master spec section 33).
///
/// The private key is generated on the device at first use and stored via
/// flutter_secure_storage, which is backed by the Android Keystore
/// (EncryptedSharedPreferences) and the iOS Keychain. It is never written to
/// source, never logged, never placed in the database, and never leaves the
/// device.
///
/// Honest limitation: flutter_secure_storage stores key MATERIAL protected by
/// the platform keystore; it does not make the key non-extractable inside a
/// hardware security module. A fully hardware-bound key would require a
/// platform-channel implementation using Keystore-generated Ed25519/ECDSA keys
/// with `setUserAuthenticationRequired`. That is a documented future hardening
/// step, recorded in docs/SECURITY.md rather than overstated here.
library;

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

/// Abstracted so tests can substitute an in-memory store without touching
/// platform channels.
abstract class SigningKeyStore {
  /// Returns the device key pair, generating and persisting one on first use.
  Future<SimpleKeyPair> loadOrCreateKeyPair();

  /// Stable identifier for the public key, used in evidence records so a
  /// verifier knows which key to check against.
  Future<String> publicKeyId();

  /// Raw public key bytes, base64url-encoded without padding.
  Future<String> publicKeyBase64();

  /// Monotonic version, incremented if a key is ever rotated. Recorded in
  /// every signed record.
  Future<int> keyVersion();
}

class SecureStorageKeyStore implements SigningKeyStore {
  SecureStorageKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  final Ed25519 _algorithm = Ed25519();

  static const String _privateKeyKey =
      '${AppConfig.signingKeyAlias}.private';
  static const String _keyVersionKey =
      '${AppConfig.signingKeyAlias}.version';

  SimpleKeyPair? _cached;

  @override
  Future<SimpleKeyPair> loadOrCreateKeyPair() async {
    final SimpleKeyPair? cached = _cached;
    if (cached != null) return cached;

    final String? stored = await _storage.read(key: _privateKeyKey);
    if (stored != null) {
      final List<int> seed = base64Url.decode(stored);
      final SimpleKeyPair pair = await _algorithm.newKeyPairFromSeed(seed);
      _cached = pair;
      return pair;
    }

    final SimpleKeyPair pair = await _algorithm.newKeyPair();
    final List<int> seed = await pair.extractPrivateKeyBytes();
    await _storage.write(key: _privateKeyKey, value: base64Url.encode(seed));
    await _storage.write(key: _keyVersionKey, value: '1');
    _cached = pair;
    return pair;
  }

  @override
  Future<String> publicKeyBase64() async {
    final SimpleKeyPair pair = await loadOrCreateKeyPair();
    final SimplePublicKey pub = await pair.extractPublicKey();
    return base64Url.encode(pub.bytes).replaceAll('=', '');
  }

  /// Key id is the first 16 hex characters of SHA-256 over the public key.
  /// Short enough for a QR payload, long enough to identify a key.
  @override
  Future<String> publicKeyId() async {
    final SimpleKeyPair pair = await loadOrCreateKeyPair();
    final SimplePublicKey pub = await pair.extractPublicKey();
    final Hash digest = await Sha256().hash(pub.bytes);
    final String hex = digest.bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return hex.substring(0, 16);
  }

  @override
  Future<int> keyVersion() async {
    final String? raw = await _storage.read(key: _keyVersionKey);
    return int.tryParse(raw ?? '1') ?? 1;
  }
}

/// In-memory key store for unit and integration tests. Never registered in a
/// release build.
class InMemoryKeyStore implements SigningKeyStore {
  InMemoryKeyStore({int? seed}) : _seed = seed;

  final int? _seed;
  final Ed25519 _algorithm = Ed25519();
  SimpleKeyPair? _pair;

  @override
  Future<SimpleKeyPair> loadOrCreateKeyPair() async {
    final SimpleKeyPair? existing = _pair;
    if (existing != null) return existing;

    final SimpleKeyPair pair;
    if (_seed != null) {
      // Deterministic key for reproducible test vectors only.
      final Random rng = Random(_seed);
      final List<int> seedBytes =
          List<int>.generate(32, (_) => rng.nextInt(256));
      pair = await _algorithm.newKeyPairFromSeed(seedBytes);
    } else {
      pair = await _algorithm.newKeyPair();
    }
    _pair = pair;
    return pair;
  }

  @override
  Future<String> publicKeyBase64() async {
    final SimplePublicKey pub =
        await (await loadOrCreateKeyPair()).extractPublicKey();
    return base64Url.encode(pub.bytes).replaceAll('=', '');
  }

  @override
  Future<String> publicKeyId() async {
    final SimplePublicKey pub =
        await (await loadOrCreateKeyPair()).extractPublicKey();
    final Hash digest = await Sha256().hash(pub.bytes);
    return digest.bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .substring(0, 16);
  }

  @override
  Future<int> keyVersion() async => 1;
}
