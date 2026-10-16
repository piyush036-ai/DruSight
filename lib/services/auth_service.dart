/// Local operator authentication (master spec section 8).
///
/// Scope: this is a local passphrase check for a field prototype. It is not
/// enterprise identity management, it does not federate, and it does not
/// verify the officer ID against any registry. Said plainly here so the
/// limitation travels with the code.
///
/// Passphrases are stored as PBKDF2-HMAC-SHA256 derived keys with a per-user
/// random salt. Plaintext is never stored, never logged and never leaves the
/// authenticate call.
///
/// Session persistence: on successful login the authenticated officer ID is
/// written to flutter_secure_storage. On the next cold start the session is
/// restored automatically, skipping the login screen — identical to how
/// consumer apps (Zomato, etc.) keep you signed in until you explicitly
/// sign out or uninstall the app.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/enums.dart';
import '../models/operator.dart';
import '../repositories/operator_repository.dart';

class AuthResult {
  const AuthResult.success(this.session)
      : failureMessage = null,
        succeeded = true;

  const AuthResult.failure(this.failureMessage)
      : session = null,
        succeeded = false;

  final bool succeeded;
  final OperatorSession? session;
  final String? failureMessage;
}

class AuthService {
  AuthService(this._repository);

  final OperatorRepository _repository;

  /// OWASP-aligned iteration count for PBKDF2-HMAC-SHA256 on mobile. High
  /// enough to be meaningful, low enough not to stall a field login.
  static const int pbkdf2Iterations = 210000;
  static const int _saltBytes = 16;
  static const int _keyBytes = 32;

  /// Secure-storage key that holds the persisted officer ID.
  static const String _sessionKey = 'drusight_session_officer_id';

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  OperatorSession? _current;
  OperatorSession? get currentSession => _current;

  /// Called once during [ServiceLocator.bootstrap]. Reads the persisted
  /// officer ID and, if the account still exists and is active, restores the
  /// session so the app can skip the login screen.
  Future<void> restoreSession() async {
    final String? officerId = await _storage.read(key: _sessionKey);
    if (officerId == null) return;

    final OperatorAccount? account =
        await _repository.findByOfficerId(officerId);
    if (account == null || !account.active) {
      await _storage.delete(key: _sessionKey);
      return;
    }

    _current = OperatorSession(
      sessionId: _generateId(),
      account: account,
      authenticatedAtUtc: DateTime.now().toUtc(),
    );
  }

  Future<OperatorAccount> register({
    required String officerId,
    required String displayName,
    required OperatorRole role,
    required String passphrase,
  }) async {
    if (passphrase.length < 8) {
      throw ArgumentError('Passphrase must be at least 8 characters.');
    }

    final String salt = _generateSalt();
    final String hash = await _derive(passphrase, salt);

    final OperatorAccount account = OperatorAccount(
      operatorId: _generateId(),
      officerId: officerId.trim(),
      displayName: displayName.trim(),
      role: role,
      passphraseHash: hash,
      passphraseSalt: salt,
      createdAtUtc: DateTime.now().toUtc(),
      active: true,
    );
    await _repository.insert(account, pbkdf2Iterations);
    return account;
  }

  Future<AuthResult> authenticate({
    required String officerId,
    required String passphrase,
  }) async {
    final OperatorAccount? account =
        await _repository.findByOfficerId(officerId.trim());

    if (account == null || !account.active) {
      // Deliberately identical message for unknown and wrong-passphrase, so
      // the screen does not reveal which officer IDs exist.
      return const AuthResult.failure('Officer ID or passphrase is incorrect.');
    }

    final int iterations =
        await _repository.iterationsFor(account.operatorId) ?? pbkdf2Iterations;
    final String candidate =
        await _derive(passphrase, account.passphraseSalt, iterations);

    if (!_constantTimeEquals(candidate, account.passphraseHash)) {
      return const AuthResult.failure('Officer ID or passphrase is incorrect.');
    }

    final OperatorSession session = OperatorSession(
      sessionId: _generateId(),
      account: account,
      authenticatedAtUtc: DateTime.now().toUtc(),
    );
    _current = session;
    // Persist the officer ID so the next cold start skips login.
    await _storage.write(key: _sessionKey, value: account.officerId);
    return AuthResult.success(session);
  }

  /// Signs out and clears the persisted session token.
  Future<void> signOut() async {
    _current = null;
    await _storage.delete(key: _sessionKey);
  }

  static Future<String> _derive(
    String passphrase,
    String saltBase64, [
    int iterations = pbkdf2Iterations,
  ]) async {
    final Pbkdf2 pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: _keyBytes * 8,
    );
    final SecretKey key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: base64.decode(saltBase64),
    );
    return base64.encode(await key.extractBytes());
  }

  static String _generateSalt() {
    final Random rng = Random.secure();
    final Uint8List bytes = Uint8List(_saltBytes);
    for (int i = 0; i < _saltBytes; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return base64.encode(bytes);
  }

  static String _generateId() {
    final Random rng = Random.secure();
    final Uint8List bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes.map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
