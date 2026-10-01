import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/sports/sport_blocks.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Showing up (design §8). Hiking 🥾 and running 🏃 are about turning up,
/// not winning: their record block is twelve months of check-ins (bars for
/// hiking, track lanes for running) and their "recent games" are recent
/// outings. Every other sport with check-ins gets the compact
/// [ShowingUpStrip].

/// The attendance record block: check-ins month by month, then the last 30
/// days, this year and the weekly streak.
class AttendanceBlock extends StatelessWidget {
  const AttendanceBlock({
    super.key,
    required this.family,
    required this.attendance,
  });
  final SportFamily family;
  final Map<String, dynamic> attendance;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final months = monthlyOf(attendance);
    final last30 = statInt(attendance['last30']);
    final thisYear = statInt(attendance['thisYear']);
    final streak = statInt(attendance['weekStreak']);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (months.isEmpty)
        Text('The month-by-month view appears after the next check-in.',
            style: TextStyle(color: p.muted, fontSize: 12.5))
      else if (family == SportFamily.running)
        _LaneChart(months: months)
      else
        _MonthBars(family: family, months: months),
      const SizedBox(height: 14),
      Wrap(spacing: 6, runSpacing: 6, children: [
        MiniChip('Last 30 days: $last30', color: sportInk(family, dark: dark)),
        MiniChip('$thisYear this year'),
        if (streak > 0) MiniChip('🔥 $streak-week streak', color: p.orangeInk),
      ]),
    ]);
  }
}

/// Hiking: twelve vertical bars, oldest on the left; this month in the
/// trail's sun-yellow.
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.family, required this.months});
  final SportFamily family;
  final List<(String, int)> months;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = sportInk(family, dark: dark);
    final now = dark ? const Color(0xFFFDE68A) : const Color(0xFFD97706);
    final top = months.fold<int>(0, (m, e) => math.max(m, e.$2));
    const maxBar = 92.0;

    return SizedBox(
      height: 132,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < months.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (months[i].$2 > 0)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${months[i].$2}',
                        style: TextStyle(
                            color: i == months.length - 1 ? p.ink : p.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            fontFeatures: tabularFigures)),
                  ),
                const SizedBox(height: 3),
                Container(
                  height: months[i].$2 <= 0 || top <= 0
                      ? 3.0
                      : math.max(6.0, maxBar * months[i].$2 / top),
                  decoration: BoxDecoration(
                    color: i == months.length - 1
                        ? now
                        : months[i].$2 <= 0
                            ? p.surface2
                            : ink.withAlpha(dark ? 150 : 175),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6), bottom: Radius.circular(2)),
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(monthLabel(months[i].$1),
                      maxLines: 1,
                      style: TextStyle(
                          color: i == months.length - 1 ? p.ink : p.muted,
                          fontSize: 10,
                          fontWeight: i == months.length - 1
                              ? FontWeight.w800
                              : FontWeight.w600)),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// Running: the months as track lanes — lane 1 is this month — each with a
