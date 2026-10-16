/// Exposure assessment from the luminance histogram.
///
/// Reports the fraction of clipped-dark and clipped-bright pixels plus mean
/// luminance. Clipped pixels carry no colour information at all, so a region
/// with significant clipping cannot be calibrated or measured honestly -
/// hence these are gates, not cosmetic warnings (master spec section 13).
library;

import 'package:image/image.dart' as img;

class ExposureReport {
  const ExposureReport({
    required this.meanLuminance,
    required this.shadowClippedFraction,
    required this.highlightClippedFraction,
    required this.dynamicRange,
  });

  /// Mean Rec. 601 luma in [0, 255].
  final double meanLuminance;

  /// Fraction of pixels at or below the shadow-clip threshold, in [0, 1].
  final double shadowClippedFraction;

  /// Fraction of pixels at or above the highlight-clip threshold, in [0, 1].
  final double highlightClippedFraction;

  /// p99 - p1 luminance spread. A very small spread means a flat, low-contrast
  /// capture in which colour differences are unreliable.
  final double dynamicRange;

  Map<String, Object?> toJson() => <String, Object?>{
        'meanLuminance': meanLuminance,
        'shadowClippedFraction': shadowClippedFraction,
        'highlightClippedFraction': highlightClippedFraction,
        'dynamicRange': dynamicRange,
      };
}

class ExposureMetric {
  const ExposureMetric._();

  static const int shadowClipThreshold = 4;
  static const int highlightClipThreshold = 251;

  static ExposureReport evaluate(img.Image image) {
    final List<int> histogram = List<int>.filled(256, 0);
    int total = 0;
    double sum = 0;

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final img.Pixel p = image.getPixel(x, y);
        final double luma = 0.299 * p.r.toDouble() +
            0.587 * p.g.toDouble() +
            0.114 * p.b.toDouble();
        final int bin = luma.round().clamp(0, 255).toInt();
        histogram[bin]++;
        sum += luma;
        total++;
      }
    }

    if (total == 0) {
      return const ExposureReport(
        meanLuminance: 0,
        shadowClippedFraction: 1,
        highlightClippedFraction: 0,
        dynamicRange: 0,
      );
    }

    int shadowClipped = 0;
    for (int i = 0; i <= shadowClipThreshold; i++) {
      shadowClipped += histogram[i];
    }
    int highlightClipped = 0;
    for (int i = highlightClipThreshold; i < 256; i++) {
      highlightClipped += histogram[i];
    }

    return ExposureReport(
      meanLuminance: sum / total,
      shadowClippedFraction: shadowClipped / total,
      highlightClippedFraction: highlightClipped / total,
      dynamicRange: (_percentileBin(histogram, total, 0.99) -
              _percentileBin(histogram, total, 0.01))
          .toDouble(),
    );
  }

  static int _percentileBin(List<int> histogram, int total, double p) {
    final int target = (total * p).round();
    int cumulative = 0;
    for (int i = 0; i < 256; i++) {
      cumulative += histogram[i];
      if (cumulative >= target) return i;
    }
    return 255;
  }
}
