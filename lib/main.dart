/// DruSight entry point.
///
/// See docs/ARCHITECTURE.md for the module map and docs/LIMITATIONS.md for
/// what this prototype does and does not establish.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/service_locator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait only: the capture guides and their mapping to image coordinates
  // assume a fixed orientation.
  await SystemChrome.setPreferredOrientations(
    <DeviceOrientation>[DeviceOrientation.portraitUp],
  );

  final ServiceLocator services = await ServiceLocator.bootstrap();
  await services.installBundledContent();

  runApp(DruSightApp(services: services));
}
