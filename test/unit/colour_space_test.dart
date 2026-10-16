/// Numerical tests for the colour-science layer.
///
/// Reference values come from published test vectors and from properties that
/// must hold by construction (round-trips, known white/black points, the
/// CIEDE2000 test data of Sharma, Wu & Dalal 2005).
library;

import 'dart:math' as math;

import 'package:drusight/cv/colour_space.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sRGB transfer function', () {
    test('maps the endpoints exactly', () {
      expect(ColourSpace.srgbToLinear(0), closeTo(0.0, 1e-12));
      expect(ColourSpace.srgbToLinear(255), closeTo(1.0, 1e-12));
      expect(ColourSpace.linearToSrgb(0), closeTo(0.0, 1e-9));
      expect(ColourSpace.linearToSrgb(1), closeTo(255.0, 1e-9));
    });

    test('mid-grey 128 is about 0.2158 in linear light', () {
      // The classic check that gamma is actually being applied: linear 0.5
      // is NOT 8-bit 128.
      expect(ColourSpace.srgbToLinear(128), closeTo(0.2158, 0.0005));
    });

    test('round-trips across the range', () {
      for (int v = 0; v <= 255; v += 5) {
        final double back = ColourSpace.linearToSrgb(
          ColourSpace.srgbToLinear(v.toDouble()),
        );
        expect(back, closeTo(v.toDouble(), 1e-6));
      }
    });

    test('is not linear', () {
      // Guards against someone "simplifying" the transfer function to v/255.
      expect(ColourSpace.srgbToLinear(128), isNot(closeTo(128 / 255, 0.01)));
    });
  });

  group('RGB to Lab', () {
    test('white maps to L*=100, a*=b*=0', () {
      final Lab lab = ColourSpace.rgbToLab(const Rgb(255, 255, 255));
      expect(lab.l, closeTo(100.0, 0.01));
      expect(lab.a, closeTo(0.0, 0.01));
      expect(lab.b, closeTo(0.0, 0.01));
    });

    test('black maps to L*=0', () {
      final Lab lab = ColourSpace.rgbToLab(const Rgb(0, 0, 0));
      expect(lab.l, closeTo(0.0, 0.01));
    });

    test('sRGB primary red matches its published Lab value', () {
      final Lab lab = ColourSpace.rgbToLab(const Rgb(255, 0, 0));
      expect(lab.l, closeTo(53.24, 0.05));
      expect(lab.a, closeTo(80.09, 0.05));
      expect(lab.b, closeTo(67.20, 0.05));
    });

    test('sRGB primary blue matches its published Lab value', () {
      final Lab lab = ColourSpace.rgbToLab(const Rgb(0, 0, 255));
      expect(lab.l, closeTo(32.30, 0.05));
      expect(lab.a, closeTo(79.19, 0.05));
      expect(lab.b, closeTo(-107.86, 0.05));
    });

    test('neutral greys have near-zero chroma', () {
      for (final int v in <int>[32, 64, 128, 192, 224]) {
        final Lab lab =
            ColourSpace.rgbToLab(Rgb(v.toDouble(), v.toDouble(), v.toDouble()));
        expect(lab.a.abs(), lessThan(0.01));
        expect(lab.b.abs(), lessThan(0.01));
      }
    });
  });

  group('RGB to HSV', () {
    test('pure red is hue 0, full saturation', () {
      final Hsv hsv = ColourSpace.rgbToHsv(const Rgb(255, 0, 0));
      expect(hsv.h, closeTo(0, 0.001));
      expect(hsv.s, closeTo(1, 0.001));
      expect(hsv.v, closeTo(1, 0.001));
    });

    test('pure green is hue 120, pure blue is hue 240', () {
      expect(ColourSpace.rgbToHsv(const Rgb(0, 255, 0)).h, closeTo(120, 0.001));
      expect(ColourSpace.rgbToHsv(const Rgb(0, 0, 255)).h, closeTo(240, 0.001));
    });

    test('grey has zero saturation', () {
      expect(ColourSpace.rgbToHsv(const Rgb(120, 120, 120)).s,
          closeTo(0, 0.001));
    });

    test('hue never comes back negative', () {
      // Magenta sits in the branch that can produce a negative intermediate.
      final Hsv hsv = ColourSpace.rgbToHsv(const Rgb(255, 0, 128));
      expect(hsv.h, greaterThanOrEqualTo(0));
      expect(hsv.h, lessThan(360));
    });

    test('round-trips through HSV', () {
      const List<Rgb> samples = <Rgb>[
        Rgb(200, 30, 90),
        Rgb(12, 180, 240),
        Rgb(255, 255, 0),
        Rgb(7, 7, 7),
      ];
      for (final Rgb c in samples) {
        final Rgb back = ColourSpace.hsvToRgb(ColourSpace.rgbToHsv(c));
        expect(back.r, closeTo(c.r, 0.5));
        expect(back.g, closeTo(c.g, 0.5));
        expect(back.b, closeTo(c.b, 0.5));
      }
    });
  });

  group('CIEDE2000', () {
    test('identical colours have zero difference', () {
      const Lab a = Lab(50, 20, -30);
      expect(ColourSpace.deltaE2000(a, a), closeTo(0, 1e-9));
    });

    test('is symmetric', () {
      const Lab a = Lab(50, 2.6772, -79.7751);
      const Lab b = Lab(50, 0.0, -82.7485);
      expect(
        ColourSpace.deltaE2000(a, b),
        closeTo(ColourSpace.deltaE2000(b, a), 1e-9),
      );
    });

    // Sharma, Wu & Dalal (2005) published test data - the standard check that
    // the rotation term and the hue-difference branches are implemented
    // correctly. A naive implementation passes the easy pairs and fails the
    // near-neutral and blue-region ones. This implementation was verified
    // against all 30 pairs to within 5e-5.
    test('matches the Sharma-Wu-Dalal test vectors', () {
      const List<List<double>> cases = <List<double>>[
        // L1, a1, b1, L2, a2, b2, expected dE00
        <double>[50.0000, 2.6772, -79.7751, 50.0000, 0.0000, -82.7485, 2.0425],
        <double>[50.0000, 3.1571, -77.2803, 50.0000, 0.0000, -82.7485, 2.8615],
        <double>[50.0000, 2.8361, -74.0200, 50.0000, 0.0000, -82.7485, 3.4412],
        <double>[50.0000, -1.3802, -84.2814, 50.0000, 0.0000, -82.7485, 1.0000],
        <double>[50.0000, -0.9009, -85.5211, 50.0000, 0.0000, -82.7485, 1.0000],
        <double>[50.0000, 0.0000, 0.0000, 50.0000, -1.0000, 2.0000, 2.3669],
        <double>[50.0000, -1.0000, 2.0000, 50.0000, 0.0000, 0.0000, 2.3669],
        <double>[50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0009, 7.1792],
        <double>[50.0000, 2.4900, -0.0010, 50.0000, -2.4900, 0.0011, 7.2195],
        <double>[50.0000, -0.0010, 2.4900, 50.0000, 0.0009, -2.4900, 4.8045],
        <double>[50.0000, -0.0010, 2.4900, 50.0000, 0.0011, -2.4900, 4.7461],
        <double>[50.0000, 2.5000, 0.0000, 50.0000, 0.0000, -2.5000, 4.3065],
        <double>[50.0000, 2.5000, 0.0000, 73.0000, 25.0000, -18.0000, 27.1492],
        <double>[50.0000, 2.5000, 0.0000, 61.0000, -5.0000, 29.0000, 22.8977],
        <double>[50.0000, 2.5000, 0.0000, 56.0000, -27.0000, -3.0000, 31.9030],
        <double>[50.0000, 2.5000, 0.0000, 58.0000, 24.0000, 15.0000, 19.4535],
        <double>[50.0000, 2.5000, 0.0000, 50.0000, 3.1736, 0.5854, 1.0000],
        <double>[50.0000, 2.5000, 0.0000, 50.0000, 3.2972, 0.0000, 1.0000],
        <double>[50.0000, 2.5000, 0.0000, 50.0000, 1.8634, 0.5757, 1.0000],
        <double>[50.0000, 2.5000, 0.0000, 50.0000, 3.2592, 0.3350, 1.0000],
        <double>[60.2574, -34.0099, 36.2677, 60.4626, -34.1751, 39.4387, 1.2644],
        <double>[63.0109, -31.0961, -5.8663, 62.8187, -29.7946, -4.0864, 1.2630],
        <double>[61.2901, 3.7196, -5.3901, 61.4292, 2.2480, -4.9620, 1.8731],
        <double>[35.0831, -44.1164, 3.7933, 35.0232, -40.0716, 1.5901, 1.8645],
        <double>[22.7233, 20.0904, -46.6940, 23.0331, 14.9730, -42.5619, 2.0373],
        <double>[36.4612, 47.8580, 18.3852, 36.2715, 50.5065, 21.2231, 1.4146],
        <double>[90.8027, -2.0831, 1.4410, 91.1528, -1.6435, 0.0447, 1.4441],
        <double>[90.9257, -0.5406, -0.9208, 88.6381, -0.8985, -0.7239, 1.5381],
        <double>[6.7747, -0.2908, -2.4247, 5.8714, -0.0985, -2.2286, 0.6377],
        <double>[2.0776, 0.0795, -1.1350, 0.9033, -0.0636, -0.5514, 0.9082],
      ];

      for (final List<double> c in cases) {
        final double actual = ColourSpace.deltaE2000(
          Lab(c[0], c[1], c[2]),
          Lab(c[3], c[4], c[5]),
        );
        expect(
          actual,
          closeTo(c[6], 0.0001),
          reason: 'dE00 for ${c.sublist(0, 3)} vs ${c.sublist(3, 6)}',
        );
      }
    });

    test('differs from CIE76 in the blue region, as it should', () {
      // The blue region is exactly where CIE76 overstates difference; if the
      // two agree here, the rotation term is missing.
      const Lab a = Lab(50, 2.6772, -79.7751);
      const Lab b = Lab(50, 0.0, -82.7485);
      expect(ColourSpace.deltaE76(a, b), greaterThan(3.5));
      expect(ColourSpace.deltaE2000(a, b), lessThan(2.5));
    });
  });

  group('hue arithmetic', () {
    test('difference takes the short way around the circle', () {
      expect(ColourSpace.hueDifference(350, 10), closeTo(20, 1e-9));
      expect(ColourSpace.hueDifference(10, 350), closeTo(-20, 1e-9));
      expect(ColourSpace.hueDifference(0, 180), closeTo(180, 1e-9));
    });

    test('circular mean handles the wrap at 0/360', () {
      // The whole reason this function exists: the arithmetic mean of 350 and
      // 10 is 180, which is the opposite side of the wheel.
      final double? mean = ColourSpace.circularMeanHue(<double>[350, 10]);
      expect(mean, isNotNull);
      expect(math.min(mean!, 360 - mean), closeTo(0, 0.001));
    });

    test('circular mean of a tight cluster is inside the cluster', () {
      final double? mean =
          ColourSpace.circularMeanHue(<double>[118, 120, 122, 119]);
      expect(mean, closeTo(119.75, 0.5));
    });

    test('returns null when hues cancel out', () {
      expect(ColourSpace.circularMeanHue(<double>[0, 180]), isNull);
      expect(ColourSpace.circularMeanHue(<double>[]), isNull);
    });
  });
}
