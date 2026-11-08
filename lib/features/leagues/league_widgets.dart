import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/shared/format/event_time.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// "2026-11-01" → "Sun, 1 Nov" (a calendar date — no zone shift).
String fixtureDay(String? ymd) {
  if (ymd == null) return '';
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(ymd);
  if (m == null) return ymd;
  return DateFormat('EEE, d MMM')
      .format(DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
}

/// A fixture's kick-off the way every event time reads (shared/format/event_time):
/// the wall clock at the venue with its zone, plus the viewer's own time when
/// they're elsewhere. Null without a date and kick-off.
EventTimeParts? fixtureTime(J f) {
  final d = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(f.s('scheduledDate') ?? '');
  final t = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(f.s('startTime') ?? '');
  if (d == null || t == null) return null;
  return formatEventTime(
    eventDate: DateTime.utc(int.parse(d[1]!), int.parse(d[2]!), int.parse(d[3]!)),
    startTime: DateTime.utc(1970, 1, 1, int.parse(t[1]!), int.parse(t[2]!)),
    timezone: f.s('timezone'),
  );
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String ymdOf(DateTime d) => _ymd(d);

/// Run a league mutation with a snackbar for success / the server's message.
Future<bool> leagueAction(
  BuildContext context,
  WidgetRef ref,
  String op,
  Map<String, dynamic> input, {
  String? success,
  List<ProviderOrFamily> refresh = const [],
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(leaguesRepositoryProvider).mutate(op, input);
    for (final p in refresh) {
      ref.invalidate(p);
    }
    if (success != null) {
      messenger.showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(
        content: Text(e is ApiException ? e.message : l10n.league_somethingWentWrong)));
    return false;
  }
}

Map<String, String> get stageStatusLabel => {
      'pending': l10n.league_waiting,
      'drafting': l10n.league_drafting,
      'open': l10n.league_inPlay,
      'closed': l10n.league_closed2,
      'advanced': l10n.league_done,
    };
Map<String, String> get leagueStatusLabel => {
      'draft': l10n.league_draft,
      'published': l10n.league_fixturesOut,
      'in_progress': l10n.league_inProgress,
      'completed': l10n.league_finished,
      'cancelled': l10n.league_cancelled,
    };

/* ─── Standings ────────────────────────────────────────────────────────── */

class StandingsTableView extends StatelessWidget {
  const StandingsTableView({super.key, required this.rows, this.showDraws = true, this.highlightTeamId});
  final List<J> rows;
  final bool showDraws;

  /// The viewer's team, tinted in the table.
  final String? highlightTeamId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    TextStyle head() => TextStyle(
        color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8);
    TextStyle cell({bool bold = false}) => TextStyle(
        color: p.ink,
        fontSize: 13,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()]);
    Widget num(String v, {bool bold = false, double w = 28}) =>
        SizedBox(width: w, child: Text(v, textAlign: TextAlign.center, style: cell(bold: bold)));
    final zones = rows.any((r) => r.s('zone') != null);
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 12, 6),
          child: Row(children: [
            SizedBox(width: 26, child: Text('#', style: head())),
            Expanded(child: Text(context.l10n.league_team4, style: head())),
            for (final h in [context.l10n.league_p, context.l10n.league_w, if (showDraws) context.l10n.league_d, context.l10n.league_l, context.l10n.league_gd])
              SizedBox(width: 28, child: Text(h, textAlign: TextAlign.center, style: head())),
            SizedBox(width: 34, child: Text(context.l10n.league_pts2, textAlign: TextAlign.center, style: head())),
          ]),
        ),
        for (final r in rows)
          InkWell(
            onTap: r.o('team') == null
                ? null
                : () => context.push('/teams/${r.o('team')!.str('id')}'),
            child: Container(
              decoration: BoxDecoration(
                color: highlightTeamId != null && r.s('teamId') == highlightTeamId
                    ? p.accentTint
                    : null,
                border: Border(top: BorderSide(color: p.surface2)),
              ),
              padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
              child: Row(children: [
                Container(
                  width: 3,
                  height: 22,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: r.s('zone') == 'promotion'
                        ? p.accentDeep
                        : r.s('zone') == 'relegation'
                            ? p.danger
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: 17, child: Text('${r.i('position')}', style: cell(bold: true))),
                Crest(
                    logoUrl: r.o('team')?.s('logoUrl'),
                    label: r.o('team')?.s('name'),
                    kitPrimary: r.o('team')?.s('kitPrimary'),
                    size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(r.o('team')?.str('name', context.l10n.league_team) ?? context.l10n.league_team,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                num('${r.i('played')}'),
                num('${r.i('won')}'),
                if (showDraws) num('${r.i('drawn')}'),
                num('${r.i('lost')}'),
                num(r.i('gd') > 0 ? '+${r.i('gd')}' : '${r.i('gd')}'),
                num('${r.i('points')}', bold: true, w: 34),
              ]),
            ),
          ),
        if (zones)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
            child: Row(children: [
              _legend(p.accentDeep, context.l10n.league_promotion, p),
              const SizedBox(width: 14),
              _legend(p.danger, context.l10n.league_relegation, p),
            ]),
          ),
      ]),
    );
  }

  Widget _legend(Color c, String t, AppPalette p) => Row(children: [
        Container(width: 3, height: 12, color: c),
        const SizedBox(width: 6),
        Text(t, style: TextStyle(color: p.muted, fontSize: 11)),
      ]);
}

