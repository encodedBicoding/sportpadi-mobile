import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/features/sports/sport_theme.dart';

/// The sport's hero artwork (design §4, §8), drawn in code: a two-stop gradient
/// with the sport's playing surface in faint white lines on top.
///
/// Fills its parent — put it in a `Positioned.fill` (or any box with a
/// bounded size). The same artwork paints the record hero, the sport cards
/// and the dark summary card on the group / event / tournament record pages.
class SportArtworkBox extends StatelessWidget {
  const SportArtworkBox({
    super.key,
    required this.family,
    this.emoji,
    this.dense = false,
  });
  final SportFamily family;

  /// The category's emoji — the generic design's watermark.
  final String? emoji;

  /// Smaller surfaces (sport cards): finer lines, simpler detail.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = sportTheme(family);
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: t.gradient),
        child: CustomPaint(
          painter: sportArtworkPainter(family,
              emoji: emoji ?? t.emoji, dense: dense),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// A dark panel painted with the sport's artwork, sized by its [child].
class SportArtPanel extends StatelessWidget {
  const SportArtPanel({
    super.key,
    required this.family,
    required this.child,
    this.emoji,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.padding = const EdgeInsets.all(18),
    this.dense = false,
  });
  final SportFamily family;
  final String? emoji;
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsets padding;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: Stack(children: [
        Positioned.fill(
          child: SportArtworkBox(family: family, emoji: emoji, dense: dense),
        ),
        Padding(padding: padding, child: child),
      ]),
    );
  }
}

CustomPainter sportArtworkPainter(SportFamily family,
        {required String emoji, bool dense = false}) =>
    switch (family) {
      SportFamily.soccer => _PitchPainter(dense),
      SportFamily.basketball => _HardwoodPainter(dense),
      SportFamily.volleyball => _BeachPainter(dense),
      SportFamily.baseball => _DiamondPainter(dense),
      SportFamily.tennis => _HardCourtPainter(dense),
      SportFamily.padel => _GlassCourtPainter(dense),
      SportFamily.tableTennis => _TablePainter(dense),
      SportFamily.chess => _BoardPainter(dense),
      SportFamily.ultimate => _FieldPainter(dense),
      SportFamily.golf => _FairwayPainter(dense),
      SportFamily.hiking => _TrailPainter(dense),
      SportFamily.running => _TrackPainter(dense),
      SportFamily.paintball => _ArenaPainter(dense),
      SportFamily.generic => _GenericPainter(emoji, dense),
    };

// ── Shared ──────────────────────────────────────────────────────────────────

Paint _stroke(double width, int alpha) => Paint()
  ..color = Color.fromARGB(alpha, 255, 255, 255)
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..isAntiAlias = true;

Paint _fill(Color c) => Paint()
  ..color = c
  ..style = PaintingStyle.fill;

/// A soft darkening towards the edges, so text and lines sit on depth rather
/// than on a flat poster.
void _vignette(Canvas canvas, Size size) {
  final rect = Offset.zero & size;
  canvas.drawRect(
    rect,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.2, -0.4),
        radius: 1.25,
        colors: [Color(0x00000000), Color(0x38000000)],
      ).createShader(rect),
  );
}

/// White ~20% lines, a touch heavier on big surfaces.
double _lineWidth(Size size, bool dense) =>
    dense ? 1.1 : math.max(1.3, math.min(size.height, size.width) / 190);

abstract class _ArtPainter extends CustomPainter {
  const _ArtPainter(this.dense);
  final bool dense;

  @override
  bool shouldRepaint(covariant _ArtPainter old) =>
      old.runtimeType != runtimeType || old.dense != dense;
}

// ── Soccer: "Pitch" ─────────────────────────────────────────────────────────

class _PitchPainter extends _ArtPainter {
  const _PitchPainter(super.dense);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;

    // Six mowing stripes, alternate ones +4% white.
    final stripe = _fill(const Color(0x0AFFFFFF));
    final sw = w / 6;
    for (var i = 1; i < 6; i += 2) {
      canvas.drawRect(Rect.fromLTWH(i * sw, 0, sw, h), stripe);
    }
    _vignette(canvas, size);

    final line = _stroke(_lineWidth(size, dense), 56);
    final dot = _fill(const Color(0x47FFFFFF));
    final m = (h * 0.08).clamp(8.0, 18.0);
    final r = Rect.fromLTRB(m, m, w - m, h - m);
    final cx = w / 2, cy = h / 2, ph = r.height;

    canvas.drawRect(r, line);
    canvas.drawLine(Offset(cx, r.top), Offset(cx, r.bottom), line);
    canvas.drawCircle(Offset(cx, cy), ph * 0.2, line);
    canvas.drawCircle(Offset(cx, cy), dense ? 1.8 : 2.6, dot);

    // Both ends: penalty box, 6-yard box, spot, the "D", the goal.
    final boxW = math.min(r.width * 0.15, ph * 0.36);
    final boxH = ph * 0.6;
    final sixW = boxW * 0.38;
    final sixH = ph * 0.3;
    final dR = boxW * 0.5;
    final dA = math.acos(0.56); // where the D leaves the box edge
    for (final left in [true, false]) {
      final x0 = left ? r.left : r.right;
      final dir = left ? 1.0 : -1.0;
      canvas.drawRect(
          Rect.fromPoints(Offset(x0, cy - boxH / 2),
              Offset(x0 + dir * boxW, cy + boxH / 2)),
          line);
      canvas.drawRect(
          Rect.fromPoints(Offset(x0, cy - sixH / 2),
              Offset(x0 + dir * sixW, cy + sixH / 2)),
          line);
      final spot = Offset(x0 + dir * boxW * 0.72, cy);
      canvas.drawCircle(spot, dense ? 1.5 : 2.2, dot);
      canvas.drawArc(Rect.fromCircle(center: spot, radius: dR),
          left ? -dA : math.pi - dA, 2 * dA, false, line);
      final goalDepth = math.min(m * 0.7, 8.0);
      canvas.drawRect(
          Rect.fromPoints(Offset(x0, cy - ph * 0.09),
              Offset(x0 - dir * goalDepth, cy + ph * 0.09)),
          line);
    }

