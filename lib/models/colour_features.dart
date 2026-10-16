/// Feature vector extracted from a calibrated test region (master spec 16).
///
/// The layout is pinned by a feature-schema version and must stay in lockstep
/// with `ml_training/scripts/extract_features.py`. Changing the order or
/// meaning of any field requires a schema version bump, otherwise an old model
/// would silently be fed a differently-shaped vector.
library;

import '../cv/colour_space.dart';

class ColourFeatures {
  const ColourFeatures({
    required this.schemaVersion,
    required this.meanRgb,
    required this.medianRgb,
    required this.stdDevRgb,
    required this.meanHsv,
    required this.hueCircularMean,
    required this.hueStdDev,
    required this.meanLab,
    required this.deltaEFromReference,
    required this.spatialUniformity,
    required this.edgeDensity,
    required this.p05Luminance,
    required this.p95Luminance,
    required this.pixelCount,
  });

  final String schemaVersion;

  final Rgb meanRgb;
  final Rgb medianRgb;
  final Rgb stdDevRgb;

  /// Mean saturation and value; hue is handled separately because it is
  /// circular and an arithmetic mean of hue is meaningless.
  final Hsv meanHsv;
  final double hueCircularMean;
  final double hueStdDev;

  final Lab meanLab;

  /// CIEDE2000 distance from the kit's configured negative/baseline colour.
  /// Null when the profile defines no baseline region.
  final double? deltaEFromReference;

  /// Mean CIEDE2000 of each sub-tile from the region mean. Low values mean a
  /// homogeneous reaction; high values suggest incomplete mixing, a shadow, or
  /// that the region boundary caught something other than the reagent.
  final double spatialUniformity;

  final double edgeDensity;
  final double p05Luminance;
  final double p95Luminance;
  final int pixelCount;

  /// Ordered numeric vector for the classifier. The order IS the schema.
  List<double> toVector() => <double>[
        meanRgb.r,
        meanRgb.g,
        meanRgb.b,
        medianRgb.r,
        medianRgb.g,
        medianRgb.b,
        stdDevRgb.r,
        stdDevRgb.g,
        stdDevRgb.b,
        hueCircularMean,
        hueStdDev,
        meanHsv.s,
        meanHsv.v,
        meanLab.l,
        meanLab.a,
        meanLab.b,
        deltaEFromReference ?? -1.0,
        spatialUniformity,
        edgeDensity,
        p05Luminance,
        p95Luminance,
      ];

  /// Names matching [toVector], in the same order. Used by the explanation
  /// builder and by the Python pipeline's column headers.
  static const List<String> featureNames = <String>[
    'mean_r',
    'mean_g',
    'mean_b',
    'median_r',
    'median_g',
    'median_b',
    'std_r',
    'std_g',
    'std_b',
    'hue_circular_mean',
    'hue_std',
    'saturation_mean',
    'value_mean',
    'lab_l',
    'lab_a',
    'lab_b',
    'delta_e_from_reference',
    'spatial_uniformity',
    'edge_density',
    'p05_luminance',
    'p95_luminance',
  ];

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'meanRgb': meanRgb.toJson(),
        'medianRgb': medianRgb.toJson(),
        'stdDevRgb': stdDevRgb.toJson(),
        'meanHsv': meanHsv.toJson(),
        'hueCircularMean': hueCircularMean,
        'hueStdDev': hueStdDev,
        'meanLab': meanLab.toJson(),
        'deltaEFromReference': deltaEFromReference,
        'spatialUniformity': spatialUniformity,
        'edgeDensity': edgeDensity,
        'p05Luminance': p05Luminance,
        'p95Luminance': p95Luminance,
        'pixelCount': pixelCount,
      };
}
