/// Reference-card localisation (master spec sections 11, 14).
///
/// Two strategies are defined behind one interface:
///
///   [GuidedFrameCardDetector] - the shipped prototype detector. The capture
///   overlay draws a card-shaped guide; the operator aligns the printed card
///   inside it. Patch positions then follow from the guide rectangle and the
///   card spec's relative patch geometry. The detector still VALIDATES what it
///   sampled: patches must be internally uniform and mutually distinguishable,
///   and their observed ordering must correlate with the expected ordering.
///   If the operator photographed the wrong thing, or the card is occluded, or
///   the alignment is bad, validation fails and no calibration is attempted.
///
///   [HomographyCardDetector] - the integration point for full automatic
///   detection (quad detection, perspective rectification). Deliberately not
///   faked: it reports unavailability rather than returning invented
///   geometry.
///
/// This split is the honest engineering position for a prototype. Guided
/// alignment is a real, defensible measurement protocol - it is how reference
/// targets are used in practice - and it avoids claiming a detector that has
/// not been built and tested.
library;

import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../models/reference_card.dart';
import '../models/test_region.dart';
import 'calibration.dart';
import 'colour_space.dart';
import 'linear_algebra.dart';

class CardDetection {
  const CardDetection({
    required this.detected,
    required this.observations,
    required this.cardBox,
    required this.coverageFraction,
    required this.patchUniformity,
    required this.detectorVersion,
    this.failureReason,
  });

  factory CardDetection.failed(String reason, String detectorVersion) =>
      CardDetection(
        detected: false,
        observations: const <PatchObservation>[],
        cardBox: null,
        coverageFraction: 0,
        patchUniformity: double.nan,
        detectorVersion: detectorVersion,
        failureReason: reason,
      );

  final bool detected;
  final List<PatchObservation> observations;
  final RegionBox? cardBox;

  /// Fraction of the frame occupied by the card.
  final double coverageFraction;

  /// Mean within-patch standard deviation across channels. High values mean a
  /// patch straddled an edge, a shadow, or a glare spot.
  final double patchUniformity;

  final String detectorVersion;
  final String? failureReason;
}

abstract class ReferenceCardDetector {
  String get version;

  /// Locates the card and samples its patches.
  ///
  /// [guideBox] is the on-screen alignment rectangle in image coordinates, or
  /// null when the detector does not use operator guidance.
  CardDetection detect(
    img.Image image,
    ReferenceCardSpec spec, {
    RegionBox? guideBox,
  });
}

class GuidedFrameCardDetector implements ReferenceCardDetector {
  const GuidedFrameCardDetector();

  @override
  String get version => 'guided-card-detector-0.1.0';

  /// Maximum acceptable mean within-patch standard deviation (0-255 scale).
  /// Above this the sample is not a flat printed patch.
  static const double maxPatchStdDev = 22.0;

  /// Minimum Pearson correlation between expected and observed patch
  /// luminance ordering. A correctly aligned card preserves the ordering even
  /// under a strong colour cast; a misaligned one does not.
  static const double minOrderingCorrelation = 0.80;

  /// Patches are sampled from an inset of their nominal area so that a small
  /// alignment error does not pull in the printed border between patches.
  static const double _patchInset = 0.20;

  /// Fractional tolerance on the guide rectangle's aspect ratio against the
  /// card specification. A guide whose shape does not match the card means the
  /// relative patch geometry maps onto the wrong pixels, so the sampled
  /// colours would be wrong while looking perfectly plausible.
  static const double _aspectTolerance = 0.25;

