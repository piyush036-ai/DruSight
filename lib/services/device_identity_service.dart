/// Device identity (master spec section 9).
///
/// The installation ID is a locally-generated random value, not a hardware
/// identifier. It is stable across launches and cleared on uninstall, which
/// is exactly the property needed to chain a device's records without
/// tracking a person or a handset.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/device_identity.dart';

class DeviceIdentityService {
  DeviceIdentityService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  static const String _installationIdKey = 'drusight.installation_id';

  DeviceIdentity? _cached;

  Future<DeviceIdentity> current() async {
    final DeviceIdentity? cached = _cached;
    if (cached != null) return cached;

    final String installationId = await _installationId();
    final PackageInfo package = await PackageInfo.fromPlatform();

    String model = 'unknown';
    String osVersion = 'unknown';
    final DeviceInfoPlugin info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final AndroidDeviceInfo android = await info.androidInfo;
      model = '${android.manufacturer} ${android.model}';
      osVersion = 'Android ${android.version.release} '
          '(API ${android.version.sdkInt})';
    } else if (Platform.isIOS) {
      final IosDeviceInfo ios = await info.iosInfo;
      model = ios.utsname.machine;
      osVersion = '${ios.systemName} ${ios.systemVersion}';
    }

    final DeviceIdentity identity = DeviceIdentity(
      installationId: installationId,
      deviceModel: model,
      osVersion: osVersion,
      appVersion: package.version,
      appBuild: package.buildNumber,
    );
    _cached = identity;
    return identity;
  }

  Future<String> _installationId() async {
    final String? existing = await _storage.read(key: _installationIdKey);
    if (existing != null) return existing;

    final Random rng = Random.secure();
    final String generated = base64Url
        .encode(List<int>.generate(16, (_) => rng.nextInt(256)))
        .replaceAll('=', '');
    await _storage.write(key: _installationIdKey, value: generated);
    return generated;
  }
}
