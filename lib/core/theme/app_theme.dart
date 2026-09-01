import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Material 3 theme from the web brand tokens. Poppins is the Sportpadi face
/// (base.css `--font-display`/`--font-body`); we match the web's weights and
/// keep letter-spacing tight, reserving wide tracking for small eyebrow labels.
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
        GoogleFonts.poppins(textStyle: s, fontSize: size, fontWeight: wt, color: p.ink, height: 1.15);

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
        backgroundColor: p.bg,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle:
            GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 19, color: p.ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: _border(p.line),
        enabledBorder: _border(p.line),
        focusedBorder: _border(p.accent, width: 1.5),
        labelStyle: TextStyle(color: p.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: onAccent,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: width),
      );
}
