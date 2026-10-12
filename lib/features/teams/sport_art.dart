import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';

/// Sport cards' colours and artwork (web: packages/lib/src/sportArt.ts — the
/// data at the bottom of this file is generated from it). Shapes sit on a
/// 120 × 64 canvas; "A" = the sport's colour, "W" = white, "D" = near-black
/// (details on white objects — always dark), "K" = the theme's ink
/// (free-standing silhouettes, light in dark mode), or a literal "#rrggbb".
class SportShape {
  const SportShape(this.t, this.v, {this.d, this.fill, this.stroke, this.sw, this.o, this.rot});

  /// c (circle: cx, cy, r) · e (ellipse: cx, cy, rx, ry) · r (rect: x, y, w, h, radius) · l (line) · p (path [d]).
  final String t;
  final List<double> v;
  final String? d;
  final String? fill;
  final String? stroke;
  final double? sw;
  final double? o;

  /// Degrees, about the shape's centre (rects and ellipses).
  final double? rot;
}

class SportDef {
  const SportDef({required this.key, required this.name, required this.match, this.not = const [], required this.color, required this.art});
  final String key;
  final String name;
  final List<String> match;
  final List<String> not;
  final Color color;
  final List<SportShape> art;
}

/// The sport a category belongs to (by its name), or null for other sports.
/// "Table tennis" is ping pong and "Padel" isn't tennis — checked first.
SportDef? sportFor(String? categoryName) {
  final hay = (categoryName ?? '').toLowerCase();
  if (hay.trim().isEmpty) return null;
  bool hit(SportDef s) => s.match.any(hay.contains) && !s.not.any(hay.contains);
  for (final key in const ['pingpong', 'padel']) {
    final s = kSports.firstWhere((x) => x.key == key);
    if (hit(s)) return s;
  }
  return kSports.where(hit).firstOrNull;
}

SportDef? sportByKey(String key) => kSports.where((s) => s.key == key).firstOrNull;

/// A sport card's tint: the sport colour over the card surface (stronger in dark mode).
Color sportTint(AppPalette p, Color c) => Color.alphaBlend(c.withAlpha(p.bg.computeLuminance() < 0.2 ? 61 : 33), p.surface);

/// The sport colour as readable text on its tint.
Color sportInk(AppPalette p, Color c) =>
    p.bg.computeLuminance() < 0.2 ? Color.lerp(c, Colors.white, 0.45)! : Color.lerp(c, p.ink, 0.18)!;

/// A sport's artwork; an emoji for sports we don't draw.
class SportArt extends StatelessWidget {
  const SportArt(this.def, {super.key, this.emoji, this.width = 88});
  final SportDef? def;
  final String? emoji;
  final double width;

  @override
  Widget build(BuildContext context) {
    final h = width * 64 / 120;
    if (def == null) {
      return SizedBox(
          width: width, height: h, child: Align(alignment: Alignment.centerLeft, child: Text(emoji ?? '🏅', style: TextStyle(fontSize: h * 0.8))));
    }
    return SizedBox(width: width, height: h, child: CustomPaint(painter: _SportPainter(def!, context.palette.ink)));
  }
}

class _SportPainter extends CustomPainter {
  _SportPainter(this.def, this.ink);
  final SportDef def;
  final Color ink;

  Color? _col(String? c, double? o) {
    if (c == null) return null;
    final base = switch (c) {
      'A' => def.color,
      'W' => Colors.white,
      'K' => ink,
      'D' => const Color(0xFF1B2420),
      _ => Color(int.parse('FF${c.substring(1)}', radix: 16)),
    };
    return o == null ? base : base.withAlpha((o * 255).round());
  }

