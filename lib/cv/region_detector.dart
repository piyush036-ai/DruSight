/// Test-region localisation (master spec section 15).
///
/// Like the card detector, the prototype uses operator-guided selection with
/// automatic validation rather than a claimed automatic segmenter. The
/// operator places the region guide over the reaction area; the detector then
/// scores how plausible that region is as a single reacting surface:
///
///   - internal colour uniformity (a valid region should be one surface)
///   - contrast against its immediate surround (it should be distinguishable)
///   - absence of blown-out or crushed pixels
///
/// The resulting confidence is a QUALITY score for the selected region, not a
/// probability that an object was correctly classified. The distinction is
/// spelled out here because conflating the two is how fake confidence numbers
/// get into forensic tools.
library;

import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/enums.dart';
import '../models/test_region.dart';
import 'colour_space.dart';
import 'linear_algebra.dart';

class RegionDetection {
  const RegionDetection({
    required this.region,
    required this.uniformityDeltaE,
    required this.surroundContrastDeltaE,
    required this.clippedFraction,
    required this.detectorVersion,
    this.failureReason,
  });

  factory RegionDetection.failed(String reason, String version) =>
      RegionDetection(
        region: null,
        uniformityDeltaE: double.nan,
        surroundContrastDeltaE: double.nan,
        clippedFraction: 1,
        detectorVersion: version,
        failureReason: reason,
      );

  final TestRegion? region;
  final double uniformityDeltaE;
  final double surroundContrastDeltaE;
  final double clippedFraction;
  final String detectorVersion;
  final String? failureReason;

  bool get detected => region != null;
}

abstract class TestRegionDetector {
  String get version;

  RegionDetection detect(
    img.Image image, {
    required RegionBox candidate,
    required RegionSelectionMode mode,
  });
}

class GuidedRegionDetector implements TestRegionDetector {
  const GuidedRegionDetector();

  @override
  String get version => 'guided-region-detector-0.1.0';

  /// Region is split into this many tiles per axis for the uniformity check.
  static const int _tilesPerAxis = 4;

  /// Width of the surrounding ring sampled for the contrast check, as a
  /// fraction of the region's smaller dimension.
  static const double _surroundRingFraction = 0.25;

  @override
  RegionDetection detect(
    img.Image image, {
    required RegionBox candidate,
    required RegionSelectionMode mode,
  }) {
    if (candidate.width < 8 || candidate.height < 8) {
      return RegionDetection.failed(
        'Selected test region is smaller than 8x8 pixels. Move closer or '
        'enlarge the selection.',
        version,
      );
    }
    if (candidate.left < 0 ||
        candidate.top < 0 ||
        candidate.right > image.width ||
        candidate.bottom > image.height) {
      return RegionDetection.failed(
        'Selected test region extends outside the captured image.',
        version,
      );
    }

    final _RegionStats stats = _analyse(image, candidate);
    final Lab regionLab = ColourSpace.rgbToLab(stats.mean);

    // Uniformity: mean CIEDE2000 of each tile from the region mean.
    final List<double> tileDeltas = <double>[];
    final int tileW = candidate.width ~/ _tilesPerAxis;
    final int tileH = candidate.height ~/ _tilesPerAxis;
    if (tileW >= 2 && tileH >= 2) {
      for (int ty = 0; ty < _tilesPerAxis; ty++) {
        for (int tx = 0; tx < _tilesPerAxis; tx++) {
          final RegionBox tile = RegionBox(
            left: candidate.left + tx * tileW,
            top: candidate.top + ty * tileH,
            width: tileW,
            height: tileH,
          );
          final _RegionStats tileStats = _analyse(image, tile);
          tileDeltas.add(
            ColourSpace.deltaE2000(
              ColourSpace.rgbToLab(tileStats.mean),
              regionLab,
            ),
          );
        }
      }
    }
    final double uniformity =
        tileDeltas.isEmpty ? double.nan : LinearAlgebra.mean(tileDeltas);

    // Contrast against the surrounding ring.
    final double surroundContrast = _surroundContrast(
      image,
      candidate,
      regionLab,
    );

    // Confidence: a transparent product of three bounded quality terms. This
    // is documented in the UI as a region-quality score, never as a
    // probability of correct identification.
    final double uniformityTerm = uniformity.isNaN
        ? 0.5
        : (1.0 - (uniformity / 25.0)).clamp(0.0, 1.0);
    final double contrastTerm = surroundContrast.isNaN
        ? 0.5
        : (surroundContrast / 15.0).clamp(0.0, 1.0);
    final double clippingTerm = (1.0 - stats.clippedFraction * 3).clamp(0.0, 1.0);
    final double confidence = uniformityTerm * 0.45 +
        contrastTerm * 0.30 +
        clippingTerm * 0.25;

    return RegionDetection(
      region: TestRegion(
        box: candidate,
        confidence: double.parse(confidence.toStringAsFixed(4)),
        selectionMode: mode,
        detectorVersion: version,
      ),
      uniformityDeltaE: uniformity,
      surroundContrastDeltaE: surroundContrast,
      clippedFraction: stats.clippedFraction,
      detectorVersion: version,
    );
  }

