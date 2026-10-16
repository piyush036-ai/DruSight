/// Visual theme for a field forensic tool (master spec section 43).
///
/// Priorities that drove these choices: outdoor readability (high contrast,
/// large type, no thin weights), unambiguous status colour, and no decorative
/// animation. Status colour is always paired with a text label, because
/// colour alone fails in sunlight and for colour-blind operators - and this is
/// an app whose whole subject is colour perception.
library;

import 'package:flutter/material.dart';

import '../models/enums.dart';

class DruSightTheme {
  const DruSightTheme._();

  static const Color navy = Color(0xFF0E2A47);
  static const Color navyDark = Color(0xFF071B2F);
  static const Color accent = Color(0xFF1B6CA8);
  static const Color surface = Color(0xFFF4F6F8);

  static const Color positive = Color(0xFFB3261E);
  static const Color negative = Color(0xFF1B7F4B);
  static const Color inconclusive = Color(0xFF9A6700);
  static const Color blocked = Color(0xFF5F6368);

  static ThemeData light() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: navy,
      brightness: Brightness.light,
    ).copyWith(surface: Colors.white);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      textTheme: const TextTheme(
        headlineSmall:
            TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2),
        titleMedium:
            TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.3),
        bodyLarge: TextStyle(fontSize: 16, height: 1.45),
        bodyMedium: TextStyle(fontSize: 15, height: 1.45),
        labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  static Color forResult(TestResult result) => switch (result) {
        TestResult.presumptivePositive => positive,
        TestResult.presumptiveNegative => negative,
        TestResult.inconclusive => inconclusive,
      };

  static Color forReliability(ReliabilityStatus status) => switch (status) {
        ReliabilityStatus.pass => negative,
        ReliabilityStatus.review => inconclusive,
        ReliabilityStatus.recaptureRequired => blocked,
      };
}
