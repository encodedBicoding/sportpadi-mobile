import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';

/// Soccer ⚽ — a league-table row, then attack / discipline / starts.

/// Record block: `P W D L Pts` as a league-table row, W/D/L tinted, and a
/// win-rate ring beside it.
class SoccerRecord extends StatelessWidget {
  const SoccerRecord({super.key, required this.nums});
  final SportNumbers nums;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cells = <(String, String, Color, Color)>[
      ('P', '${nums.games}', p.surface2, p.ink),
      ('W', '${nums.wins}', p.accentTint, p.greenText),
      ('D', '${nums.draws}', p.surface2, p.muted),
      ('L', '${nums.losses}', p.liveTint, p.danger),
      ('Pts', '${nums.points}', p.hero, p.onHero),
    ];
    return Row(children: [
      Expanded(
        child: Column(children: [
          Row(children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                  child: Text(cells[i].$1.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: p.muted,
                          fontSize: 10.5,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                child: Container(
                  height: 44,
                  margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cells[i].$3,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(cells[i].$2,
                          style: TextStyle(
                              color: cells[i].$4,
                              fontSize: 18,
                              fontWeight: i == 4 ? FontWeight.w900 : FontWeight.w800,
                              fontFeatures: tabularFigures)),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      ),
      const SizedBox(width: 14),
      WinRateRing(rate: nums.games > 0 ? nums.winRate : null),
    ]);
  }
}

/// "61% wins" as a ring.
class WinRateRing extends StatelessWidget {
  const WinRateRing({
    super.key,
    required this.rate,
    this.size = 74,
    this.caption = 'wins',
    this.color,
  });

  /// 0–100, or null with no games.
  final int? rate;
  final double size;

  /// The word under the figure ("wins", "score" …).
  final String caption;

  /// The ring's colour (default: the brand green).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
            value: (rate ?? 0) / 100,
            track: p.surface2,
            color: color ?? p.accent),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(rate == null ? '—' : '$rate%',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 17,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures)),
            Text(caption,
                style: TextStyle(
                    color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(
      {required this.value, required this.track, required this.color});
  final double value;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    final v = value.clamp(0.0, 1.0);
    if (v <= 0) return;
    canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * v,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.value != value || old.track != track || old.color != color;
}

/// Stats block: attack, discipline (real cards), starts.
class SoccerStats extends StatelessWidget {
  const SoccerStats({super.key, required this.nums, this.showMore = true});
  final SportNumbers nums;
  final bool showMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = nums.games;
    final goals = nums.n('goals');
    final assists = nums.n('assists');
    final yellows = nums.n('yellows');
    final reds = nums.n('reds');
    final ownGoals = nums.n('ownGoals');
    final cards = yellows + reds;
    final starts = nums.starts;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const BlockHeading('Attack'),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: StatFigure(
              value: '$goals',
              label: 'Goals',
              sub: '${nums.rate('goals')} / game',
              color: p.greenText),
        ),
        Expanded(
          child: StatFigure(
              value: '$assists',
              label: 'Assists',
              sub: '${nums.rate('assists')} / game'),
        ),
        Expanded(
          child: StatFigure(
              value: '${goals + assists}',
              label: 'G+A',
              sub: '${perGame(goals + assists, g, decimals: 2)} / game'),
        ),
      ]),
      const BlockDivider(),
      const BlockHeading('Discipline'),
      const SizedBox(height: 12),
      Row(children: [
        _BookingCard(
            count: yellows,
            label: 'Yellow',
            color: const Color(0xFFFACC15),
            ink: const Color(0xFF3B2F00),
            tilt: -0.14),
        const SizedBox(width: 12),
        _BookingCard(
            count: reds,
            label: 'Red',
            color: const Color(0xFFEF4444),
            ink: Colors.white,
            tilt: 0.1),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    cards == 0
                        ? 'No cards — spotless.'
                        : 'A card every ${(g / cards).toStringAsFixed(1)} games',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 13.5,
                        height: 1.3,
                        fontWeight: FontWeight.w600)),
                if (ownGoals > 0) ...[
                  const SizedBox(height: 4),
                  Text(plural(ownGoals, 'own goal'),
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ],
              ]),
        ),
      ]),
      const BlockDivider(),
      BlockHeading('Starts',
          trailing: Text(g > 0 ? '${(starts * 100 / g).round()}%' : '—',
              style: TextStyle(
                  color: p.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures))),
      const SizedBox(height: 8),
      Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Started '),
          TextSpan(
              text: '$starts',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const TextSpan(text: ' of '),
          TextSpan(
              text: '$g',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        style: TextStyle(
            color: p.ink, fontSize: 14, fontFeatures: tabularFigures),
      ),
      const SizedBox(height: 8),
      ThinBar(value: g > 0 ? starts / g : 0.0),
      if (showMore)
        MoreStats(
            nums: nums,
            placed: const {'goals', 'assists', 'ownGoals', 'yellows', 'reds'}),
    ]);
  }
}

/// A booking card, slightly tilted, with the count on it.
class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.count,
    required this.label,
    required this.color,
    required this.ink,
    required this.tilt,
  });
  final int count;
  final String label;
  final Color color;
  final Color ink;
  final double tilt;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Transform.rotate(
        angle: tilt,
        child: Container(
          width: 32,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(5),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 3)),
            ],
          ),
          child: Text('$count',
              style: TextStyle(
                  color: ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  fontFeatures: tabularFigures)),
        ),
      ),
      const SizedBox(height: 7),
      Text(label,
          style: TextStyle(
              color: p.muted, fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }
}