  static double _surroundContrast(
    img.Image image,
    RegionBox region,
    Lab regionLab,
  ) {
    final int ring = math.max(
      2,
      (math.min(region.width, region.height) * _surroundRingFraction).round(),
    );
    final RegionBox outer = RegionBox(
      left: math.max(0, region.left - ring),
      top: math.max(0, region.top - ring),
      width: math.min(image.width, region.right + ring) -
          math.max(0, region.left - ring),
      height: math.min(image.height, region.bottom + ring) -
          math.max(0, region.top - ring),
    );
    if (outer.width <= region.width && outer.height <= region.height) {
      return double.nan; // Region touches the frame edge on all sides.
    }

    final List<double> rs = <double>[];
    final List<double> gs = <double>[];
    final List<double> bs = <double>[];
    for (int y = outer.top; y < outer.bottom; y++) {
      for (int x = outer.left; x < outer.right; x++) {
        final bool inside = x >= region.left &&
            x < region.right &&
            y >= region.top &&
            y < region.bottom;
        if (inside) continue;
        final img.Pixel p = image.getPixel(x, y);
        rs.add(ColourSpace.srgbToLinear(p.r.toDouble()));
        gs.add(ColourSpace.srgbToLinear(p.g.toDouble()));
        bs.add(ColourSpace.srgbToLinear(p.b.toDouble()));
      }
    }
    if (rs.isEmpty) return double.nan;

    final Rgb surroundMean = Rgb(
      ColourSpace.linearToSrgb(LinearAlgebra.mean(rs)),
      ColourSpace.linearToSrgb(LinearAlgebra.mean(gs)),
      ColourSpace.linearToSrgb(LinearAlgebra.mean(bs)),
    );
    return ColourSpace.deltaE2000(
      regionLab,
      ColourSpace.rgbToLab(surroundMean),
    );
  }

  static _RegionStats _analyse(img.Image image, RegionBox box) {
    final List<double> rs = <double>[];
    final List<double> gs = <double>[];
    final List<double> bs = <double>[];
    int clipped = 0;
    int total = 0;

    for (int y = box.top; y < box.bottom; y++) {
      for (int x = box.left; x < box.right; x++) {
        final img.Pixel p = image.getPixel(x, y);
        final double r = p.r.toDouble();
        final double g = p.g.toDouble();
        final double b = p.b.toDouble();
        rs.add(ColourSpace.srgbToLinear(r));
        gs.add(ColourSpace.srgbToLinear(g));
        bs.add(ColourSpace.srgbToLinear(b));
        final double maxC = math.max(r, math.max(g, b));
        final double minC = math.min(r, math.min(g, b));
        if (maxC >= 254 || minC <= 1) clipped++;
        total++;
      }
    }

    return _RegionStats(
      mean: Rgb(
        ColourSpace.linearToSrgb(LinearAlgebra.mean(rs)),
        ColourSpace.linearToSrgb(LinearAlgebra.mean(gs)),
        ColourSpace.linearToSrgb(LinearAlgebra.mean(bs)),
      ),
      clippedFraction: total == 0 ? 1 : clipped / total,
    );
  }
}

class _RegionStats {
  const _RegionStats({required this.mean, required this.clippedFraction});
  final Rgb mean;
  final double clippedFraction;
}
