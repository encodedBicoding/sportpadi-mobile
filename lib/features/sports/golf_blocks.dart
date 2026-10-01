import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';

/// Golf ⛳ (design §8) — the scorecard look: thin-ruled cells, a green
/// header row, tabular figures.

/// Record block: a scorecard strip — rounds, wins, (halved), losses, win %.
class GolfRecord extends StatelessWidget {
  const GolfRecord({super.key, required this.nums, this.streak});
  final SportNumbers nums;
  final String? streak;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cols = <(String, String)>[
      ('Rounds', '${nums.games}'),
      ('Wins', '${nums.wins}'),
      if (nums.draws > 0) ('Halved', '${nums.draws}'),
      ('Losses', '${nums.losses}'),
      ('Win %', nums.games > 0 ? '${nums.winRate}' : '—'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Scorecard(
        header: [for (final c in cols) c.$1],
        rows: [
          (null, [for (final c in cols) c.$2]),
        ],
        big: true,
      ),
      if (streak != null) ...[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: MiniChip('Streak $streak', color: streakColor(p, streak!)),
        ),
      ],
    ]);
  }
}

/// Stats block: every field as scorecard columns, rows Total and Per round
/// (four columns to a card, so labels stay readable on a phone).
class GolfStats extends StatelessWidget {
  const GolfStats({super.key, required this.nums});
  final SportNumbers nums;

  @override
  Widget build(BuildContext context) {
    final fields = nums.fields;
    if (fields.isEmpty) return const ResultsOnlyNote();
    final chunks = [
      for (var i = 0; i < fields.length; i += 4)
        fields.sublist(i, i + 4 > fields.length ? fields.length : i + 4),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const BlockHeading('Scorecard'),
      const SizedBox(height: 12),
      for (var i = 0; i < chunks.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        Scorecard(
          header: [for (final f in chunks[i]) f.label],
          rows: [
            ('Total', [for (final f in chunks[i]) '${nums.n(f.key)}']),
            ('Per rd', [for (final f in chunks[i]) nums.rate(f.key)]),
          ],
        ),
      ],
    ]);
  }
}

/// A scorecard: a green header row, then rows of thin-ruled cells, each row
/// with an optional label on the left.
class Scorecard extends StatelessWidget {
  const Scorecard({
    super.key,
    required this.header,
    required this.rows,
    this.big = false,
  });

  /// Column titles (not counting the label column).
  final List<String> header;

  /// (row label or null, one value per column).
  final List<(String?, List<String>)> rows;

  /// Larger figures (the record strip).
  final bool big;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final headBg = dark ? const Color(0xFF14532D) : const Color(0xFF166534);
    final labelled = rows.any((r) => r.$1 != null);
    const radius = BorderRadius.all(Radius.circular(12));

    Widget cell(String text, TextStyle style) => Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: big ? 12 : 9),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text,
                maxLines: 1, textAlign: TextAlign.center, style: style),
          ),
        );

    const headStyle = TextStyle(
        color: Color(0xFFFFFFFF),
        fontSize: 10.5,
        letterSpacing: 1,
        fontWeight: FontWeight.w800);
    final labelStyle = TextStyle(
        color: p.muted,
        fontSize: 10.5,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w800);

    return ClipRRect(
      borderRadius: radius,
      child: Table(
        border: TableBorder.all(color: p.line, borderRadius: radius),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: {if (labelled) 0: const FixedColumnWidth(62)},
        children: [
          TableRow(
            decoration: BoxDecoration(color: headBg),
            children: [
              if (labelled) cell('', headStyle),
              for (final h in header) cell(h.toUpperCase(), headStyle),
            ],
          ),
          for (var i = 0; i < rows.length; i++)
            TableRow(
              decoration: i.isOdd ? BoxDecoration(color: p.surface2) : null,
              children: [
                if (labelled) cell((rows[i].$1 ?? '').toUpperCase(), labelStyle),
                for (final v in rows[i].$2)
                  cell(
                      v,
                      TextStyle(
                          color: p.ink,
                          fontSize: big ? 22 : 16,
                          fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600,
                          fontFeatures: tabularFigures)),
              ],
            ),
        ],
      ),
    );
  }
}
