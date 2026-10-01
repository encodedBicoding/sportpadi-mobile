import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/soccer_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';

/// Chess ♟️ (design §8) — chess notation everywhere: wins 1–0, draws ½–½,
/// losses 0–1, and a score of W + ½D.

const Color _lightSquare = Color(0xFFF0D9B5);
const Color _darkSquare = Color(0xFFB58863);
const Color _onLight = Color(0xFF3F2A1D);
const Color _onDark = Color(0xFFFFFFFF);

/// Record block: Wins · Draws · Losses as board squares (light, dark,
/// light) with their notation, and the score ring.
class ChessRecord extends StatelessWidget {
  const ChessRecord({super.key, required this.nums});
  final SportNumbers nums;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final w = nums.wins, d = nums.draws, l = nums.losses, g = nums.games;
    final squares = <(int, String, String, bool)>[
      (w, '1–0', 'Wins', true),
      (d, '½–½', 'Draws', false),
      (l, '0–1', 'Losses', true),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < squares.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                  child: _Square(
                    value: squares[i].$1,
                    notation: squares[i].$2,
                    label: squares[i].$3,
                    light: squares[i].$4,
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        WinRateRing(
          rate: chessScorePct(w, d, g),
          caption: 'score',
          size: 70,
          color: sportInk(SportFamily.chess, dark: dark),
        ),
      ]),
      const SizedBox(height: 12),
      Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Score '),
          TextSpan(
              text: g > 0 ? '${chessScore(w, d)} / $g' : '—',
              style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
          TextSpan(text: '   ·   +$w =$d −$l'),
        ]),
        textAlign: TextAlign.center,
        style: TextStyle(
            color: p.muted, fontSize: 12.5, fontFeatures: tabularFigures),
      ),
    ]);
  }
}

/// One result count on a board square.
class _Square extends StatelessWidget {
  const _Square({
    required this.value,
    required this.notation,
    required this.label,
    required this.light,
  });
  final int value;
  final String notation;
  final String label;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ink = light ? _onLight : _onDark;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: light ? _lightSquare : _darkSquare,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 3,
                  offset: Offset(0, 1)),
            ],
          ),
          padding: const EdgeInsets.all(6),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$value',
                  style: TextStyle(
                      color: ink,
                      fontSize: 24,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      fontFeatures: tabularFigures)),
              const SizedBox(height: 2),
              Text(notation,
                  style: TextStyle(
                      color: ink.withAlpha(190),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFeatures: tabularFigures)),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
    ]);
  }
}

/// Stats block: the performance bar (W / D / L), then every field the sport
/// tracks under "More stats".
class ChessStats extends StatelessWidget {
  const ChessStats({super.key, required this.nums, this.showMore = true});
  final SportNumbers nums;
  final bool showMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final gold = sportInk(SportFamily.chess,
        dark: Theme.of(context).brightness == Brightness.dark);
    const drawn = Color(0xFF9CA3AF);
    final w = nums.wins, d = nums.draws, l = nums.losses;
    final total = w + d + l;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BlockHeading('Performance',
          trailing: Text(plural(nums.games, 'game'),
              style: TextStyle(
                  color: p.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures))),
      const SizedBox(height: 12),
      SegmentBar(height: 14, parts: [(w, gold), (d, drawn), (l, p.danger)]),
      const SizedBox(height: 10),
      LegendLine(color: gold, label: 'Wins  1–0', value: w, total: total),
      LegendLine(color: drawn, label: 'Draws  ½–½', value: d, total: total),
      LegendLine(color: p.danger, label: 'Losses  0–1', value: l, total: total),
      if (showMore) MoreStats(nums: nums, placed: const {}),
    ]);
  }
}
