import 'package:flutter/material.dart';

/// SportPadi 2026 palette (see the "SportPadi Mobile 2026" design canvas).
///
/// Soft canvas, white cards, near-black ink for emphasis (the dock, the
/// "Next up" hero, primary buttons). Brand green and orange come straight
/// from the logo and are used as SIGNALS — progress, chips, streaks, live
/// dots — never as large fills behind small text (contrast).
class AppPalette {
  const AppPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.amber,
    required this.danger,
    required this.accentDeep,
    required this.accentTint,
    required this.orange,
    required this.orangeTint,
    required this.orangeInk,
    required this.hero,
    required this.onHero,
    required this.heroMuted,
    required this.liveTint,
  });

  final Color bg; // page canvas
  final Color surface; // cards
  final Color surface2; // quiet fills (chips, tracks)
  final Color ink; // text + emphasis
  final Color muted; // captions
  final Color line; // hairlines
  final Color accent; // brand green (progress, icons)
  final Color amber; // gold / warning accent
  final Color danger; // live / destructive
  final Color accentDeep; // green that carries white text (AA)
  final Color accentTint; // green chip background
  final Color orange; // brand orange (dots, rings)
  final Color orangeTint; // orange chip background
  final Color orangeInk; // text on orangeTint (AA)
  final Color hero; // near-black emphasis surface (dock, Next up)
  final Color onHero; // text/icons on [hero]
  final Color heroMuted; // secondary text on [hero]
  final Color liveTint; // soft red row / chip background

  /// Green for text and small icons on [surface] or [accentTint]: the deep
  /// green in light mode, the brighter brand green in dark (the deep one
  /// loses contrast on dark tints).
  Color get greenText => bg.computeLuminance() < 0.2 ? accent : accentDeep;

  static const light = AppPalette(
    bg: Color(0xFFF3F5F2),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEEF2EF),
    ink: Color(0xFF0E1411),
    muted: Color(0xFF5E6B66),
    line: Color(0xFFE3E8E5),
    accent: Color(0xFF17A65E),
    amber: Color(0xFFF5A70A),
    danger: Color(0xFFE02424),
    accentDeep: Color(0xFF0F7A45),
    accentTint: Color(0xFFE6F6EC),
    orange: Color(0xFFF4781F),
    orangeTint: Color(0xFFFEEEDF),
    orangeInk: Color(0xFF9A4308),
    hero: Color(0xFF0E1411),
    onHero: Color(0xFFFFFFFF),
    heroMuted: Color(0xC7FFFFFF),
    liveTint: Color(0xFFFDE8E8),
  );

  static const dark = AppPalette(
    bg: Color(0xFF0B100D),
    surface: Color(0xFF151C18),
    surface2: Color(0xFF1F2823),
    ink: Color(0xFFEDF2EF),
    muted: Color(0xFF9AABA3),
    line: Color(0xFF26302B),
    accent: Color(0xFF1EB86B),
    amber: Color(0xFFF5AA14),
    danger: Color(0xFFF05252),
    accentDeep: Color(0xFF14935A),
    accentTint: Color(0xFF15301F),
    orange: Color(0xFFF4781F),
    orangeTint: Color(0xFF3A2413),
    orangeInk: Color(0xFFFFB57D),
    // Emphasis in dark mode is a RAISED neutral (not flipped to light): the
    // dock, Next up and primary buttons sit a clear step above the canvas,
    // with white on them — calm at night, still the loudest thing on screen.
    hero: Color(0xFF26332C),
    onHero: Color(0xFFFFFFFF),
    heroMuted: Color(0xB3FFFFFF),
    liveTint: Color(0xFF3A1717),
  );
}

/// Wards (violet): events one of your wards is going to — kept apart from
/// green (yours), red (live) and orange (tournaments) on the calendar.
extension WardColorsX on AppPalette {
  bool get _dark => bg.computeLuminance() < 0.2;
  Color get ward => _dark ? const Color(0xFF9580FF) : const Color(0xFF7C5CFF);
  Color get wardTint =>
      _dark ? const Color(0xFF262046) : const Color(0xFFEFEBFF);
  Color get wardInk =>
      _dark ? const Color(0xFFC4B5FF) : const Color(0xFF5A3FD6);
}

/// Convenience access to the active palette from a [BuildContext].
extension PaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
}

/// Soft, layered card shadow used across the app (none in dark mode, where
/// shadows read as mud — the surface step does the lifting there).
List<BoxShadow> cardShadow(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const []
        : const [
            BoxShadow(
                color: Color(0x0D0E1411), blurRadius: 2, offset: Offset(0, 1)),
            BoxShadow(
                color: Color(0x1F0E1411),
                blurRadius: 28,
                spreadRadius: -18,
                offset: Offset(0, 12)),
          ];