    // Corner arcs.
    final cr = math.max(4.0, ph * 0.045);
    canvas.drawArc(Rect.fromCircle(center: r.topLeft, radius: cr), 0,
        math.pi / 2, false, line);
    canvas.drawArc(Rect.fromCircle(center: r.topRight, radius: cr),
        math.pi / 2, math.pi / 2, false, line);
    canvas.drawArc(Rect.fromCircle(center: r.bottomRight, radius: cr),
        math.pi, math.pi / 2, false, line);
    canvas.drawArc(Rect.fromCircle(center: r.bottomLeft, radius: cr),
        -math.pi / 2, math.pi / 2, false, line);
  }
}

// ── Basketball: "Hardwood" ──────────────────────────────────────────────────

class _HardwoodPainter extends _ArtPainter {
  const _HardwoodPainter(super.dense);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;

    // Planks: thin vertical lines with staggered butt joints.
    final plank = _stroke(1, 15); // white 6%
    final pw = math.max(14.0, w / 22);
    var col = 0;
    for (var x = pw; x < w; x += pw) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), plank);
      final j = ((col * 37) % 100) / 100 * h;
      canvas.drawLine(Offset(x - pw, j), Offset(x, j), plank);
      canvas.drawLine(
          Offset(x - pw, (j + h * 0.5) % h), Offset(x, (j + h * 0.5) % h), plank);
      col++;
    }
    _vignette(canvas, size);

    final line = _stroke(_lineWidth(size, dense), 56);
    final s = h; // the court scales with the height
    final m = (h * 0.07).clamp(6.0, 16.0);
    final bx = w - m; // baseline, on the right
    final hy = h / 2;

    // Sidelines, baseline and the half-court line with its circle.
    final halfX = math.max(m, bx - s * 0.95);
    canvas.drawLine(Offset(halfX, m), Offset(bx, m), line);
    canvas.drawLine(Offset(halfX, h - m), Offset(bx, h - m), line);
    canvas.drawLine(Offset(bx, m), Offset(bx, h - m), line);
    if (halfX > m) {
      canvas.drawLine(Offset(halfX, m), Offset(halfX, h - m), line);
    }
    canvas.drawCircle(Offset(halfX, hy), s * 0.17, line);

    // The key (lane) and the free-throw circle.
    final keyLen = s * 0.4;
    final laneW = s * 0.34;
    canvas.drawRect(
        Rect.fromLTRB(bx - keyLen, hy - laneW / 2, bx, hy + laneW / 2), line);
    canvas.drawCircle(Offset(bx - keyLen, hy), laneW / 2, line);

    // Hoop, backboard, restricted area.
    final hx = bx - s * 0.1;
    canvas.drawLine(Offset(bx - s * 0.055, hy - s * 0.085),
        Offset(bx - s * 0.055, hy + s * 0.085), _stroke(line.strokeWidth * 1.6, 82));
    canvas.drawLine(Offset(bx - s * 0.055, hy), Offset(hx + s * 0.035, hy), line);
    canvas.drawCircle(Offset(hx, hy), s * 0.035, _stroke(line.strokeWidth * 1.3, 92));
    canvas.drawArc(Rect.fromCircle(center: Offset(hx, hy), radius: s * 0.11),
        math.pi / 2, math.pi, false, line);

    // Three-point line: corner straights joined by the arc.
    final r3 = s * 0.47;
    const k = 0.9; // corner offset as a share of the radius
    final a = math.asin(k);
    // From the bottom corner (π − a) clockwise round the far side to the
    // top corner (π + a).
    canvas.drawArc(Rect.fromCircle(center: Offset(hx, hy), radius: r3),
        math.pi - a, 2 * a, false, line);
    final meetX = hx - r3 * math.cos(a);
    canvas.drawLine(Offset(meetX, hy - r3 * k), Offset(bx, hy - r3 * k), line);
    canvas.drawLine(Offset(meetX, hy + r3 * k), Offset(bx, hy + r3 * k), line);
  }
}

// ── Volleyball: "Beach" ─────────────────────────────────────────────────────

class _BeachPainter extends _ArtPainter {
  const _BeachPainter(super.dense);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;

