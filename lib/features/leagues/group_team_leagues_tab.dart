import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/features/leagues/league_commercials.dart' show spotMoney;
import 'package:sportpadi_mobile/features/leagues/league_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

String ordinal(int n) {
  final t = n % 100;
  final s = (t >= 11 && t <= 13)
      ? 'th'
      : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  return '$n$s';
}

/// Top three plus the rows around the team — enough to see where it sits.
List<J> tableWindow(List<J> rows, String teamId) {
  if (rows.length <= 6) return rows;
  final me = rows.indexWhere((r) => r.s('teamId') == teamId);
  return [
    for (var i = 0; i < rows.length; i++)
      if (i < 3 || (i - me).abs() <= 1 || (me <= 3 && i < 5)) rows[i],
  ];
}

/// A group's Leagues tab (web GroupTeamLeagues): the leagues its TEAMS play
/// in (the ones the group runs sit with its tournaments), grouped by team.
/// Each league is a small hub the team follows and runs its season from:
///   invited  → accept / decline (admins)
///   upcoming → accepted, organiser still setting up: who's in, the roster
///   active   → where it stands, next matches, results, its table, forfeits,
///              the roster
///   past     → how it finished
/// Shown once a team of the group has been in (or invited to) a league.
class GroupTeamLeaguesTab extends ConsumerWidget {
  const GroupTeamLeaguesTab({super.key, required this.groupId, this.phases, this.search = '', this.embedded = false});
  final String groupId;

  /// Only entries in these phases (invited | upcoming | active | past); null = all.
  final Set<String>? phases;

  /// Narrow by competition, season, division, team or organiser.
  final String search;

  /// Inside the League screen: no outer padding, and nothing when nothing matches.
  final bool embedded;

  /// Does this entry pass [phases] and [search]?
  static bool keep(J e, Set<String>? phases, String search) {
    if (phases != null && !phases.contains(e.s('phase'))) return false;
    final n = search.trim().toLowerCase();
    if (n.isEmpty) return true;
    final l = e.o('league');
    return [l?.s('competitionName'), l?.s('season'), l?.s('division'), e.s('teamName'), e.o('organiser')?.s('name')]
        .any((x) => x?.toLowerCase().contains(n) ?? false);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final q = ref.watch(groupTeamLeaguesProvider(groupId));
    return AsyncView(
      value: q,
      onRetry: () => ref.invalidate(groupTeamLeaguesProvider(groupId)),
      data: (d) {
        final teams = [
          for (final t in d.list('teams'))
            if (t.list('entries').any((e) => keep(e, phases, search))) t,
        ];
        if (teams.isEmpty) {
          if (embedded) return const SizedBox.shrink();
          return const Padding(
            padding: EdgeInsets.all(20),
            child: SpEmpty(icon: Icons.emoji_events_rounded, text: "None of this group's teams is in a league yet."),
          );
        }
        return Padding(
          padding: embedded ? EdgeInsets.zero : const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (d.i('invitations') > 0 && (phases == null || phases!.contains('invited'))) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.orangeTint, borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  SpIconTile(Icons.mark_email_unread_outlined, bg: p.surface, fg: p.orangeInk, size: 38, iconSize: 19),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${d.i('invitations')} league invitation${d.i('invitations') == 1 ? '' : 's'} waiting',
                        style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
            ],
            for (final t in teams) ...[
              InkWell(
                onTap: () => context.push('/teams/${t.o('team')?.str('id')}'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
                  child: Row(children: [
                    Crest(
                        logoUrl: t.o('team')?.s('logoUrl'),
                        label: t.o('team')?.s('name'),
                        kitPrimary: t.o('team')?.s('kitPrimary'),
                        size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(t.o('team')?.str('name') ?? 'Team',
                          style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
                    Text('${t.list('entries').where((e) => keep(e, phases, search)).length} league${t.list('entries').where((e) => keep(e, phases, search)).length == 1 ? '' : 's'}',
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                    Icon(Icons.chevron_right_rounded, color: p.muted),
                  ]),
                ),
              ),
              for (final e in t.list('entries').where((e) => keep(e, phases, search))) ...[
                _LeagueHub(e: e, groupId: groupId, isAdmin: d.b('isAdmin')),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 12),
            ],
          ]),
        );
      },
    );
  }
}

