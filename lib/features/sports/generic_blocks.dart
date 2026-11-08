import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Every other sport — a neutral record: W / D / L tiles and a grid of
/// every field the sport tracks.

/// Record block: three tiles, W / D / L.
class GenericRecord extends StatelessWidget {
  const GenericRecord({super.key, required this.nums});
  final SportNumbers nums;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tiles = <(String, int, Color, Color)>[
      (context.l10n.profile_won, nums.wins, p.accentTint, p.greenText),
      (context.l10n.profile_p5Drawn, nums.draws, p.surface2, p.muted),
      (context.l10n.profile_lost, nums.losses, p.liveTint, p.danger),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (var i = 0; i < tiles.length; i++)
          Expanded(
            child: Container(
              height: 68,
              margin: EdgeInsets.only(left: i == 0 ? 0 : 8),
              decoration: BoxDecoration(
                color: tiles[i].$3,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${tiles[i].$2}',
                        style: TextStyle(
                            color: tiles[i].$4,
                            fontSize: 24,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            fontFeatures: tabularFigures)),
                    const SizedBox(height: 2),
                    Text(tiles[i].$1,
                        style: TextStyle(
                            color: p.muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600)),
                  ]),
            ),
          ),
      ]),
      const SizedBox(height: 10),
      Text(
          context.l10n.profile_p5GamesWinsPts(nums.games, (nums.games > 0 ? '${nums.winRate}%' : '—'), nums.points),
          textAlign: TextAlign.center,
          style: TextStyle(
              color: p.muted, fontSize: 12, fontFeatures: tabularFigures)),
    ]);
  }
}

/// Stats block: every field with its total and per game.
class GenericStats extends StatelessWidget {
  const GenericStats({super.key, required this.nums});
  final SportNumbers nums;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (nums.fields.isEmpty) {
      return Text(context.l10n.profile_thisSportKeepsResultsOnly,
          style: TextStyle(color: p.muted, fontSize: 12.5));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BlockHeading(context.l10n.profile_stats2),
      const SizedBox(height: 10),
      StatTileGrid(fields: nums.fields, counts: nums.counts, games: nums.games),
    ]);
  }
}