    // Late sun, top right.
    final sun = Offset(w * 0.86, h * 0.1);
    final sunRect = Rect.fromCircle(center: sun, radius: h * 0.55);
    canvas.drawCircle(
      sun,
      h * 0.55,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x40FDE68A), Color(0x00FDE68A)],
        ).createShader(sunRect),
    );

    // Sand along the bottom, with a soft wave and a little grain.
    final sandTop = h * 0.74;
    final sand = Path()
      ..moveTo(0, sandTop)
      ..quadraticBezierTo(w * 0.25, sandTop - h * 0.05, w * 0.5, sandTop)
      ..quadraticBezierTo(w * 0.75, sandTop + h * 0.05, w, sandTop - h * 0.01)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(sand, _fill(const Color(0x40E9C46A)));
    final grain = _fill(const Color(0x22FFFFFF));
    final rnd = math.Random(7);
    final grains = dense ? 26 : 60;
    for (var i = 0; i < grains; i++) {
      final gx = rnd.nextDouble() * w;
      final gy = sandTop + h * 0.04 + rnd.nextDouble() * (h - sandTop);
      canvas.drawCircle(Offset(gx, gy), 0.6 + rnd.nextDouble() * 0.9, grain);
    }
    _vignette(canvas, size);

    final line = _stroke(_lineWidth(size, dense), 56);

    // Court lines in perspective, the near half below the net.
    final floorY = h * 0.47;
    canvas.drawLine(Offset(w * 0.24, floorY), Offset(w * 0.76, floorY), line);
    canvas.drawLine(Offset(w * 0.24, floorY), Offset(w * 0.02, h), line);
    canvas.drawLine(Offset(w * 0.76, floorY), Offset(w * 0.98, h), line);
    canvas.drawLine(
        Offset(w * 0.19, h * 0.6), Offset(w * 0.81, h * 0.6), _stroke(line.strokeWidth, 36));

    // The net across the upper third: posts, a mesh band, the top tape.
    final top = h * 0.17, bottom = h * 0.35;
    final postL = w * 0.05, postR = w * 0.95;
    final post = _stroke(math.max(2.0, line.strokeWidth * 1.8), 72);
    canvas.drawLine(Offset(postL, top - h * 0.05), Offset(postL, floorY + h * 0.06), post);
    canvas.drawLine(Offset(postR, top - h * 0.05), Offset(postR, floorY + h * 0.06), post);

    canvas.save();
    canvas.clipRect(Rect.fromLTRB(postL, top, postR, bottom));
    final mesh = _stroke(dense ? 0.6 : 0.8, 38);
    final band = bottom - top;
    final gap = math.max(7.0, h * 0.04);
    for (var d = postL - band; d < postR; d += gap) {
      canvas.drawLine(Offset(d, bottom), Offset(d + band, top), mesh);
      canvas.drawLine(Offset(d, top), Offset(d + band, bottom), mesh);
    }
    canvas.restore();
    canvas.drawLine(Offset(postL, top), Offset(postR, top),
        _stroke(math.max(2.4, h * 0.014), 96));
    canvas.drawLine(
        Offset(postL, bottom), Offset(postR, bottom), _stroke(line.strokeWidth, 52));
  }
}

// ── Baseball: "Diamond" ─────────────────────────────────────────────────────

class _DiamondPainter extends _ArtPainter {
  const _DiamondPainter(super.dense);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final cx = w * (dense ? 0.72 : 0.66);
    final hy = h * 0.94; // home plate
    final d = h * 0.28; // home → first, along each axis
    final home = Offset(cx, hy);
    final first = Offset(cx + d, hy - d);
    final second = Offset(cx, hy - 2 * d);
    final third = Offset(cx - d, hy - d);

    // Infield dirt arc.
    canvas.drawCircle(Offset(cx, hy - d), d * 1.32, _fill(const Color(0x33B45309)));
    canvas.drawCircle(home, d * 0.26, _fill(const Color(0x33B45309)));
    _vignette(canvas, size);

    final line = _stroke(_lineWidth(size, dense), 56);

    // Foul lines running out, and the outfield fence arc between them.
    final run = (w + h) * 1.2;
    canvas.drawLine(home, Offset(cx + run, hy - run), line);
    canvas.drawLine(home, Offset(cx - run, hy - run), line);
    canvas.drawArc(Rect.fromCircle(center: home, radius: d * 2.9),
        -3 * math.pi / 4, math.pi / 2, false, line);
    canvas.drawArc(Rect.fromCircle(center: home, radius: d * 2.05),
        -3 * math.pi / 4, math.pi / 2, false, _stroke(line.strokeWidth, 26));

    // The diamond itself.
    canvas.drawPath(
        Path()
          ..moveTo(home.dx, home.dy)
          ..lineTo(first.dx, first.dy)
          ..lineTo(second.dx, second.dy)
          ..lineTo(third.dx, third.dy)
          ..close(),
        line);

    // Pitcher's mound + rubber.
    final mound = Offset(cx, hy - d * 0.95);
    canvas.drawCircle(mound, d * 0.15, line);
    canvas.drawRect(
        Rect.fromCenter(center: mound, width: d * 0.1, height: d * 0.025),
        _fill(const Color(0x66FFFFFF)));

    // Bases (squares rotated 45°) and home plate.
    final base = _fill(const Color(0x66FFFFFF));
    final b = math.max(3.0, d * 0.055);
    for (final o in [first, second, third]) {
      canvas.drawPath(
          Path()
            ..moveTo(o.dx, o.dy - b)
            ..lineTo(o.dx + b, o.dy)
            ..lineTo(o.dx, o.dy + b)
            ..lineTo(o.dx - b, o.dy)
            ..close(),
          base);
    }
    canvas.drawPath(
        Path()
          ..moveTo(cx - b, hy - b)
          ..lineTo(cx + b, hy - b)
          ..lineTo(cx + b, hy)
          ..lineTo(cx, hy + b)
          ..lineTo(cx - b, hy)
          ..close(),
        base);
  }
}

// ── Everything else ─────────────────────────────────────────────────────────

class _GenericPainter extends _ArtPainter {
  const _GenericPainter(this.emoji, super.dense);
  final String emoji;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;

    // Soft diagonal lines.
    final diag = _stroke(1, 13);
    final gap = dense ? 18.0 : 24.0;
    for (var x = -h; x < w; x += gap) {
      canvas.drawLine(Offset(x, h), Offset(x + h, 0), diag);
    }
    _vignette(canvas, size);

