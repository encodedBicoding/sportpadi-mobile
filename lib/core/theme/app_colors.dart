import 'package:flutter/material.dart';

/// Palette mirrored from the web design tokens (apps/web globals.css) so both
/// clients read as one brand. Light values are the exact web tokens; dark keeps
/// the same brand green + gold accent on dark green-tinted surfaces.
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
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color ink;
  final Color muted;
  final Color line;
  final Color accent; // brand green  (--primary 150 76% 37%)
  final Color amber; // gold accent  (--accent  40 92% 50%)
  final Color danger; // --destructive

  static const light = AppPalette(
    bg: Color(0xFFEBF0ED),
    surface: Color(0xFFFCFDFC),
    surface2: Color(0xFFE1EAE6),
    ink: Color(0xFF1F2933),
    muted: Color(0xFF576375),
    line: Color(0xFFD3DADF),
    accent: Color(0xFF17A65E),
    amber: Color(0xFFF5A70A),
    danger: Color(0xFFDE2121),
  );

  static const dark = AppPalette(
    bg: Color(0xFF0E1512),
    surface: Color(0xFF18201C),
    surface2: Color(0xFF242E29),
    ink: Color(0xFFEBEFEE),
    muted: Color(0xFF95A7A0),
    line: Color(0xFF303B36),
    accent: Color(0xFF1EB86B),
    amber: Color(0xFFF5AA14),
    danger: Color(0xFFE44E4E),
  );
}

/// Convenience access to the active palette from a [BuildContext].
extension PaletteX on BuildContext {
  AppPalette get palette => Theme.of(this).brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;
}
