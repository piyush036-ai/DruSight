/// Status indicators. Colour is always accompanied by a text label
/// (master spec section 43).
library;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../models/enums.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.colour,
    this.icon,
    super.key,
  });

  factory StatusChip.result(TestResult result) => StatusChip(
        label: result.displayLabel,
        colour: DruSightTheme.forResult(result),
      );

  factory StatusChip.reliability(ReliabilityStatus status) => StatusChip(
        label: status.displayLabel,
        colour: DruSightTheme.forReliability(status),
      );

  final String label;
  final Color colour;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colour, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 16, color: colour),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: colour,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
