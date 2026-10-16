/// Colour-space conversions and colour-distance metrics.
///
/// Pure Dart, no OpenCV dependency (master spec section 6). All conversions
/// use the sRGB colour space with a D65 white point, which is the working
/// assumption for consumer phone cameras.
///
/// Every function here is deterministic and covered by unit tests; these are
/// the numerical foundation of the whole measurement layer.
library;

import 'dart:math' as math;

/// A colour in non-linear 8-bit sRGB, as delivered by the camera pipeline.
class Rgb {
  const Rgb(this.r, this.g, this.b);

  /// Channel values in [0, 255].
  final double r;
  final double g;
  final double b;

  Rgb clamped() => Rgb(
        r.clamp(0.0, 255.0),
        g.clamp(0.0, 255.0),
        b.clamp(0.0, 255.0),
      );

  Map<String, double> toJson() => <String, double>{'r': r, 'g': g, 'b': b};

  @override
  String toString() =>
      'Rgb(${r.toStringAsFixed(1)}, ${g.toStringAsFixed(1)}, '
      '${b.toStringAsFixed(1)})';
}

/// Hue-Saturation-Value. Hue in degrees [0, 360), S and V in [0, 1].
class Hsv {
  const Hsv(this.h, this.s, this.v);

  final double h;
  final double s;
  final double v;

  Map<String, double> toJson() => <String, double>{'h': h, 's': s, 'v': v};

  @override
  String toString() =>
      'Hsv(${h.toStringAsFixed(1)}deg, ${s.toStringAsFixed(3)}, '
      '${v.toStringAsFixed(3)})';
}

/// CIE L*a*b* under a D65 illuminant.
class Lab {
  const Lab(this.l, this.a, this.b);

  final double l;
  final double a;
  final double b;

  Map<String, double> toJson() => <String, double>{'L': l, 'a': a, 'b': b};

  @override
  String toString() =>
      'Lab(${l.toStringAsFixed(2)}, ${a.toStringAsFixed(2)}, '
      '${b.toStringAsFixed(2)})';
}

/// Colour-space conversion and distance functions.
class ColourSpace {
  const ColourSpace._();

  // D65 white point in XYZ, scaled to Y = 100.
  static const double _xn = 95.047;
  static const double _yn = 100.000;
  static const double _zn = 108.883;

