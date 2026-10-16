/// Tests for the colour-calibration solver.
///
/// Strategy: synthesise a known camera distortion, apply it to the reference
/// patches, then check the solver recovers a transform that undoes it -
/// including for colours that were not on the card. That is the property that
/// matters; the coefficient values themselves are not interesting.
///
/// Thresholds below were established by running the same arithmetic offline
/// before being written here, so they assert real behaviour rather than
/// aspirations. Where the solver cannot win - highlight clipping - the test
/// asserts the residual RISES, because that is what makes the calibration
/// gate work.
library;

import 'package:drusight/cv/calibration.dart';
import 'package:drusight/cv/colour_space.dart';
import 'package:flutter_test/flutter_test.dart';

/// Eight patches matching the DS-CARD-A specification.
const List<Rgb> _cardPatches = <Rgb>[
  Rgb(242, 242, 242),
  Rgb(178, 178, 178),
  Rgb(105, 105, 105),
  Rgb(38, 38, 38),
  Rgb(190, 45, 45),
  Rgb(50, 150, 75),
  Rgb(45, 75, 170),
  Rgb(225, 190, 55),
];

/// Applies a per-channel gain and offset in LINEAR light: a simple but
/// realistic stand-in for an unknown illuminant plus exposure error. Values
/// are clamped to [0, 1], exactly as a real sensor clips.
Rgb _distort(Rgb truth, List<double> gain, List<double> offset) {
  double channel(double v, int i) => ColourSpace.linearToSrgb(
        (ColourSpace.srgbToLinear(v) * gain[i] + offset[i]).clamp(0.0, 1.0),
      );
  return Rgb(channel(truth.r, 0), channel(truth.g, 1), channel(truth.b, 2));
}

List<PatchObservation> _observations(
  List<double> gain,
  List<double> offset,
) =>
    <PatchObservation>[
      for (int i = 0; i < _cardPatches.length; i++)
        PatchObservation(
          patchId: 'p$i',
          expected: _cardPatches[i],
          observed: _distort(_cardPatches[i], gain, offset),
        ),
    ];

double _dE(Rgb a, Rgb b) => ColourSpace.deltaE2000(
      ColourSpace.rgbToLab(a),
      ColourSpace.rgbToLab(b),
    );

void main() {
  const ColourCalibrator calibrator =
      ColourCalibrator(calibrationVersion: 'calib-test');

  group('fitting an affine distortion', () {
    test('recovers a per-channel gain almost exactly', () {
      // Gains below 1.0 so nothing clips: the distortion is then genuinely
      // affine in linear light, which is what the solver models.
      const List<double> gain = <double>[0.85, 1.0, 0.78];
      final CalibrationResult result =
          calibrator.fit(_observations(gain, <double>[0, 0, 0]));

      expect(result.succeeded, isTrue);
      expect(result.meanResidualDeltaE, lessThan(0.01));
      expect(result.maxResidualDeltaE, lessThan(0.01));

      for (final Rgb truth in _cardPatches) {
        final Rgb observed = _distort(truth, gain, <double>[0, 0, 0]);
        expect(_dE(result.apply(observed), truth), lessThan(0.01));
      }
    });

    test('recovers gain plus offset (veiling glare)', () {
      final CalibrationResult result = calibrator.fit(
        _observations(
          <double>[0.92, 0.95, 0.88],
          <double>[0.02, 0.01, 0.03],
        ),
      );
      expect(result.succeeded, isTrue);
      expect(result.meanResidualDeltaE, lessThan(0.01));
    });

    test('an undistorted card yields a near-identity correction', () {
      final CalibrationResult result =
          calibrator.fit(_observations(<double>[1, 1, 1], <double>[0, 0, 0]));

      expect(result.succeeded, isTrue);
      expect(result.meanResidualDeltaE, lessThan(0.01));
      expect(_dE(result.apply(const Rgb(120, 60, 200)),
          const Rgb(120, 60, 200)), lessThan(0.01));
    });

    test('correction generalises to a colour not on the card', () {
      // This is the whole point of calibration: correcting colours the solver
      // never saw. A fit that only reproduces its own training patches would
      // be useless for measuring a reaction.
      const List<double> gain = <double>[0.80, 0.97, 0.70];
      final CalibrationResult result =
          calibrator.fit(_observations(gain, <double>[0, 0, 0]));

      const Rgb unseenTruth = Rgb(130, 85, 160);
      final Rgb unseenObserved =
          _distort(unseenTruth, gain, <double>[0, 0, 0]);

      final double before = _dE(unseenObserved, unseenTruth);
      final double after = _dE(result.apply(unseenObserved), unseenTruth);

      expect(before, greaterThan(4.0),
          reason: 'the synthetic distortion should be substantial');
      expect(after, lessThan(0.05),
          reason: 'calibration should almost entirely remove it');
    });
  });

  group('honest failure', () {
    test('highlight clipping raises the residual monotonically', () {
      // Clipping is not an affine distortion, so no affine transform can undo
      // it: the information is gone. The correct behaviour is a rising
      // residual, which the kit profile's maxCalibrationResidualDeltaE then
      // rejects. A solver that reported a low residual here would be
      // producing a confident, wrong calibration - the worst failure mode in
      // this system.
      double residualFor(List<double> gain) =>
          calibrator.fit(_observations(gain, <double>[0, 0, 0]))
              .meanResidualDeltaE;

      final double none = residualFor(<double>[1.0, 1.0, 1.0]);
      final double slight = residualFor(<double>[1.15, 1.0, 1.0]);
      final double moderate = residualFor(<double>[1.25, 1.0, 0.78]);
      final double severe = residualFor(<double>[1.6, 1.0, 0.6]);

      expect(none, lessThan(0.01));
      expect(slight, greaterThan(none));
      expect(moderate, greaterThan(slight));
      expect(severe, greaterThan(moderate));

      // The demonstration kit profile's limit is 4.0, so moderate clipping
      // must land near enough to it to be caught in practice.
      expect(moderate, greaterThan(1.0));
    });

    test('a badly photographed card produces a large residual', () {
      final List<PatchObservation> noisy = <PatchObservation>[
        for (int i = 0; i < _cardPatches.length; i++)
          PatchObservation(
            patchId: 'p$i',
            expected: _cardPatches[i],
            observed: Rgb(
              (_cardPatches[i].r + (i.isEven ? 45 : -45)).clamp(0.0, 255.0),
              (_cardPatches[i].g + (i % 3 == 0 ? -40 : 35)).clamp(0.0, 255.0),
              (_cardPatches[i].b + (i % 4 == 0 ? 50 : -30)).clamp(0.0, 255.0),
            ),
          ),
      ];

      final CalibrationResult result = calibrator.fit(noisy);
      expect(result.succeeded, isTrue);
      // Comfortably above the demonstration profile's 4.0 limit.
      expect(result.meanResidualDeltaE, greaterThan(8.0));
    });

    test('refuses fewer patches than the solver needs', () {
      final CalibrationResult result = calibrator.fit(
        _observations(<double>[1, 1, 1], <double>[0, 0, 0]).take(3).toList(),
      );
      expect(result.succeeded, isFalse);
      expect(result.failureReason, contains('at least'));
    });

    test('refuses an empty patch list', () {
      expect(calibrator.fit(<PatchObservation>[]).succeeded, isFalse);
    });

    test('applying a failed calibration throws rather than guessing', () {
      final CalibrationResult failed =
          CalibrationResult.failed('no card', 'calib-test');
      expect(
        () => failed.apply(const Rgb(100, 100, 100)),
        throwsA(isA<StateError>()),
      );
    });
  });
}