/* ─── Fixtures ─────────────────────────────────────────────────────────── */

class FixtureTile extends StatelessWidget {
  const FixtureTile({super.key, required this.f, this.trailing});
  final J f;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final live = f.s('gameStatus') == 'live' || f.s('status') == 'live';
    final done = f.s('status') == 'completed';
    final st = f.s('startTime');
    final center = done || live
        ? '${f.i('homeScore')} – ${f.i('awayScore')}'
        : st != null
            ? formatTime12(st)
            : context.l10n.profile_vsLabel;
    final dec = f.s('decision');
    final sub = dec == 'forfeit'
        ? context.l10n.league_forfeit
        : dec == 'shootout'
            ? context.l10n.league_pens2(f.i('homeSo'), f.i('awaySo'))
            : dec == 'extra_time'
                ? context.l10n.league_p5Aet
                : live
                    ? context.l10n.league_live2
                    : switch (f.s('status')) {
                        'postponed' => context.l10n.league_postponed,
                        'cancelled' => context.l10n.league_cancelled,
                        'unscheduled' => context.l10n.league_noDate,
                        _ => null,
                      };
    Widget side(J? team, String? slot, bool home) {
      final name = Text(team?.str('name') ?? slot ?? context.l10n.league_tbc,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: home ? TextAlign.right : TextAlign.left,
          style: TextStyle(
              color: team == null ? p.muted : p.ink,
              fontStyle: team == null ? FontStyle.italic : FontStyle.normal,
              fontSize: 13,
              fontWeight: FontWeight.w600));
      final crest = Crest(
          logoUrl: team?.s('logoUrl'), label: team?.s('name') ?? '?', kitPrimary: team?.s('kitPrimary'), size: 26);
      return Expanded(
        child: Row(
          mainAxisAlignment: home ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: home
              ? [Flexible(child: name), const SizedBox(width: 8), crest]
              : [crest, const SizedBox(width: 8), Flexible(child: name)],
        ),
      );
    }

