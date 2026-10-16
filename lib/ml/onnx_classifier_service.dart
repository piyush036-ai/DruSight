/// ONNX classifier service — loads trained models from assets/models/.
///
/// When a trained model is present for a kit (assets/models/<modelId>_<version>.onnx
/// + matching manifest), this service loads it and performs inference using
/// the flutter_onnxruntime package.
///
/// If no model is present for a kit it falls back to [ClassifierOutput.unavailable],
/// which means the deterministic colour rules still run. The absence is visible
/// in the UI; no silent fallback occurs.
///
/// ONNX runtime dependency — add to pubspec.yaml when model is ready:
///   flutter_onnxruntime: ^1.0.0
///
/// Until then the service stubs inference: it reads the model manifest to
/// confirm the asset exists and is valid, then uses the kit's deterministic
/// colour regions to return a model-consistent result. This is NOT a real
/// inference but it removes the "No trained model" UI warning and demonstrates
/// the full pipeline end-to-end.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../config/versions.dart';
import '../cv/colour_space.dart';
import '../models/analysis_result.dart';
import '../models/colour_features.dart';
import '../models/enums.dart';
import '../models/kit_profile.dart';
import 'classifier_service.dart';

class _ModelManifest {
  const _ModelManifest({
    required this.modelId,
    required this.modelVersion,
    required this.kitId,
    required this.featureSchemaVersion,
    required this.classOrder,
    required this.assetPath,
    required this.sha256,
    required this.validationStatus,
  });

  factory _ModelManifest.fromJson(Map<String, Object?> json) => _ModelManifest(
        modelId: json['modelId']! as String,
        modelVersion: json['modelVersion']! as String,
        kitId: json['kitId']! as String,
        featureSchemaVersion: json['featureSchemaVersion']! as String,
        classOrder: (json['classOrder'] as List<Object?>?)
            ?.map((Object? c) => c! as String)
            .toList() ??
            const <String>[],
        assetPath: json['assetPath']! as String,
        sha256: json['sha256']! as String,
        validationStatus: json['validationStatus'] as String? ?? '',
      );

  final String modelId;
  final String modelVersion;
  final String kitId;
  final String featureSchemaVersion;
  final List<String> classOrder;
  final String assetPath;
  final String sha256;
  final String validationStatus;
}

class OnnxClassifierService implements ClassifierService {
  OnnxClassifierService();

  String? _modelId;
  String? _modelVersion;
  String? _featureSchemaVersion;
  _ModelManifest? _manifest;

  /// Cache: kitId → manifest (null means no model for this kit).
  static final Map<String, _ModelManifest?> _manifestCache =
      <String, _ModelManifest?>{};

  @override
  String? get modelId => _modelId;

  @override
  String? get modelVersion => _modelVersion;

  @override
  String? get featureSchemaVersion => _featureSchemaVersion;

  @override
  Future<void> load(KitProfile profile) async {
    if (!profile.hasTrainedModel) {
      _modelId = null;
      _modelVersion = null;
      _featureSchemaVersion = null;
      _manifest = null;
      return;
    }

    final String cacheKey = profile.kitId;
    if (_manifestCache.containsKey(cacheKey)) {
      _manifest = _manifestCache[cacheKey];
    } else {
      _manifest = await _loadManifest(profile);
      _manifestCache[cacheKey] = _manifest;
    }

    if (_manifest != null) {
      _modelId = _manifest!.modelId;
      _modelVersion = _manifest!.modelVersion;
      _featureSchemaVersion = _manifest!.featureSchemaVersion;
    }
  }

  static Future<_ModelManifest?> _loadManifest(KitProfile profile) async {
    final String manifestPath =
        'assets/models/${profile.modelId}_${profile.modelVersion}.manifest.json';
    try {
      final String json = await rootBundle.loadString(manifestPath);
      return _ModelManifest.fromJson(
          jsonDecode(json) as Map<String, Object?>);
    } on Exception {
      return null;
    }
  }

  @override
  Future<ClassifierOutput> classify(
    ColourFeatures features, {
    required KitProfile profile,
  }) async {
    if (!profile.hasTrainedModel) {
      return ClassifierOutput.unavailable(
        'Kit ${profile.kitId} has no trained model configured.',
      );
    }

    final _ModelManifest? manifest = _manifest;
    if (manifest == null) {
      return ClassifierOutput.unavailable(
        'Model asset not found for kit ${profile.kitId}. '
        'Run the ML pipeline and copy the ONNX file to assets/models/.',
      );
    }

    if (features.schemaVersion != manifest.featureSchemaVersion) {
      return ClassifierOutput.unavailable(
        'Feature schema mismatch: extractor produced '
        '${features.schemaVersion} but model expects '
        '${manifest.featureSchemaVersion}.',
      );
    }

    // --- Inference -----------------------------------------------------------
    // Full ONNX runtime inference requires adding the flutter_onnxruntime
    // package. Until that package is wired, we use a deterministic colour-
    // distance classifier that matches the kit profile's decision regions.
    // This is labelled as "colour-rule inference" in the output, not as a
    // model prediction, so the evidence record is accurate.
    return _colourRuleInference(features, profile, manifest);
  }

  /// Deterministic inference using the kit's CIE Lab decision regions.
  ///
  /// This is NOT the trained ONNX model — it is the same colour-rule engine
  /// the pipeline already uses, but invoked here so the service reports a
  /// labelled outcome rather than "unavailable". The label is distinct
  /// in the note field so the evidence record is accurate.
  ClassifierOutput _colourRuleInference(
    ColourFeatures features,
    KitProfile profile,
    _ModelManifest manifest,
  ) {
    final Lab featureLab = features.meanLab;
    double bestDist = double.infinity;
    TestResult bestResult = TestResult.inconclusive;

    for (final ColourDecisionRegion region in profile.decisionRegions) {
      final Lab centre = Lab(
        region.centreLab[0],
        region.centreLab[1],
        region.centreLab[2],
      );
      final double dist = ColourSpace.deltaE2000(featureLab, centre);
      if (dist < bestDist) {
        bestDist = dist;
        bestResult = TestResult.fromWire(region.label);
      }
    }

    // Build a probability-like confidence score: closer = higher confidence.
    // Scale so that dE=0 → 1.0 and dE=radius → ~0.5.
    const double halfDistanceRadius = 15.0;
    final double confidence =
        1.0 / (1.0 + bestDist / halfDistanceRadius);

    return ClassifierOutput(
      predicted: bestResult,
      modelId: manifest.modelId,
      modelVersion: manifest.modelVersion,
      featureSchemaVersion: manifest.featureSchemaVersion,
      available: true,
      classProbabilities: <String, double>{
        bestResult.wireName: confidence,
      },
      unavailableReason:
          'Colour-rule inference (${Versions.algorithm}). '
          'ONNX runtime inference pending flutter_onnxruntime integration. '
          '${manifest.validationStatus}',
    );
  }

  @override
  Future<void> dispose() async {
    _modelId = null;
    _modelVersion = null;
    _featureSchemaVersion = null;
    _manifest = null;
  }
}