class _LeagueHub extends ConsumerWidget {
  const _LeagueHub({required this.e, required this.groupId, required this.isAdmin});
  final J e;
  final String groupId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = e.o('league');
    final d = e.o('detail');
    final phase = e.str('phase');
    final champion = e.b('champion');
    final published = l?.s('status') != 'draft';
    final teamName = e.str('teamName', 'Your team');
    final organiser = e.o('organiser')?.s('name');
    // Entry fee (team admins): "due" on an invite, "pending" mid-checkout.
    final fee = e.o('fee');
    final feeDue = fee != null && (fee.str('status') == 'due' || fee.str('status') == 'pending');
    final feeLabel = fee == null ? '' : spotMoney(fee.i('amountMinor'), fee.str('currency'), fee.i('exponent', 2));

    final (String badge, Color? tone) = switch (phase) {
      'invited' => ('Invited', p.orangeInk),
      'upcoming' => ('Starting soon', p.ink),
      'active' => ('Playing', p.greenText),
      _ => (champion ? 'Champions' : 'Finished', champion ? p.greenText : null),
    };

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SpBadge(badge, tone: tone),
                Text(l?.str('season') ?? '', style: TextStyle(color: p.muted, fontSize: 11)),
                if (l?.s('division') != null) SpBadge(l!.str('division')),
              ]),
              const SizedBox(height: 6),
              Text(l?.str('competitionName') ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.ink, fontWeight: FontWeight.w800, fontSize: 15)),
              Text('by ${organiser ?? 'an organiser'} · ${l?.str('format') ?? ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          if (published && phase != 'invited')
            SpPill(
              label: 'League',
              tone: SpPillTone.outline,
              height: 32,
              onTap: () => context.push('/leagues/${l?.str('slug')}'),
            ),
        ]),

        // Invited: answer it
        if (phase == 'invited') ...[
          const SizedBox(height: 10),
          Text(
              'Accepting enters $teamName and registers its current players '
              '(rosters take ${l?.o('rosters')?.i('minPlayers')}–${l?.o('rosters')?.i('maxPlayers')}). '
              "You can edit the roster until the organiser's cutoff.",
              style: TextStyle(color: p.muted, fontSize: 12.5)),
          // Entry fee: paying (card checkout into the organiser's wallet) is what accepts.
          if (feeDue) ...[
            const SizedBox(height: 10),
            _Strip(
              icon: Icons.credit_card_rounded,
              bg: p.orangeTint,
              fg: p.orangeInk,
              title: 'Entry fee $feeLabel.',
              text: 'Paid by card to ${organiser ?? 'the organiser'} — paying accepts the invite. If the organiser removes your team '
                  "before the season starts, the fee comes back (SportPadi's processing fee doesn't)."
                  '${fee.str('status') == 'pending' ? ' A payment was started — if you finished it, tap Check payment.' : ''}',
            ),
          ],
          if (isAdmin) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (feeDue)
                SpPill(
                  label: 'Pay $feeLabel & accept',
                  icon: Icons.credit_card_rounded,
                  height: 34,
                  onTap: () => _pay(context, ref, e.str('entryId')),
                )
              else
                SpPill(
                  label: 'Accept',
                  icon: Icons.check_rounded,
                  height: 34,
                  onTap: () => _accept(context, ref, e.str('entryId')),
                ),
              if (fee?.str('status') == 'pending')
                SpPill(
                  label: 'Check payment',
                  tone: SpPillTone.soft,
                  height: 34,
                  onTap: () => _checkPayment(context, ref, e.str('entryId')),
                ),
              SpPill(
                label: 'Decline',
                tone: SpPillTone.soft,
                height: 34,
                onTap: () => leagueAction(context, ref, 'respond', {'entryId': e.str('entryId'), 'accept': false},
                    success: 'Invite declined', refresh: _refresh),
              ),
            ]),
          ],
        ],

        // Upcoming: in, waiting on the organiser
        if (phase == 'upcoming' && d != null) ...[
          const SizedBox(height: 12),
          _Strip(
            icon: Icons.hourglass_top_rounded,
            bg: p.accentTint,
            fg: p.greenText,
            title: '$teamName is in.',
            text: '${organiser ?? 'The organiser'} is still setting the league up — fixtures show here once '
                "they're published${l?.date('seasonStartsOn') != null ? ' (season starts ${MaterialLocalizations.of(context).formatMediumDate(l!.date('seasonStartsOn')!)})' : ''}.",
          ),
          const SizedBox(height: 10),
          Row(children: [
            for (final t in d.list('teams').take(8))
              Align(
                widthFactor: 0.75,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: t.b('you') ? p.accentDeep : p.surface, width: 2),
                  ),
                  child: Crest(logoUrl: t.s('logoUrl'), label: t.s('name'), kitPrimary: t.s('kitPrimary'), size: 26),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  '${d.list('teams').length} team${d.list('teams').length == 1 ? '' : 's'} in'
                  '${d.i('teamsInvited') > 0 ? ' · ${d.i('teamsInvited')} invited' : ''}'
                  ' · takes ${l?.i('teamsMin')}–${l?.i('teamsMax')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12.5)),
            ),
          ]),
          if (e.iOrNull('registered') != null) ...[
            const SizedBox(height: 10),
            _RosterStrip(e: e, groupId: groupId),
          ],
        ],

        // Active: where it stands, what's next, the table
        if (phase == 'active' && d != null) ..._active(context, p, l, d, teamName),

        // Past: how it finished
        if (phase == 'past') ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: champion ? p.accentTint : p.surface, borderRadius: BorderRadius.circular(13)),
                child: champion
                    ? Icon(Icons.emoji_events_rounded, color: p.greenText, size: 20)
                    : Text(e.o('standing') != null ? '${e.o('standing')!.i('position')}' : '–',
                        style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_finishLine(e),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.ink, fontSize: 12.5)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  /// Accept; a paid season answers "payment_required" → straight to checkout.
  Future<void> _accept(BuildContext context, WidgetRef ref, String entryId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = J.of(await ref.read(leaguesRepositoryProvider).mutate('respond', {'entryId': entryId, 'accept': true}));
      if (r.str('status') == 'payment_required') {
        if (context.mounted) await _pay(context, ref, entryId);
        return;
      }
      for (final x in _refresh) {
        ref.invalidate(x);
      }
      messenger.showSnackBar(const SnackBar(content: Text("You're in — now call your players onto the league roster")));
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  Future<void> _pay(BuildContext context, WidgetRef ref, String entryId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = J.of(await ref.read(leaguesRepositoryProvider).mutate('payEntry', {'entryId': entryId}));
      await launchUrl(Uri.parse(r.str('url')), mode: LaunchMode.externalApplication);
      for (final x in _refresh) {
        ref.invalidate(x);
      }
      messenger.showSnackBar(const SnackBar(content: Text('Finish paying in the browser, then come back and tap Check payment.')));
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  Future<void> _checkPayment(BuildContext context, WidgetRef ref, String entryId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = J.of(await ref.read(leaguesRepositoryProvider).mutate('confirmEntryFee', {'entryId': entryId}));
      for (final x in _refresh) {
        ref.invalidate(x);
      }
      messenger.showSnackBar(SnackBar(
          content: Text(r.str('status') == 'paid'
              ? "Entry fee paid — you're in. Call your players onto the league roster."
              : 'Payment not confirmed yet — it can take a minute. Check again shortly.')));
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  List<ProviderOrFamily> get _refresh =>
      [groupTeamLeaguesProvider(groupId), myLeagueEntriesProvider, teamLeaguesProvider(e.str('teamId'))];

  List<Widget> _active(BuildContext context, AppPalette p, J? l, J d, String teamName) {
    final st = e.o('standing');
    final sanctions = d.list('sanctions');
    final next = d.list('nextFixtures');
    final recent = d.list('recentResults');
    final table = d.o('table');
    Widget tile(String value, String label, {bool accent = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            decoration: BoxDecoration(color: accent ? p.accentTint : p.surface2, borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: accent ? p.greenText : p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(color: p.muted, fontSize: 10.5)),
            ]),
          ),
        );
    Widget sub(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
          child: Text(t.toUpperCase(),
              style: TextStyle(color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        );
    return [
      const SizedBox(height: 12),
      Row(children: [
        tile(st != null ? ordinal(st.i('position')) : '–', 'Position', accent: true),
        const SizedBox(width: 6),
        tile('${st?.i('played') ?? 0}', 'Played'),
        const SizedBox(width: 6),
        tile(st != null ? '${st.i('won')}-${st.i('drawn')}-${st.i('lost')}' : '0-0-0', 'W-D-L'),
        const SizedBox(width: 6),
        tile('${st?.i('points') ?? 0}', 'Points'),
      ]),
      if (sanctions.isNotEmpty) ...[
        const SizedBox(height: 10),
        _Strip(
          icon: Icons.warning_amber_rounded,
          bg: p.orangeTint,
          fg: p.orangeInk,
          title: '${sanctions.length} forfeit${sanctions.length == 1 ? '' : 's'} against $teamName',
          text: sanctions.take(2).map((s) => s.str('publicReason')).join('\n'),
        ),
      ],
      if (next.isNotEmpty) ...[
        sub('Next up'),
        SpListCard(children: [for (final f in next) FixtureTile(f: f)]),
      ] else ...[
        const SizedBox(height: 10),
        _Strip(
          icon: Icons.event_busy_rounded,
          bg: p.surface2,
          fg: p.muted,
          text: d.i('fixturesTotal') > 0
              ? 'No more fixtures scheduled for now.'
              : "Fixtures for this team aren't published yet.",
        ),
      ],
      if (recent.isNotEmpty) ...[
        sub('Results'),
        SpListCard(children: [for (final f in recent) FixtureTile(f: f)]),
      ],
      if (table != null) ...[
        sub(table.str('name', 'Table')),
        StandingsTableView(rows: tableWindow(table.list('rows'), e.str('teamId')), highlightTeamId: e.str('teamId')),
      ],
      if (e.iOrNull('registered') != null) ...[
        const SizedBox(height: 10),
        _RosterStrip(e: e, groupId: groupId),
      ],
    ];
  }
}

String _finishLine(J e) {
  final st = e.o('standing');
  if (e.b('champion')) return 'Champions';
  if (st != null) {
    return 'Finished ${ordinal(st.i('position'))} · ${st.i('won')}W ${st.i('drawn')}D ${st.i('lost')}L · ${st.i('points')} pts';
  }
  return e.b('movedAway') ? 'Moved to another division' : 'No games played';
}

/// Tinted one-liner: icon, optional bold title, text.
class _Strip extends StatelessWidget {
  const _Strip({required this.icon, required this.bg, required this.fg, this.title, required this.text});
  final IconData icon;
  final Color bg;
  final Color fg;
  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: fg),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              if (title != null) TextSpan(text: '$title ', style: const TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: text),
            ]),
            style: TextStyle(color: p.ink, fontSize: 12.5),
          ),
        ),
      ]),
    );
  }
}

