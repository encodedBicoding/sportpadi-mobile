import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';

/// Basketball 🏀 — a scoreboard, a box score, shooting and a foul meter.

/// Record block: W–L in big "LED" figures on an inset panel.
class BasketballRecord extends StatelessWidget {
  const BasketballRecord({super.key, required this.nums, this.streak});
  final SportNumbers nums;
  final String? streak;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF111111) : p.surface2,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(child: _Led(value: nums.wins, caption: 'Wins', dark: dark)),
          Container(
            width: 1,
            height: 56,
            color: dark ? const Color(0x1FFFFFFF) : p.line,
          ),
          Expanded(
              child: _Led(value: nums.losses, caption: 'Losses', dark: dark)),
        ]),
        const SizedBox(height: 12),
        Wrap(
            alignment: WrapAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              if (nums.draws > 0) MiniChip('D ${nums.draws}'),
              MiniChip(nums.games > 0 ? '${nums.winRate}% wins' : 'No games'),
              if (streak != null)
                MiniChip('Streak $streak', color: streakColor(p, streak!)),
            ]),
      ]),
    );
  }
}

class _Led extends StatelessWidget {
  const _Led({required this.value, required this.caption, required this.dark});
  final int value;
  final String caption;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = '$value';
    final ghost = '8' * (text.length < 2 ? 2 : text.length);
    final lit = dark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C);
    TextStyle style(Color c, {bool glow = false}) => TextStyle(
          color: c,
          fontSize: 46,
          height: 1,
          letterSpacing: 2,
          fontWeight: FontWeight.w900,
          fontFeatures: tabularFigures,
          shadows: glow
              ? const [Shadow(color: Color(0x99F97316), blurRadius: 14)]
              : null,
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Stack(alignment: Alignment.centerRight, children: [
          // The unlit segments behind the number, like a real board.
          Text(ghost,
              style: style(
                  dark ? const Color(0x0FFFFFFF) : const Color(0x0F000000))),
          Text(text, style: style(lit, glow: dark)),
        ]),
      ),
      const SizedBox(height: 6),
      Text(caption.toUpperCase(),
          style: TextStyle(
              color: dark ? const Color(0x8CFFFFFF) : p.muted,
              fontSize: 10.5,
              letterSpacing: 2,
              fontWeight: FontWeight.w800)),
    ]);
  }
}

/// Stats block: the box score, shooting splits and the foul meter.
class BasketballStats extends StatelessWidget {
  const BasketballStats({super.key, required this.nums, this.showMore = true});
  final SportNumbers nums;
  final bool showMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = nums.games;
    final cols = <(String, String)>[
      ('PTS', 'points'),
      if (nums.has('reb')) ('REB', 'reb'),
      if (nums.has('assists')) ('AST', 'assists'),
      if (nums.has('fouls')) ('PF', 'fouls'),
    ];
    final shooting = <(String, int, int)>[
      for (final (label, made, att) in const [
        ('2PT', 'fg2Made', 'fg2Att'),
        ('3PT', 'fg3Made', 'fg3Att'),
        ('FT', 'ftMade', 'ftAtt'),
      ])
        if (nums.n(att) > 0) (label, nums.n(made), nums.n(att)),
    ];
    final foulAvg = g > 0 ? nums.n('fouls') / g : 0.0;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const BlockHeading('Box score'),
      const SizedBox(height: 10),
      StatTable(
        columns: ['G', for (final c in cols) c.$1],
        rows: [
          ('Total', ['$g', for (final c in cols) '${nums.n(c.$2)}']),
          ('Per game', ['', for (final c in cols) nums.rate(c.$2)]),
        ],
      ),
      if (shooting.isNotEmpty) ...[
        const BlockDivider(),
        const BlockHeading('Shooting'),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < shooting.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shooting[i].$1,
                        style: TextStyle(
                            color: p.muted,
                            fontSize: 10.5,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('${shooting[i].$2}/${shooting[i].$3}',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              fontFeatures: tabularFigures)),
                    ),
                    const SizedBox(height: 6),
                    ThinBar(
                        value: shooting[i].$2 / shooting[i].$3,
                        color: const Color(0xFFF97316)),
                    const SizedBox(height: 4),
                    Text('${(shooting[i].$2 * 100 / shooting[i].$3).round()}%',
                        style: TextStyle(
                            color: p.muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            fontFeatures: tabularFigures)),
                  ]),
            ),
          ],
        ]),
      ],
      if (nums.has('fouls')) ...[
        const BlockDivider(),
        BlockHeading('Foul meter',
            trailing: Text('${nums.rate('fouls')} / game',
                style: TextStyle(
                    color: p.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: tabularFigures))),
        const SizedBox(height: 12),
        Row(children: [
          for (var i = 0; i < 5; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _Pip(
              fill: (foulAvg - i).clamp(0.0, 1.0).toDouble(),
              color: foulAvg >= 4 ? p.danger : const Color(0xFFF97316),
            ),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Text('Fouls out at 5',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(color: p.muted, fontSize: 11.5)),
          ),
        ]),
      ],
      if (showMore)
        MoreStats(
            nums: nums, placed: const {'points', 'reb', 'assists', 'fouls'}),
    ]);
  }
}

/// One foul pip, filled left-to-right by [fill] (0–1).
class _Pip extends StatelessWidget {
  const _Pip({required this.fill, required this.color});
  final double fill;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const size = 22.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        Container(
            decoration:
                BoxDecoration(color: p.surface2, shape: BoxShape.circle)),
        ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: fill,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
      ]),
    );
  }
}
