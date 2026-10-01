import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';

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
      ('Won', nums.wins, p.accentTint, p.greenText),
      ('Drawn', nums.draws, p.surface2, p.muted),
      ('Lost', nums.losses, p.liveTint, p.danger),
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
          '${plural(nums.games, 'game')} · '
          '${nums.games > 0 ? '${nums.winRate}%' : '—'} wins · '
          '${nums.points} pts',
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
      return Text('This sport keeps results only — no individual stats.',
          style: TextStyle(color: p.muted, fontSize: 12.5));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const BlockHeading('Stats'),
      const SizedBox(height: 10),
      StatTileGrid(fields: nums.fields, counts: nums.counts, games: nums.games),
    ]);
  }
}
