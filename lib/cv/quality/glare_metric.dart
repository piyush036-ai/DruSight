/// Specular-glare estimation.
///
/// Glare is distinguished from a legitimately bright subject by being both
/// very bright AND very desaturated: a specular highlight reflects the
/// illuminant's own colour and swamps the surface colour underneath. Pixels
/// meeting both conditions carry no usable reagent colour, so their fraction
/// within a region is a direct measure of how much of that region is
/// unmeasurable.
library;

import 'package:image/image.dart' as img;

class GlareReport {
  const GlareReport({
    required this.glareFraction,
    required this.largestGlareRunFraction,
  });

  /// Fraction of pixels classified as specular glare, in [0, 1].
  final double glareFraction;

  /// Fraction occupied by the largest contiguous horizontal glare run,
  /// normalised by image width. A single large blown-out patch is far more
  /// damaging than the same pixel count scattered as speckle.
  final double largestGlareRunFraction;

  Map<String, Object?> toJson() => <String, Object?>{
        'glareFraction': glareFraction,
        'largestGlareRunFraction': largestGlareRunFraction,
      };
}

class GlareMetric {
  const GlareMetric._();

  static const int brightnessThreshold = 240;
  static const double saturationThreshold = 0.12;

  static GlareReport evaluate(img.Image image) {
    int glarePixels = 0;
    int total = 0;
    int longestRun = 0;

    for (int y = 0; y < image.height; y++) {
      int run = 0;
      for (int x = 0; x < image.width; x++) {
        final img.Pixel p = image.getPixel(x, y);
        final double r = p.r.toDouble();
        final double g = p.g.toDouble();
        final double b = p.b.toDouble();

        final double maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
        final double minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
        final double saturation = maxC == 0 ? 0 : (maxC - minC) / maxC;

        final bool isGlare =
            maxC >= brightnessThreshold && saturation <= saturationThreshold;

        if (isGlare) {
          glarePixels++;
          run++;
          if (run > longestRun) longestRun = run;
        } else {
          run = 0;
        }
        total++;
      }
    }

    if (total == 0) {
      return const GlareReport(glareFraction: 0, largestGlareRunFraction: 0);
    }
    return GlareReport(
      glareFraction: glarePixels / total,
      largestGlareRunFraction:
          image.width == 0 ? 0 : longestRun / image.width,
    );
  }
}
