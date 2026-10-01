import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';

/// Volleyball 🏐 — won/lost with a split bar, then where the points come
/// from.

const Color _attackColor = Color(0xFF06B6D4);
const Color _aceColor = Color(0xFFF59E0B);
const Color _blockColor = Color(0xFFF43F5E);

/// Record block: W and L as two big numbers over a split bar.
class VolleyballRecord extends StatelessWidget {
  const VolleyballRecord({super.key, required this.nums, this.streak});
  final SportNumbers nums;
  final String? streak;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final w = nums.wins, d = nums.draws, l = nums.losses;
    Widget big(String v, String label, Color c, CrossAxisAlignment a) =>
        Column(crossAxisAlignment: a, mainAxisSize: MainAxisSize.min, children: [
          Text(v,
              style: TextStyle(
                  color: c,
                  fontSize: 40,
                  height: 1,
                  letterSpacing: -1,
                  fontWeight: FontWeight.w900,
                  fontFeatures: tabularFigures)),
          const SizedBox(height: 4),
          Text(label.toUpperCase(),
              style: TextStyle(
                  color: p.muted,
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800)),
        ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        big('$w', 'Won', p.greenText, CrossAxisAlignment.start),
        Expanded(
          child: Column(children: [
            Text(nums.games > 0 ? '${nums.winRate}%' : '—',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures)),
            Text('win rate',
                style: TextStyle(color: p.muted, fontSize: 11)),
          ]),
        ),
        big('$l', 'Lost', p.danger, CrossAxisAlignment.end),
      ]),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 12,
          child: w + d + l == 0
              ? ColoredBox(color: p.surface2)
              : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (w > 0) Expanded(flex: w, child: ColoredBox(color: p.accent)),
                  if (w > 0 && d + l > 0) const SizedBox(width: 3),
                  if (d > 0)
                    Expanded(
                        flex: d,
                        child: const ColoredBox(color: Color(0xFF9CA3AF))),
                  if (d > 0 && l > 0) const SizedBox(width: 3),
                  if (l > 0) Expanded(flex: l, child: ColoredBox(color: p.danger)),
                ]),
        ),
      ),
      if (d > 0 || streak != null) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (d > 0) MiniChip('D $d'),
          if (streak != null)
            MiniChip('Streak $streak', color: streakColor(p, streak!)),
        ]),
      ],
    ]);
  }
}

/// Stats block: the scoring mix (attack / aces / blocks) and per-game rates.
class VolleyballStats extends StatelessWidget {
  const VolleyballStats({super.key, required this.nums, this.showMore = true});
  final SportNumbers nums;
  final bool showMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final aces = nums.n('aces');
    final blocks = nums.n('blocks');
    // `points` counts every point the player won (kills, aces, blocks and
    // the rest), so attack is what's left once aces and blocks are taken
    // out. A sport without a points key falls back to kills.
    final attack = nums.has('points')
        ? (nums.n('points') - aces - blocks).clamp(0, 1 << 30).toInt()
        : nums.n('kills');
    final sources = <(String, int, Color)>[
      ('Attack', attack, _attackColor),
      ('Aces', aces, _aceColor),
      ('Blocks', blocks, _blockColor),
    ];
    final total = attack + aces + blocks;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BlockHeading('Scoring mix',
          trailing: Text(plural(total, 'point'),
              style: TextStyle(
                  color: p.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures))),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 14,
          child: total == 0
              ? ColoredBox(color: p.surface2)
              : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final (i, s) in sources.indexed)
                    if (s.$2 > 0) ...[
                      if (sources.take(i).any((x) => x.$2 > 0))
                        const SizedBox(width: 2),
                      Expanded(flex: s.$2, child: ColoredBox(color: s.$3)),
                    ],
                ]),
        ),
      ),
      const SizedBox(height: 12),
      for (final s in sources)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: s.$3, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(s.$1,
                  style: TextStyle(
                      color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
            Text('${s.$2}',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures)),
            SizedBox(
              width: 48,
              child: Text(total > 0 ? '${(s.$2 * 100 / total).round()}%' : '—',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 12.5,
                      fontFeatures: tabularFigures)),
            ),
          ]),
        ),
      const BlockDivider(),
      const BlockHeading('Per game'),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: StatFigure(
              value: nums.rate('points'),
              label: 'Points',
              sub: '${nums.n('points')} total'),
        ),
        Expanded(
          child: StatFigure(
              value: nums.rate('aces'),
              label: 'Aces',
              sub: '$aces total',
              color: const Color(0xFFD97706)),
        ),
        Expanded(
          child: StatFigure(
              value: nums.rate('blocks'),
              label: 'Blocks',
              sub: '$blocks total',
              color: _blockColor),
        ),
      ]),
      if (showMore)
        MoreStats(nums: nums, placed: const {'points', 'aces', 'blocks'}),
    ]);
  }
}
