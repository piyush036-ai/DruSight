/// Camera overlay showing the reference-card and test-region guides
/// (master spec section 14).
///
/// The guides are not decoration: their rectangles, in image coordinates, are
/// exactly what the guided card and region detectors sample. What the operator
/// sees is what gets measured.
library;

import 'package:flutter/material.dart';

import '../models/test_region.dart';

/// Whether calibration uses the screen's built-in digital card bar or a
/// physical printed reference card placed inside the camera frame.
enum ReferenceCardMode {
  /// The built-in digital colour bar is shown at the bottom of the UI.
  /// No physical card is needed; the operator only frames the test region.
  builtin,

  /// A physical printed reference card must be placed flat beside the sample
  /// inside the on-screen card guide. The digital bar is hidden.
  physical,
}

class CaptureGuideGeometry {
  const CaptureGuideGeometry({
    required this.regionGuide,
    this.physicalCardGuide,
  });

  /// Guide as a fraction of the preview area, so it maps cleanly onto the
  /// captured image regardless of preview resolution.
  final Rect regionGuide;

  /// Guide rectangle for a physical reference card. Only shown when
  /// [ReferenceCardMode.physical] is selected. Positioned in the lower portion
  /// of the frame so both the test region and the card fit comfortably.
  final Rect? physicalCardGuide;

  /// Layout when using the built-in digital card: reaction area centred in the
  /// upper portion of the frame; no physical card guide is needed.
  static const CaptureGuideGeometry standard = CaptureGuideGeometry(
    regionGuide: Rect.fromLTWH(0.25, 0.10, 0.50, 0.40),
  );

  /// Layout when a physical card is in-frame: test region in the upper half,
  /// physical card guide in the lower-left quarter.
  static const CaptureGuideGeometry withPhysicalCard = CaptureGuideGeometry(
    regionGuide: Rect.fromLTWH(0.25, 0.05, 0.50, 0.38),
    physicalCardGuide: Rect.fromLTWH(0.05, 0.55, 0.90, 0.30),
  );

  RegionBox toImageBox(Rect fraction, int imageWidth, int imageHeight) =>
      RegionBox(
        left: (fraction.left * imageWidth).round(),
        top: (fraction.top * imageHeight).round(),
        width: (fraction.width * imageWidth).round(),
        height: (fraction.height * imageHeight).round(),
      );

  RegionBox regionBoxIn(int width, int height) =>
      toImageBox(regionGuide, width, height);
}

class CaptureOverlay extends StatelessWidget {
  const CaptureOverlay({
    required this.geometry,
    required this.regionOk,
    this.cardMode = ReferenceCardMode.builtin,
    super.key,
  });

  final CaptureGuideGeometry geometry;
  final bool regionOk;

  /// When [ReferenceCardMode.physical], a second labelled guide box is drawn
  /// for the physical card placement area.
  final ReferenceCardMode cardMode;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _OverlayPainter(
          geometry: geometry,
          regionOk: regionOk,
          cardMode: cardMode,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.geometry,
    required this.regionOk,
    required this.cardMode,
  });

  final CaptureGuideGeometry geometry;
  final bool regionOk;
  final ReferenceCardMode cardMode;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGuide(
      canvas,
      _scale(geometry.regionGuide, size),
      regionOk,
      'TEST REGION',
    );

    // Physical card guide — amber colour so it is visually distinct from the
    // green/white test-region guide.
    if (cardMode == ReferenceCardMode.physical &&
        geometry.physicalCardGuide != null) {
      _drawGuide(
        canvas,
        _scale(geometry.physicalCardGuide!, size),
        false,
        'REFERENCE CARD',
        colour: const Color(0xFFFFC107),
      );
    }
  }

  static Rect _scale(Rect fraction, Size size) => Rect.fromLTWH(
        fraction.left * size.width,
        fraction.top * size.height,
        fraction.width * size.width,
        fraction.height * size.height,
      );

  void _drawGuide(
    Canvas canvas,
    Rect rect,
    bool ok,
    String label, {
    Color? colour,
  }) {
    final Color c = colour ?? (ok ? const Color(0xFF2ECC71) : const Color(0xFFFFFFFF));

    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ok ? 3.5 : 2.5
      ..color = c;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      stroke,
    );

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: c,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          shadows: const <Shadow>[
            Shadow(blurRadius: 3, color: Colors.black54),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(rect.left, rect.top - 18));
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.regionOk != regionOk || old.cardMode != cardMode;
}
