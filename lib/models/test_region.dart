/// The analysed reaction region within a capture (master spec section 15).
library;

import 'enums.dart';

/// Axis-aligned bounding box in absolute image pixels.
class RegionBox {
  const RegionBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  factory RegionBox.fromJson(Map<String, Object?> json) => RegionBox(
        left: (json['left']! as num).toInt(),
        top: (json['top']! as num).toInt(),
        width: (json['width']! as num).toInt(),
        height: (json['height']! as num).toInt(),
      );

  final int left;
  final int top;
  final int width;
  final int height;

  int get right => left + width;
  int get bottom => top + height;
  int get area => width * height;

  Map<String, Object?> toJson() => <String, Object?>{
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };
}

class TestRegion {
  const TestRegion({
    required this.box,
    required this.confidence,
    required this.selectionMode,
    required this.detectorVersion,
  });

  final RegionBox box;

  /// Detector confidence in [0, 1]. For a manually drawn region this is 1.0
  /// by definition of operator intent, and [selectionMode] records that so the
  /// two are never confused.
  final double confidence;

  final RegionSelectionMode selectionMode;
  final String detectorVersion;

  Map<String, Object?> toJson() => <String, Object?>{
        'box': box.toJson(),
        'confidence': confidence,
        'selectionMode': selectionMode.wireName,
        'detectorVersion': detectorVersion,
      };
}
