/// Aggregated capture-quality assessment produced by the Smart Capture Guard
/// (master spec section 13).
library;

import '../cv/quality/exposure_metric.dart';
import '../cv/quality/glare_metric.dart';

/// A single actionable instruction shown to the operator, e.g. "Move closer."
class CaptureHint {
  const CaptureHint(this.message, {this.blocking = true});

  final String message;

  /// Blocking hints prevent capture; non-blocking ones are advisory.
  final bool blocking;
}

class CaptureQuality {
  const CaptureQuality({
    required this.blurVariance,
    required this.exposure,
    required this.glare,
    required this.imageWidthPx,
    required this.imageHeightPx,
    required this.referenceCardDetected,
    required this.cardCoverageFraction,
    required this.testRegionDetected,
    required this.regionConfidence,
    required this.hints,
    required this.acceptable,
  });

  final double blurVariance;
  final ExposureReport exposure;
  final GlareReport glare;
  final int imageWidthPx;
  final int imageHeightPx;
  final bool referenceCardDetected;
  final double cardCoverageFraction;
  final bool testRegionDetected;
  final double regionConfidence;

  /// Ordered most-important-first so the UI can show a single clear
  /// instruction rather than a wall of warnings.
  final List<CaptureHint> hints;

  /// True only when no blocking hint remains.
  final bool acceptable;

  CaptureHint? get primaryHint => hints.isEmpty ? null : hints.first;

  Map<String, Object?> toJson() => <String, Object?>{
        'blurVariance': blurVariance,
        'exposure': exposure.toJson(),
        'glare': glare.toJson(),
        'imageWidthPx': imageWidthPx,
        'imageHeightPx': imageHeightPx,
        'referenceCardDetected': referenceCardDetected,
        'cardCoverageFraction': cardCoverageFraction,
        'testRegionDetected': testRegionDetected,
        'regionConfidence': regionConfidence,
        'acceptable': acceptable,
      };
}
