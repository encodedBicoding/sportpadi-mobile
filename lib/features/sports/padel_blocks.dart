import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/generic_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Padel 🎾 (design §8) — tennis's keys, doubles-flavoured. The record block
/// is the pairs record (W–L over a split bar, shared with volleyball); the
/// stats lead with points per match and weigh winners against errors.

/// Stats block: per match (points, aces, faults), then winners vs errors.
class PadelStats extends StatelessWidget {
  const PadelStats({super.key, required this.nums, this.showMore = true});
  final SportNumbers nums;
  final bool showMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ink = sportInk(SportFamily.padel,
        dark: Theme.of(context).brightness == Brightness.dark);
    final hasPoints = nums.has('points');
    final hasAces = nums.has('aces');
    final hasFaults = nums.has('faults');
    if (!hasPoints && !hasAces && !hasFaults) return GenericStats(nums: nums);
    final points = nums.n('points');
    final faults = nums.n('faults');

    final figures = <Widget>[
      if (hasPoints)
        StatFigure(
            value: nums.rate('points'),
            label: context.l10n.profile_pointsMatch,
            sub: context.l10n.profile_total2(points),
            color: ink),
      if (hasAces)
        StatFigure(
            value: '${nums.n('aces')}',
            label: nums.field('aces').label,
            sub: context.l10n.profile_match(nums.rate('aces'))),
      if (hasFaults)
        StatFigure(
            value: '$faults',
            label: nums.field('faults').label,
            sub: context.l10n.profile_match(nums.rate('faults'))),
    ];
    final total = points + faults;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BlockHeading(context.l10n.profile_perMatch),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final f in figures) Expanded(child: f),
      ]),
      if (hasPoints && hasFaults) ...[
        const BlockDivider(),
        BlockHeading(context.l10n.profile_winnersVsErrors,
            trailing: Text(
                total > 0 ? context.l10n.profile_winners2((points * 100 / total).round()) : '—',
                style: TextStyle(
                    color: p.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: tabularFigures))),
        const SizedBox(height: 12),
        SegmentBar(height: 14, parts: [(points, ink), (faults, p.danger)]),
        const SizedBox(height: 10),
        Wrap(spacing: 18, runSpacing: 6, children: [
          LegendItem(color: ink, label: context.l10n.profile_winners, value: '$points'),
          LegendItem(color: p.danger, label: context.l10n.profile_errors, value: '$faults'),
        ]),
      ],
      if (showMore)
        MoreStats(nums: nums, placed: const {'points', 'aces', 'faults'}),
    ]);
  }
}