    final gameId = f.s('gameId');
    final agg = f.o('aggregate');
    // Kick-off is local time at the venue: its zone, and the viewer's own time when elsewhere.
    final when = done ? null : fixtureTime(f);
    final meta = [
      f.s('label'),
      if (agg != null)
        agg.s('decidedBy') == 'away_goals'
            ? context.l10n.league_p5AggAwayGoals(agg.i('home'), agg.i('away'))
            : context.l10n.league_p5Agg(agg.i('home'), agg.i('away')),
      f.s('scheduledDate') != null ? fixtureDay(f.s('scheduledDate')) : null,
      if (when?.venueZone != null) '${when!.venueTime} ${when.venueZone}',
      if (when?.viewerTime != null) context.l10n.common_yourTime(when!.viewerTime!),
      f.s('venue') ?? (f.s('scheduledDate') != null && !done ? context.l10n.league_p5VenueTbc : null),
    ]
        .whereType<String>()
        .join(' · ');
    return InkWell(
      onTap: gameId == null ? null : () => context.push('/games/$gameId'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(children: [
              Row(children: [
                side(f.o('home'), f.s('homeSlot'), true),
                SizedBox(
                  width: 70,
                  child: Column(children: [
                    Text(center,
                        style: TextStyle(
                            color: live ? p.danger : p.ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
                    if (sub != null)
                      Text(sub,
                          style: TextStyle(
                              color: live ? p.danger : p.muted,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6)),
                  ]),
                ),
                side(f.o('away'), f.s('awaySlot'), false),
              ]),
              const SizedBox(height: 4),
              Text(meta.isEmpty ? context.l10n.league_dateToBeConfirmed : meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}

/// Fixtures grouped by round, each round a card of tiles.
class RoundsView extends StatelessWidget {
  const RoundsView({super.key, required this.fixtures, this.trailing});
  final List<J> fixtures;
  final Widget? Function(J f)? trailing;

  @override
  Widget build(BuildContext context) {
    final rounds = <int, List<J>>{};
    for (final f in fixtures) {
      rounds.putIfAbsent(f.i('round'), () => []).add(f);
    }
    final keys = rounds.keys.toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final r in keys) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
          child: SpSectionTitle(
              rounds[r]!.first.s('label')?.replaceAll(RegExp(r'\s\d+$'), '') ?? context.l10n.league_round3(r)),
        ),
        SpListCard(children: [
          for (final f in rounds[r]!) FixtureTile(f: f, trailing: trailing?.call(f)),
        ]),
      ],
    ]);
  }
}

/* ─── Bracket ──────────────────────────────────────────────────────────── */

class BracketView extends StatelessWidget {
  const BracketView({
    super.key,
    required this.fixtures,
    this.actions,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });
  final List<J> fixtures;
  final Widget? Function(J f)? actions;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Legs of a tie share stage + bracket key; a tie's column is its deciding leg's round.
    final byKey = <String, List<J>>{};
    for (final f in fixtures) {
      final k = f.s('bracketKey') != null ? '${f.s('stageId')}|${f.s('bracketKey')}' : f.str('id');
      (byKey[k] ??= []).add(f);
    }
    final ties = [
      for (final legs in byKey.values) (legs..sort((a, b) => a.i('leg').compareTo(b.i('leg')))),
    ];
    J deciding(List<J> t) => t.last;
    bool third(List<J> t) => deciding(t).s('bracketKey') == '3P';
    final rounds = ties.where((t) => !third(t)).map((t) => deciding(t).i('round')).toSet().toList()..sort();
    if (rounds.isEmpty) return const SizedBox.shrink();
    String nameOf(J f) => f.s('tieName') ?? f.s('label')?.replaceAll(RegExp(r'\s\d+$'), '') ?? context.l10n.league_round4(f.i('round'));
    Widget tie(List<J> t) {
      final d = deciding(t);
      if (t.length < 2) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: _BracketMatch(f: d, action: actions?.call(d), p: p),
        );
      }
      final agg = d.o('aggregate');
      final w = d.s('status') == 'completed' ? d.s('winnerTeamId') : null;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final f in t) ...[
            _BracketMatch(f: f, action: actions?.call(f), p: p, legLabel: f.i('leg') == 1 ? context.l10n.league_t1stLeg : context.l10n.league_t2ndLeg, quiet: true),
            const SizedBox(height: 4),
          ],
          if (agg != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                  _aggLine(context, d, agg, w),
                  style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w600)),
            ),
        ]),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final r in rounds) ...[
            SizedBox(
              width: 210,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Eyebrow(nameOf(deciding(ties.firstWhere((t) => !third(t) && deciding(t).i('round') == r)))),
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      for (final t in ties.where((t) => !third(t) && deciding(t).i('round') == r)) tie(t),
                      if (r == rounds.last)
                        for (final t in ties.where(third)) ...[
                          Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 2), child: Eyebrow(context.l10n.league_thirdPlace)),
                          tie(t),
                        ],
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 10),
          ],
        ]),
      ),
    );
  }
}

