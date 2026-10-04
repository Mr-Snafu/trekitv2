import 'package:flutter/material.dart';

abstract final class TrekItColors {
  static const deepTeal = Color(0xFF073E47);
  static const teal = Color(0xFF0D5963);
  static const sunset = Color(0xFFF5A019);
  static const sage = Color(0xFF9AA16D);
  static const cream = Color(0xFFFFF8EA);
  static const ink = Color(0xFF172B2E);
}

abstract final class TrekItTheme {
  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: TrekItColors.deepTeal,
      primary: TrekItColors.deepTeal,
      secondary: TrekItColors.sunset,
      surface: TrekItColors.cream,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: TrekItColors.cream,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          height: 1.05,
          letterSpacing: -1,
        ),
        headlineSmall: TextStyle(
          color: TrekItColors.ink,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
        bodyLarge: TextStyle(color: TrekItColors.ink, height: 1.45),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0x1A073E47)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: TrekItColors.deepTeal, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