    // The sport's emoji, very large, bottom right, at 12%.
    final tp = TextPainter(
      text: TextSpan(text: emoji, style: TextStyle(fontSize: h * 0.82)),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.saveLayer(Offset.zero & size, Paint()..color = const Color(0x1F000000));
    canvas.translate(w - tp.width * 0.78, h - tp.height * 0.8);
    canvas.rotate(-0.18);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
    tp.dispose();
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) =>
      super.shouldRepaint(old) || (old is _GenericPainter && old.emoji != emoji);
}

// ── §8 helpers ──────────────────────────────────────────────────────────────

/// Draw in landscape: on a portrait box the canvas turns a quarter, so a
/// court's long axis always runs along the longer side. Returns the size to
/// draw in. Call between `save()` and `restore()`.
Size _landscape(Canvas canvas, Size size) {
  if (size.width >= size.height) return size;
  canvas.translate(size.width, 0);
  canvas.rotate(math.pi / 2);
  return Size(size.height, size.width);
}

/// [path] as dashes.
void _dashed(Canvas canvas, Path path, Paint paint,
    {double dash = 6, double gap = 5}) {
  for (final m in path.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
      d += dash + gap;
    }
  }
}

/// [path] as a row of dots.
void _dotted(Canvas canvas, Path path, Paint paint,
    {double every = 9, double radius = 1.3}) {
  for (final m in path.computeMetrics()) {
    for (var d = 0.0; d <= m.length; d += every) {
      final t = m.getTangentForOffset(d);
      if (t != null) canvas.drawCircle(t.position, radius, paint);
    }
  }
}

/// A court of [aspect] (length ÷ width) centred in [box], as big as fits
/// inside [margin].
Rect _courtIn(Size box, double aspect, double margin) {
  var len = box.width - 2 * margin;
  var wid = len / aspect;
  if (wid > box.height - 2 * margin) {
    wid = box.height - 2 * margin;
    len = wid * aspect;
  }
  return Rect.fromCenter(
      center: Offset(box.width / 2, box.height / 2), width: len, height: wid);
}

/// A net across a court at [x], with a post dot beyond each side.
void _net(Canvas canvas, Rect court, double x, double stroke, double over) {
  canvas.drawLine(Offset(x, court.top - over), Offset(x, court.bottom + over),
      _stroke(math.max(3.0, stroke * 2.6), 28));
  canvas.drawLine(Offset(x, court.top - over), Offset(x, court.bottom + over),
      _stroke(stroke * 1.25, 100));
  final post = _fill(const Color(0x8CFFFFFF));
  canvas.drawCircle(Offset(x, court.top - over), stroke * 1.7, post);
  canvas.drawCircle(Offset(x, court.bottom + over), stroke * 1.7, post);
}

// ── Tennis: "Hard court" ────────────────────────────────────────────────────

class _HardCourtPainter extends _ArtPainter {
  const _HardCourtPainter(super.dense);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    _vignette(canvas, size);
    final line = _stroke(_lineWidth(size, dense), 60);

    canvas.save();
    final land = _landscape(canvas, size);
    final m = (math.min(land.width, land.height) * 0.09).clamp(8.0, 22.0);
    // Doubles court, 23.77 × 10.97 m.
    final r = _courtIn(land, 23.77 / 10.97, m);
    final len = r.width, wid = r.height;
    final cx = r.center.dx, cy = r.center.dy;

    // The playing area a shade lighter than the run-off, as on a real court.
    canvas.drawRect(r, _fill(const Color(0x0DFFFFFF)));
    canvas.drawRect(r, line);

    // Singles sidelines (the tramlines inside the doubles court).
    final alley = wid * 1.37 / 10.97;
    final sTop = r.top + alley, sBot = r.bottom - alley;
    canvas.drawLine(Offset(r.left, sTop), Offset(r.right, sTop), line);
    canvas.drawLine(Offset(r.left, sBot), Offset(r.right, sBot), line);

    // Service lines 6.40 m either side of the net, and the centre line.
    final svc = len * 6.40 / 23.77;
    canvas.drawLine(Offset(cx - svc, sTop), Offset(cx - svc, sBot), line);
    canvas.drawLine(Offset(cx + svc, sTop), Offset(cx + svc, sBot), line);
    canvas.drawLine(Offset(cx - svc, cy), Offset(cx + svc, cy), line);

    // Centre marks on the baselines.
    final tick = math.max(3.0, len * 0.014);
    canvas.drawLine(Offset(r.left, cy), Offset(r.left + tick, cy), line);
    canvas.drawLine(Offset(r.right, cy), Offset(r.right - tick, cy), line);

    _net(canvas, r, cx, line.strokeWidth, math.max(4.0, wid * 0.06));
    canvas.restore();

    // A ball, in screen space so it never turns with the court.
    final br = dense ? 6.5 : (math.min(w, h) * 0.04).clamp(9.0, 15.0);
    _tennisBall(canvas, Offset(w * (dense ? 0.9 : 0.84), h * (dense ? 0.24 : 0.2)),
        br, const Color(0xBFD9F99D));
  }
}

/// A tennis ball with its seam.
void _tennisBall(Canvas canvas, Offset c, double r, Color color) {
  canvas.drawCircle(c, r, _fill(color));
  canvas.save();
  canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
  final seam = _stroke(math.max(1.0, r * 0.14), 165);
  canvas.drawCircle(c.translate(-r * 1.25, 0), r * 0.85, seam);
  canvas.drawCircle(c.translate(r * 1.25, 0), r * 0.85, seam);
  canvas.restore();
}

// ── Padel: "Glass court" ────────────────────────────────────────────────────

class _GlassCourtPainter extends _ArtPainter {
  const _GlassCourtPainter(super.dense);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _vignette(canvas, size);
    final line = _stroke(_lineWidth(size, dense), 60);

