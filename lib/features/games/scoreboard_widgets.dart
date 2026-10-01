import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';

/// The match scoreboard's sport-aware pieces (mobile twin of web
/// components/games/scoreboard.tsx).
///
///  * [boardSpec] — what the score counts (goals / points / runs) and what a
///    finished game is called in that sport (Full time / Final / Match over).
///  * [CourtLines] — faint markings of the sport's playing surface behind the
///    score: a pitch, a court, a diamond, an oval.
///  * [ScoreCrest] — the team's logo when it has one (tournament teams), else
///    a tile in the kit colour. With a logo, a small shirt in the kit colour
///    sits on the crest's corner, so the board still shows who wears what.
///
/// `family` is the server's officiating profile family (sportFamilyFor).

class BoardSpec {
  const BoardSpec(this.unit, this.finalLabel, this.finalShort, this.court);
  final String unit;
  final String finalLabel;
  final String finalShort;
  final String court;
}

const _specs = <String, BoardSpec>{
  'soccer': BoardSpec('Goals', 'Full time', 'FT', 'pitch'),
  'hockey': BoardSpec('Goals', 'Full time', 'FT', 'hockey'),
  'handball': BoardSpec('Goals', 'Full time', 'FT', 'handball'),
  'netball': BoardSpec('Goals', 'Full time', 'FT', 'netball'),
  'basketball': BoardSpec('Points', 'Final', 'Final', 'basketball'),
  'volleyball': BoardSpec('Points', 'Match over', 'Final', 'volleyball'),
  'racket': BoardSpec('Points', 'Match over', 'Final', 'tennis'),
  'rugby': BoardSpec('Points', 'Full time', 'FT', 'rugby'),
  'american_football': BoardSpec('Points', 'Final', 'Final', 'gridiron'),
  'cricket': BoardSpec('Runs', 'Result', 'Result', 'cricket'),
  'baseball': BoardSpec('Runs', 'Final', 'Final', 'diamond'),
  'generic': BoardSpec('Score', 'Final', 'Final', 'none'),
};

BoardSpec boardSpec(String? family) =>
    _specs[family ?? 'generic'] ?? _specs['generic']!;

/// Faint playing-surface markings; fills its parent (use in a Stack).
class CourtLines extends StatelessWidget {
  const CourtLines({super.key, required this.family});
  final String? family;

  @override
  Widget build(BuildContext context) {
    final court = boardSpec(family).court;
    if (court == 'none') return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(painter: _CourtPainter(court), size: Size.infinite),
    );
  }
}

class _CourtPainter extends CustomPainter {
  _CourtPainter(this.court);
  final String court;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw on a 400×220 field, scaled to cover (like SVG "slice").
    const w = 400.0, h = 220.0;
    final scale =
        (size.width / w) > (size.height / h) ? size.width / w : size.height / h;
    canvas.save();
    canvas.translate(
        (size.width - w * scale) / 2, (size.height - h * scale) / 2);
    canvas.scale(scale);
    final paint = Paint()
      ..color = const Color(0x12FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final net = Paint()
      ..color = const Color(0x12FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    void line(double x1, double y1, double x2, double y2, [Paint? pt]) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), pt ?? paint);
    void dashed(double x1, double y1, double x2, double y2) {
      const dash = 4.0, gap = 6.0;
      final len = (Offset(x2, y2) - Offset(x1, y1)).distance;
      final dx = (x2 - x1) / len, dy = (y2 - y1) / len;
      for (var d = 0.0; d < len; d += dash + gap) {
        final e = (d + dash).clamp(0.0, len);
        line(x1 + dx * d, y1 + dy * d, x1 + dx * e, y1 + dy * e);
      }
    }

