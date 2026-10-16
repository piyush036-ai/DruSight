/// Local classifier abstraction (master spec sections 22, 72).
///
/// The pipeline depends only on this interface, so a trained model can be
/// dropped in without touching analysis, evidence or UI code.
library;

import '../models/analysis_result.dart';
import '../models/colour_features.dart';
import '../models/kit_profile.dart';

abstract class ClassifierService {
  /// Identifier of the loaded model, or null when none is loaded.
  String? get modelId;
  String? get modelVersion;

  /// Feature-schema version the loaded model expects. The pipeline refuses to
  /// run a model whose schema does not match the extractor's.
  String? get featureSchemaVersion;

  Future<void> load(KitProfile profile);

  /// Runs inference. Implementations must return
  /// [ClassifierOutput.unavailable] rather than a guess when they cannot
  /// produce a genuine prediction.
  Future<ClassifierOutput> classify(
    ColourFeatures features, {
    required KitProfile profile,
  });

  Future<void> dispose();
}
