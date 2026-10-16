/// Placeholder classifier used until a real model has been trained.
///
/// It deliberately does NOT invent a prediction. Every call returns
/// [ClassifierOutput.unavailable], which propagates through the reliability
/// engine as a documented reason the result rests on deterministic colour
/// rules alone (master spec sections 55, 72).
///
/// The temptation here is to return a plausible-looking label so the demo
/// feels complete. That is exactly the fabrication the spec forbids: a
/// fabricated prediction in a forensic tool is worse than an absent one,
/// because the absence is visible and the fabrication is not.
library;

import '../models/analysis_result.dart';
import '../models/colour_features.dart';
import '../models/kit_profile.dart';
import 'classifier_service.dart';

class MockClassifierService implements ClassifierService {
  @override
  String? get modelId => null;

  @override
  String? get modelVersion => null;

  @override
  String? get featureSchemaVersion => null;

  @override
  Future<void> load(KitProfile profile) async {}

  @override
  Future<ClassifierOutput> classify(
    ColourFeatures features, {
    required KitProfile profile,
  }) async =>
      ClassifierOutput.unavailable(
        'No trained model is installed for kit ${profile.kitId}. The result '
        'shown is derived from the deterministic colour rules in the kit '
        'profile only.',
      );

  @override
  Future<void> dispose() async {}
}