  /// sRGB electro-optical transfer function: 8-bit encoded value to linear
  /// light in [0, 1]. This inverse-gamma step must happen before any
  /// physically meaningful averaging or colour transform.
  static double srgbToLinear(double channel8Bit) {
    final double c = (channel8Bit / 255.0).clamp(0.0, 1.0);
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  /// Inverse of [srgbToLinear]: linear light in [0, 1] back to 8-bit sRGB.
  static double linearToSrgb(double linear) {
    final double c = linear.clamp(0.0, 1.0);
    final double encoded =
        c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
    return (encoded * 255.0).clamp(0.0, 255.0);
  }

  /// sRGB (8-bit, non-linear) to HSV.
  static Hsv rgbToHsv(Rgb rgb) {
    final double r = rgb.r / 255.0;
    final double g = rgb.g / 255.0;
    final double b = rgb.b / 255.0;

    final double max = math.max(r, math.max(g, b));
    final double min = math.min(r, math.min(g, b));
    final double delta = max - min;

    double h;
    if (delta == 0) {
      h = 0;
    } else if (max == r) {
      h = 60 * (((g - b) / delta) % 6);
    } else if (max == g) {
      h = 60 * (((b - r) / delta) + 2);
    } else {
      h = 60 * (((r - g) / delta) + 4);
    }
    if (h < 0) h += 360;

    final double s = max == 0 ? 0 : delta / max;
    return Hsv(h, s, max);
  }

  /// HSV back to 8-bit sRGB. Provided for rendering calibrated swatches.
  static Rgb hsvToRgb(Hsv hsv) {
    final double c = hsv.v * hsv.s;
    final double hp = (hsv.h % 360) / 60.0;
    final double x = c * (1 - ((hp % 2) - 1).abs());
    final double m = hsv.v - c;

    double r;
    double g;
    double b;
    if (hp < 1) {
      r = c; g = x; b = 0;
    } else if (hp < 2) {
      r = x; g = c; b = 0;
    } else if (hp < 3) {
      r = 0; g = c; b = x;
    } else if (hp < 4) {
      r = 0; g = x; b = c;
    } else if (hp < 5) {
      r = x; g = 0; b = c;
    } else {
      r = c; g = 0; b = x;
    }
    return Rgb((r + m) * 255, (g + m) * 255, (b + m) * 255);
  }

  /// sRGB (8-bit, non-linear) to CIE XYZ (D65, Y scaled to 100).
  static List<double> rgbToXyz(Rgb rgb) {
    final double r = srgbToLinear(rgb.r);
    final double g = srgbToLinear(rgb.g);
    final double b = srgbToLinear(rgb.b);

    return <double>[
      (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) * 100.0,
      (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) * 100.0,
      (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) * 100.0,
    ];
  }

  /// sRGB (8-bit, non-linear) to CIE L*a*b* (D65).
  static Lab rgbToLab(Rgb rgb) {
    final List<double> xyz = rgbToXyz(rgb);
    final double fx = _labF(xyz[0] / _xn);
    final double fy = _labF(xyz[1] / _yn);
    final double fz = _labF(xyz[2] / _zn);

    return Lab(
      116 * fy - 16,
      500 * (fx - fy),
      200 * (fy - fz),
    );
  }

  static double _labF(double t) {
    const double delta = 6.0 / 29.0;
    return t > delta * delta * delta
        ? math.pow(t, 1 / 3).toDouble()
        : t / (3 * delta * delta) + 4.0 / 29.0;
  }

  /// CIE76 colour difference: plain Euclidean distance in Lab.
  ///
  /// Cheap and adequate for coarse gating. Prefer [deltaE2000] for anything
  /// reported to the operator or fed to the classifier.
  static double deltaE76(Lab a, Lab b) {
    final double dl = a.l - b.l;
    final double da = a.a - b.a;
    final double db = a.b - b.b;
    return math.sqrt(dl * dl + da * da + db * db);
  }

  /// CIEDE2000 colour difference.
  ///
  /// Implements the formulation of Sharma, Wu & Dalal (2005). This is the
  /// metric reported as "deltaE" in evidence records, because it correlates
  /// far better with perceived difference than CIE76 in the saturated
  /// blue/purple region where several colourimetric reagents operate.
  static double deltaE2000(
    Lab s,
    Lab t, {
    double kL = 1.0,
    double kC = 1.0,
    double kH = 1.0,
  }) {
    const double pow25To7 = 6103515625.0; // 25^7

    final double c1 = math.sqrt(s.a * s.a + s.b * s.b);
    final double c2 = math.sqrt(t.a * t.a + t.b * t.b);
    final double cBar = (c1 + c2) / 2.0;

    final double cBar7 = math.pow(cBar, 7).toDouble();
    final double g = 0.5 * (1 - math.sqrt(cBar7 / (cBar7 + pow25To7)));

    final double a1p = (1 + g) * s.a;
    final double a2p = (1 + g) * t.a;

    final double c1p = math.sqrt(a1p * a1p + s.b * s.b);
    final double c2p = math.sqrt(a2p * a2p + t.b * t.b);

    final double h1p = _hueAngleDegrees(s.b, a1p);
    final double h2p = _hueAngleDegrees(t.b, a2p);

    final double dLp = t.l - s.l;
    final double dCp = c2p - c1p;

    double dhp;
    if (c1p * c2p == 0) {
      dhp = 0;
    } else {
      final double diff = h2p - h1p;
      if (diff.abs() <= 180) {
        dhp = diff;
      } else if (diff > 180) {
        dhp = diff - 360;
      } else {
        dhp = diff + 360;
      }
    }
    final double dHp =
        2 * math.sqrt(c1p * c2p) * math.sin(_radians(dhp) / 2.0);

    final double lBarP = (s.l + t.l) / 2.0;
    final double cBarP = (c1p + c2p) / 2.0;

    double hBarP;
    if (c1p * c2p == 0) {
      hBarP = h1p + h2p;
    } else {
      final double diff = (h1p - h2p).abs();
      if (diff <= 180) {
        hBarP = (h1p + h2p) / 2.0;
      } else if (h1p + h2p < 360) {
        hBarP = (h1p + h2p + 360) / 2.0;
      } else {
        hBarP = (h1p + h2p - 360) / 2.0;
      }
    }

    final double tTerm = 1 -
        0.17 * math.cos(_radians(hBarP - 30)) +
        0.24 * math.cos(_radians(2 * hBarP)) +
        0.32 * math.cos(_radians(3 * hBarP + 6)) -
        0.20 * math.cos(_radians(4 * hBarP - 63));

    final double dTheta = 30 * math.exp(-math.pow((hBarP - 275) / 25, 2).toDouble());
    final double cBarP7 = math.pow(cBarP, 7).toDouble();
    final double rC = 2 * math.sqrt(cBarP7 / (cBarP7 + pow25To7));
    final double rT = -rC * math.sin(2 * _radians(dTheta));

    final double lBarPMinus50Sq = (lBarP - 50) * (lBarP - 50);
    final double sL =
        1 + (0.015 * lBarPMinus50Sq) / math.sqrt(20 + lBarPMinus50Sq);
    final double sC = 1 + 0.045 * cBarP;
    final double sH = 1 + 0.015 * cBarP * tTerm;

    final double termL = dLp / (kL * sL);
    final double termC = dCp / (kC * sC);
    final double termH = dHp / (kH * sH);

    return math.sqrt(
      termL * termL + termC * termC + termH * termH + rT * termC * termH,
    );
  }

  static double _hueAngleDegrees(double b, double ap) {
    if (b == 0 && ap == 0) return 0;
    final double deg = _degrees(math.atan2(b, ap));
    return deg >= 0 ? deg : deg + 360;
  }

  static double _radians(double degrees) => degrees * math.pi / 180.0;
  static double _degrees(double radians) => radians * 180.0 / math.pi;

  /// Shortest signed angular distance between two hues, in degrees.
  /// Result is in (-180, 180]. Needed because hue wraps at 360.
  static double hueDifference(double h1, double h2) {
    double diff = (h2 - h1) % 360.0;
    if (diff > 180) diff -= 360;
    if (diff <= -180) diff += 360;
    return diff;
  }

  /// Circular mean of a set of hue angles in degrees.
  ///
  /// A plain arithmetic mean is wrong for hue: the mean of 350 and 10 is 0,
  /// not 180. Returns null if the hues cancel out (no dominant direction).
  static double? circularMeanHue(List<double> hues) {
    if (hues.isEmpty) return null;
    double sumSin = 0;
    double sumCos = 0;
    for (final double h in hues) {
      sumSin += math.sin(_radians(h));
      sumCos += math.cos(_radians(h));
    }
    if (sumSin.abs() < 1e-12 && sumCos.abs() < 1e-12) return null;
    final double mean = _degrees(math.atan2(sumSin, sumCos));
    return mean >= 0 ? mean : mean + 360;
  }
}
