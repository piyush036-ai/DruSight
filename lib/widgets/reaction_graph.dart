/// Reaction trajectory plot (master spec section 17).
///
/// Plots L*, hue and saturation against capture offset. Three series rather
/// than a single "colour change" line, because which channel moved is the
/// diagnostically interesting part: a shift in L* alone usually means the
/// lighting changed, not the chemistry.
library;

import 'package:flutter/material.dart';

import '../models/reaction_series.dart';

class ReactionGraph extends StatelessWidget {
  const ReactionGraph({required this.trajectory, super.key});

  final ReactionTrajectory trajectory;

  @override
  Widget build(BuildContext context) {
    if (trajectory.samples.length < 2) {
      return const Text(
        'No timed sequence was captured for this kit profile.',
        style: TextStyle(fontSize: 14, color: Colors.black54),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 180,
          child: CustomPaint(
            painter: _TrajectoryPainter(trajectory),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 16,
          children: <Widget>[
            _LegendDot(Color(0xFF1B6CA8), 'Lightness L*'),
            _LegendDot(Color(0xFFB3261E), 'Hue'),
            _LegendDot(Color(0xFF1B7F4B), 'Saturation'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.colour, this.label);
  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(width: 10, height: 10, color: colour),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}

class _TrajectoryPainter extends CustomPainter {
  _TrajectoryPainter(this.trajectory);

  final ReactionTrajectory trajectory;

  @override
  void paint(Canvas canvas, Size size) {
    const double padLeft = 34;
    const double padBottom = 22;
    final Rect plot = Rect.fromLTRB(padLeft, 8, size.width - 8,
        size.height - padBottom);

    final Paint axis = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1;
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axis);
    canvas.drawLine(plot.topLeft, plot.bottomLeft, axis);

    final List<ReactionSample> s = trajectory.samples;
    final int tMin = s.first.offsetSeconds;
    final int tMax = s.last.offsetSeconds;
    final double tSpan = (tMax - tMin) == 0 ? 1 : (tMax - tMin).toDouble();

    double xFor(int t) => plot.left + (t - tMin) / tSpan * plot.width;
    double yForNormalised(double v) =>
        plot.bottom - v.clamp(0.0, 1.0) * plot.height;

    // Each series is normalised to its own natural range so all three are
    // legible on one axis. The axis is therefore unitless; exact values are
    // listed in the measurements table beneath the graph.
    _drawSeries(
      canvas,
      s,
      const Color(0xFF1B6CA8),
      xFor,
      yForNormalised,
      (ReactionSample x) => x.calibratedLab.l / 100.0,
    );
    _drawSeries(
      canvas,
      s,
      const Color(0xFFB3261E),
      xFor,
      yForNormalised,
      (ReactionSample x) => x.calibratedHsv.h / 360.0,
    );
    _drawSeries(
      canvas,
      s,
      const Color(0xFF1B7F4B),
      xFor,
      yForNormalised,
      (ReactionSample x) => x.calibratedHsv.s,
    );

    for (final ReactionSample sample in s) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: '${sample.offsetSeconds}s',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(xFor(sample.offsetSeconds) - tp.width / 2, plot.bottom + 5),
      );
    }
  }

  void _drawSeries(
    Canvas canvas,
    List<ReactionSample> samples,
    Color colour,
    double Function(int) xFor,
    double Function(double) yFor,
    double Function(ReactionSample) value,
  ) {
    final Paint line = Paint()
      ..color = colour
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Path path = Path();
    for (int i = 0; i < samples.length; i++) {
      final Offset point = Offset(
        xFor(samples[i].offsetSeconds),
        yFor(value(samples[i])),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawCircle(point, 3, Paint()..color = colour);
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_TrajectoryPainter old) =>
      old.trajectory != trajectory;
}
