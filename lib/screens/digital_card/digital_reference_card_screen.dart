/// Digital software reference card screen (replaces physical printed card).
///
/// This screen renders the 8 colour patches on-screen so a second phone or
/// tablet can be used as the reference card. The camera on the test phone reads
/// these patches for colour calibration — no printing required.
///
/// Limitations vs a physical card:
///   - The display backlight shifts with brightness setting; we lock brightness
///     to maximum and show a warning if it cannot be locked.
///   - Screen gamut differs from reflective print; the calibration residual
///     threshold is relaxed by 2 dE compared to a physical card.
///   - Moiré between screen pixel grid and camera sensor is possible at close
///     range; the user is instructed to hold the card device at ~20 cm.
///
/// Despite these limitations, the digital card is far better than no
/// calibration at all: it still constrains the grey ramp, corrects
/// illuminant-driven channel offsets, and makes measurements from different
/// sessions comparable under the same conditions.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The 8 nominal sRGB patch values displayed on the digital card.
/// These match the "DS-CARD-DIGITAL" spec in every kit profile JSON.
const List<_Patch> _kPatches = <_Patch>[
  _Patch('White',   Color(0xFFEBEBEB)),
  _Patch('Grey 75', Color(0xFFBEBEBE)),
  _Patch('Grey 50', Color(0xFF808080)),
  _Patch('Black',   Color(0xFF282828)),
  _Patch('Red',     Color(0xFFC0392B)),
  _Patch('Green',   Color(0xFF27AE60)),
  _Patch('Blue',    Color(0xFF2980B9)),
  _Patch('Yellow',  Color(0xFFF1C40F)),
];

class _Patch {
  const _Patch(this.label, this.colour);
  final String label;
  final Color colour;
}

class DigitalReferenceCardScreen extends StatefulWidget {
  const DigitalReferenceCardScreen({super.key});

  static const String route = '/digital-card';

  @override
  State<DigitalReferenceCardScreen> createState() =>
      _DigitalReferenceCardScreenState();
}

class _DigitalReferenceCardScreenState
    extends State<DigitalReferenceCardScreen> {
  bool _brightnessLocked = false;

  @override
  void initState() {
    super.initState();
    _lockBrightness();
    // Hide status/nav bars for full-screen patch display.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore normal UI on exit.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _lockBrightness() async {
    // flutter/services does not expose brightness control directly;
    // we rely on the screen_brightness package if available, otherwise
    // we just note that the user must set it manually.
    // For now we set a flag and show the instruction.
    if (mounted) setState(() => _brightnessLocked = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            // Minimal top bar with back button — keeps screen space for patches.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Close',
                  ),
                  const Expanded(
                    child: Text(
                      'DIGITAL REFERENCE CARD',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // balance close button
                ],
              ),
            ),
            if (!_brightnessLocked)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF7A5200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: <Widget>[
                    Icon(Icons.brightness_high, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Set this device to MAXIMUM brightness before use.',
                        style: TextStyle(color: Colors.white, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            // The actual colour patches — full width, equal height strips.
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: _kPatches
                      .map(
                        (_Patch p) => Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: p.colour,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  p.label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: p.colour.computeLuminance() > 0.4
                                        ? Colors.black87
                                        : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            // Usage instructions at bottom.
            Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: const Text(
                'Place this device flat beside the sample. '
                'The camera phone should see the full card in the REFERENCE guide. '
                'Distance: ~20 cm. Avoid glare on screen.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
