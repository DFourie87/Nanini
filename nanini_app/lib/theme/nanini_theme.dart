import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand colors, lifted directly from the web app's CSS variables
/// (`Nanini App/index.html` `:root{...}`) so both clients look identical.
class NaniniColors {
  NaniniColors._();

  static const ink = Color(0xFF000000);
  static const paper = Color(0xFFFFFFFF);
  static const line = Color(0xFFE4D6C3);
  static const rust = Color(0xFFEC1F24);
  static const rustDark = Color(0xFFC41A1E);
  static const muted = Color(0xFF4A4A4A);
  static const disabledBg = Color(0xFFF0E7D8);

  static const green = Color(0xFF2E7D32);
  static const amber = Color(0xFFE07B00);
  static const red = Color(0xFFC81E1E);
}

class NaniniTheme {
  NaniniTheme._();

  static ThemeData get light {
    final headingFont = GoogleFonts.oswaldTextTheme();
    final bodyFont = GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: NaniniColors.paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: NaniniColors.rust,
        primary: NaniniColors.rust,
        secondary: NaniniColors.rustDark,
        surface: NaniniColors.paper,
        brightness: Brightness.light,
      ),
      fontFamily: bodyFont.bodyMedium?.fontFamily,
      textTheme: bodyFont.copyWith(
        headlineLarge: headingFont.headlineLarge?.copyWith(fontWeight: FontWeight.w600),
        headlineMedium: headingFont.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        headlineSmall: headingFont.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        titleLarge: headingFont.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: headingFont.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: headingFont.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: NaniniColors.paper,
        foregroundColor: NaniniColors.ink,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: headingFont.titleLarge?.copyWith(
          color: NaniniColors.ink,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: NaniniColors.ink),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NaniniColors.rust,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: bodyFont.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NaniniColors.ink,
          side: const BorderSide(color: NaniniColors.line),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NaniniColors.paper,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: NaniniColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: NaniniColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: NaniniColors.rustDark, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      cardTheme: CardThemeData(
        color: NaniniColors.paper,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: NaniniColors.line),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: NaniniColors.paper,
        selectedItemColor: NaniniColors.rustDark,
        unselectedItemColor: NaniniColors.muted,
        type: BottomNavigationBarType.fixed,
      ),
      dividerTheme: const DividerThemeData(color: NaniniColors.line),
    );
  }
}
