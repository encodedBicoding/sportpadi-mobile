import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/generic_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';

/// Ping pong 🏓 (design §8) — W–L with the last ten results as little bats,
/// then the rally numbers: points, service aces, faults.

/// Record block: "12–7" big, the win rate, and the last ten results.
class TableTennisRecord extends StatelessWidget {
  const TableTennisRecord({
    super.key,
    required this.nums,
    this.recent = const [],
    this.streak,
  });
  final SportNumbers nums;

  /// The scope's recent games, newest first.
  final List<Map<String, dynamic>> recent;
  final String? streak;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    TextStyle big(Color c) => TextStyle(
        color: c,
        fontSize: 40,
        height: 1,
        letterSpacing: -1,
        fontWeight: FontWeight.w900,
        fontFeatures: tabularFigures);
    // Oldest on the left, newest on the right; empty bats pad the left.
    final last = formOf(recent).take(10).toList().reversed.toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${nums.wins}', style: big(p.greenText)),
              TextSpan(text: ' – ', style: big(p.muted.withAlpha(110))),
              TextSpan(text: '${nums.losses}', style: big(p.danger)),
            ])),
          ),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(nums.games > 0 ? '${nums.winRate}%' : '—',
              style: TextStyle(
                  color: p.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFeatures: tabularFigures)),
          Text('win rate', style: TextStyle(color: p.muted, fontSize: 11)),
        ]),
      ]),
      const SizedBox(height: 4),
      Text('WON – LOST',
          style: TextStyle(
              color: p.muted,
              fontSize: 10.5,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800)),
      if (last.isNotEmpty) ...[
        const SizedBox(height: 16),
        Row(children: [
          Text('LAST ${last.length}',
              style: TextStyle(
                  color: p.muted,
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800)),
          const Spacer(),
          if (streak != null)
            MiniChip('Streak $streak', color: streakColor(p, streak!)),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var i = 0; i < 10 - last.length; i++)
            _Bat(color: p.line, filled: false),
          for (final r in last)
            _Bat(
              color: switch (r) {
                'W' => p.accent,
                'L' => p.danger,
                _ => const Color(0xFF9CA3AF),
              },
              filled: true,
            ),
        ]),
      ] else if (streak != null) ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: MiniChip('Streak $streak', color: streakColor(p, streak!)),
        ),
      ],
      if (nums.draws > 0) ...[
        const SizedBox(height: 10),
        Align(
            alignment: Alignment.centerLeft,
            child: MiniChip('D ${nums.draws}')),
      ],
    ]);
  }
}

/// One result as a little bat (outlined when the slot is still empty).
class _Bat extends StatelessWidget {
  const _Bat({required this.color, required this.filled});
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 18,
        height: 26,
        child: CustomPaint(painter: _BatPainter(color: color, filled: filled)),
      );
}

class _BatPainter extends CustomPainter {
  const _BatPainter({required this.color, required this.filled});
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width * 0.44;
    canvas.save();
    canvas.translate(size.width / 2, r + 1);
    canvas.rotate(-math.pi / 14);
    final shape = Path()
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: r))
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(-r * 0.22, r * 0.78, r * 0.44, size.height - r * 2.1),
          Radius.circular(r * 0.2)));
    canvas.drawPath(
        shape,
        Paint()
          ..color = color
          ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BatPainter old) =>
      old.color != color || old.filled != filled;
}

/// Stats block: points (total and per game), service aces, faults.
class TableTennisStats extends StatelessWidget {
  const TableTennisStats({super.key, required this.nums, this.showMore = true});
  final SportNumbers nums;
  final bool showMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ink = sportInk(SportFamily.tableTennis,
        dark: Theme.of(context).brightness == Brightness.dark);
    final hasPoints = nums.has('points');
    final hasAces = nums.has('aces');
    final hasFaults = nums.has('faults');
    if (!hasPoints && !hasAces && !hasFaults) return GenericStats(nums: nums);
    final acesLabel = nums.field('aces').label;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const BlockHeading('Rally'),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (hasPoints)
          Expanded(
            child: StatFigure(
                value: '${nums.n('points')}',
                label: nums.field('points').label,
                sub: '${nums.rate('points')} / game',
                color: ink),
          ),
        if (hasAces)
          Expanded(
            child: StatFigure(
                value: '${nums.n('aces')}',
                label: acesLabel == 'Aces' ? 'Service aces' : acesLabel,
                sub: '${nums.rate('aces')} / game'),
          ),
        if (hasFaults)
          Expanded(
            child: StatFigure(
                value: '${nums.n('faults')}',
                label: nums.field('faults').label,
                sub: '${nums.rate('faults')} / game',
                color: p.danger),
          ),
      ]),
      if (showMore)
        MoreStats(nums: nums, placed: const {'points', 'aces', 'faults'}),
    ]);
  }
}