/// bar as long as its runs.
class _LaneChart extends StatelessWidget {
  const _LaneChart({required this.months});
  final List<(String, int)> months;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final track = dark ? const Color(0xFF3B1D1A) : const Color(0xFFFBE3DD);
    final laneLine = dark ? const Color(0x2EFFFFFF) : const Color(0xFFFFFFFF);
    final laneNo = dark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);
    final bar = sportInk(SportFamily.running, dark: dark);
    final lanes = months.reversed.toList();
    final top = lanes.fold<int>(0, (m, e) => math.max(m, e.$2));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        for (var i = 0; i < lanes.length; i++)
          Container(
            height: 24,
            decoration: i < lanes.length - 1
                ? BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: laneLine, width: 1.5)))
                : null,
            child: Row(children: [
              SizedBox(
                width: 18,
                child: Text('${i + 1}',
                    style: TextStyle(
                        color: laneNo,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        fontFeatures: tabularFigures)),
              ),
              SizedBox(
                width: 32,
                child: Text(monthLabel(lanes[i].$1),
                    maxLines: 1,
                    style: TextStyle(
                        color: i == 0 ? p.ink : p.muted,
                        fontSize: 11.5,
                        fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600)),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor:
                        top <= 0 ? 0.0 : (lanes[i].$2 / top).clamp(0.0, 1.0),
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: i == 0 ? bar : bar.withAlpha(dark ? 140 : 150),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text(lanes[i].$2 > 0 ? '${lanes[i].$2}' : '–',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: lanes[i].$2 > 0 ? p.ink : p.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        fontFeatures: tabularFigures)),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Running with races on record: won and lost, and podiums (= wins).
class RaceRecord extends StatelessWidget {
  const RaceRecord({super.key, required this.nums});
  final SportNumbers nums;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tiles = <(String, int, Color, Color)>[
      ('Won', nums.wins, p.accentTint, p.greenText),
      if (nums.draws > 0) ('Drawn', nums.draws, p.surface2, p.muted),
      ('Lost', nums.losses, p.liveTint, p.danger),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (var i = 0; i < tiles.length; i++)
          Expanded(
            child: Container(
              height: 64,
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
      Wrap(spacing: 6, runSpacing: 6, children: [
        MiniChip('🏅 ${plural(nums.wins, 'podium')}', color: p.orangeInk),
        MiniChip(gamesPhrase(SportFamily.running, nums.games)),
      ]),
    ]);
  }
}

/// Recent outings — the events of this sport they checked in to, newest
/// first. Tap → the event.
class RecentOutings extends StatefulWidget {
  const RecentOutings({
    super.key,
    required this.family,
    required this.outings,
    this.title = 'Recent outings',
    this.initial = 5,
  });
  final SportFamily family;

  /// `attendance.recent`, newest first.
  final List<Map<String, dynamic>> outings;
  final String title;
  final int initial;

  @override
  State<RecentOutings> createState() => _RecentOutingsState();
}

class _RecentOutingsState extends State<RecentOutings> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final outings = widget.outings;
    final shown = _all ? outings : outings.take(widget.initial).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RecordSectionTitle(widget.title, count: outings.length),
      const SizedBox(height: 10),
      RecordList(children: [
        for (final o in shown) OutingRow(family: widget.family, outing: o),
        if (outings.length > shown.length)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _all = true),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Center(
                child: Text('Show all ${outings.length}',
                    style: TextStyle(
                        color: p.greenText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
      ]),
    ]);
  }
}

/// One outing: the event, its day, where, and with which group.
class OutingRow extends StatelessWidget {
  const OutingRow({super.key, required this.family, required this.outing});
  final SportFamily family;
  final Map<String, dynamic> outing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = sportInk(family, dark: dark);
    final title = parseStr(outing['title']) ?? 'Event';
    final target = parseStr(outing['slug']) ?? parseStr(outing['eventId']);
    final eventDay = shortDay(outing['date']);
    final day = eventDay.isNotEmpty ? eventDay : shortDay(outing['checkedInAt']);
    final meta = [
      day,
      parseStr(outing['locationName']),
      parseStr(outing['groupName']),
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final emoji = switch (family) {
      SportFamily.hiking => '⛰️',
      SportFamily.running => '👟',
      _ => '📍',
    };

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: target == null ? null : () => context.push('/events/$target'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: ink.withAlpha(dark ? 40 : 26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ],
                ]),
          ),
          if (target != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
          ],
        ]),
      ),
    );
  }
}

/// "Showing up": check-ins this year · weekly streak, for a sport with
/// check-ins whose record leads with games.
class ShowingUpStrip extends StatelessWidget {
  const ShowingUpStrip({super.key, required this.attendance});
  final Map<String, dynamic> attendance;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final checkIns = statInt(attendance['checkIns']);
    final thisYear = statInt(attendance['thisYear']);
    final streak = statInt(attendance['weekStreak']);
    final last = shortDay(attendance['lastAt']);
    final line = [
      thisYear > 0
          ? '${plural(thisYear, 'check-in')} this year'
          : '${plural(checkIns, 'check-in')} in all',
      if (streak > 0)
        '$streak-week streak'
      else if (last.isNotEmpty)
        'last $last',
    ].join(' · ');

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(children: [
        SpIconTile(Icons.event_available_rounded,
            bg: p.accentTint, fg: p.greenText, size: 40, iconSize: 19),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Showing up',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 12.5,
                        fontFeatures: tabularFigures)),
              ]),
        ),
        if (streak > 0) ...[
          const SizedBox(width: 8),
          MiniChip('🔥 $streak', color: p.orangeInk),
        ],
      ]),
    );
  }
}
