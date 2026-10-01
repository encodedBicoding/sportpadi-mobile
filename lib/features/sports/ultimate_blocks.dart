import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/generic_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';

/// Ultimate 🥏 (design §8) — scores and assists. The record block is W–L
/// over a split bar (shared with volleyball). Spirit isn't tracked, so it
/// isn't shown.

/// The keys a sport might call a score by, in order of preference.
const ultimateScoreKeys = ['points', 'goals', 'scores'];

/// Stats block: "Scores & assists" tiles with per-game rates, then how many
/// scores they had a hand in.
class UltimateStats extends StatelessWidget {
  const UltimateStats({super.key, required this.nums, this.showMore = true});
  final SportNumbers nums;
  final bool showMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = sportInk(SportFamily.ultimate, dark: dark);
    final scoreKey = firstStatKey(ultimateScoreKeys, nums.fields, nums.counts);
    final hasAssists = nums.has('assists');
    if (scoreKey == null && !hasAssists) return GenericStats(nums: nums);

    final tiles = <(String, String, int, String)>[
      if (scoreKey != null)
        (
          nums.field(scoreKey).icon ?? '🥏',
          'Scores',
          nums.n(scoreKey),
          nums.rate(scoreKey)
        ),
      if (hasAssists)
        (
          nums.field('assists').icon ?? '🅰️',
          nums.field('assists').label,
          nums.n('assists'),
          nums.rate('assists')
        ),
    ];
    final involved = (scoreKey == null ? 0 : nums.n(scoreKey)) +
        (hasAssists ? nums.n('assists') : 0);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BlockHeading(scoreKey != null && hasAssists
          ? 'Scores & assists'
          : scoreKey != null
              ? 'Scores'
              : 'Assists'),
      const SizedBox(height: 12),
      Row(children: [
        for (var i = 0; i < tiles.length; i++)
          Expanded(
            child: Container(
              margin: EdgeInsets.only(left: i == 0 ? 0 : 8),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
              decoration: BoxDecoration(
                color: ink.withAlpha(dark ? 34 : 24),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(tiles[i].$1, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(tiles[i].$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('${tiles[i].$3}',
                          style: TextStyle(
                              color: i == 0 ? ink : p.ink,
                              fontSize: 30,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              fontFeatures: tabularFigures)),
                    ),
                    const SizedBox(height: 4),
                    Text('${tiles[i].$4} / game',
                        style: TextStyle(
                            color: p.muted,
                            fontSize: 11.5,
                            fontFeatures: tabularFigures)),
                  ]),
            ),
          ),
      ]),
      if (tiles.length == 2) ...[
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'A hand in '),
            TextSpan(
                text: '$involved',
                style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
            TextSpan(
                text:
                    ' ${involved == 1 ? 'score' : 'scores'} · ${perGame(involved, nums.games)} a game'),
          ]),
          style: TextStyle(
              color: p.muted, fontSize: 12.5, fontFeatures: tabularFigures),
        ),
      ],
      if (showMore)
        MoreStats(
            nums: nums, placed: {if (scoreKey != null) scoreKey, 'assists'}),
    ]);
  }
}