  @override
  CardDetection detect(
    img.Image image,
    ReferenceCardSpec spec, {
    RegionBox? guideBox,
  }) {
    if (guideBox == null) {
      return CardDetection.failed(
        'No alignment guide supplied; the guided detector requires the '
        'operator to align the card within the on-screen guide.',
        version,
      );
    }
    if (guideBox.width < 40 || guideBox.height < 40) {
      return CardDetection.failed(
        'Reference card area is too small in frame. Move closer.',
        version,
      );
    }

    final double guideAspect = guideBox.width / guideBox.height;
    final double aspectError =
        (guideAspect - spec.aspectRatio).abs() / spec.aspectRatio;
    if (aspectError > _aspectTolerance) {
      // This is a configuration fault, not an operator fault: the capture
      // layout does not match the shape of the card this profile declares.
      return CardDetection.failed(
        'Capture layout does not match reference card ${spec.cardId}: the '
        'alignment guide is ${guideAspect.toStringAsFixed(2)}:1 but the card '
        'is ${spec.aspectRatio.toStringAsFixed(2)}:1. Patch positions would '
        'not line up, so no calibration was attempted.',
        version,
      );
    }

    final List<PatchObservation> observations = <PatchObservation>[];
    final List<double> uniformities = <double>[];
    final List<double> expectedLuma = <double>[];
    final List<double> observedLuma = <double>[];

    for (final ReferencePatch patch in spec.patches) {
      final RegionBox box = _patchBoxInImage(guideBox, patch);
      if (box.width < 3 || box.height < 3) {
        return CardDetection.failed(
          'Reference patch "${patch.id}" resolves to fewer than 3 pixels. '
          'Move closer to the card.',
          version,
        );
      }
      if (box.left < 0 ||
          box.top < 0 ||
          box.right > image.width ||
          box.bottom > image.height) {
        return CardDetection.failed(
          'Reference card extends outside the frame. Reposition the card.',
          version,
        );
      }

      final _PatchStats stats = _samplePatch(image, box);
      observations.add(
        PatchObservation(
          patchId: patch.id,
          expected: patch.expectedSrgb,
          observed: stats.mean,
        ),
      );
      uniformities.add(stats.meanStdDev);
      expectedLuma.add(_luma(patch.expectedSrgb));
      observedLuma.add(_luma(stats.mean));
    }

    if (observations.isEmpty) {
      return CardDetection.failed(
        'Reference card specification defines no patches.',
        version,
      );
    }

    final double meanUniformity = LinearAlgebra.mean(uniformities);
    if (meanUniformity > maxPatchStdDev) {
      return CardDetection.failed(
        'Reference card patches are not uniform (mean std dev '
        '${meanUniformity.toStringAsFixed(1)}). The card may be misaligned, '
        'partially blocked, or affected by glare or shadow.',
        version,
      );
    }

    final double correlation = _pearson(expectedLuma, observedLuma);
    if (correlation.isNaN || correlation < minOrderingCorrelation) {
      return CardDetection.failed(
        'Sampled patches do not match the expected reference-card layout '
        '(ordering correlation ${correlation.isNaN ? "undefined" : correlation.toStringAsFixed(2)}). '
        'Check that the correct card is aligned inside the guide.',
        version,
      );
    }

    final double coverage = image.width * image.height == 0
        ? 0
        : guideBox.area / (image.width * image.height);

    return CardDetection(
      detected: true,
      observations: observations,
      cardBox: guideBox,
      coverageFraction: coverage,
      patchUniformity: meanUniformity,
      detectorVersion: version,
    );
  }

  static RegionBox _patchBoxInImage(RegionBox card, ReferencePatch patch) {
    final double insetW = patch.relativeWidth * _patchInset;
    final double insetH = patch.relativeHeight * _patchInset;

    final double x = patch.relativeX + insetW;
    final double y = patch.relativeY + insetH;
    final double w = patch.relativeWidth - 2 * insetW;
    final double h = patch.relativeHeight - 2 * insetH;

    return RegionBox(
      left: (card.left + x * card.width).round(),
      top: (card.top + y * card.height).round(),
      width: math.max(1, (w * card.width).round()),
      height: math.max(1, (h * card.height).round()),
    );
  }

  static _PatchStats _samplePatch(img.Image image, RegionBox box) {
    final List<double> rs = <double>[];
    final List<double> gs = <double>[];
    final List<double> bs = <double>[];

    for (int y = box.top; y < box.bottom; y++) {
      for (int x = box.left; x < box.right; x++) {
        final img.Pixel p = image.getPixel(x, y);
        rs.add(p.r.toDouble());
        gs.add(p.g.toDouble());
        bs.add(p.b.toDouble());
      }
    }

    // Mean in LINEAR light, then re-encode. Averaging gamma-encoded values
    // biases the result dark; this matters because the whole point of the
    // patch is to be a photometric reference.
    final Rgb mean = Rgb(
      ColourSpace.linearToSrgb(
        LinearAlgebra.mean(rs.map(ColourSpace.srgbToLinear).toList()),
      ),
      ColourSpace.linearToSrgb(
        LinearAlgebra.mean(gs.map(ColourSpace.srgbToLinear).toList()),
      ),
      ColourSpace.linearToSrgb(
        LinearAlgebra.mean(bs.map(ColourSpace.srgbToLinear).toList()),
      ),
    );

    final double stdDev = (LinearAlgebra.stdDev(rs) +
            LinearAlgebra.stdDev(gs) +
            LinearAlgebra.stdDev(bs)) /
        3.0;

    return _PatchStats(mean: mean, meanStdDev: stdDev);
  }

  static double _luma(Rgb c) => 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;

  static double _pearson(List<double> a, List<double> b) {
    if (a.length != b.length || a.length < 2) return double.nan;
    final double ma = LinearAlgebra.mean(a);
    final double mb = LinearAlgebra.mean(b);
    double num = 0;
    double da = 0;
    double db = 0;
    for (int i = 0; i < a.length; i++) {
      final double x = a[i] - ma;
      final double y = b[i] - mb;
      num += x * y;
      da += x * x;
      db += y * y;
    }
    if (da == 0 || db == 0) return double.nan;
    return num / math.sqrt(da * db);
  }
}

class _PatchStats {
  const _PatchStats({required this.mean, required this.meanStdDev});
  final Rgb mean;
  final double meanStdDev;
}

/// Integration point for fully automatic card detection.
///
/// Not implemented. It reports unavailability rather than returning a guessed
/// quadrilateral, because a wrong card location produces a plausible-looking
/// but wrong calibration - the most dangerous failure mode in this system.
class HomographyCardDetector implements ReferenceCardDetector {
  const HomographyCardDetector();

  @override
  String get version => 'homography-card-detector-unimplemented';

  @override
  CardDetection detect(
    img.Image image,
    ReferenceCardSpec spec, {
    RegionBox? guideBox,
  }) =>
      CardDetection.failed(
        'Automatic homography-based card detection is not implemented in this '
        'build. Use guided alignment capture.',
        version,
      );
}
