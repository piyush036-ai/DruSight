/// Smart Capture Guard (master spec sections 13, 14).
///
/// Evaluates a frame against the kit profile's thresholds and produces ordered,
/// actionable instructions. Ordering matters: showing five warnings at once is
/// useless in the field, so hints are sorted by how much they block progress
/// and the UI shows the first one.
library;

import 'package:image/image.dart' as img;

import '../cv/quality/blur_metric.dart';
import '../cv/quality/exposure_metric.dart';
import '../cv/quality/glare_metric.dart';
import '../cv/region_detector.dart';
import '../models/capture_quality.dart';
import '../models/kit_profile.dart';

class CaptureGuard {
  const CaptureGuard();

  /// Evaluates a frame. [regionDetection] may be null during live preview
  /// when the operator has not yet aligned the guide.
  CaptureQuality evaluate(
    img.Image image, {
    required KitProfile profile,
    RegionDetection? regionDetection,
  }) {
    final QualityThresholds t = profile.qualityThresholds;
    final List<_RankedHint> hints = <_RankedHint>[];

    // --- Resolution ---------------------------------------------------------
    if (image.width < t.minImageWidthPx) {
      hints.add(
        _RankedHint(
          0,
          CaptureHint(
            'Image resolution is too low (${image.width}px wide, '
            '${t.minImageWidthPx}px required).',
          ),
        ),
      );
    }

    // --- Exposure -----------------------------------------------------------
    final ExposureReport exposure = ExposureMetric.evaluate(image);
    if (exposure.meanLuminance < t.minMeanLuminance) {
      hints.add(const _RankedHint(1, CaptureHint('Image too dark. Add light.')));
    } else if (exposure.meanLuminance > t.maxMeanLuminance) {
      hints.add(
        const _RankedHint(1, CaptureHint('Image too bright. Reduce light.')),
      );
    }
    if (exposure.shadowClippedFraction > t.maxShadowClippedFraction) {
      hints.add(
        const _RankedHint(
          2,
          CaptureHint('Excessive shadow. Move out of direct shadow.'),
        ),
      );
    }
    if (exposure.highlightClippedFraction > t.maxHighlightClippedFraction) {
      hints.add(
        const _RankedHint(
          2,
          CaptureHint(
            'Overexposed. Move away from the direct light source.',
          ),
        ),
      );
    }
    if (exposure.dynamicRange < t.minDynamicRange) {
      hints.add(
        const _RankedHint(
          5,
          CaptureHint(
            'Lighting is too flat for reliable colour measurement.',
            blocking: false,
          ),
        ),
      );
    }

    // --- Glare --------------------------------------------------------------
    final GlareReport glare = GlareMetric.evaluate(image);
    if (glare.glareFraction > t.maxGlareFraction) {
      hints.add(
        const _RankedHint(
          2,
          CaptureHint('Too much glare. Change angle or move the light.'),
        ),
      );
    }

    // --- Focus --------------------------------------------------------------
    final double blur = BlurMetric.varianceOfLaplacian(image);
    if (blur < t.minBlurVariance) {
      hints.add(
        const _RankedHint(
          1,
          CaptureHint('Image is not sharp. Hold the phone steady.'),
        ),
      );
    }

    // --- Test region --------------------------------------------------------
    final bool regionOk = regionDetection?.detected ?? false;
    if (!regionOk) {
      hints.add(
        _RankedHint(
          0,
          CaptureHint(
            regionDetection?.failureReason ??
                'Test region not detected. Place the region guide over the '
                'reaction area.',
          ),
        ),
      );
    } else if (regionDetection!.region!.confidence < t.minRegionConfidence) {
      hints.add(
        _RankedHint(
          3,
          CaptureHint(
            'Test region quality is low '
            '(${regionDetection.region!.confidence.toStringAsFixed(2)}). '
            'Reposition so the reaction area fills the guide evenly.',
          ),
        ),
      );
    }

    hints.sort((_RankedHint a, _RankedHint b) => a.rank.compareTo(b.rank));
    final List<CaptureHint> ordered =
        hints.map((_RankedHint h) => h.hint).toList(growable: false);
    final bool acceptable =
        !ordered.any((CaptureHint h) => h.blocking);

    return CaptureQuality(
      blurVariance: blur,
      exposure: exposure,
      glare: glare,
      imageWidthPx: image.width,
      imageHeightPx: image.height,
      referenceCardDetected: true, // always true — digital screen card
      cardCoverageFraction: 1.0,
      testRegionDetected: regionOk,
      regionConfidence: regionDetection?.region?.confidence ?? 0,
      hints: acceptable
          ? <CaptureHint>[
              const CaptureHint('Capture accepted.', blocking: false),
              ...ordered,
            ]
          : ordered,
      acceptable: acceptable,
    );
  }
}

class _RankedHint {
  const _RankedHint(this.rank, this.hint);
  final int rank;
  final CaptureHint hint;
}