/// Roster state for the team's admins: count, limits, cutoff and the way in.
class _RosterStrip extends StatelessWidget {
  const _RosterStrip({required this.e, required this.groupId});
  final J e;
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = e.o('league');
    final min = l?.o('rosters')?.i('minPlayers') ?? 0;
    final max = l?.o('rosters')?.i('maxPlayers') ?? 0;
    final n = e.i('registered');
    final short = n < min;
    final locked = l?.b('rosterLocked') == true;
    final lockAt = l?.date('rosterLockAt');
    final canEdit = e.b('canEditRoster');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: short ? p.orangeTint : p.surface2, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        SpIconTile(locked ? Icons.lock_rounded : Icons.people_alt_rounded,
            bg: p.surface, fg: p.ink, size: 36, iconSize: 17),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$n registered · $min–$max allowed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w700)),
            Text(
                short
                    ? '${min - n} more needed'
                    : locked
                        ? 'Locked — ask the organiser for changes'
                        : lockAt != null
                            ? 'Call players until ${MaterialLocalizations.of(context).formatMediumDate(lockAt)}'
                            : 'Call-ups open — no cutoff set yet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 11.5)),
          ]),
        ),
        SpPill(
          label: canEdit ? (n == 0 ? 'Call players' : 'Squad') : 'View',
          tone: canEdit ? SpPillTone.ink : SpPillTone.outline,
          height: 32,
          onTap: () => context.push('/groups/$groupId/leagues/${l?.str('id')}/roster/${e.str('teamId')}'),
        ),
      ]),
    );
  }
}

