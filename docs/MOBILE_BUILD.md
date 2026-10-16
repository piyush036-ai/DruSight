# Mobile build

## Requirements

- Flutter 3.29+ / Dart 3.3+ (`CardThemeData` and `Color.withValues` need 3.27+)
- Android SDK 34, minSdk 24 (camera2 + Keystore behaviour relied on)
- JDK 17

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

With the demonstration environment:

```bash
flutter run --dart-define=DRUSIGHT_DEMO=true
```

## Android permissions

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-feature android:name="android.hardware.camera" android:required="true" />
```

No `INTERNET` permission is requested. Core functionality does not need it, and
its absence is a verifiable statement that the app cannot exfiltrate anything.
Adding it later to support optional sync would be a deliberate, reviewable
change.

## Release build

```bash
flutter build apk --split-per-abi --release
flutter build appbundle --release
```

`--split-per-abi` produces per-architecture APKs, typically 30-40% smaller than
a universal APK.

## Signing

Create `android/key.properties` (already gitignored):

```properties
storePassword=<...>
keyPassword=<...>
keyAlias=<...>
storeFile=<absolute path to .jks>
```

Wire it into `android/app/build.gradle` per the Flutter deployment docs. Never
commit the keystore or this file.

## Measuring APK size

```bash
flutter build apk --split-per-abi --release --analyze-size
ls -lh build/app/outputs/flutter-apk/
```

**Record the actual measured figure.** Do not estimate it.

Size decisions already made:

- No OpenCV. The CV layer is pure Dart over the `image` package. OpenCV would
  add tens of megabytes for functions that fit on one screen.
- No bundled ML model, because none exists. When one ships, it is a single
  small ONNX file for a tabular classifier — kilobytes, not megabytes.
- No bundled sample images.
- No custom fonts; the platform font is used.
- Kit profiles and knowledge entries are small JSON.

## R8 / ProGuard

Default Flutter release settings apply. If you add rules, keep reflection-using
packages (`sqflite`, `device_info_plus`) intact.

## Release logging

Release builds must not log evidence contents, keys, credentials or personal
data. `avoid_print` is enabled in `analysis_options.yaml`; developer logging
should be guarded by `kDebugMode`.

## Status

`android/` is generated and configured: `minSdk` is pinned to 24, the manifest
declares CAMERA and the two location permissions, and `INTERNET` is
deliberately absent.

**The Gradle build has never run.** The development machine had no Android SDK
and no JDK. `flutter analyze` is clean and all 98 tests pass, so the Dart is
sound, but these remain unconfirmed:

- the Gradle build itself and native plugin linkage,
- R8 shrinking behaviour,
- **the APK size** — there is no measured figure anywhere in this repository,
  because no measurement exists. Do not quote one.

To confirm, install the Android SDK (command-line tools are enough) and a
JDK 17, accept the SDK licences with `flutter doctor --android-licenses`, then
run the release build above and record the real size.