    canvas.save();
    final land = _landscape(canvas, size);
    final m = (math.min(land.width, land.height) * 0.1).clamp(10.0, 24.0);
    // 20 × 10 m, walls all round.
    final r = _courtIn(land, 2, m);
    final len = r.width, wid = r.height;
    final cx = r.center.dx, cy = r.center.dy;
    final t = math.max(4.0, wid * 0.06); // wall thickness, as drawn
    final corner = len * 4 / 20; // side glass: 4 m of each side
    final glass = _fill(const Color(0x1AFFFFFF)); // white 10%
    final frame = _stroke(1, 50);

    canvas.drawRect(r, _fill(const Color(0x0AFFFFFF)));

    for (final left in [true, false]) {
      // Back wall: glass the full width of the end, in panels.
      final wall = Rect.fromLTWH(
          left ? r.left - t : r.right, r.top - t, t, wid + 2 * t);
      canvas.drawRect(wall, glass);
      canvas.drawRect(wall, frame);
      for (var i = 1; i < 5; i++) {
        final y = wall.top + wall.height * i / 5;
        canvas.drawLine(Offset(wall.left, y), Offset(wall.right, y), frame);
      }
      // Side glass in the corners, two panels each.
      for (final top in [true, false]) {
        final side = Rect.fromLTWH(left ? r.left : r.right - corner,
            top ? r.top - t : r.bottom, corner, t);
        canvas.drawRect(side, glass);
        canvas.drawRect(side, frame);
        canvas.drawLine(Offset(side.center.dx, side.top),
            Offset(side.center.dx, side.bottom), frame);
      }
    }

    // Mesh fence along the middle of both sides.
    final mesh = _stroke(0.7, 34);
    final gap = math.max(3.0, t * 0.7);
    for (final top in [true, false]) {
      final band = Rect.fromLTWH(
          r.left + corner, top ? r.top - t : r.bottom, len - 2 * corner, t);
      canvas.save();
      canvas.clipRect(band);
      for (var d = band.left - t; d < band.right; d += gap) {
        canvas.drawLine(Offset(d, band.bottom), Offset(d + t, band.top), mesh);
        canvas.drawLine(Offset(d, band.top), Offset(d + t, band.bottom), mesh);
      }
      canvas.restore();
      canvas.drawRect(band, frame);
    }

    // Court lines: service lines 6.95 m from the net, the centre line.
    canvas.drawRect(r, line);
    final svc = len * 6.95 / 20;
    canvas.drawLine(Offset(cx - svc, r.top), Offset(cx - svc, r.bottom), line);
    canvas.drawLine(Offset(cx + svc, r.top), Offset(cx + svc, r.bottom), line);
    canvas.drawLine(Offset(cx - svc, cy), Offset(cx + svc, cy), line);

    _net(canvas, r, cx, line.strokeWidth, t);
    canvas.restore();
  }
}

// ── Ping pong: "Table" ──────────────────────────────────────────────────────

class _TablePainter extends _ArtPainter {
  const _TablePainter(super.dense);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    _vignette(canvas, size);
    final line = _stroke(_lineWidth(size, dense), 60);

    canvas.save();
    final land = _landscape(canvas, size);
    final m = (math.min(land.width, land.height) * 0.17).clamp(14.0, 52.0);
    // 2.74 × 1.525 m.
    final r = _courtIn(land, 2.74 / 1.525, m);
    canvas.drawRect(r, _fill(const Color(0x0FFFFFFF)));
    // The white edge lines, the centre line, the net.
    canvas.drawRect(r, _stroke(line.strokeWidth * 1.6, 84));
    canvas.drawLine(Offset(r.left, r.center.dy), Offset(r.right, r.center.dy),
        _stroke(line.strokeWidth * 0.8, 46));
    _net(canvas, r, r.center.dx, line.strokeWidth, r.height * 0.08);
    canvas.restore();

    // Two paddles (red and black, 25%) and the ball.
    final pr = math.min(w, h) * (dense ? 0.2 : 0.13);
    _paddle(canvas, Offset(w * 0.9, h * (dense ? 0.62 : 0.56)), pr, -0.7,
        const Color(0x40DC2626));
    _paddle(canvas, Offset(w * 0.08, h * 0.92), pr * 0.92, 2.5,
        const Color(0x40000000));
    canvas.drawCircle(Offset(w * 0.72, h * 0.3), math.max(2.5, pr * 0.11),
        _fill(const Color(0xCCF97316)));
  }
}

/// A table-tennis bat: a round blade and a handle, as one silhouette.
void _paddle(Canvas canvas, Offset c, double r, double angle, Color color) {
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(angle);
  final shape = Path()
    ..addOval(Rect.fromCircle(center: Offset.zero, radius: r))
    ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(-r * 0.19, r * 0.8, r * 0.38, r * 0.95),
        Radius.circular(r * 0.12)));
  canvas.drawPath(shape, _fill(color));
  canvas.restore();
}

// ── Chess: "Board" ──────────────────────────────────────────────────────────

class _BoardPainter extends _ArtPainter {
  const _BoardPainter(super.dense);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;

    // 8 × 8 squares anchored bottom right, fading in from that corner:
    // light squares up to 8% white, dark squares clear.
    final s = h / (dense ? 5.5 : 6);
    final reach = math.min(8 * s, math.sqrt(w * w + h * h)) * 1.05;
    for (var row = 0; row < 8; row++) {
      for (var col = 0; col < 8; col++) {
        if ((row + col).isOdd) continue;
        final rect = Rect.fromLTWH(w - (col + 1) * s, h - (row + 1) * s, s, s);
        if (rect.right < 0 || rect.bottom < 0) continue;
        final d = (Offset(w, h) - rect.center).distance;
        final fade = math.pow((1 - d / reach).clamp(0.0, 1.0), 1.3).toDouble();
        if (fade <= 0) continue;
        canvas.drawRect(
            rect, _fill(Color.fromARGB((20 * fade).round(), 255, 255, 255)));
      }
    }
    _vignette(canvas, size);