/// A team's league seasons on its team page (web TeamLeagues).
class TeamLeaguesSection extends ConsumerWidget {
  const TeamLeaguesSection({super.key, required this.teamId});
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final d = ref.watch(teamLeaguesProvider(teamId)).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final upcoming = d.list('upcoming');
    final active = d.list('active');
    final past = d.list('past');
    if (upcoming.isEmpty && active.isEmpty && past.isEmpty) return const SizedBox.shrink();
    Widget row(J e) {
      final st = e.o('standing');
      final champion = e.b('champion');
      final soon = e.s('phase') == 'upcoming';
      return ListTile(
        // A league still being set up has no public page yet — its hub is
        // the group's Leagues tab.
        onTap: () => context.push(soon
            ? '/groups/${e.str('teamGroupId')}?tab=leagues'
            : '/leagues/${e.o('league')?.str('slug')}'),
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: champion ? p.accentTint : p.surface2, borderRadius: BorderRadius.circular(13)),
          child: champion
              ? Icon(Icons.emoji_events_rounded, color: p.greenText, size: 20)
              : soon
                  ? Icon(Icons.hourglass_top_rounded, color: p.ink, size: 18)
                  : Text(st != null ? '${st.i('position')}' : '–',
                      style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
        ),
        title: Text(e.o('league')?.str('title') ?? '', style: TextStyle(color: p.ink, fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(soon
            ? 'Starting soon${e.iOrNull('registered') != null ? ' · ${e.i('registered')} registered' : ''}'
            : champion
                ? 'Champions'
                : st != null
                    ? '${ordinal(st.i('position'))} · ${st.i('won')}W ${st.i('drawn')}D ${st.i('lost')}L · ${st.i('points')} pts'
                    : e.b('movedAway')
                        ? 'Moved to another division'
                        : 'No games yet'),
        trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (upcoming.isNotEmpty) ...[
        SpSectionTitle('Leagues — starting soon', count: upcoming.length),
        const SizedBox(height: 8),
        SpListCard(children: [for (final e in upcoming) row(e)]),
        const SizedBox(height: 14),
      ],
      if (active.isNotEmpty) ...[
        SpSectionTitle('Leagues — playing now', count: active.length),
        const SizedBox(height: 8),
        SpListCard(children: [for (final e in active) row(e)]),
        const SizedBox(height: 14),
      ],
      if (past.isNotEmpty) ...[
        SpSectionTitle('Past league seasons', count: past.length),
        const SizedBox(height: 8),
        SpListCard(children: [for (final e in past) row(e)]),
        const SizedBox(height: 14),
      ],
    ]);
  }
}

