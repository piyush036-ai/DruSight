/// Versioned test-kit profile (master spec sections 10 and 62).
///
/// Every threshold that can change a result lives here, in a versioned asset,
/// not scattered through code. The profile version is recorded in the evidence
/// record, so an old record always states the rules it was judged under.
library;

import 'reference_card.dart';

/// Capture-quality gates for one kit. Absolute values are kit- and
/// card-specific; there is no universal "good enough" threshold.
class QualityThresholds {
  const QualityThresholds({
    required this.minBlurVariance,
    required this.maxGlareFraction,
    required this.maxShadowClippedFraction,
    required this.maxHighlightClippedFraction,
    required this.minMeanLuminance,
    required this.maxMeanLuminance,
    required this.minDynamicRange,
    required this.maxCalibrationResidualDeltaE,
    required this.minRegionConfidence,
    required this.minImageWidthPx,
    required this.minCardCoverageFraction,
  });

  factory QualityThresholds.fromJson(Map<String, Object?> json) =>
      QualityThresholds(
        minBlurVariance: (json['minBlurVariance']! as num).toDouble(),
        maxGlareFraction: (json['maxGlareFraction']! as num).toDouble(),
        maxShadowClippedFraction:
            (json['maxShadowClippedFraction']! as num).toDouble(),
        maxHighlightClippedFraction:
            (json['maxHighlightClippedFraction']! as num).toDouble(),
        minMeanLuminance: (json['minMeanLuminance']! as num).toDouble(),
        maxMeanLuminance: (json['maxMeanLuminance']! as num).toDouble(),
        minDynamicRange: (json['minDynamicRange']! as num).toDouble(),
        maxCalibrationResidualDeltaE:
            (json['maxCalibrationResidualDeltaE']! as num).toDouble(),
        minRegionConfidence: (json['minRegionConfidence']! as num).toDouble(),
        minImageWidthPx: (json['minImageWidthPx']! as num).toInt(),
        minCardCoverageFraction:
            (json['minCardCoverageFraction']! as num).toDouble(),
      );

  final double minBlurVariance;
  final double maxGlareFraction;
  final double maxShadowClippedFraction;
  final double maxHighlightClippedFraction;
  final double minMeanLuminance;
  final double maxMeanLuminance;
  final double minDynamicRange;
  final double maxCalibrationResidualDeltaE;
  final double minRegionConfidence;
  final int minImageWidthPx;

  /// Minimum fraction of the frame the reference card must occupy. Too small
  /// and its patches are averaged over too few pixels to be a useful
  /// reference.
  final double minCardCoverageFraction;

  Map<String, Object?> toJson() => <String, Object?>{
        'minBlurVariance': minBlurVariance,
        'maxGlareFraction': maxGlareFraction,
        'maxShadowClippedFraction': maxShadowClippedFraction,
        'maxHighlightClippedFraction': maxHighlightClippedFraction,
        'minMeanLuminance': minMeanLuminance,
        'maxMeanLuminance': maxMeanLuminance,
        'minDynamicRange': minDynamicRange,
        'maxCalibrationResidualDeltaE': maxCalibrationResidualDeltaE,
        'minRegionConfidence': minRegionConfidence,
        'minImageWidthPx': minImageWidthPx,
        'minCardCoverageFraction': minCardCoverageFraction,
      };
}

/// Timed capture schedule for kits whose reaction evolves (master spec 17).
class ReactionWindow {
  const ReactionWindow({
    required this.enabled,
    required this.captureOffsetsSeconds,
    required this.stabilityDeltaE,
    required this.observationNotes,
  });

  factory ReactionWindow.fromJson(Map<String, Object?> json) => ReactionWindow(
        enabled: json['enabled']! as bool,
        captureOffsetsSeconds: (json['captureOffsetsSeconds']! as List<Object?>)
            .map((Object? v) => (v! as num).toInt())
            .toList(growable: false),
        stabilityDeltaE: (json['stabilityDeltaE']! as num).toDouble(),
        observationNotes: json['observationNotes'] as String? ?? '',
      );

  final bool enabled;

  /// Offsets from reagent contact, in seconds. Kit-specific: never hard-coded
  /// globally.
  final List<int> captureOffsetsSeconds;

  /// CIEDE2000 change between consecutive frames below which the reaction is
  /// considered to have stabilised.
  final double stabilityDeltaE;

  final String observationNotes;

  Map<String, Object?> toJson() => <String, Object?>{
        'enabled': enabled,
        'captureOffsetsSeconds': captureOffsetsSeconds,
        'stabilityDeltaE': stabilityDeltaE,
        'observationNotes': observationNotes,
      };
}

/// A configured colour region in Lab used by the deterministic interpretation
/// rules. Membership is decided by CIEDE2000 distance to [centreLab].
class ColourDecisionRegion {
  const ColourDecisionRegion({
    required this.label,
    required this.centreLab,
    required this.radiusDeltaE,
    required this.borderlineMarginDeltaE,
  });

