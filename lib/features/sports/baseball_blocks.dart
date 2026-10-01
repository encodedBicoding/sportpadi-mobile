import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';

/// Baseball ⚾ — a standings line and the back of a baseball card.

/// Record block: W · L · PCT · STRK as a standings line.
class BaseballRecord extends StatelessWidget {
  const BaseballRecord({super.key, required this.nums, this.streak});
  final SportNumbers nums;
  final String? streak;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cells = <(String, String, Color)>[
      ('W', '${nums.wins}', p.ink),
      ('L', '${nums.losses}', p.ink),
      if (nums.draws > 0) ('T', '${nums.draws}', p.ink),
      ('PCT', baseballPct(nums.wins, nums.games), p.ink),
      ('STRK', streak ?? '—', streak == null ? p.muted : streakColor(p, streak!)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 68,
        decoration: BoxDecoration(
          border: Border.all(color: p.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0)
              Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 14),
                  color: p.line),
            Expanded(
              flex: cells[i].$1 == 'PCT' ? 3 : 2,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(cells[i].$1,
                        style: TextStyle(
                            color: p.muted,
                            fontSize: 10.5,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(cells[i].$2,
                            style: TextStyle(
                                color: cells[i].$3,
                                fontSize: 22,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                fontFeatures: tabularFigures)),
                      ),
                    ),
                  ]),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 8),
      Text('${plural(nums.games, 'game')} played',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, fontSize: 12)),
    ]);
  }
}

/// Stats block: the batting line (G · R · H · HR · K), then power.
class BaseballStats extends StatelessWidget {
  const BaseballStats({super.key, required this.nums, this.showMore = true});
  final SportNumbers nums;
  final bool showMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final g = nums.games;
    final cols = <(String, String)>[
      ('R', 'runs'),
      if (nums.has('hits')) ('H', 'hits'),
      if (nums.has('homeRuns')) ('HR', 'homeRuns'),
      if (nums.has('strikeouts')) ('K', 'strikeouts'),
    ];
    final runs = nums.n('runs');
    final hr = nums.n('homeRuns');
    final stitch = dark ? const Color(0xFFF87171) : const Color(0xFFDC2626);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const BlockHeading('Batting line'),
      const SizedBox(height: 10),
      StatTable(
        columns: ['G', for (final c in cols) c.$1],
        rows: [
          ('Total', ['$g', for (final c in cols) '${nums.n(c.$2)}']),
          ('Per game', ['', for (final c in cols) nums.rate(c.$2)]),
        ],
      ),
      if (runs > 0 && nums.has('homeRuns')) ...[
        const BlockDivider(),
        const BlockHeading('Power'),
        const SizedBox(height: 8),
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '${(hr * 100 / runs).round()}%',
                style: TextStyle(color: stitch, fontWeight: FontWeight.w800)),
            const TextSpan(text: ' of runs from home runs'),
          ]),
          style: TextStyle(
              color: p.ink, fontSize: 14, fontFeatures: tabularFigures),
        ),
        const SizedBox(height: 8),
        ThinBar(value: hr / runs, color: stitch),
      ],
      if (showMore)
        MoreStats(
            nums: nums,
            placed: const {'runs', 'hits', 'homeRuns', 'strikeouts'}),
    ]);
  }
}
