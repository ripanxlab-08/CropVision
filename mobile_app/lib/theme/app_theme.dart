import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens grounded in real plant pathology: healthy leaves decay
/// through green -> chlorotic yellow -> rust necrosis -> charred brown
/// as disease progresses. That real botanical sequence is used as the
/// severity gradient throughout the app instead of a generic traffic-
/// light red/yellow/green, so the color itself teaches the farmer
/// something true about what they're looking at.
class AppColors {
  static const canopy = Color(0xFF2F5233); // healthy leaf green (severity data)
  static const chlorotic = Color(0xFFD9A62E); // early disease yellowing
  static const rust = Color(0xFFB5651D); // necrotic rust-brown
  static const char = Color(0xFF3B2A20); // charred/critical necrosis

  // App chrome (backgrounds, buttons, chat bubbles etc.) - dark theme
  // with a neon accent, distinct from the severity data colors above,
  // which stay true-to-plant-pathology regardless of UI theme.
  static const darkBg = Color(0xFF10181A); // near-black deep teal
  static const darkSurface = Color(0xFF1C2A2C); // card/surface on dark bg
  static const darkSurfaceElevated = Color(0xFF243638); // slightly lighter, for elevated elements
  static const neon = Color(0xFF8CFF3B); // bright lime-green accent
  static const neonDim = Color(0xFF5FCC1F); // slightly deeper, for gradients
  static const ink = Color(0xFFEAF2EC); // near-white text on dark backgrounds
  static const inkMuted = Color(0xFFA9BDB6); // secondary text on dark backgrounds

  // Kept for any legacy reference to the old light palette.
  static const parchment = Color(0xFFF6F3EA);
}

/// Continuous interpolation through the decay sequence, driven by the
/// actual severity percentage (0-100) rather than snapping to 4 flat
/// bucket colors - so 38% and 39% (both "G2") still read as visually
/// distinct, which matters when a farmer is tracking whether treatment
/// is working over several days.
Color severityColorForPercent(double percent) {
  final p = percent.clamp(0, 100) / 100;
  if (p <= 0.33) {
    return Color.lerp(AppColors.canopy, AppColors.chlorotic, p / 0.33)!;
  } else if (p <= 0.66) {
    return Color.lerp(AppColors.chlorotic, AppColors.rust, (p - 0.33) / 0.33)!;
  }
  return Color.lerp(AppColors.rust, AppColors.char, (p - 0.66) / 0.34)!;
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.neon,
        primary: AppColors.neon,
        surface: AppColors.darkSurface,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: AppColors.darkBg,
      brightness: Brightness.dark,
    );

    const displayFont = GoogleFonts.spaceGrotesk;
    const bodyFont = GoogleFonts.inter;

    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            headlineSmall: displayFont(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
            titleLarge: displayFont(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
            titleMedium: displayFont(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          )
          .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
          .merge(GoogleFonts.interTextTheme(base.textTheme).apply(
            bodyColor: AppColors.ink,
            displayColor: AppColors.ink,
          )),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkBg,
        foregroundColor: AppColors.ink,
        elevation: 0,
        titleTextStyle: displayFont(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      ),
      // Consistent smooth zoom transition on every screen push, across
      // Android/web/desktop alike (default Flutter varies this
      // per-platform, which reads as inconsistent polish). Using
      // ZoomPageTransitionsBuilder uniformly avoids needing a
      // cupertino.dart import just for iOS/macOS specifically, which
      // this project doesn't target anyway.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.neon.withValues(alpha: 0.15)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.neon,
          foregroundColor: AppColors.darkBg,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: bodyFont(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.neon.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.neon, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.inkMuted),
        hintStyle: const TextStyle(color: AppColors.inkMuted),
      ),
    );
  }
}
