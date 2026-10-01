import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/sports/attendance_blocks.dart';
import 'package:sportpadi_mobile/features/sports/baseball_blocks.dart';
import 'package:sportpadi_mobile/features/sports/basketball_blocks.dart';
import 'package:sportpadi_mobile/features/sports/chess_blocks.dart';
import 'package:sportpadi_mobile/features/sports/generic_blocks.dart';
import 'package:sportpadi_mobile/features/sports/golf_blocks.dart';
import 'package:sportpadi_mobile/features/sports/padel_blocks.dart';
import 'package:sportpadi_mobile/features/sports/paintball_blocks.dart';
import 'package:sportpadi_mobile/features/sports/soccer_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/features/sports/table_tennis_blocks.dart';
import 'package:sportpadi_mobile/features/sports/tennis_blocks.dart';
import 'package:sportpadi_mobile/features/sports/ultimate_blocks.dart';
import 'package:sportpadi_mobile/features/sports/volleyball_blocks.dart';

/// The two bespoke blocks of a sport record (design §5), and the pieces the
/// per-sport files share.
///
/// [SportRecordBlock] answers "how do they do" — the sport's own way of
/// writing a record (a league-table row, a scoreboard, standings …).
/// [SportStatsBlock] answers "what do they do" — the sport's numbers laid out
/// the way that sport reads them, then "More stats" for any key the sport's
/// owner added that the design doesn't know.

/// One scope's numbers for one sport, with the lookups every block needs.
class SportNumbers {
  SportNumbers(this.family, List<Map<String, dynamic>> rawFields, this.tally)
      : fields = statFields(rawFields, family),
        counts = mapOf(tally['counts']);

  final SportFamily family;
  final Map<String, dynamic> tally;
  final List<SportStat> fields;
  final Map<String, dynamic> counts;

  int get games => gamesOf(tally);
  int get starts => statInt(tally['starts']);
  int get wins => statInt(tally['wins']);
  int get draws => statInt(tally['draws']);
  int get losses => statInt(tally['losses']);
  int get winRate => statInt(tally['winRate']);
  int get points => statInt(tally['points']);

  int n(String key) => countOf(counts, key);
  bool has(String key) => hasStat(key, fields, counts);
  SportStat field(String key) => fieldFor(key, fields, family);
  String rate(String key, {int decimals = 1}) =>
      perGame(n(key), games, decimals: decimals);
}

/// The sport's record block for one scope.
class SportRecordBlock extends StatelessWidget {
  const SportRecordBlock({
    super.key,
    required this.family,
    required this.tally,
    this.recent = const [],
  });
  final SportFamily family;
  final Map<String, dynamic> tally;

  /// The scope's recent games (newest first) — for the streak (and ping
  /// pong's last ten).
  final List<Map<String, dynamic>> recent;

  @override
  Widget build(BuildContext context) {
    final nums = SportNumbers(family, const [], tally);
    final streak = streakOf(recent);
    return switch (family) {
      SportFamily.soccer => SoccerRecord(nums: nums),
      SportFamily.basketball => BasketballRecord(nums: nums, streak: streak),
      SportFamily.volleyball => VolleyballRecord(nums: nums, streak: streak),
      SportFamily.baseball => BaseballRecord(nums: nums, streak: streak),
      SportFamily.tennis => TennisRecord(nums: nums, streak: streak),
      // Pairs, and ultimate's teams: W–L over a split bar.
      SportFamily.padel ||
      SportFamily.ultimate =>
        VolleyballRecord(nums: nums, streak: streak),
      SportFamily.tableTennis =>
        TableTennisRecord(nums: nums, recent: recent, streak: streak),
      SportFamily.chess => ChessRecord(nums: nums),
      SportFamily.golf => GolfRecord(nums: nums, streak: streak),
      SportFamily.running => RaceRecord(nums: nums),
      SportFamily.paintball => PaintballRecord(nums: nums, streak: streak),
      SportFamily.hiking || SportFamily.generic => GenericRecord(nums: nums),
    };
  }
}