    // A large faint knight, bottom right.
    final tp = TextPainter(
      text: TextSpan(
          text: '♞',
          style: TextStyle(
              fontSize: h * (dense ? 0.95 : 0.78),
              height: 1,
              color: const Color(0x24F5D08A))),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(w - tp.width * 0.92, h - tp.height * 0.9));
    tp.dispose();
  }
}

// ── Ultimate: "Field" ───────────────────────────────────────────────────────

class _FieldPainter extends _ArtPainter {
  const _FieldPainter(super.dense);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;

    // Faint mowing stripes.
    final stripe = _fill(const Color(0x08FFFFFF));
    final sw = w / 10;
    for (var i = 1; i < 10; i += 2) {
      canvas.drawRect(Rect.fromLTWH(i * sw, 0, sw, h), stripe);
    }

    final m = (h * 0.08).clamp(8.0, 18.0);
    final r = Rect.fromLTRB(m, m, w - m, h - m);
    final cy = r.center.dy;
    // End zones (18 of 100 m) a shade darker at both ends.
    final ez = r.width * 0.18;
    final shade = _fill(const Color(0x26000000));
    canvas.drawRect(Rect.fromLTWH(r.left, r.top, ez, r.height), shade);
    canvas.drawRect(Rect.fromLTWH(r.right - ez, r.top, ez, r.height), shade);
    _vignette(canvas, size);

    final line = _stroke(_lineWidth(size, dense), 56);
    canvas.drawRect(r, line);
    canvas.drawLine(
        Offset(r.left + ez, r.top), Offset(r.left + ez, r.bottom), line);
    canvas.drawLine(
        Offset(r.right - ez, r.top), Offset(r.right - ez, r.bottom), line);

    // Brick marks: crosses on the middle line, 18 m out from each goal line.
    final b = math.max(3.0, h * 0.02);
    for (final x in [r.left + ez + r.width * 0.18, r.right - ez - r.width * 0.18]) {
      canvas.drawLine(Offset(x - b, cy - b), Offset(x + b, cy + b), line);
      canvas.drawLine(Offset(x - b, cy + b), Offset(x + b, cy - b), line);
    }

    // The disc in flight along a dashed arc.
    final start = Offset(w * 0.16, h * 0.84);
    final end = Offset(w * 0.8, h * 0.32);
    final flight = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(w * 0.4, h * 0.02, end.dx, end.dy);
    _dashed(canvas, flight, _stroke(line.strokeWidth, 92),
        dash: dense ? 4 : 6, gap: dense ? 4 : 6);
    final dr = (math.min(w, h) * 0.06).clamp(6.0, 18.0);
    canvas.save();
    canvas.translate(end.dx, end.dy);
    canvas.rotate(-0.35);
    final disc = Rect.fromCenter(center: Offset.zero, width: dr * 2.3, height: dr * 1.05);
    canvas.drawOval(disc, _fill(const Color(0xCCFEF08A)));
    canvas.drawOval(
        disc.deflate(dr * 0.28),
        Paint()
          ..color = const Color(0x33000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);
    canvas.restore();
  }
}

// ── Golf: "Fairway" ─────────────────────────────────────────────────────────

class _FairwayPainter extends _ArtPainter {
  const _FairwayPainter(super.dense);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final s = math.min(w, h);
    final green = Offset(w * 0.78, h * (dense ? 0.38 : 0.32));
    final gr = s * (dense ? 0.17 : 0.13);

    // The fairway: a broad lighter band curving up to the green.
    final fairway = Path()
      ..moveTo(w * 0.02, h * 1.08)
      ..cubicTo(w * 0.34, h * 0.78, w * 0.32, h * 0.46, green.dx, green.dy);
    canvas.drawPath(
        fairway,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = s * 0.34
          ..color = const Color(0x12FFFFFF));
    canvas.drawPath(
        fairway,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = s * 0.16
          ..color = const Color(0x0AFFFFFF));
    _vignette(canvas, size);

    // The green with its fringe.
    canvas.drawCircle(green, gr * 1.2, _fill(const Color(0x0FFFFFFF)));
    canvas.drawCircle(green, gr, _fill(const Color(0x1CFFFFFF)));
    canvas.drawCircle(green, gr, _stroke(_lineWidth(size, dense), 44));

    // A sand bunker short-left of the green.
    canvas.save();
    canvas.translate(green.dx - gr * 1.45, green.dy + gr * 1.1);
    canvas.rotate(-0.45);
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: gr * 1.4, height: gr * 0.7),
        _fill(const Color(0x4DE9C46A)));
    canvas.restore();

    // Dotted ball path from the tee to the hole.
    final hole = green.translate(gr * 0.15, gr * 0.12);
    final tee = Offset(w * 0.12, h * 0.9);
    final shot = Path()
      ..moveTo(tee.dx, tee.dy)
      ..quadraticBezierTo(w * 0.28, h * 0.12, hole.dx - gr * 0.45, hole.dy + gr * 0.1);
    _dotted(canvas, shot, _fill(const Color(0x80FFFFFF)),
        every: dense ? 7 : 9, radius: dense ? 1.0 : 1.4);
    canvas.drawCircle(tee, dense ? 2.4 : 3.4, _fill(const Color(0xCCFFFFFF)));

    // The hole, the flagstick and its pennant.
    canvas.drawCircle(
        hole, math.max(1.6, gr * 0.07), _fill(const Color(0x73000000)));
    final stick = gr * 1.75;
    final top = hole.translate(0, -stick);
    canvas.drawLine(
        hole, top, _stroke(math.max(1.2, _lineWidth(size, dense)), 170));
    canvas.drawPath(
        Path()
          ..moveTo(top.dx, top.dy)
          ..lineTo(top.dx + stick * 0.44, top.dy + stick * 0.13)
          ..lineTo(top.dx, top.dy + stick * 0.27)
          ..close(),
        _fill(const Color(0xE6FACC15)));
  }
}

