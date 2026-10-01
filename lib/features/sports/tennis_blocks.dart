import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/generic_blocks.dart';
import 'package:sportpadi_mobile/features/sports/soccer_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';

/// Tennis 🎾 (design §8) — a match record like the scoreboard on court, then
/// the serve: aces against faults.

/// The tennis-ball colour on a card: the hero's optic yellow in dark mode,
/// a deeper lime on white.
Color tennisBall(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFD9F99D)
        : const Color(0xFF65A30D);

/// Record block: "Won" / "Lost" as two scoreboard rows (the ball marks the
/// side that leads) beside the win-rate ring, then the streak.
class TennisRecord extends StatelessWidget {
  const TennisRecord({super.key, required this.nums, this.streak});
  final SportNumbers nums;
  final String? streak;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ball = tennisBall(context);
    final w = nums.wins, l = nums.losses;

    Widget row(String label, int value, bool leads) => Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: leads ? ball : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 11,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800)),
            ),
            Text('$value',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 26,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    fontFeatures: tabularFigures)),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Column(children: [
            row('Won', w, w > 0 && w >= l),
            const SizedBox(height: 6),
            row('Lost', l, l > w),
          ]),
        ),
        const SizedBox(width: 14),
        WinRateRing(rate: nums.games > 0 ? nums.winRate : null),
      ]),
      if (nums.draws > 0 || streak != null) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (nums.draws > 0) MiniChip('D ${nums.draws}'),
          if (streak != null)
            MiniChip('Streak $streak', color: streakColor(p, streak!)),
        ]),
      ],
    ]);
  }
}

/// Stats block: the serve (aces vs faults as a two-part bar, aces per
/// match), then points and points per match when the sport tracks them.
class TennisStats extends StatelessWidget {
  const TennisStats({super.key, required this.nums, this.showMore = true});
  final SportNumbers nums;
  final bool showMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ball = tennisBall(context);
    final hasAces = nums.has('aces');
    final hasFaults = nums.has('faults');
    final hasPoints = nums.has('points');
    if (!hasAces && !hasFaults && !hasPoints) return GenericStats(nums: nums);
    final aces = nums.n('aces');
    final faults = nums.n('faults');
    final hasServe = hasAces || hasFaults;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (hasServe) ...[
        BlockHeading('Serve',
            trailing: hasAces
                ? Text('${nums.rate('aces')} aces / match',
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFeatures: tabularFigures))
                : null),
        const SizedBox(height: 12),
        SegmentBar(height: 14, parts: [
          if (hasAces) (aces, ball),
          if (hasFaults) (faults, p.danger),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 18, runSpacing: 6, children: [
          if (hasAces)
            LegendItem(
                color: ball, label: nums.field('aces').label, value: '$aces'),
          if (hasFaults)
            LegendItem(
                color: p.danger,
                label: nums.field('faults').label,
                value: '$faults'),
        ]),
      ],
      if (hasPoints) ...[
        if (hasServe) const BlockDivider(),
        const BlockHeading('Points'),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: StatFigure(
                value: '${nums.n('points')}',
                label: nums.field('points').label),
          ),
          Expanded(
            child: StatFigure(value: nums.rate('points'), label: 'Per match'),
          ),
          if (hasAces)
            Expanded(
              child: StatFigure(
                  value: nums.rate('aces'),
                  label: 'Aces / match',
                  color: sportInk(SportFamily.tennis,
                      dark: Theme.of(context).brightness == Brightness.dark)),
            ),
        ]),
      ],
      if (showMore)
        MoreStats(nums: nums, placed: const {'aces', 'faults', 'points'}),
    ]);
  }
}
