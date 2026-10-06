import 'package:flutter/material.dart';

abstract final class TrekItColors {
  static const deepTeal = Color(0xFF073E47);
  static const teal = Color(0xFF0D5963);
  static const sunset = Color(0xFFF5A019);
  static const sage = Color(0xFF9AA16D);
  static const cream = Color(0xFFFFF8EA);
  static const warmWhite = Color(0xFFFFFCF6);
  static const orangeMist = Color(0xFFFFF1D6);
  static const orangeWash = Color(0xFFFFE5B5);
  static const orangeGlow = Color(0xFFFFD28A);
  static const ink = Color(0xFF172B2E);
}

abstract final class TrekItTheme {
  static ThemeData get light {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: TrekItColors.deepTeal,
          primary: TrekItColors.deepTeal,
          secondary: TrekItColors.sunset,
          surface: TrekItColors.cream,
          brightness: Brightness.light,
        ).copyWith(
          onSecondary: TrekItColors.ink,
          primaryContainer: TrekItColors.orangeWash,
          onPrimaryContainer: TrekItColors.ink,
          secondaryContainer: TrekItColors.orangeGlow,
          onSecondaryContainer: TrekItColors.ink,
          surface: TrekItColors.cream,
          surfaceDim: const Color(0xFFF3DFC0),
          surfaceBright: TrekItColors.warmWhite,
          surfaceContainerLowest: TrekItColors.warmWhite,
          surfaceContainerLow: const Color(0xFFFFF5E5),
          surfaceContainer: TrekItColors.orangeMist,
          surfaceContainerHigh: TrekItColors.orangeWash,
          surfaceContainerHighest: const Color(0xFFFFDDAA),
          outlineVariant: const Color(0xFFD8B77F),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: TrekItColors.cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: TrekItColors.orangeWash,
        foregroundColor: TrekItColors.ink,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: TrekItColors.orangeMist,
        surfaceTintColor: Colors.transparent,
        shadowColor: TrekItColors.sunset.withValues(alpha: 0.16),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xFFFFF3DF),
        indicatorColor: TrekItColors.orangeGlow,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: TrekItColors.warmWhite,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TrekItColors.warmWhite,
        surfaceTintColor: Colors.transparent,
      ),
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