  static Path _parse(String d) {
    final path = Path();
    final tokens = RegExp(r'[MLQCZ]|-?\d*\.?\d+').allMatches(d).map((m) => m[0]!).toList();
    var i = 0;
    double n() => double.parse(tokens[i++]);
    String cmd = 'M';
    while (i < tokens.length) {
      if (RegExp(r'^[MLQCZ]$').hasMatch(tokens[i])) cmd = tokens[i++];
      switch (cmd) {
        case 'M':
          path.moveTo(n(), n());
          cmd = 'L';
        case 'L':
          path.lineTo(n(), n());
        case 'Q':
          path.quadraticBezierTo(n(), n(), n(), n());
        case 'C':
          path.cubicTo(n(), n(), n(), n(), n(), n());
        case 'Z':
          path.close();
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 120, size.height / 64);
    for (final s in def.art) {
      final fill = s.t == 'l' ? null : _col(s.fill, s.o);
      final stroke = _col(s.stroke, s.o);
      final fp = fill == null ? null : (Paint()..color = fill);
      final sp = stroke == null || (s.sw ?? 0) <= 0
          ? null
          : (Paint()
            ..color = stroke
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.sw!
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
      void rotated(Offset c, void Function() draw) {
        if ((s.rot ?? 0) == 0) return draw();
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(s.rot! * 3.141592653589793 / 180);
        canvas.translate(-c.dx, -c.dy);
        draw();
        canvas.restore();
      }

      final v = s.v;
      switch (s.t) {
        case 'c':
          if (fp != null) canvas.drawCircle(Offset(v[0], v[1]), v[2], fp);
          if (sp != null) canvas.drawCircle(Offset(v[0], v[1]), v[2], sp);
        case 'e':
          final r = Rect.fromCenter(center: Offset(v[0], v[1]), width: v[2] * 2, height: v[3] * 2);
          rotated(r.center, () {
            if (fp != null) canvas.drawOval(r, fp);
            if (sp != null) canvas.drawOval(r, sp);
          });
        case 'r':
          final rr = RRect.fromRectAndRadius(Rect.fromLTWH(v[0], v[1], v[2], v[3]), Radius.circular(v[4]));
          rotated(rr.center, () {
            if (fp != null) canvas.drawRRect(rr, fp);
            if (sp != null) canvas.drawRRect(rr, sp);
          });
        case 'l':
          if (sp != null) canvas.drawLine(Offset(v[0], v[1]), Offset(v[2], v[3]), sp);
        case 'p':
          final path = _parse(s.d ?? '');
          if (fp != null) canvas.drawPath(path, fp);
          if (sp != null) canvas.drawPath(path, sp);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SportPainter old) => old.def != def || old.ink != ink;
}

// GENERATED from packages/lib/src/sportArt.ts (the web's source of truth) —
// regenerate rather than edit, so the cards match on web and in the app.
const kSports = <SportDef>[
  SportDef(
    key: 'soccer',
    name: 'Soccer',
    match: ['soccer', 'football', 'futsal', '5-a-side', 'five-a-side'],
    not: ['american', 'australian', 'aussie', 'gaelic', 'flag football'],
    color: Color(0xFF16A34A),
    art: [
      SportShape('r', [60,12,52,40,3], stroke: 'A', sw: 3),
      SportShape('l', [70,13,70,51], stroke: 'A', sw: 1.2, o: 0.45),
      SportShape('l', [80,13,80,51], stroke: 'A', sw: 1.2, o: 0.45),
      SportShape('l', [90,13,90,51], stroke: 'A', sw: 1.2, o: 0.45),
      SportShape('l', [100,13,100,51], stroke: 'A', sw: 1.2, o: 0.45),
      SportShape('l', [61,22,111,22], stroke: 'A', sw: 1.2, o: 0.45),
      SportShape('l', [61,32,111,32], stroke: 'A', sw: 1.2, o: 0.45),
      SportShape('l', [61,42,111,42], stroke: 'A', sw: 1.2, o: 0.45),
      SportShape('c', [32,34,19], fill: 'W', stroke: 'D', sw: 2),
      SportShape('p', [], d: 'M32 26 L39 31 L36 39 L28 39 L25 31 Z', fill: 'D'),
      SportShape('l', [32,26,32,15], stroke: 'D', sw: 1.6),
      SportShape('l', [39,31,49,28], stroke: 'D', sw: 1.6),
      SportShape('l', [36,39,42,49], stroke: 'D', sw: 1.6),
      SportShape('l', [28,39,22,49], stroke: 'D', sw: 1.6),
      SportShape('l', [25,31,15,28], stroke: 'D', sw: 1.6),
    ],
  ),
  SportDef(
    key: 'baseball',
    name: 'Baseball',
    match: ['baseball', 'softball'],
    not: [],
    color: Color(0xFF1D4ED8),
    art: [
      SportShape('l', [56,56,108,10], stroke: '#c08a4b', sw: 9),
      SportShape('l', [56,56,70,44], stroke: 'K', sw: 6),
      SportShape('c', [54,58,4], fill: 'K'),
      SportShape('c', [30,33,18], fill: 'W', stroke: 'D', sw: 2),
      SportShape('p', [], d: 'M19 19 Q27 33 19 47', stroke: '#dc2626', sw: 2.2),
      SportShape('p', [], d: 'M41 19 Q33 33 41 47', stroke: '#dc2626', sw: 2.2),
      SportShape('l', [21,24,25,23], stroke: '#dc2626', sw: 1.4),
      SportShape('l', [21,30,25,29], stroke: '#dc2626', sw: 1.4),
      SportShape('l', [21,36,25,35], stroke: '#dc2626', sw: 1.4),
      SportShape('l', [21,42,25,41], stroke: '#dc2626', sw: 1.4),
      SportShape('l', [39,24,35,23], stroke: '#dc2626', sw: 1.4),
      SportShape('l', [39,30,35,29], stroke: '#dc2626', sw: 1.4),
      SportShape('l', [39,36,35,35], stroke: '#dc2626', sw: 1.4),
      SportShape('l', [39,42,35,41], stroke: '#dc2626', sw: 1.4),
    ],
  ),
  SportDef(
    key: 'basketball',
    name: 'Basketball',
    match: ['basketball', 'hoops'],
    not: [],
    color: Color(0xFFEA580C),
    art: [
      SportShape('r', [76,6,36,24,3], fill: 'W', stroke: 'D', sw: 2),
      SportShape('r', [87,14,14,10,0], stroke: 'A', sw: 2),
      SportShape('l', [82,31,106,31], stroke: 'A', sw: 3.5),
      SportShape('l', [86,32,87,44], stroke: 'K', sw: 1, o: 0.55),
      SportShape('l', [92,32,93,44], stroke: 'K', sw: 1, o: 0.55),
      SportShape('l', [98,32,95,44], stroke: 'K', sw: 1, o: 0.55),
      SportShape('l', [104,32,101,44], stroke: 'K', sw: 1, o: 0.55),
      SportShape('c', [32,36,19], fill: 'A', stroke: 'D', sw: 2),
      SportShape('l', [13,36,51,36], stroke: 'D', sw: 1.8),
      SportShape('l', [32,17,32,55], stroke: 'D', sw: 1.8),
      SportShape('p', [], d: 'M19 22 Q27 36 19 50', stroke: 'D', sw: 1.8),
      SportShape('p', [], d: 'M45 22 Q37 36 45 50', stroke: 'D', sw: 1.8),
    ],
  ),
  SportDef(
    key: 'volleyball',
    name: 'Volleyball',
    match: ['volleyball', 'volley'],
    not: [],
    color: Color(0xFFCA8A04),
    art: [
      SportShape('l', [66,10,66,58], stroke: 'K', sw: 2.5),
      SportShape('l', [114,10,114,58], stroke: 'K', sw: 2.5),
      SportShape('r', [66,12,48,4,0], fill: 'W', stroke: 'D', sw: 1),
      SportShape('l', [66,22,114,22], stroke: 'K', sw: 1, o: 0.4),
      SportShape('l', [66,28,114,28], stroke: 'K', sw: 1, o: 0.4),
      SportShape('l', [66,34,114,34], stroke: 'K', sw: 1, o: 0.4),
      SportShape('l', [74,16,74,38], stroke: 'K', sw: 1, o: 0.4),
      SportShape('l', [82,16,82,38], stroke: 'K', sw: 1, o: 0.4),
      SportShape('l', [90,16,90,38], stroke: 'K', sw: 1, o: 0.4),
      SportShape('l', [98,16,98,38], stroke: 'K', sw: 1, o: 0.4),
      SportShape('l', [106,16,106,38], stroke: 'K', sw: 1, o: 0.4),
      SportShape('c', [32,35,19], fill: 'W', stroke: 'D', sw: 2),
      SportShape('p', [], d: 'M32 16 Q24 30 32 35 Q42 30 50 40', stroke: 'A', sw: 3),
      SportShape('p', [], d: 'M32 35 Q30 46 20 50', stroke: 'A', sw: 3),
      SportShape('p', [], d: 'M13 33 Q24 26 32 35', stroke: 'D', sw: 1.6),
    ],
  ),
  SportDef(
    key: 'chess',
    name: 'Chess',
    match: ['chess'],
    not: [],
    color: Color(0xFF475569),
    art: [
      SportShape('r', [6,42,22,11,0], fill: 'W', o: 0.9),
      SportShape('r', [6,53,22,11,0], fill: 'D', o: 0.75),
      SportShape('r', [28,42,22,11,0], fill: 'D', o: 0.75),
      SportShape('r', [28,53,22,11,0], fill: 'W', o: 0.9),
      SportShape('r', [50,42,22,11,0], fill: 'W', o: 0.9),
      SportShape('r', [50,53,22,11,0], fill: 'D', o: 0.75),
      SportShape('r', [72,42,22,11,0], fill: 'D', o: 0.75),
      SportShape('r', [72,53,22,11,0], fill: 'W', o: 0.9),
      SportShape('r', [94,42,22,11,0], fill: 'W', o: 0.9),
      SportShape('r', [94,53,22,11,0], fill: 'D', o: 0.75),
      SportShape('c', [30,14,6], fill: 'K'),
      SportShape('p', [], d: 'M24 22 L36 22 L33 32 Q38 36 38 42 L22 42 Q22 36 27 32 Z', fill: 'K'),
      SportShape('p', [], d: 'M74 42 L74 20 L72 20 L72 10 L78 10 L78 14 L82 14 L82 10 L88 10 L88 14 L92 14 L92 10 L98 10 L98 20 L96 20 L96 42 Z', fill: 'A', stroke: 'D', sw: 1.6),
    ],
  ),
  SportDef(
    key: 'frisbee',
    name: 'Frisbee',
    match: ['frisbee', 'ultimate', 'disc golf'],
    not: [],
    color: Color(0xFF0284C7),
    art: [
      SportShape('l', [6,22,30,22], stroke: 'A', sw: 3, o: 0.35),
      SportShape('l', [2,32,32,32], stroke: 'A', sw: 3, o: 0.55),
      SportShape('l', [10,42,34,42], stroke: 'A', sw: 3, o: 0.35),
      SportShape('e', [70,34,38,15], fill: 'A', stroke: 'D', sw: 2, rot: -10),
      SportShape('e', [70,31,26,9], stroke: 'W', sw: 2.2, o: 0.8, rot: -10),
      SportShape('e', [70,30,12,4], fill: 'W', o: 0.5, rot: -10),
    ],
  ),
  SportDef(
    key: 'golf',
    name: 'Golf',
    match: ['golf'],
    not: [],
    color: Color(0xFF0F766E),
    art: [
      SportShape('p', [], d: 'M4 56 Q60 40 116 56 L116 64 L4 64 Z', fill: 'A', o: 0.35),
      SportShape('e', [78,52,9,3], fill: 'K'),
      SportShape('l', [78,52,78,6], stroke: 'K', sw: 2.2),
      SportShape('p', [], d: 'M78 7 L104 14 L78 22 Z', fill: '#dc2626'),
      SportShape('c', [30,44,10], fill: 'W', stroke: 'D', sw: 1.8),
      SportShape('c', [26,40,1.2], fill: 'D', o: 0.4),
      SportShape('c', [32,39,1.2], fill: 'D', o: 0.4),
      SportShape('c', [28,46,1.2], fill: 'D', o: 0.4),
      SportShape('c', [34,45,1.2], fill: 'D', o: 0.4),
      SportShape('c', [24,45,1.2], fill: 'D', o: 0.4),
      SportShape('c', [31,51,1.2], fill: 'D', o: 0.4),
      SportShape('l', [30,54,30,60], stroke: 'K', sw: 2.5),
    ],
  ),
  SportDef(
    key: 'hiking',
    name: 'Hiking',
    match: ['hiking', 'hike', 'trek', 'trail', 'walking'],
    not: [],
    color: Color(0xFFA16207),
    art: [
      SportShape('c', [98,14,8], fill: '#f5a70a'),
      SportShape('p', [], d: 'M2 58 L34 16 L54 40 L70 22 L104 58 Z', fill: 'A'),
      SportShape('p', [], d: 'M34 16 L41 25 L37 23 L33 27 L29 23 L27 25 Z', fill: 'W'),
      SportShape('p', [], d: 'M70 22 L77 30 L72 28 L68 31 L64 28 Z', fill: 'W'),
      SportShape('p', [], d: 'M48 58 Q58 48 52 42 Q46 36 56 30', stroke: 'W', sw: 2.2, o: 0.8),
      SportShape('l', [0,58,120,58], stroke: 'K', sw: 2),
    ],
  ),
  SportDef(
    key: 'hockey',
    name: 'Hockey',
    match: ['hockey'],
    not: [],
    color: Color(0xFF2563EB),
    art: [
      SportShape('p', [], d: 'M22 6 L56 48 Q60 54 68 54 L82 54', stroke: 'K', sw: 6),
      SportShape('p', [], d: 'M98 6 L64 48 Q60 54 52 54 L38 54', stroke: 'A', sw: 6),
      SportShape('l', [22,6,32,18], stroke: 'W', sw: 6, o: 0.85),
      SportShape('l', [98,6,88,18], stroke: 'W', sw: 6, o: 0.85),
      SportShape('e', [60,60,11,3.5], fill: 'D'),
      SportShape('r', [49,56,22,4,0], fill: 'D'),
      SportShape('e', [60,56,11,3.5], fill: '#3b4643'),
    ],
  ),
  SportDef(
    key: 'padel',
    name: 'Padel',
    match: ['padel', 'paddle tennis'],
    not: [],
    color: Color(0xFF0891B2),
    art: [
      SportShape('r', [52,40,8,22,3], fill: 'K', rot: -35),
      SportShape('e', [40,26,17,21], fill: 'A', stroke: 'D', sw: 2, rot: -35),
      SportShape('c', [34,20,1.8], fill: 'W', o: 0.9),
      SportShape('c', [42,18,1.8], fill: 'W', o: 0.9),
      SportShape('c', [38,27,1.8], fill: 'W', o: 0.9),
      SportShape('c', [46,25,1.8], fill: 'W', o: 0.9),
      SportShape('c', [32,30,1.8], fill: 'W', o: 0.9),
      SportShape('c', [42,34,1.8], fill: 'W', o: 0.9),
      SportShape('c', [36,37,1.8], fill: 'W', o: 0.9),
      SportShape('c', [92,42,10], fill: '#c5e00e', stroke: 'D', sw: 1.6),
      SportShape('p', [], d: 'M84 36 Q92 42 84 49', stroke: 'W', sw: 1.6),
      SportShape('p', [], d: 'M100 36 Q92 42 100 49', stroke: 'W', sw: 1.6),
      SportShape('l', [70,12,82,22], stroke: 'A', sw: 2.5, o: 0.4),
      SportShape('l', [76,6,88,16], stroke: 'A', sw: 2.5, o: 0.4),
    ],
  ),
  SportDef(
    key: 'paintball',
    name: 'Paintball',
    match: ['paintball', 'airsoft'],
    not: [],
    color: Color(0xFFDB2777),
    art: [
      SportShape('c', [34,30,15], fill: 'A'),
      SportShape('c', [18,18,5], fill: 'A'),
      SportShape('c', [50,16,4], fill: 'A'),
      SportShape('c', [14,40,4], fill: 'A'),
      SportShape('c', [52,44,6], fill: 'A'),
      SportShape('c', [34,50,3], fill: 'A'),
      SportShape('c', [46,8,2.5], fill: 'A'),
      SportShape('c', [8,28,2.5], fill: 'A'),
      SportShape('c', [86,24,11], fill: '#7c3aed'),
      SportShape('c', [74,14,3], fill: '#7c3aed'),
      SportShape('c', [100,16,4], fill: '#7c3aed'),
      SportShape('c', [98,34,3], fill: '#7c3aed'),
      SportShape('c', [78,36,2.5], fill: '#7c3aed'),
      SportShape('c', [92,52,7], fill: '#f59e0b'),
      SportShape('c', [104,58,2.5], fill: '#f59e0b'),
      SportShape('c', [30,26,4], fill: 'W', o: 0.5),
    ],
  ),
  SportDef(
    key: 'pingpong',
    name: 'Ping pong',
    match: ['ping pong', 'pingpong', 'ping-pong', 'table tennis'],
    not: [],
    color: Color(0xFFDC2626),
    art: [
      SportShape('r', [4,50,112,6,2], fill: '#1e40af'),
      SportShape('l', [60,40,60,50], stroke: 'K', sw: 2),
      SportShape('l', [52,40,68,40], stroke: 'K', sw: 1.5),
      SportShape('r', [31,30,8,18,3], fill: '#c08a4b', stroke: 'D', sw: 1.2, rot: 30),
      SportShape('c', [26,20,15], fill: 'A', stroke: 'D', sw: 2),
      SportShape('c', [92,16,6], fill: 'W', stroke: 'D', sw: 1.6),
      SportShape('p', [], d: 'M78 26 Q70 34 62 30', stroke: 'K', sw: 1.4, o: 0.4),
    ],
  ),
  SportDef(
    key: 'running',
    name: 'Running',
    match: ['running', 'run', 'jog', 'marathon', 'athletics', 'track'],
    not: [],
    color: Color(0xFF7C3AED),
    art: [
      SportShape('p', [], d: 'M2 62 Q50 10 118 22', stroke: 'A', sw: 10, o: 0.85),
      SportShape('p', [], d: 'M2 62 Q50 10 118 22', stroke: 'W', sw: 1.4, o: 0.9),
      SportShape('p', [], d: 'M14 64 Q56 24 118 34', stroke: 'A', sw: 10, o: 0.55),
      SportShape('p', [], d: 'M28 64 Q64 38 118 46', stroke: 'A', sw: 10, o: 0.3),
      SportShape('c', [98,12,9], fill: 'W', stroke: 'D', sw: 2),
      SportShape('l', [98,12,98,7], stroke: 'D', sw: 1.6),
      SportShape('l', [98,12,102,14], stroke: 'D', sw: 1.6),
      SportShape('r', [96,0,4,3,0], fill: 'D'),
    ],
  ),
  SportDef(
    key: 'tennis',
    name: 'Tennis',
    match: ['tennis'],
    not: [],
    color: Color(0xFF65A30D),
    art: [
      SportShape('r', [82,40,7,22,3], fill: 'K', rot: 35),
      SportShape('e', [96,22,15,19], fill: 'W', stroke: 'D', sw: 2.4, rot: 35),
      SportShape('l', [82,10,94,34], stroke: 'D', sw: 0.9, o: 0.5),
      SportShape('l', [87,10,99,34], stroke: 'D', sw: 0.9, o: 0.5),
      SportShape('l', [92,10,104,34], stroke: 'D', sw: 0.9, o: 0.5),
      SportShape('l', [97,10,109,34], stroke: 'D', sw: 0.9, o: 0.5),
      SportShape('l', [86,18,106,10], stroke: 'D', sw: 0.9, o: 0.5),
      SportShape('l', [86,23,106,15], stroke: 'D', sw: 0.9, o: 0.5),
      SportShape('l', [86,28,106,20], stroke: 'D', sw: 0.9, o: 0.5),
      SportShape('l', [86,33,106,25], stroke: 'D', sw: 0.9, o: 0.5),
      SportShape('c', [32,34,18], fill: '#c5e00e', stroke: 'D', sw: 2),
      SportShape('p', [], d: 'M18 22 Q30 34 18 46', stroke: 'W', sw: 2.4),
      SportShape('p', [], d: 'M46 22 Q34 34 46 46', stroke: 'W', sw: 2.4),
    ],
  ),
];
