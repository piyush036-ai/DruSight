/// Built-in digital reference card bar (master spec extension: screen card).
///
/// Renders the reference card's colour patches as a horizontal strip at the
/// bottom of the capture screen. The patches display the known sRGB values
/// from the kit profile — these are the exact values used by [ScreenCardCalibrator]
/// to perform automatic calibration. No printing, no physical card needed.
///
/// The bar is purely informational: calibration does not require the camera to
/// photograph these patches. They are shown so:
///   1. The operator can confirm the expected colours for their kit.
///   2. A supervisor reviewing footage can see the reference values.
///   3. The UI communicates that calibration is active and standardised.
library;

import 'package:flutter/material.dart';

import '../models/reference_card.dart';

class DigitalCardBar extends StatelessWidget {
  const DigitalCardBar({required this.spec, super.key});

  final ReferenceCardSpec spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111111),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.palette_outlined,
                color: Color(0xFF4CAF50),
                size: 13,
              ),
              const SizedBox(width: 5),
              const Text(
                'BUILT-IN REFERENCE CARD',
                style: TextStyle(
                  color: Color(0xFF4CAF50),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                spec.cardId,
                style: const TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 9,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: Row(
              children: spec.patches.map((ReferencePatch patch) {
                final Color patchColor = Color.fromARGB(
                  255,
                  patch.expectedSrgb.r.round().clamp(0, 255),
                  patch.expectedSrgb.g.round().clamp(0, 255),
                  patch.expectedSrgb.b.round().clamp(0, 255),
                );
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: patchColor,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: Colors.white12,
                        width: 0.5,
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Calibration active — no physical card required',
            style: TextStyle(
              color: Color(0xFF555555),
              fontSize: 9,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