/// What a record block is called in the sport's own words.
String recordBlockTitle(SportFamily f) => switch (f) {
      SportFamily.soccer => 'League table',
      SportFamily.basketball => 'Scoreboard',
      SportFamily.volleyball => 'Won – lost',
      SportFamily.baseball => 'Standings',
      SportFamily.tennis => 'Match record',
      SportFamily.padel => 'Pairs record',
      SportFamily.tableTennis => 'Won – lost',
      SportFamily.chess => 'Results',
      SportFamily.ultimate => 'Won – lost',
      SportFamily.golf => 'Scorecard',
      SportFamily.running => 'Races',
      SportFamily.paintball => 'Won – lost',
      SportFamily.hiking || SportFamily.generic => 'Record',
    };

/// The sport's stats block for one scope (no card of its own — the caller
/// puts it in one).
class SportStatsBlock extends StatelessWidget {
  const SportStatsBlock({
    super.key,
    required this.family,
    required this.fields,
    required this.tally,
    this.showMore = true,
  });
  final SportFamily family;
  final List<Map<String, dynamic>> fields;
  final Map<String, dynamic> tally;

  /// Follow with "More stats" for keys the design doesn't place.
  final bool showMore;

  @override
  Widget build(BuildContext context) {
    final nums = SportNumbers(family, fields, tally);
    return switch (family) {
      SportFamily.soccer => SoccerStats(nums: nums, showMore: showMore),
      SportFamily.basketball => BasketballStats(nums: nums, showMore: showMore),
      SportFamily.volleyball => VolleyballStats(nums: nums, showMore: showMore),
      SportFamily.baseball => BaseballStats(nums: nums, showMore: showMore),
      SportFamily.tennis => TennisStats(nums: nums, showMore: showMore),
      SportFamily.padel => PadelStats(nums: nums, showMore: showMore),
      SportFamily.tableTennis =>
        TableTennisStats(nums: nums, showMore: showMore),
      SportFamily.chess => ChessStats(nums: nums, showMore: showMore),
      SportFamily.ultimate => UltimateStats(nums: nums, showMore: showMore),
      SportFamily.golf => GolfStats(nums: nums),
      SportFamily.paintball => PaintballStats(nums: nums),
      SportFamily.hiking ||
      SportFamily.running ||
      SportFamily.generic =>
        GenericStats(nums: nums),
    };
  }
}

// ── Shared pieces ───────────────────────────────────────────────────────────

/// A small uppercase heading inside a block.
class BlockHeading extends StatelessWidget {
  const BlockHeading(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(children: [
      Expanded(
        child: Text(text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: p.muted,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800)),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

/// A hairline between a block's sections.
class BlockDivider extends StatelessWidget {
  const BlockDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Divider(height: 1, thickness: 1, color: context.palette.line),
      );
}

/// A big figure, its label and an optional per-game line.
class StatFigure extends StatelessWidget {
  const StatFigure({
    super.key,
    required this.value,
    required this.label,
    this.sub,
    this.color,
    this.size = 26,
  });
  final String value;
  final String label;
  final String? sub;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                maxLines: 1,
                style: TextStyle(
                    color: color ?? p.ink,
                    fontSize: size,
                    height: 1.05,
                    letterSpacing: -0.5,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures)),
          ),
          const SizedBox(height: 3),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
          if (sub != null)
            Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.muted,
                    fontSize: 11,
                    fontFeatures: tabularFigures)),
        ]);
  }
}

/// A simple stat table: a header row of tiny uppercase column names, then
/// zebra rows of tabular figures ("Total", "Per game").
class StatTable extends StatelessWidget {
  const StatTable({super.key, required this.columns, required this.rows});

  /// Column headers ("G", "PTS" …).
  final List<String> columns;

  /// (row label, one value per column).
  final List<(String, List<String>)> rows;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const labelW = 72.0;
    Widget cell(String text, {required bool head, bool bold = false}) =>
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(text,
                maxLines: 1,
                textAlign: TextAlign.center,
                style: head
                    ? TextStyle(
                        color: p.muted,
                        fontSize: 10.5,
                        letterSpacing: 1,
                        fontWeight: FontWeight.w800)
                    : TextStyle(
                        color: p.ink,
                        fontSize: 16,
                        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                        fontFeatures: tabularFigures)),
          ),
        );
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          const SizedBox(width: labelW),
          for (final c in columns) cell(c, head: true),
        ]),
      ),
      const SizedBox(height: 6),
      for (var i = 0; i < rows.length; i++)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: i.isEven ? p.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            SizedBox(
              width: labelW,
              child: Text(rows[i].$1.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 10.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800)),
            ),
            for (final v in rows[i].$2) cell(v, head: false, bold: i == 0),
          ]),
        ),
    ]);
  }
}