  factory ColourDecisionRegion.fromJson(Map<String, Object?> json) {
    final List<Object?> lab = json['centreLab']! as List<Object?>;
    return ColourDecisionRegion(
      label: json['label']! as String,
      centreLab: <double>[
        (lab[0]! as num).toDouble(),
        (lab[1]! as num).toDouble(),
        (lab[2]! as num).toDouble(),
      ],
      radiusDeltaE: (json['radiusDeltaE']! as num).toDouble(),
      borderlineMarginDeltaE:
          (json['borderlineMarginDeltaE']! as num).toDouble(),
    );
  }

  /// One of the TestResult wire names.
  final String label;
  final List<double> centreLab;
  final double radiusDeltaE;

  /// Width of the band around the boundary within which a sample is treated as
  /// borderline and escalated rather than classified (master spec section 25).
  final double borderlineMarginDeltaE;

  Map<String, Object?> toJson() => <String, Object?>{
        'label': label,
        'centreLab': centreLab,
        'radiusDeltaE': radiusDeltaE,
        'borderlineMarginDeltaE': borderlineMarginDeltaE,
      };
}

class KitProfile {
  const KitProfile({
    required this.kitId,
    required this.profileVersion,
    required this.manufacturer,
    required this.testName,
    required this.reagentType,
    required this.referenceCard,
    required this.qualityThresholds,
    required this.reactionWindow,
    required this.decisionRegions,
    required this.modelId,
    required this.modelVersion,
    required this.featureSchemaVersion,
    required this.calibrationVersion,
    required this.captureInstructions,
    required this.safetyNotes,
    required this.documentationUrl,
    required this.lastVerifiedDate,
    required this.validationStatus,
  });

  factory KitProfile.fromJson(Map<String, Object?> json) => KitProfile(
        kitId: json['kitId']! as String,
        profileVersion: json['profileVersion']! as String,
        manufacturer: json['manufacturer']! as String,
        testName: json['testName']! as String,
        reagentType: json['reagentType']! as String,
        referenceCard: ReferenceCardSpec.fromJson(
            json['referenceCard']! as Map<String, Object?>),
        qualityThresholds: QualityThresholds.fromJson(
            json['qualityThresholds']! as Map<String, Object?>),
        reactionWindow: ReactionWindow.fromJson(
            json['reactionWindow']! as Map<String, Object?>),
        decisionRegions: (json['decisionRegions']! as List<Object?>)
            .map((Object? r) =>
                ColourDecisionRegion.fromJson(r! as Map<String, Object?>))
            .toList(growable: false),
        modelId: json['modelId'] as String?,
        modelVersion: json['modelVersion'] as String?,
        featureSchemaVersion: json['featureSchemaVersion']! as String,
        calibrationVersion: json['calibrationVersion']! as String,
        captureInstructions: (json['captureInstructions']! as List<Object?>)
            .map((Object? s) => s! as String)
            .toList(growable: false),
        safetyNotes: (json['safetyNotes']! as List<Object?>)
            .map((Object? s) => s! as String)
            .toList(growable: false),
        documentationUrl: json['documentationUrl'] as String?,
        lastVerifiedDate: json['lastVerifiedDate'] as String?,
        validationStatus: json['validationStatus']! as String,
      );

  final String kitId;
  final String profileVersion;
  final String manufacturer;
  final String testName;
  final String reagentType;
  final ReferenceCardSpec referenceCard;
  final QualityThresholds qualityThresholds;
  final ReactionWindow reactionWindow;
  final List<ColourDecisionRegion> decisionRegions;

  /// Null until a model has actually been trained and exported for this kit.
  /// A null model is not an error: the deterministic colour rules still run,
  /// and the absence is surfaced rather than papered over.
  final String? modelId;
  final String? modelVersion;

  final String featureSchemaVersion;
  final String calibrationVersion;
  final List<String> captureInstructions;
  final List<String> safetyNotes;
  final String? documentationUrl;
  final String? lastVerifiedDate;

  /// Free-text provenance of this profile's thresholds, e.g.
  /// "UNVALIDATED - illustrative values for prototype demonstration".
  /// Displayed verbatim in the UI so nobody mistakes a placeholder for
  /// validated science (master spec section 55).
  final String validationStatus;

  bool get hasTrainedModel => modelId != null && modelVersion != null;

  Map<String, Object?> toJson() => <String, Object?>{
        'kitId': kitId,
        'profileVersion': profileVersion,
        'manufacturer': manufacturer,
        'testName': testName,
        'reagentType': reagentType,
        'referenceCard': referenceCard.toJson(),
        'qualityThresholds': qualityThresholds.toJson(),
        'reactionWindow': reactionWindow.toJson(),
        'decisionRegions':
            decisionRegions.map((ColourDecisionRegion r) => r.toJson()).toList(),
        'modelId': modelId,
        'modelVersion': modelVersion,
        'featureSchemaVersion': featureSchemaVersion,
        'calibrationVersion': calibrationVersion,
        'captureInstructions': captureInstructions,
        'safetyNotes': safetyNotes,
        'documentationUrl': documentationUrl,
        'lastVerifiedDate': lastVerifiedDate,
        'validationStatus': validationStatus,
      };
}
