/// Colour-feature extraction from a calibrated test region
/// (master spec section 16).
///
/// Extraction happens AFTER calibration: every pixel is passed through the
/// fitted transform before any statistic is computed. Extracting features from
/// raw camera RGB and calibrating the summary afterwards is not equivalent,
/// because the transform is affine in linear light and the statistics are not.
library;

import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/colour_features.dart';
import '../models/test_region.dart';
import 'calibration.dart';
import 'colour_space.dart';
import 'linear_algebra.dart';

class FeatureExtractor {
  const FeatureExtractor({required this.schemaVersion});

  final String schemaVersion;

  /// Region is tiled this many times per axis for the spatial-uniformity term.
  static const int _tilesPerAxis = 4;

  /// Extracts the feature vector.
  ///
  /// [baselineLab] is the kit's configured negative/baseline colour, used for
  /// the deltaE-from-reference feature. Pass null when the profile defines
  /// none; the feature is then encoded as -1.0 (an impossible CIEDE2000
  /// value) so the model can distinguish "no baseline" from "zero distance".
  ColourFeatures extract(
    img.Image image, {
    required TestRegion region,
    required CalibrationResult calibration,
    Lab? baselineLab,
  }) {
    if (!calibration.succeeded) {
      throw StateError(
        'Refusing to extract features from an uncalibrated image. '
        'Calibration failed: ${calibration.failureReason}',
      );
    }

    final RegionBox box = region.box;
    final List<double> rs = <double>[];
    final List<double> gs = <double>[];
    final List<double> bs = <double>[];
    final List<double> hues = <double>[];
    final List<double> sats = <double>[];
    final List<double> vals = <double>[];
    final List<double> lumas = <double>[];

    for (int y = box.top; y < box.bottom; y++) {
      for (int x = box.left; x < box.right; x++) {
        final img.Pixel p = image.getPixel(x, y);
        final Rgb calibrated = calibration.apply(
          Rgb(p.r.toDouble(), p.g.toDouble(), p.b.toDouble()),
        );
        rs.add(calibrated.r);
        gs.add(calibrated.g);
        bs.add(calibrated.b);

        final Hsv hsv = ColourSpace.rgbToHsv(calibrated);
        // Hue is meaningless for near-grey pixels: a tiny channel difference
        // can swing it 180 degrees. Excluding them keeps the circular mean
        // from being dominated by noise.
        if (hsv.s > 0.08) hues.add(hsv.h);
        sats.add(hsv.s);
        vals.add(hsv.v);
        lumas.add(
          0.299 * calibrated.r + 0.587 * calibrated.g + 0.114 * calibrated.b,
        );
      }
    }

    if (rs.isEmpty) {
      throw StateError('Test region contains no pixels.');
    }

    final Rgb meanRgb = Rgb(
      LinearAlgebra.mean(rs),
      LinearAlgebra.mean(gs),
      LinearAlgebra.mean(bs),
    );
    final Lab meanLab = ColourSpace.rgbToLab(meanRgb);

    return ColourFeatures(
      schemaVersion: schemaVersion,
      meanRgb: meanRgb,
      medianRgb: Rgb(
        LinearAlgebra.percentile(rs, 0.5),
        LinearAlgebra.percentile(gs, 0.5),
        LinearAlgebra.percentile(bs, 0.5),
      ),
      stdDevRgb: Rgb(
        LinearAlgebra.stdDev(rs),
        LinearAlgebra.stdDev(gs),
        LinearAlgebra.stdDev(bs),
      ),
      meanHsv: Hsv(
        ColourSpace.circularMeanHue(hues) ?? 0,
        LinearAlgebra.mean(sats),
        LinearAlgebra.mean(vals),
      ),
      hueCircularMean: ColourSpace.circularMeanHue(hues) ?? 0,
      hueStdDev: _circularStdDev(hues),
      meanLab: meanLab,
      deltaEFromReference: baselineLab == null
          ? null
          : ColourSpace.deltaE2000(meanLab, baselineLab),
      spatialUniformity: _spatialUniformity(image, box, calibration, meanLab),
      edgeDensity: _edgeDensity(lumas, box.width, box.height),
      p05Luminance: LinearAlgebra.percentile(lumas, 0.05),
      p95Luminance: LinearAlgebra.percentile(lumas, 0.95),
      pixelCount: rs.length,
    );
  }

  /// Circular standard deviation in degrees, derived from the mean resultant
  /// length. Zero means all hues identical; large values mean no dominant hue.
  static double _circularStdDev(List<double> hues) {
    if (hues.length < 2) return 0;
    double sumSin = 0;
    double sumCos = 0;
    for (final double h in hues) {
      final double rad = h * math.pi / 180.0;
      sumSin += math.sin(rad);
      sumCos += math.cos(rad);
    }
    final double r =
        math.sqrt(sumSin * sumSin + sumCos * sumCos) / hues.length;
    if (r >= 1.0) return 0;
    if (r <= 0) return 180;
    return math.sqrt(-2 * math.log(r)) * 180.0 / math.pi;
  }

  static double _spatialUniformity(
    img.Image image,
    RegionBox box,
    CalibrationResult calibration,
    Lab regionMeanLab,
  ) {
    final int tileW = box.width ~/ _tilesPerAxis;
    final int tileH = box.height ~/ _tilesPerAxis;
    if (tileW < 2 || tileH < 2) return 0;

    final List<double> deltas = <double>[];
    for (int ty = 0; ty < _tilesPerAxis; ty++) {
      for (int tx = 0; tx < _tilesPerAxis; tx++) {
        final List<double> lr = <double>[];
        final List<double> lg = <double>[];
        final List<double> lb = <double>[];
        for (int y = box.top + ty * tileH; y < box.top + (ty + 1) * tileH; y++) {
          for (int x = box.left + tx * tileW;
              x < box.left + (tx + 1) * tileW;
              x++) {
            final img.Pixel p = image.getPixel(x, y);
            final Rgb c = calibration.apply(
              Rgb(p.r.toDouble(), p.g.toDouble(), p.b.toDouble()),
            );
            lr.add(c.r);
            lg.add(c.g);
            lb.add(c.b);
          }
        }
        if (lr.isEmpty) continue;
        deltas.add(
          ColourSpace.deltaE2000(
            ColourSpace.rgbToLab(
              Rgb(
                LinearAlgebra.mean(lr),
                LinearAlgebra.mean(lg),
                LinearAlgebra.mean(lb),
              ),
            ),
            regionMeanLab,
          ),
        );
      }
    }
    return deltas.isEmpty ? 0 : LinearAlgebra.mean(deltas);
  }

  /// Fraction of pixels whose local gradient magnitude exceeds a fixed
  /// threshold. High edge density inside a reaction region suggests texture,
  /// debris or a boundary was included rather than a clean reagent surface.
  static double _edgeDensity(List<double> luma, int width, int height) {
    if (width < 3 || height < 3 || luma.length != width * height) return 0;
    const double threshold = 18.0;
    int edges = 0;
    int counted = 0;
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final int i = y * width + x;
        final double gx = luma[i + 1] - luma[i - 1];
        final double gy = luma[i + width] - luma[i - width];
        if (math.sqrt(gx * gx + gy * gy) > threshold) edges++;
        counted++;
      }
    }
    return counted == 0 ? 0 : edges / counted;
  }
}
