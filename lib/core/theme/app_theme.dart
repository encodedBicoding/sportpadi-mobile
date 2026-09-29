import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Material 3 theme, SportPadi 2026: Poppins (the brand face, same as web),
/// soft canvas, white cards with large radii, pill buttons, ink for emphasis.
/// Tight letter-spacing on headings; wide tracking only on eyebrow labels.
class AppTheme {
  static ThemeData light() => _base(Brightness.light, AppPalette.light);
  static ThemeData dark() => _base(Brightness.dark, AppPalette.dark);

  static ThemeData _base(Brightness brightness, AppPalette p) {
    const onAccent = Colors.white;
    final scheme = ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: brightness,
    ).copyWith(
      primary: p.accent,
      onPrimary: onAccent,
      secondary: p.amber,
      surface: p.surface,
      onSurface: p.ink,
      error: p.danger,
      outline: p.line,
    );

    final base = ThemeData(brightness: brightness);
    final text = GoogleFonts.poppinsTextTheme(base.textTheme)
        .apply(bodyColor: p.ink, displayColor: p.ink);

    TextStyle h(TextStyle? s, double size, [FontWeight wt = FontWeight.w700]) =>
        GoogleFonts.poppins(
            textStyle: s,
            fontSize: size,
            fontWeight: wt,
            color: p.ink,
            height: 1.15,
            letterSpacing: size >= 20 ? -0.4 : -0.1);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      splashFactory: InkSparkle.splashFactory,
      textTheme: text.copyWith(
        headlineMedium: h(text.headlineMedium, 26, FontWeight.w800),
        headlineSmall: h(text.headlineSmall, 21, FontWeight.w800),
        titleLarge: h(text.titleLarge, 18),
        titleMedium: h(text.titleMedium, 15, FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              brightness == Brightness.dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: brightness,
          systemNavigationBarColor: p.bg,
          systemNavigationBarIconBrightness:
              brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        ),
        backgroundColor: p.bg,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
            fontWeight: FontWeight.w700, fontSize: 19, color: p.ink, letterSpacing: -0.3),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.hero,
        side: BorderSide(color: p.line),
        shape: const StadiumBorder(),
        labelStyle: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink),
        secondaryLabelStyle:
            GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.onHero),
        checkmarkColor: p.onHero,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        showDragHandle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.hero,
        contentTextStyle: GoogleFonts.poppins(color: p.onHero, fontSize: 13.5, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          side: BorderSide(color: p.line),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accentDeep,
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: _border(p.line),
        enabledBorder: _border(p.line),
        focusedBorder: _border(p.accent, width: 1.5),
        labelStyle: TextStyle(color: p.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.hero,
          foregroundColor: p.onHero,
          minimumSize: const Size.fromHeight(52),
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.surface2,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? p.accent : p.muted,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
    );
  }

  static OutlineInputBorder _border(Color c, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c, width: width),
      );
}