// ── Hiking: "Trail" ─────────────────────────────────────────────────────────

class _TrailPainter extends _ArtPainter {
  const _TrailPainter(super.dense);

  static const _back = [
    (0.0, 0.6), (0.12, 0.47), (0.24, 0.55), (0.4, 0.28), (0.55, 0.48), //
    (0.7, 0.34), (0.86, 0.5), (1.0, 0.4),
  ];
  static const _mid = [
    (0.0, 0.72), (0.18, 0.55), (0.3, 0.64), (0.48, 0.45), (0.62, 0.6), //
    (0.8, 0.5), (1.0, 0.62),
  ];
  static const _front = [
    (0.0, 0.86), (0.2, 0.76), (0.38, 0.82), (0.66, 0.52), (0.84, 0.7), //
    (1.0, 0.78),
  ];
  // Zig-zags up the front ridge to its summit (0.66, 0.52).
  static const _trail = [
    (0.46, 1.02), (0.6, 0.92), (0.5, 0.84), (0.64, 0.76), (0.56, 0.69), //
    (0.66, 0.6), (0.66, 0.53),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    Offset at((double, double) p) => Offset(p.$1 * w, p.$2 * h);
    Path ridgeLine(List<(double, double)> pts) {
      final path = Path()..moveTo(at(pts.first).dx, at(pts.first).dy);
      for (final p in pts.skip(1)) {
        path.lineTo(at(p).dx, at(p).dy);
      }
      return path;
    }

    Path mountain(List<(double, double)> pts) => ridgeLine(pts)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    // A small sun with a soft glow.
    final sun = Offset(w * 0.8, h * (dense ? 0.24 : 0.18));
    final sr = math.min(w, h) * (dense ? 0.08 : 0.06);
    final glow = Rect.fromCircle(center: sun, radius: sr * 3.2);
    canvas.drawCircle(
        sun,
        sr * 3.2,
        Paint()
          ..shader = const RadialGradient(
                  colors: [Color(0x33FDE68A), Color(0x00FDE68A)])
              .createShader(glow));
    canvas.drawCircle(sun, sr, _fill(const Color(0x8CFDE68A)));

    // Three ridges, the farthest palest, the nearest darkest.
    canvas.drawPath(mountain(_back), _fill(const Color(0x14FFFFFF)));
    canvas.drawPath(ridgeLine(_back), _stroke(_lineWidth(size, dense), 40));
    canvas.drawPath(mountain(_mid), _fill(const Color(0x1F000000)));
    canvas.drawPath(ridgeLine(_mid), _stroke(_lineWidth(size, dense), 30));
    canvas.drawPath(mountain(_front), _fill(const Color(0x47000000)));
    canvas.drawPath(ridgeLine(_front), _stroke(_lineWidth(size, dense), 26));
    _vignette(canvas, size);

    // The switchback trail, dashed, and a flag on the summit.
    _dashed(canvas, ridgeLine(_trail),
        _stroke(_lineWidth(size, dense) * 1.15, 115),
        dash: dense ? 3.5 : 5, gap: dense ? 3 : 4);
    final peak = at(_front[3]);
    final pole = h * (dense ? 0.1 : 0.07);
    canvas.drawLine(peak, peak.translate(0, -pole), _stroke(1.2, 150));
    canvas.drawPath(
        Path()
          ..moveTo(peak.dx, peak.dy - pole)
          ..lineTo(peak.dx + pole * 0.6, peak.dy - pole * 0.82)
          ..lineTo(peak.dx, peak.dy - pole * 0.64)
          ..close(),
        _fill(const Color(0xCCFDE68A)));
  }
}

// ── Running: "Track" ────────────────────────────────────────────────────────

class _TrackPainter extends _ArtPainter {
  const _TrackPainter(super.dense);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final s = math.min(w, h);
    final lane = s * 0.045; // lane width
    final r0 = s * 0.18; // inside of lane 1 on the bend
    final x0 = w * 0.42; // where the straight meets the bend
    final y0 = h * 0.66; // lane 1's inside line on the home straight
    final yc = y0 - r0; // centre of the bend

    // Line i (0 = inside of lane 1 … 6 = outside of lane 6): the home
    // straight, round the bend, back along the far straight.
    Path laneLine(double offset) {
      final rr = r0 + offset;
      return Path()
        ..moveTo(0, yc + rr)
        ..lineTo(x0, yc + rr)
        ..arcTo(Rect.fromCircle(center: Offset(x0, yc), radius: rr),
            math.pi / 2, -math.pi, false)
        ..lineTo(0, yc - rr);
    }

