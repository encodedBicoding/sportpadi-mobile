import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';

/// Paintball 🎯 (design §8) — wins and losses as paint splats, then the
/// field stats with per-game rates.

/// Record block: W and L as splat badges (pink win, grey loss) either side
/// of the win rate.
class PaintballRecord extends StatelessWidget {
  const PaintballRecord({super.key, required this.nums, this.streak});
  final SportNumbers nums;
  final String? streak;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final win = dark ? const Color(0xFFEC4899) : const Color(0xFFDB2777);
    final loss = dark ? const Color(0xFF4B5563) : const Color(0xFF9CA3AF);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        _SplatBadge(value: nums.wins, label: 'Won', color: win, seed: 5),
        Expanded(
          child: Column(children: [
            Text(nums.games > 0 ? '${nums.winRate}%' : '—',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures)),
            Text('win rate', style: TextStyle(color: p.muted, fontSize: 11)),
            if (streak != null) ...[
              const SizedBox(height: 8),
              MiniChip('Streak $streak', color: streakColor(p, streak!)),
            ],
          ]),
        ),
        _SplatBadge(value: nums.losses, label: 'Lost', color: loss, seed: 9),
      ]),
      if (nums.draws > 0) ...[
        const SizedBox(height: 10),
        Center(child: MiniChip('D ${nums.draws}')),
      ],
    ]);
  }
}

class _SplatBadge extends StatelessWidget {
  const _SplatBadge({
    required this.value,
    required this.label,
    required this.color,
    required this.seed,
  });
  final int value;
  final String label;
  final Color color;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 88,
        height: 88,
        child: CustomPaint(
          painter: _SplatPainter(color: color, seed: seed),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('$value',
                    style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 30,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        fontFeatures: tabularFigures)),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 2),
      Text(label.toUpperCase(),
          style: TextStyle(
              color: p.muted,
              fontSize: 10.5,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800)),
    ]);
  }
}

/// A lumpy splat with a few droplets, the same every time for a [seed].
class _SplatPainter extends CustomPainter {
  const _SplatPainter({required this.color, required this.seed});
  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.34;
    final paint = Paint()..color = color;
    const n = 12;
    final pts = <Offset>[
      for (var i = 0; i < n; i++)
        c +
            Offset(math.cos(i / n * math.pi * 2),
                    math.sin(i / n * math.pi * 2)) *
                (r * (0.82 + rnd.nextDouble() * 0.3)),
    ];
    final start = (pts.last + pts.first) / 2;
    final path = Path()..moveTo(start.dx, start.dy);
    for (var i = 0; i < n; i++) {
      final pt = pts[i];
      final mid = (pt + pts[(i + 1) % n]) / 2;
      path.quadraticBezierTo(pt.dx, pt.dy, mid.dx, mid.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
    for (var i = 0; i < 5; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final d = r * (1.12 + rnd.nextDouble() * 0.2);
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * d,
          r * (0.06 + rnd.nextDouble() * 0.08), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SplatPainter old) =>
      old.color != color || old.seed != seed;
}

/// Stats block: every field as a tile with its per-game rate.
class PaintballStats extends StatelessWidget {
  const PaintballStats({super.key, required this.nums});
  final SportNumbers nums;

  @override
  Widget build(BuildContext context) {
    if (nums.fields.isEmpty) return const ResultsOnlyNote();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const BlockHeading('On the field'),
      const SizedBox(height: 10),
      StatTileGrid(fields: nums.fields, counts: nums.counts, games: nums.games),
    ]);
  }
}