class _BracketMatch extends StatelessWidget {
  const _BracketMatch({required this.f, required this.p, this.action, this.legLabel, this.quiet = false});
  final J f;
  final AppPalette p;
  final Widget? action;

  /// "1st leg" / "2nd leg" for two-leg ties.
  final String? legLabel;

  /// Legs don't bold a winner — the aggregate decides.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final done = f.s('status') == 'completed';
    final winner = f.s('winnerTeamId');
    Widget row(J? team, String? slot, int score, int? so) {
      final won = !quiet && done && team != null && team.s('id') == winner;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(children: [
          Crest(logoUrl: team?.s('logoUrl'), label: team?.s('name') ?? '?', kitPrimary: team?.s('kitPrimary'), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(team?.str('name') ?? slot ?? context.l10n.league_tbc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: team == null ? p.muted : p.ink,
                    fontStyle: team == null ? FontStyle.italic : FontStyle.normal,
                    fontSize: 12.5,
                    fontWeight: won ? FontWeight.w800 : FontWeight.w500)),
          ),
          if (done || f.s('gameStatus') == 'live')
            Text('$score${f.s('decision') == 'shootout' && so != null ? ' ($so)' : ''}',
                style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: won ? FontWeight.w800 : FontWeight.w500)),
        ]),
      );
    }

    final gameId = f.s('gameId');
    return GlassCard(
      padding: EdgeInsets.zero,
      onTap: gameId == null ? null : () => context.push('/games/$gameId'),
      child: Column(children: [
        row(f.o('home'), f.s('homeSlot'), f.i('homeScore'), f.iOrNull('homeSo')),
        Divider(height: 1, color: p.surface2),
        row(f.o('away'), f.s('awaySlot'), f.i('awayScore'), f.iOrNull('awaySo')),
        Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: p.surface2))),
          padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
          child: Row(children: [
            Expanded(
              child: Text(
                  [
                    if (legLabel != null) legLabel!,
                    f.s('decision') == 'forfeit'
                        ? context.l10n.league_forfeit
                        : f.s('scheduledDate') != null
                            ? fixtureDay(f.s('scheduledDate'))
                            : context.l10n.tournament_dateTbc,
                  ].join(' · '),
                  style: TextStyle(color: p.muted, fontSize: 10.5)),
            ),
            if (action != null) action!,
          ]),
        ),
      ]),
    );
  }
}

/// A two-leg tie's aggregate line — one whole sentence per outcome:
/// "Agg Lions 3–2 Tigers · Lions through on away goals".
String _aggLine(BuildContext context, J d, J agg, String? winnerId) {
  final l = context.l10n;
  final home = d.o('home')?.str('name', l.league_home) ?? l.league_home;
  final away = d.o('away')?.str('name', l.league_away) ?? l.league_away;
  final hg = agg.i('home');
  final ag = agg.i('away');
  if (winnerId == null) return l.league_p5AggTie(home, hg, ag, away);
  final winner = (winnerId == d.o('home')?.s('id') ? d.o('home')?.str('name') : d.o('away')?.str('name')) ?? '';
  return switch (agg.s('decidedBy')) {
    'away_goals' => l.league_p5AggTieThroughAwayGoals(home, hg, ag, away, winner),
    'shootout' => l.league_p5AggTieThroughPenalties(home, hg, ag, away, winner),
    _ => l.league_p5AggTieThrough(home, hg, ag, away, winner),
  };
}

/// A rotating-ish label for the league/stage kind.
String stageKindLabel(String? k) => switch (k) {
      'groups' => l10n.league_groups,
      'split' => l10n.league_splitTables,
      'knockout' => l10n.league_knockout,
      _ => l10n.league_leagueTable,
    };