    // The running surface a shade darker than the infield.
    canvas.drawPath(
        laneLine(lane * 3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lane * 6
          ..color = const Color(0x1F000000));
    _vignette(canvas, size);

    final line = _stroke(dense ? 0.9 : _lineWidth(size, dense), 58);
    for (var i = 0; i <= 6; i++) {
      canvas.drawPath(laneLine(lane * i), line);
    }

    // The start line with lane numbers 1–6 behind it.
    final startX = w * 0.12;
    canvas.drawLine(Offset(startX, y0), Offset(startX, y0 + lane * 6),
        _stroke(line.strokeWidth * 1.4, 90));
    if (!dense) {
      for (var i = 1; i <= 6; i++) {
        final tp = TextPainter(
          text: TextSpan(
              text: '$i',
              style: TextStyle(
                  fontSize: lane * 0.62,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: const Color(0x66FFFFFF))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
            canvas,
            Offset(startX - lane * 0.5 - tp.width,
                y0 + lane * (i - 0.5) - tp.height / 2));
        tp.dispose();
      }
    }

    // The finish line: a checker band across all six lanes.
    final fx = x0 - lane * 1.2;
    final cell = lane / 2;
    final check = _fill(const Color(0x59FFFFFF));
    for (var row = 0; row < 12; row++) {
      for (var col = 0; col < 2; col++) {
        if ((row + col).isOdd) continue;
        canvas.drawRect(
            Rect.fromLTWH(fx + col * cell, y0 + row * cell, cell, cell), check);
      }
    }
  }
}

// ── Paintball: "Arena" ──────────────────────────────────────────────────────

class _ArenaPainter extends _ArtPainter {
  const _ArenaPainter(super.dense);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final w = size.width, h = size.height;
    final s = math.min(w, h) * (dense ? 0.22 : 0.15);
    final olive = _fill(const Color(0x40A3B04A)); // olive 25%
    final seam = _stroke(1, 26);

    // The centre line, dashed.
    _dashed(canvas, Path()..moveTo(w / 2, 0)..lineTo(w / 2, h),
        _stroke(_lineWidth(size, dense), 40),
        dash: 7, gap: 6);

    // Inflatable bunkers: cones ("doritos"), cans and a snake.
    void cone(double fx, double fy, double sz, double angle) {
      canvas.save();
      canvas.translate(w * fx, h * fy);
      canvas.rotate(angle);
      final path = Path()
        ..moveTo(0, -sz * 0.6)
        ..quadraticBezierTo(sz * 0.08, -sz * 0.66, sz * 0.14, -sz * 0.52)
        ..lineTo(sz * 0.55, sz * 0.38)
        ..quadraticBezierTo(sz * 0.6, sz * 0.5, sz * 0.45, sz * 0.5)
        ..lineTo(-sz * 0.45, sz * 0.5)
        ..quadraticBezierTo(-sz * 0.6, sz * 0.5, -sz * 0.55, sz * 0.38)
        ..lineTo(-sz * 0.14, -sz * 0.52)
        ..quadraticBezierTo(-sz * 0.08, -sz * 0.66, 0, -sz * 0.6)
        ..close();
      canvas.drawPath(path, olive);
      canvas.drawPath(path, seam);
      canvas.restore();
    }

    void can(double fx, double fy, double sz) {
      final rect = Rect.fromCenter(
          center: Offset(w * fx, h * fy), width: sz * 0.7, height: sz);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(sz * 0.35));
      canvas.drawRRect(rr, olive);
      canvas.drawRRect(rr, seam);
      canvas.drawLine(Offset(rect.left, rect.center.dy),
          Offset(rect.right, rect.center.dy), seam);
    }

    final snake = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(w * 0.5, h * 0.9), width: w * 0.46, height: s * 0.42),
        Radius.circular(s * 0.21));
    canvas.drawRRect(snake, olive);
    canvas.drawRRect(snake, seam);
    cone(0.2, 0.42, s, -0.1);
    cone(0.8, 0.62, s * 1.1, 0.12);
    can(0.62, 0.3, s * 0.85);
    can(0.36, 0.72, s * 0.75);
    if (!dense) cone(0.92, 0.18, s * 0.8, -0.2);
    _vignette(canvas, size);

    // Paint splats: neon pink, yellow and cyan at 35–45%.
    const pink = Color(0x73F472B6);
    const yellow = Color(0x66FDE047);
    const cyan = Color(0x5922D3EE);
    final splats = <(double, double, double, Color)>[
      (0.3, 0.24, 1.0, pink),
      (0.72, 0.46, 0.8, yellow),
      (0.56, 0.8, 0.9, cyan),
      (0.88, 0.84, 0.7, pink),
      if (!dense) (0.1, 0.64, 0.6, yellow),
      if (!dense) (0.46, 0.5, 0.5, cyan),
    ];
    for (final (i, sp) in splats.indexed) {
      _splat(canvas, Offset(w * sp.$1, h * sp.$2), s * 0.32 * sp.$3, sp.$4,
          11 + i * 7);
    }
  }
}

/// A paint splat: a lumpy blob with a few droplets thrown out.
void _splat(Canvas canvas, Offset c, double r, Color color, int seed) {
  final rnd = math.Random(seed);
  final paint = _fill(color);
  const n = 12;
  final pts = <Offset>[
    for (var i = 0; i < n; i++)
      c +
          Offset(math.cos(i / n * math.pi * 2), math.sin(i / n * math.pi * 2)) *
              (r * (0.68 + rnd.nextDouble() * 0.5)),
  ];
  final start = (pts.last + pts.first) / 2;
  final path = Path()..moveTo(start.dx, start.dy);
  for (var i = 0; i < n; i++) {
    final p = pts[i];
    final mid = (p + pts[(i + 1) % n]) / 2;
    path.quadraticBezierTo(p.dx, p.dy, mid.dx, mid.dy);
  }
  path.close();
  canvas.drawPath(path, paint);
  for (var i = 0; i < 5; i++) {
    final a = rnd.nextDouble() * math.pi * 2;
    final d = r * (1.25 + rnd.nextDouble() * 0.75);
    canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * d,
        r * (0.08 + rnd.nextDouble() * 0.12), paint);
  }
}
