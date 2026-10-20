import 'package:flutter/material.dart';

class TvTheme {
  static const Color background = Color(0xFF090A0E);
  static const Color surface = Color(0xFF13151B);
  static const Color surfaceElevated = Color(0xFF1C1F28);
  static const Color surfaceFocus = Color(0xFF262A36);
  static const Color primary = Color(0xFF3B82F6);
  static const Color primaryAccent = Color(0xFF60A5FA);
  static const Color accentGold = Color(0xFFF59E0B);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textBright = Color(0xFFF8FAFC);
  static const Color borderSubtle = Color(0xFF2E3440);

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: primaryAccent,
        surface: surface,
      ),
      focusColor: primaryAccent.withValues(alpha: 0.25),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: textBright,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: TextStyle(
          color: textBright,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: textBright,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: textBright,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: TextStyle(color: textMuted, fontSize: 13, height: 1.4),
        labelSmall: TextStyle(
          color: textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF161922),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: primaryAccent, width: 1.5),
        ),
        elevation: 16,
      ),
    );
  }
}
