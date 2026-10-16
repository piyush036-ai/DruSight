/// Focus/blur estimation by variance of the Laplacian.
///
/// The Laplacian responds to intensity second derivatives, i.e. edges. A sharp
/// image has a broad distribution of Laplacian responses; a defocused one has
/// them all near zero. The variance of the response is therefore a usable
/// sharpness proxy and is cheap enough to run per preview frame.
///
/// Caveat that matters for interpretation: the absolute value is scene- and
/// resolution-dependent, so it is compared against a per-kit threshold from
/// the kit profile, never against a universal constant.
library;

import 'package:image/image.dart' as img;

class BlurMetric {
  const BlurMetric._();

  /// Returns the variance of the 4-neighbour Laplacian over the image
  /// luminance. Higher means sharper. Returns 0 for degenerate input.
  static double varianceOfLaplacian(img.Image image) {
    final int w = image.width;
    final int h = image.height;
    if (w < 3 || h < 3) return 0;

    // Precompute luminance once; repeated getPixel calls dominate otherwise.
    final List<double> luma = _luminancePlane(image);

    double sum = 0;
    double sumSq = 0;
    int count = 0;

    for (int y = 1; y < h - 1; y++) {
      final int rowBase = y * w;
      for (int x = 1; x < w - 1; x++) {
        final int i = rowBase + x;
        final double lap = luma[i - 1] +
            luma[i + 1] +
            luma[i - w] +
            luma[i + w] -
            4 * luma[i];
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }

    if (count == 0) return 0;
    final double mean = sum / count;
    final double variance = (sumSq / count) - (mean * mean);
    return variance < 0 ? 0 : variance;
  }

  /// Rec. 601 luma, matching what the exposure metric uses so the two scores
  /// describe the same underlying plane.
  static List<double> _luminancePlane(img.Image image) {
    final int w = image.width;
    final int h = image.height;
    final List<double> out = List<double>.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final img.Pixel p = image.getPixel(x, y);
        out[y * w + x] =
            0.299 * p.r.toDouble() + 0.587 * p.g.toDouble() + 0.114 * p.b.toDouble();
      }
    }
    return out;
  }
}