    void rect(double x, double y, double rw, double rh, [double r = 0]) =>
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, rw, rh), Radius.circular(r)),
            paint);
    void dQuad(double edge, double depth, double top, double bottom) {
      // A "D" / arc from the goal line: edge x, bulging to depth x.
      final path = Path()
        ..moveTo(edge, top)
        ..quadraticBezierTo(depth, top, depth, (top + bottom) / 2)
        ..quadraticBezierTo(depth, bottom, edge, bottom);
      canvas.drawPath(path, paint);
    }

    switch (court) {
      case 'pitch':
        rect(16, 16, 368, 188, 6);
        line(200, 16, 200, 204);
        canvas.drawCircle(const Offset(200, 110), 30, paint);
        rect(16, 62, 50, 96);
        rect(334, 62, 50, 96);
        rect(16, 88, 18, 44);
        rect(366, 88, 18, 44);
      case 'hockey':
        rect(16, 16, 368, 188, 6);
        line(200, 16, 200, 204);
        dashed(108, 16, 108, 204);
        dashed(292, 16, 292, 204);
        dQuad(16, 76, 60, 160);
        dQuad(384, 324, 60, 160);
      case 'handball':
        rect(16, 16, 368, 188, 6);
        line(200, 16, 200, 204);
        dQuad(16, 70, 62, 158);
        dQuad(384, 330, 62, 158);
      case 'netball':
        rect(16, 16, 368, 188, 6);
        line(138.7, 16, 138.7, 204);
        line(261.3, 16, 261.3, 204);
        canvas.drawCircle(const Offset(200, 110), 12, paint);
        dQuad(16, 58, 70, 150);
        dQuad(384, 342, 70, 150);
      case 'basketball':
        rect(16, 16, 368, 188, 6);
        line(200, 16, 200, 204);
        canvas.drawCircle(const Offset(200, 110), 24, paint);
        rect(16, 84, 62, 52);
        rect(322, 84, 62, 52);
        dQuad(16, 118, 36, 184);
        dQuad(384, 282, 36, 184);
      case 'volleyball':
        rect(46, 16, 308, 188, 4);
        line(200, 10, 200, 210, net);
        line(148.7, 16, 148.7, 204);
        line(251.3, 16, 251.3, 204);
      case 'tennis':
        rect(16, 16, 368, 188, 2);
        line(16, 40, 384, 40);
        line(16, 180, 384, 180);
        line(200, 10, 200, 210, net);
        line(112, 40, 112, 180);
        line(288, 40, 288, 180);
        line(112, 110, 288, 110);
      case 'rugby':
        rect(16, 16, 368, 188, 4);
        line(36, 16, 36, 204);
        line(364, 16, 364, 204);
        line(200, 16, 200, 204);
        line(104, 16, 104, 204);
        line(296, 16, 296, 204);
        dashed(168, 16, 168, 204);
        dashed(232, 16, 232, 204);
      case 'gridiron':
        rect(16, 16, 368, 188, 4);
        line(46, 16, 46, 204);
        line(354, 16, 354, 204);
        for (var i = 1; i < 10; i++) {
          final x = 46 + i * 308 / 10;
          if (i == 5) {
            line(x, 16, x, 204);
          } else {
            dashed(x, 16, x, 204);
          }
        }
      case 'cricket':
        canvas.drawOval(
            Rect.fromCenter(
                center: const Offset(200, 110), width: 368, height: 192),
            paint);
        rect(170, 100, 60, 20, 2);
      case 'diamond':
        final d = Path()
          ..moveTo(200, 196)
          ..lineTo(120, 116)
          ..lineTo(200, 36)
          ..lineTo(280, 116)
          ..close();
        canvas.drawPath(d, paint);
        dashed(200, 196, 40, 36);
        dashed(200, 196, 360, 36);
        canvas.drawCircle(const Offset(200, 120), 10, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CourtPainter old) => old.court != court;
}

/// A side's crest on the dark scoreboard: logo first, else the kit colour.
class ScoreCrest extends ConsumerWidget {
  const ScoreCrest({
    super.key,
    required this.name,
    required this.color,
    this.logoUrl,
    required this.size,
    required this.radius,
    this.won = false,
    required this.outline,
  });

  final String name;

  /// The kit colour for this game (null when none was set).
  final Color? color;
  final String? logoUrl;
  final double size;
  final double radius;
  final bool won;

  /// The scoreboard background — separates the shirt from the crest.
  final Color outline;

  static const _mint = Color(0xFF6EDC9E);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var url = logoUrl;
    if (url != null && url.startsWith('/')) {
      url = '${ref.watch(appConfigProvider).apiBaseUrl}$url';
    }
    final border = won ? Border.all(color: _mint, width: 2.5) : null;
    final tile = _colourTile(border);
    if (url == null || url.isEmpty) return tile;

    final shirt = (size * 0.4).roundToDouble();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          padding: EdgeInsets.all(size * 0.1),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
            border: border,
          ),
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        if (color != null)
          Positioned(
            right: -shirt * 0.3,
            bottom: -shirt * 0.25,
            child: Semantics(
              label: '$name kit colour',
              child: KitShirt(color: color!, size: shirt, outline: outline),
            ),
          ),
      ]),
    );
  }

  Widget _colourTile(BoxBorder? border) {
    final bg = color ?? const Color(0xFF888888);
    final fg =
        bg.computeLuminance() > 0.6 ? const Color(0xFF0E1411) : Colors.white;
    final words =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty
        ? '?'
        : words.length == 1
            ? words.first
                .substring(0, words.first.length >= 2 ? 2 : 1)
                .toUpperCase()
            : (words[0][0] + words[1][0]).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: border,
      ),
      child: Text(initials,
          style: TextStyle(
              color: fg,
              fontSize: (size * 0.3).roundToDouble(),
              fontWeight: FontWeight.w800)),
    );
  }
}

/// A small football shirt filled with the kit colour.
class KitShirt extends StatelessWidget {
  const KitShirt(
      {super.key, required this.color, this.size = 20, required this.outline});
  final Color color;
  final double size;
  final Color outline;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _ShirtPainter(color, outline),
      );
}

class _ShirtPainter extends CustomPainter {
  _ShirtPainter(this.color, this.outline);
  final Color color;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    // Same outline as the web KitShirt (24×24).
    final path = Path()
      ..moveTo(8.2 * s, 2.5 * s)
      ..lineTo(3.4 * s, 4.6 * s)
      ..lineTo(0.9 * s, 9.3 * s)
      ..lineTo(4.2 * s, 11.2 * s)
      ..lineTo(5.3 * s, 10.0 * s)
      ..lineTo(5.3 * s, 21.5 * s)
      ..lineTo(18.7 * s, 21.5 * s)
      ..lineTo(18.7 * s, 10.0 * s)
      ..lineTo(19.8 * s, 11.2 * s)
      ..lineTo(23.1 * s, 9.3 * s)
      ..lineTo(20.6 * s, 4.6 * s)
      ..lineTo(15.8 * s, 2.5 * s)
      ..cubicTo(15.4 * s, 4.2 * s, 13.8 * s, 5.4 * s, 12 * s, 5.4 * s)
      ..cubicTo(10.2 * s, 5.4 * s, 8.6 * s, 4.2 * s, 8.2 * s, 2.5 * s)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
        path,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * s
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_ShirtPainter old) =>
      old.color != color || old.outline != outline;
}