/// Two-up tiles for stat fields: icon + label, the total, and per game.
class StatTileGrid extends StatelessWidget {
  const StatTileGrid({
    super.key,
    required this.fields,
    required this.counts,
    required this.games,
  });
  final List<SportStat> fields;
  final Map<String, dynamic> counts;
  final int games;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(builder: (context, box) {
      final tileW = (box.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in fields)
          Container(
            width: tileW,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(16),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (f.icon != null) ...[
                  Text(f.icon!, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(f.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Text('${countOf(counts, f.key)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 22,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          fontFeatures: tabularFigures)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                      '${perGame(countOf(counts, f.key), games)} / game',
                      style: TextStyle(
                          color: p.muted,
                          fontSize: 11,
                          fontFeatures: tabularFigures)),
                ),
              ]),
            ]),
          ),
      ]);
    });
  }
}

/// "More stats": every field of the sport the bespoke design didn't place.
class MoreStats extends StatelessWidget {
  const MoreStats({super.key, required this.nums, required this.placed});
  final SportNumbers nums;

  /// Keys the design already shows.
  final Set<String> placed;

  @override
  Widget build(BuildContext context) {
    final rest = [
      for (final f in nums.fields)
        if (!placed.contains(f.key)) f
    ];
    if (rest.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const BlockDivider(),
      const BlockHeading('More stats'),
      const SizedBox(height: 10),
      StatTileGrid(fields: rest, counts: nums.counts, games: nums.games),
    ]);
  }
}

/// A thin rounded progress bar.
class ThinBar extends StatelessWidget {
  const ThinBar({super.key, required this.value, this.color, this.height = 6});
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ColoredBox(
          color: p.surface2,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.isNaN ? 0.0 : value.clamp(0.0, 1.0),
            child: ColoredBox(color: color ?? p.accent),
          ),
        ),
      ),
    );
  }
}

/// A small coloured chip ("W3", "61% wins").
class MiniChip extends StatelessWidget {
  const MiniChip(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = color ?? p.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color == null ? p.surface2 : c.withAlpha(36),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              color: c,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              fontFeatures: tabularFigures)),
    );
  }
}

/// A rounded bar split into coloured parts — zero parts drop out, a hairline
/// gap between the rest; an empty track when everything is zero.
class SegmentBar extends StatelessWidget {
  const SegmentBar({super.key, required this.parts, this.height = 12});

  /// (count, colour), left to right.
  final List<(int, Color)> parts;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final shown = [
      for (final part in parts)
        if (part.$1 > 0) part
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: shown.isEmpty
            ? ColoredBox(color: p.surface2)
            : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                      flex: shown[i].$1, child: ColoredBox(color: shown[i].$2)),
                ],
              ]),
      ),
    );
  }
}

/// One line of a bar's legend: dot, label, count and share of [total].
class LegendLine extends StatelessWidget {
  const LegendLine({
    super.key,
    required this.color,
    required this.label,
    required this.value,
    required this.total,
  });
  final Color color;
  final String label;
  final int value;
  final int total;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
        Text('$value',
            style: TextStyle(
                color: p.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                fontFeatures: tabularFigures)),
        SizedBox(
          width: 48,
          child: Text(total > 0 ? '${(value * 100 / total).round()}%' : '—',
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: p.muted,
                  fontSize: 12.5,
                  fontFeatures: tabularFigures)),
        ),
      ]),
    );
  }
}

/// "● Aces 24" — an inline legend item.
class LegendItem extends StatelessWidget {
  const LegendItem(
      {super.key,
      required this.color,
      required this.label,
      required this.value});
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 7),
      Flexible(
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: '$label  ', style: TextStyle(color: p.muted)),
            TextSpan(
                text: value,
                style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFeatures: tabularFigures),
        ),
      ),
    ]);
  }
}

/// "This sport keeps results only" — a stats block with no stats to show.
class ResultsOnlyNote extends StatelessWidget {
  const ResultsOnlyNote({super.key});

  @override
  Widget build(BuildContext context) =>
      Text('This sport keeps results only — no individual stats.',
          style: TextStyle(color: context.palette.muted, fontSize: 12.5));
}

/// The colour a streak chip reads in.
Color streakColor(AppPalette p, String streak) => streak.startsWith('W')
    ? p.greenText
    : streak.startsWith('L')
        ? p.danger
        : p.muted;
