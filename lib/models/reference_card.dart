/// Reference colour-card specification (master spec section 11).
///
/// The card is the measurement reference: its patches have known sRGB values,
/// and the difference between those and what the camera records is what the
/// calibration solver inverts. A card spec is part of a versioned kit profile,
/// because a different printed card is a different instrument.
library;

import '../cv/colour_space.dart';

/// One printed patch of known colour.
class ReferencePatch {
  const ReferencePatch({
    required this.id,
    required this.expectedSrgb,
    required this.relativeX,
    required this.relativeY,
    required this.relativeWidth,
    required this.relativeHeight,
  });

  factory ReferencePatch.fromJson(Map<String, Object?> json) {
    final List<Object?> rgb = (json['expectedSrgb']! as List<Object?>);
    return ReferencePatch(
      id: json['id']! as String,
      expectedSrgb: Rgb(
        (rgb[0]! as num).toDouble(),
        (rgb[1]! as num).toDouble(),
        (rgb[2]! as num).toDouble(),
      ),
      relativeX: (json['x']! as num).toDouble(),
      relativeY: (json['y']! as num).toDouble(),
      relativeWidth: (json['w']! as num).toDouble(),
      relativeHeight: (json['h']! as num).toDouble(),
    );
  }

  final String id;
  final Rgb expectedSrgb;

  /// Patch geometry as fractions of the card's own bounding box, so the spec
  /// is independent of how large the card appears in frame.
  final double relativeX;
  final double relativeY;
  final double relativeWidth;
  final double relativeHeight;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'expectedSrgb': <double>[
          expectedSrgb.r,
          expectedSrgb.g,
          expectedSrgb.b,
        ],
        'x': relativeX,
        'y': relativeY,
        'w': relativeWidth,
        'h': relativeHeight,
      };
}

class ReferenceCardSpec {
  const ReferenceCardSpec({
    required this.cardId,
    required this.version,
    required this.description,
    required this.patches,
    required this.aspectRatio,
    this.printNotes,
  });

  factory ReferenceCardSpec.fromJson(Map<String, Object?> json) =>
      ReferenceCardSpec(
        cardId: json['cardId']! as String,
        version: json['version']! as String,
        description: json['description'] as String? ?? '',
        aspectRatio: (json['aspectRatio']! as num).toDouble(),
        printNotes: json['printNotes'] as String?,
        patches: (json['patches']! as List<Object?>)
            .map((Object? p) =>
                ReferencePatch.fromJson(p! as Map<String, Object?>))
            .toList(growable: false),
      );

  final String cardId;
  final String version;
  final String description;
  final List<ReferencePatch> patches;

  /// Width / height of the printed card, used to reject a detected quad whose
  /// shape is wrong for this card.
  final double aspectRatio;

  /// How the card must be produced for measurements to be meaningful.
  final String? printNotes;

  Map<String, Object?> toJson() => <String, Object?>{
        'cardId': cardId,
        'version': version,
        'description': description,
        'aspectRatio': aspectRatio,
        'printNotes': printNotes,
        'patches': patches.map((ReferencePatch p) => p.toJson()).toList(),
      };
}
