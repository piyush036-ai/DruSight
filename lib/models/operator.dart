/// Operator identity for the prototype's local authentication.
///
/// This is deliberately minimal local authentication, NOT enterprise identity
/// management (master spec section 8). Only the fields needed for
/// accountability are stored.
library;

import 'enums.dart';

class OperatorAccount {
  const OperatorAccount({
    required this.operatorId,
    required this.officerId,
    required this.displayName,
    required this.role,
    required this.passphraseHash,
    required this.passphraseSalt,
    required this.createdAtUtc,
    required this.active,
  });

  final String operatorId;

  /// Institutional officer identifier as entered by the operator. Treated as
  /// an opaque string; the app does not validate it against any registry.
  final String officerId;

  final String displayName;
  final OperatorRole role;

  /// PBKDF2-HMAC-SHA256 digest, hex-encoded. The plaintext passphrase is never
  /// stored or logged.
  final String passphraseHash;
  final String passphraseSalt;

  final DateTime createdAtUtc;
  final bool active;

  Map<String, Object?> toJson() => <String, Object?>{
        'operatorId': operatorId,
        'officerId': officerId,
        'displayName': displayName,
        'role': role.wireName,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'active': active,
      };
}

/// An authenticated session. Session IDs appear in evidence records so a group
/// of tests can be attributed to one continuous field session.
class OperatorSession {
  const OperatorSession({
    required this.sessionId,
    required this.account,
    required this.authenticatedAtUtc,
  });

  final String sessionId;
  final OperatorAccount account;
  final DateTime authenticatedAtUtc;
}
