/// Device and build identity recorded with every test (master spec section 9).
///
/// Privacy-minimising by design: [installationId] is a random value generated
/// on first launch and stored locally. No hardware serial, advertising ID, IMEI
/// or account identifier is collected.
library;

class DeviceIdentity {
  const DeviceIdentity({
    required this.installationId,
    required this.deviceModel,
    required this.osVersion,
    required this.appVersion,
    required this.appBuild,
  });

  factory DeviceIdentity.fromJson(Map<String, Object?> json) => DeviceIdentity(
        installationId: json['installationId']! as String,
        deviceModel: json['deviceModel']! as String,
        osVersion: json['osVersion']! as String,
        appVersion: json['appVersion']! as String,
        appBuild: json['appBuild']! as String,
      );

  final String installationId;
  final String deviceModel;
  final String osVersion;
  final String appVersion;
  final String appBuild;

  Map<String, Object?> toJson() => <String, Object?>{
        'installationId': installationId,
        'deviceModel': deviceModel,
        'osVersion': osVersion,
        'appVersion': appVersion,
        'appBuild': appBuild,
      };
}