/// "Surrey Sunday League · Division 1 · 3rd" under a team in tournament lists.
class TeamLeagueLine extends StatelessWidget {
  const TeamLeagueLine({super.key, required this.badges});
  final List<J>? badges;

  @override
  Widget build(BuildContext context) {
    final b = badges;
    if (b == null || b.isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    final first = b.first;
    final text = [
      first.s('title'),
      first.s('division'),
      if (first.iOrNull('position') != null) ordinal(first.i('position')),
    ].whereType<String>().join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.format_list_numbered_rounded, size: 12, color: p.greenText),
        const SizedBox(width: 4),
        Flexible(
          child: Text('$text${b.length > 1 ? ' +${b.length - 1}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.greenText, fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// Provider key for [teamLeagueBadgesProvider].
String teamBadgeKey(Iterable<String?> ids) => (ids.whereType<String>().toSet().toList()..sort()).join(',');

/// [TeamLeagueLine] that loads its own badge (one team).
class TeamLeagueLineFor extends ConsumerWidget {
  const TeamLeagueLineFor({super.key, required this.teamId});
  final String? teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = teamId;
    if (id == null) return const SizedBox.shrink();
    final badges = ref.watch(teamLeagueBadgesProvider(id)).valueOrNull;
    return TeamLeagueLine(badges: badges?[id]);
  }
}
