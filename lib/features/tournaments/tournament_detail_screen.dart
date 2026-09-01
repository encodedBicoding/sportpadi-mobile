import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Tournament page — a card-by-card port of the web page:
/// header (badges + title + date/time/location + description), then for a
/// friendly the Matchup card (Host/Guest columns with records, entry-fee row)
/// and the Match section; for multi-team/league the Teams, Matches and Awards
/// cards; plus the admin Sell tickets / Cancel row.
class TournamentDetailScreen extends ConsumerWidget {
  const TournamentDetailScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tournamentDetailProvider(eventId));
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Tournament',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: AsyncView(
        value: t,
        onRetry: () {
          ref.invalidate(tournamentDetailProvider(eventId));
          ref.invalidate(tournamentMatchProvider(eventId));
        },
        data: (m) {
          final event = m['event'] is Map
              ? Map<String, dynamic>.from(m['event'] as Map)
              : const <String, dynamic>{};
          final category = event['category'] is Map
              ? Map<String, dynamic>.from(event['category'] as Map)
              : null;
          final mode = parseStr(m['mode']) ?? 'friendly';
          final isFriendly = mode == 'friendly';
          final canManage = m['canManage'] == true;
          final maxTeams = parseInt(m['maxTeams']) ?? 2;
          final feeLabel = _fmtMoney(
              m['feeMinor'], m['feeCurrency'], m['feeCurrencyExponent']);
          final status = parseStr(event['status']) ?? 'upcoming';
          final ended = status == 'completed' || status == 'cancelled';
          final teams = m['teams'] is List ? (m['teams'] as List) : const [];
          final rows = [
            for (final raw in teams)
              if (raw is Map) Map<String, dynamic>.from(raw)
          ];
          Map<String, dynamic>? hostRow;
          Map<String, dynamic>? guestRow;
          for (final row in rows) {
            if (parseStr(row['role']) == 'host') {
              hostRow = row;
            } else {
              guestRow ??= row;
            }
          }
          final guestApproved = parseStr(guestRow?['status']) == 'approved';
          final inTeams = [
            for (final r in rows)
              if (parseStr(r['status']) != 'rejected') r
          ];
          final approvedPick = [
            for (final r in rows)
              if (parseStr(r['status']) == 'approved' && r['team'] is Map)
                (
                  id: parseStr(r['id']) ?? '',
                  name: parseStr((r['team'] as Map)['name']) ?? 'Team',
                ),
          ];

          return RefreshIndicator(
            onRefresh: () {
              ref.invalidate(tournamentMatchProvider(eventId));
              ref.invalidate(tournamentGamesProvider(eventId));
              ref.invalidate(tournamentAwardsProvider(eventId));
              return ref.refresh(tournamentDetailProvider(eventId).future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _HeaderCard(event: event, mode: mode, status: status),
                if (isFriendly) ...[
                  const SizedBox(height: 14),
                  _MatchupCard(
                    eventId: eventId,
                    hostRow: hostRow,
                    guestRow: guestRow,
                    feeLabel: feeLabel,
                    canManage: canManage,
                  ),
                  const SizedBox(height: 14),
                  _MatchSection(
                    eventId: eventId,
                    canCreate: canManage,
                    guestApproved: guestApproved,
                    category: category,
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  _TeamsCard(
                    eventId: eventId,
                    rows: inTeams,
                    maxTeams: maxTeams,
                    canManage: canManage,
                    ended: ended,
                    feeLabel: feeLabel,
                    categoryId:
                        category != null ? parseStr(category['id']) : null,
                    hostGroupId: parseStr(event['groupId']),
                  ),
                  const SizedBox(height: 14),
                  _MatchesCard(
                    eventId: eventId,
                    canManage: canManage,
                    ended: ended,
                    approvedPick: approvedPick,
                    category: category,
                  ),
                  const SizedBox(height: 14),
                  _AwardsCard(eventId: eventId),
                ],
                if (canManage) ...[
                  const SizedBox(height: 14),
                  _ManageRow(
                      eventId: eventId,
                      ended: ended,
                      hostGroupId: parseStr(event['groupId'])),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

String? _fmtMoney(dynamic minor, dynamic currency, dynamic exponent) {
  final v = parseInt(minor);
  final cur = parseStr(currency);
  final exp = parseInt(exponent);
  if (v == null || cur == null || exp == null) return null;
  final major = v / _pow10(exp);
  return '$cur ${major.toStringAsFixed(exp)}';
}

/// 'yyyy-MM-dd' schedule strings render as-is (no timezone round trip).
String _fmtSchedDate(String ymd) {
  final parts = ymd.split('-');
  if (parts.length != 3) return ymd;
  final y = int.tryParse(parts[0]);
  final mo = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || mo == null || d == null) return ymd;
  return formatDayYear(DateTime.utc(y, mo, d));
}

int _pow10(int e) {
  var r = 1;
  for (var i = 0; i < e; i++) {
    r *= 10;
  }
  return r;
}

/// Hand-rolled outline button (the *Button.icon constructors crash this
/// Flutter build's semantics compiler).
class _OutlineBtn extends StatelessWidget {
  const _OutlineBtn({
    required this.label,
    required this.onTap,
    this.icon,
    this.tone,
    this.expand = false,
    this.small = false,
  });
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color? tone;
  final bool expand;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = tone ?? p.ink;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: small ? 10 : 14, vertical: small ? 7 : 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.line),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: small ? 14 : 16, color: c),
                const SizedBox(width: 5),
              ],
              Text(label,
                  style: TextStyle(
                      color: c,
                      fontSize: small ? 12 : 13.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header card — badges, title, date · time · location, description.
// ---------------------------------------------------------------------------

class _HeaderCard extends StatelessWidget {
  const _HeaderCard(
      {required this.event, required this.mode, required this.status});
  final Map<String, dynamic> event;
  final String mode;
  final String status;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final category = event['category'] is Map
        ? Map<String, dynamic>.from(event['category'] as Map)
        : null;
    final modeLabel = mode == 'league'
        ? 'League'
        : mode == 'multi_team'
            ? 'Multi-team'
            : 'Friendly';
    final start = formatClock(event['startTime']);
    final end = formatClock(event['endTime']);
    final location = parseStr(event['locationName']);
    final description = parseStr(event['description']);

    Widget meta(IconData icon, String text) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: p.muted),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: p.muted, fontSize: 12)),
        ]);

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          SpBadge('🏆 $modeLabel'),
          if (category != null)
            SpBadge(
                '${parseStr(category['emoji']) ?? ''} ${parseStr(category['name']) ?? ''}'
                    .trim()),
          SpBadge(status),
        ]),
        const SizedBox(height: 8),
        Text(parseStr(event['title']) ?? 'Tournament',
            style: TextStyle(
                color: p.ink, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(spacing: 12, runSpacing: 4, children: [
          meta(Icons.calendar_today_outlined, formatDayYear(event['eventDate'])),
          if (start != null)
            meta(Icons.schedule, end != null ? '$start – $end' : start),
          if (location != null) meta(Icons.place_outlined, location),
        ]),
        if (description != null) ...[
          const SizedBox(height: 10),
          Text(description,
              style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.4)),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Friendly: Matchup card — Host | ⚔ VS | Guest columns with all-time records,
// then the guest-status / entry-fee / refund row.
// ---------------------------------------------------------------------------

class _MatchupCard extends ConsumerWidget {
  const _MatchupCard({
    required this.eventId,
    required this.hostRow,
    required this.guestRow,
    required this.feeLabel,
    required this.canManage,
  });
  final String eventId;
  final Map<String, dynamic>? hostRow;
  final Map<String, dynamic>? guestRow;
  final String? feeLabel;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final guestStatus = parseStr(guestRow?['status']);
    final guestFeeStatus = parseStr(guestRow?['feeStatus']);
    final guestRowId = parseStr(guestRow?['id']);

    final feeSuffix = guestFeeStatus == 'paid'
        ? ' · paid'
        : guestFeeStatus == 'refunded'
            ? ' · refunded'
            : guestFeeStatus == 'pending'
                ? ' · unpaid'
                : '';

    return GlassCard(
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _TeamCol(label: 'Host', row: hostRow)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(children: [
              const SizedBox(height: 22),
              const Text('⚔️', style: TextStyle(fontSize: 20)),
              Text('VS',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
          Expanded(child: _TeamCol(label: 'Guest', row: guestRow)),
        ]),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.line)),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (guestStatus != null)
                SpBadge(
                  'Guest: $guestStatus',
                  tone: guestStatus == 'approved'
                      ? p.accent
                      : guestStatus == 'rejected'
                          ? p.danger
                          : p.amber,
                ),
              if (feeLabel != null)
                SpBadge('🎟 Entry fee $feeLabel$feeSuffix'),
              if (canManage && guestFeeStatus == 'paid' && guestRowId != null)
                _OutlineBtn(
                  label: 'Refund fee',
                  icon: Icons.replay_rounded,
                  tone: p.danger,
                  small: true,
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await ref
                          .read(tournamentsRepositoryProvider)
                          .refundFee(eventId, guestRowId);
                      ref.invalidate(tournamentDetailProvider(eventId));
                      messenger.showSnackBar(const SnackBar(
                          content: Text('Entry fee refunded')));
                    } catch (e) {
                      messenger
                          .showSnackBar(SnackBar(content: Text('$e')));
                    }
                  },
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _TeamCol extends StatelessWidget {
  const _TeamCol({required this.label, required this.row});
  final String label;
  final Map<String, dynamic>? row;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final team = row?['team'] is Map
        ? Map<String, dynamic>.from(row!['team'] as Map)
        : null;
    final record = row?['record'] is Map
        ? Map<String, dynamic>.from(row!['record'] as Map)
        : null;
    final played = parseInt(record?['played']) ?? 0;
    final teamId = team != null ? parseStr(team['id']) : null;

    final col = Column(children: [
      Text(label.toUpperCase(),
          style: TextStyle(
              color: p.muted,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8)),
      const SizedBox(height: 6),
      Crest(
        logoUrl: team != null ? parseStr(team['logoUrl']) : null,
        kitPrimary: team != null ? parseStr(team['kitPrimary']) : null,
        kitSecondary: team != null ? parseStr(team['kitSecondary']) : null,
        label: team != null ? (parseStr(team['name']) ?? label) : label,
        size: 64,
      ),
      const SizedBox(height: 6),
      Text(
        team != null ? (parseStr(team['name']) ?? 'TBD') : 'TBD',
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: p.ink, fontSize: 13, fontWeight: FontWeight.w700),
      ),
      if (team != null && parseStr(team['username']) != null)
        Text('@${parseStr(team['username'])}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.muted, fontSize: 11)),
      if (team != null && parseStr(team['groupName']) != null)
        Text(parseStr(team['groupName'])!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.muted, fontSize: 11)),
      if (played > 0)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '${played}P · ${parseInt(record?['won']) ?? 0}W '
            '${parseInt(record?['drawn']) ?? 0}D '
            '${parseInt(record?['lost']) ?? 0}L · '
            '${parseInt(record?['goalsFor']) ?? 0}-'
            '${parseInt(record?['goalsAgainst']) ?? 0}',
            style: TextStyle(
                color: p.muted, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ),
    ]);

    if (teamId == null) return col;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/teams/$teamId'),
      child: Padding(padding: const EdgeInsets.all(4), child: col),
    );
  }
}

// ---------------------------------------------------------------------------
// Friendly: Match section — heading + create button, empty states, and the
// match card (status/schedule/edit time, line-up clash, officiant,
// accept/decline, open/view, reset).
// ---------------------------------------------------------------------------

class _MatchSection extends ConsumerWidget {
  const _MatchSection({
    required this.eventId,
    required this.canCreate,
    required this.guestApproved,
    required this.category,
  });
  final String eventId;
  final bool canCreate;
  final bool guestApproved;
  final Map<String, dynamic>? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final matchAsync = ref.watch(tournamentMatchProvider(eventId));
    final match = matchAsync.valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Eyebrow('Match'),
          const Spacer(),
          if (match == null &&
              !matchAsync.isLoading &&
              canCreate &&
              guestApproved)
            SpButton(
              label: 'Create match game',
              icon: Icons.flag_outlined,
              onTap: () => _CreateMatchSheet.show(context,
                  eventId: eventId, category: category),
            ),
        ]),
        const SizedBox(height: 8),
        if (matchAsync.isLoading && match == null)
          GlassCard(
            child: Center(
              child: Text('Loading…',
                  style: TextStyle(color: p.muted, fontSize: 13)),
            ),
          )
        else if (match == null)
          GlassCard(
            padding: const EdgeInsets.all(22),
            child: Center(
              child: Text(
                guestApproved
                    ? canCreate
                        ? 'No match game yet — create one to set the officiant and kickoff time.'
                        : "The match game hasn't been set up yet."
                    : 'The match game unlocks once the invited team accepts.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 13),
              ),
            ),
          )
        else
          _matchCard(context, ref, match),
      ],
    );
  }

  Widget _matchCard(
      BuildContext context, WidgetRef ref, Map<String, dynamic> m) {
    final p = context.palette;
    final status = parseStr(m['status']) ?? 'scheduled';
    final gameId = parseStr(m['gameId']);
    final officiant = m['officiant'] is Map
        ? Map<String, dynamic>.from(m['officiant'] as Map)
        : null;
    final canRespond = m['viewerCanRespond'] == true;
    final canOfficiate = m['viewerCanOfficiate'] == true;
    final isHostAdmin = m['isHostAdmin'] == true;
    final schedule = [
      if (parseStr(m['scheduledDate']) != null)
        _fmtSchedDate(parseStr(m['scheduledDate'])!),
      if (parseStr(m['scheduledTime']) != null)
        formatTime12(parseStr(m['scheduledTime'])!),
    ].join(' · ');
    final conflicts = m['starterConflicts'] is List
        ? [
            for (final c in m['starterConflicts'] as List)
              if (c is Map) Map<String, dynamic>.from(c)
          ]
        : const <Map<String, dynamic>>[];

    Future<void> act(Future<void> Function() op) async {
      try {
        await op();
        ref.invalidate(tournamentMatchProvider(eventId));
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }

    final offStatus = officiant != null ? parseStr(officiant['status']) : null;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SpBadge(
              status == 'live' ? '⚡ Live' : status,
              tone: status == 'live' ? p.amber : p.muted,
            ),
            const SizedBox(width: 8),
            Icon(Icons.calendar_today_outlined, size: 13, color: p.muted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(schedule.isEmpty ? 'TBD' : schedule,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ),
            if (isHostAdmin && status == 'scheduled' && gameId != null)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _ScheduleSheet.show(context,
                    eventId: eventId,
                    gameId: gameId,
                    initialDate: parseStr(m['scheduledDate']),
                    initialTime: parseStr(m['scheduledTime'])),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.schedule, size: 13, color: p.muted),
                    const SizedBox(width: 3),
                    Text('Edit time',
                        style: TextStyle(
                            color: p.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
          ]),
          if (conflicts.isNotEmpty && gameId != null) ...[
            const SizedBox(height: 10),
            _ConflictsBlock(
              eventId: eventId,
              gameId: gameId,
              conflicts: conflicts,
              benchByTeam: m['benchByTeam'] is Map
                  ? Map<String, dynamic>.from(m['benchByTeam'] as Map)
                  : const {},
              canResolve: m['viewerCanResolveLineup'] == true,
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.flag_outlined, size: 15, color: p.muted),
            const SizedBox(width: 6),
            Expanded(
              child: officiant != null
                  ? Row(children: [
                      Flexible(
                        child: Text(
                          'Officiant: ${parseStr(officiant['label']) ?? '—'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SpBadge(
                        offStatus ?? 'pending',
                        tone: offStatus == 'approved'
                            ? p.accent
                            : offStatus == 'rejected'
                                ? p.danger
                                : p.amber,
                      ),
                    ])
                  : Text('No officiant assigned',
                      style: TextStyle(color: p.muted, fontSize: 13)),
            ),
          ]),
          if (canRespond && gameId != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: SpButton(
                  label: 'Accept officiating',
                  icon: Icons.check_rounded,
                  expand: true,
                  onTap: () => act(() => ref
                      .read(tournamentsRepositoryProvider)
                      .respondOfficiant(eventId, gameId, true)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OutlineBtn(
                  label: 'Decline',
                  expand: true,
                  onTap: () => act(() => ref
                      .read(tournamentsRepositoryProvider)
                      .respondOfficiant(eventId, gameId, false)),
                ),
              ),
            ]),
          ],
          if (gameId != null) ...[
            const SizedBox(height: 12),
            _OutlineBtn(
              label: canOfficiate ? 'Open & manage match' : 'View match',
              icon: Icons.flag_outlined,
              expand: true,
              onTap: () => context.push('/games/$gameId'),
            ),
          ],
          if (isHostAdmin) ...[
            const SizedBox(height: 6),
            Center(
              child: InkWell(
                onTap: () => _confirmReset(context, ref),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text('Reset match',
                      style: TextStyle(
                          color: p.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset this match?'),
        content: const Text(
            'This deletes the current match game (and any recorded stats) so '
            "you can recreate it with each team's current squad."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reset match')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(tournamentsRepositoryProvider).resetMatch(eventId);
      ref.invalidate(tournamentMatchProvider(eventId));
      messenger.showSnackBar(const SnackBar(
          content: Text(
              'Match reset — create it again to pull in the current squads.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

/// The web line-up clash block: a starter on both teams must be benched (or
/// substituted) on one side before kickoff.
class _ConflictsBlock extends ConsumerWidget {
  const _ConflictsBlock({
    required this.eventId,
    required this.gameId,
    required this.conflicts,
    required this.benchByTeam,
    required this.canResolve,
  });
  final String eventId;
  final String gameId;
  final List<Map<String, dynamic>> conflicts;
  final Map<String, dynamic> benchByTeam;
  final bool canResolve;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;

    Future<void> subOff(String teamId, String playerId,
        {String? swapInPlayerId}) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref.read(tournamentsRepositoryProvider).subOffStarter(eventId,
            gameId: gameId,
            teamId: teamId,
            playerId: playerId,
            swapInPlayerId: swapInPlayerId);
        ref.invalidate(tournamentMatchProvider(eventId));
        messenger
            .showSnackBar(const SnackBar(content: Text('Line-up updated')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('$e')));
      }
    }

    Future<void> pickSub(String teamId, String playerId,
        List<Map<String, dynamic>> bench) async {
      final chosen = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: p.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Text('Sub on…',
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final b in bench)
                ListTile(
                  dense: true,
                  title: Text(parseStr(b['name']) ?? 'Player',
                      style: TextStyle(color: p.ink, fontSize: 14)),
                  onTap: () => Navigator.pop(ctx, parseStr(b['playerId'])),
                ),
            ],
          ),
        ),
      );
      if (chosen != null && context.mounted) {
        await subOff(teamId, playerId, swapInPlayerId: chosen);
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.danger.withAlpha(102)),
        color: p.danger.withAlpha(13),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: p.danger),
          const SizedBox(width: 6),
          Expanded(
            child: Text("Line-up clash — can't start",
                style: TextStyle(
                    color: p.danger,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          "A player can't start for both teams. Sub them off one team (they "
          'stay a starter for the other) so the match can kick off.',
          style: TextStyle(color: p.muted, fontSize: 12),
        ),
        for (final c in conflicts) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: p.surface,
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(parseStr(c['name']) ?? 'Player',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                  if (canResolve) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Pick the team they should not play for — bench them, '
                      'or bring a substitute on in their place.',
                      style: TextStyle(color: p.muted, fontSize: 11),
                    ),
                    for (final t in (c['teams'] is List
                        ? [
                            for (final x in c['teams'] as List)
                              if (x is Map) Map<String, dynamic>.from(x)
                          ]
                        : const <Map<String, dynamic>>[])) ...[
                      const SizedBox(height: 6),
                      Builder(builder: (context) {
                        final teamId = parseStr(t['teamId']) ?? '';
                        final playerId = parseStr(c['playerId']) ?? '';
                        final bench = benchByTeam[teamId] is List
                            ? [
                                for (final b in benchByTeam[teamId] as List)
                                  if (b is Map) Map<String, dynamic>.from(b)
                              ]
                            : const <Map<String, dynamic>>[];
                        return Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: p.line),
                          ),
                          child: Row(children: [
                            Expanded(
                              child: Text(parseStr(t['name']) ?? 'Team',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                            _OutlineBtn(
                              label: 'Bench',
                              icon: Icons.person_remove_outlined,
                              small: true,
                              onTap: () => subOff(teamId, playerId),
                            ),
                            if (bench.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              _OutlineBtn(
                                label: 'Sub on…',
                                small: true,
                                onTap: () =>
                                    pickSub(teamId, playerId, bench),
                              ),
                            ],
                          ]),
                        );
                      }),
                    ],
                  ] else ...[
                    const SizedBox(height: 4),
                    Text(
                      'Starting for '
                      '${(c['teams'] is List ? [for (final x in c['teams'] as List) if (x is Map) parseStr((x)['name']) ?? ''] : const <String>[]).join(' & ')}'
                      ' — an admin or the officiant must bench them on one team.',
                      style: TextStyle(color: p.muted, fontSize: 11),
                    ),
                  ],
                ]),
          ),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-team / league: Teams card — "Teams n/max" + Invite team, then rows.
// ---------------------------------------------------------------------------

class _TeamsCard extends ConsumerWidget {
  const _TeamsCard({
    required this.eventId,
    required this.rows,
    required this.maxTeams,
    required this.canManage,
    required this.ended,
    required this.feeLabel,
    required this.categoryId,
    required this.hostGroupId,
  });
  final String eventId;
  final List<Map<String, dynamic>> rows;
  final int maxTeams;
  final bool canManage;
  final bool ended;
  final String? feeLabel;
  final String? categoryId;
  final String? hostGroupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.group_outlined, size: 16, color: p.muted),
          const SizedBox(width: 6),
          Text('Teams',
              style: TextStyle(
                  color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text('${rows.length}/$maxTeams',
              style: TextStyle(color: p.muted, fontSize: 13)),
          const Spacer(),
          if (canManage && !ended && rows.length < maxTeams)
            _OutlineBtn(
              label: 'Invite team',
              icon: Icons.add,
              small: true,
              onTap: () => _InviteTeamSheet.show(context,
                  eventId: eventId,
                  categoryId: categoryId,
                  hostGroupId: hostGroupId,
                  existingTeamIds: [
                    for (final r in rows)
                      if (r['team'] is Map)
                        parseStr((r['team'] as Map)['id']) ?? ''
                  ]),
            ),
        ]),
        const SizedBox(height: 10),
        for (final r in rows) _teamRow(context, r),
      ]),
    );
  }

  Widget _teamRow(BuildContext context, Map<String, dynamic> r) {
    final p = context.palette;
    final team = r['team'] is Map
        ? Map<String, dynamic>.from(r['team'] as Map)
        : null;
    final role = parseStr(r['role']);
    final status = parseStr(r['status']) ?? 'pending';
    final feeStatus = parseStr(r['feeStatus']);
    final teamId = team != null ? parseStr(team['id']) : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap:
              teamId != null ? () => context.push('/teams/$teamId') : null,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.line),
            ),
            child: Row(children: [
              Crest(
                logoUrl: team != null ? parseStr(team['logoUrl']) : null,
                kitPrimary:
                    team != null ? parseStr(team['kitPrimary']) : null,
                kitSecondary:
                    team != null ? parseStr(team['kitSecondary']) : null,
                label: team != null
                    ? (parseStr(team['name']) ?? 'Team')
                    : 'Team',
                size: 40,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        team != null
                            ? (parseStr(team['name']) ?? 'Team')
                            : 'Team',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                          if (team != null &&
                              parseStr(team['username']) != null)
                            '@${parseStr(team['username'])}',
                          if (team != null &&
                              parseStr(team['groupName']) != null)
                            parseStr(team['groupName'])!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 11),
                      ),
                    ]),
              ),
              const SizedBox(width: 6),
              role == 'host'
                  ? const SpBadge('Host')
                  : SpBadge(
                      status,
                      tone: status == 'approved'
                          ? p.accent
                          : status == 'rejected'
                              ? p.danger
                              : p.amber,
                    ),
              if (feeLabel != null && role != 'host') ...[
                const SizedBox(width: 6),
                Text(
                  feeStatus == 'paid'
                      ? 'paid'
                      : feeStatus == 'refunded'
                          ? 'refunded'
                          : feeStatus == 'pending'
                              ? 'unpaid'
                              : '',
                  style: TextStyle(color: p.muted, fontSize: 10),
                ),
              ],
              Icon(Icons.chevron_right, size: 18, color: p.muted),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-team / league: Matches card — create button + home vs away rows.
// ---------------------------------------------------------------------------

class _MatchesCard extends ConsumerWidget {
  const _MatchesCard({
    required this.eventId,
    required this.canManage,
    required this.ended,
    required this.approvedPick,
    required this.category,
  });
  final String eventId;
  final bool canManage;
  final bool ended;
  final List<({String id, String name})> approvedPick;
  final Map<String, dynamic>? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final gamesAsync = ref.watch(tournamentGamesProvider(eventId));
    final games = gamesAsync.valueOrNull ?? const <Map<String, dynamic>>[];

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('⚔️', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          Text('Matches',
              style: TextStyle(
                  color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (canManage && !ended && approvedPick.length >= 2)
            _OutlineBtn(
              label: 'Create match',
              icon: Icons.add,
              small: true,
              onTap: () => _CreateMatchSheet.show(context,
                  eventId: eventId,
                  category: category,
                  teams: approvedPick),
            ),
        ]),
        const SizedBox(height: 10),
        if (gamesAsync.isLoading && games.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text('Loading matches…',
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ),
          )
        else if (games.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                approvedPick.length >= 2
                    ? 'No matches yet. Create one to get started.'
                    : 'Once at least two teams have accepted, you can create matches.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ),
          )
        else
          for (final g in games) _gameRow(context, g),
      ]),
    );
  }

  Widget _gameRow(BuildContext context, Map<String, dynamic> g) {
    final p = context.palette;
    final status = parseStr(g['status']) ?? 'scheduled';
    final gameId = parseStr(g['gameId']);
    final teams = g['teams'] is List
        ? [
            for (final t in g['teams'] as List)
              if (t is Map) Map<String, dynamic>.from(t)
          ]
        : const <Map<String, dynamic>>[];
    Map<String, dynamic>? home;
    Map<String, dynamic>? away;
    for (final t in teams) {
      if (t['isHome'] == true && home == null) {
        home = t;
      } else {
        away ??= t;
      }
    }
    home ??= teams.isNotEmpty ? teams[0] : null;
    away ??= teams.length > 1 ? teams[1] : null;
    final showScore = status == 'live' || status == 'completed';
    final schedule = [
      if (parseStr(g['scheduledDate']) != null)
        _fmtSchedDate(parseStr(g['scheduledDate'])!),
      if (parseStr(g['scheduledTime']) != null)
        formatTime12(parseStr(g['scheduledTime'])!),
    ].join(' · ');

    Map<String, dynamic>? teamOf(Map<String, dynamic>? row) =>
        row?['team'] is Map
            ? Map<String, dynamic>.from(row!['team'] as Map)
            : null;
    final ht = teamOf(home);
    final at = teamOf(away);

    Widget crest(Map<String, dynamic>? t) => Crest(
          logoUrl: t != null ? parseStr(t['logoUrl']) : null,
          kitPrimary: t != null ? parseStr(t['kitPrimary']) : null,
          kitSecondary: t != null ? parseStr(t['kitSecondary']) : null,
          label: t != null ? (parseStr(t['name']) ?? 'TBD') : 'TBD',
          size: 32,
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: gameId != null ? () => context.push('/games/$gameId') : null,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.line),
            ),
            child: Row(children: [
              Expanded(
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          ht != null
                              ? (parseStr(ht['name']) ?? 'TBD')
                              : 'TBD',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 6),
                      crest(ht),
                    ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(children: [
                  Text(
                    showScore
                        ? '${parseInt(home?['score']) ?? 0}–${parseInt(away?['score']) ?? 0}'
                        : 'vs',
                    style: TextStyle(
                        color: showScore ? p.ink : p.muted,
                        fontSize: showScore ? 14 : 11,
                        fontWeight: FontWeight.w800),
                  ),
                  Text(
                    status == 'live'
                        ? '⚡ LIVE'
                        : status == 'completed'
                            ? 'FT'
                            : (schedule.isEmpty ? 'TBD' : schedule),
                    style: TextStyle(color: p.muted, fontSize: 9),
                  ),
                ]),
              ),
              Expanded(
                child: Row(children: [
                  crest(at),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      at != null ? (parseStr(at['name']) ?? 'TBD') : 'TBD',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Awards card — provisional/final award tiles.
// ---------------------------------------------------------------------------

class _AwardsCard extends ConsumerWidget {
  const _AwardsCard({required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final data = ref.watch(tournamentAwardsProvider(eventId)).valueOrNull;
    if (data == null) return const SizedBox.shrink();
    final isFinal = parseStr(data['eventStatus']) == 'completed';
    final gamesCounted = parseInt(data['gamesCounted']) ?? 0;
    final awards = data['awards'] is List
        ? [
            for (final a in data['awards'] as List)
              if (a is Map) Map<String, dynamic>.from(a)
          ]
        : const <Map<String, dynamic>>[];

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.emoji_events_outlined, size: 16, color: p.amber),
          const SizedBox(width: 6),
          Text('Awards',
              style: TextStyle(
                  color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          const Spacer(),
          SpBadge(isFinal ? 'Final' : 'Provisional'),
        ]),
        if (gamesCounted == 0) ...[
          const SizedBox(height: 10),
          Text('Awards appear here as match games are completed.',
              style: TextStyle(color: p.muted, fontSize: 12)),
        ] else ...[
          const SizedBox(height: 10),
          for (final a in awards) _awardTile(context, a),
          if (!isFinal)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'These update as matches finish and are locked in when the '
                'tournament ends.',
                style: TextStyle(color: p.muted, fontSize: 11),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _awardTile(BuildContext context, Map<String, dynamic> a) {
    final p = context.palette;
    final winner = a['winner'] is Map
        ? Map<String, dynamic>.from(a['winner'] as Map)
        : null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
        color: p.surface,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(parseStr(a['icon']) ?? '🏅',
              style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(parseStr(a['label']) ?? 'Award',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 6),
        if (winner != null) ...[
          Text(parseStr(winner['name']) ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
          if (parseStr(winner['teamName']) != null)
            Text(parseStr(winner['teamName'])!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 11)),
          if (parseStr(winner['detail']) != null)
            Text(parseStr(winner['detail'])!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 11)),
        ] else
          Text('Not enough data yet.',
              style: TextStyle(color: p.muted, fontSize: 12)),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin row — Sell tickets (web-managed) + Cancel tournament.
// ---------------------------------------------------------------------------

class _ManageRow extends ConsumerWidget {
  const _ManageRow(
      {required this.eventId, required this.ended, this.hostGroupId});
  final String eventId;
  final String? hostGroupId;
  final bool ended;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Row(children: [
      if (!ended) ...[
        Expanded(
          child: _OutlineBtn(
            label: 'Sell tickets',
            icon: Icons.confirmation_number_outlined,
            expand: true,
            onTap: hostGroupId == null
                ? null
                : () => context.push('/groups/$hostGroupId/tickets'),
          ),
        ),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: _OutlineBtn(
          label: 'Cancel',
          icon: Icons.delete_outline,
          tone: p.danger,
          expand: true,
          onTap: () => _confirmCancel(context, ref),
        ),
      ),
    ]);
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this tournament?'),
        content: const Text(
            'This cancels the tournament and its invitations. Any paid ticket '
            'holders are automatically refunded to their original payment '
            'method. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel & refund')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(tournamentsRepositoryProvider).cancelTournament(eventId);
      messenger.showSnackBar(
          const SnackBar(content: Text('Tournament cancelled')));
      router.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

// ---------------------------------------------------------------------------
// Create match game sheet — the web dialog: (multi) home/away pick, optional
// date/time, soccer match format, optional officiant search.
// ---------------------------------------------------------------------------

class _CreateMatchSheet extends ConsumerStatefulWidget {
  const _CreateMatchSheet({
    required this.eventId,
    required this.category,
    this.teams,
  });
  final String eventId;
  final Map<String, dynamic>? category;
  final List<({String id, String name})>? teams;

  static void show(BuildContext context,
      {required String eventId,
      required Map<String, dynamic>? category,
      List<({String id, String name})>? teams}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CreateMatchSheet(
          eventId: eventId, category: category, teams: teams),
    );
  }

  @override
  ConsumerState<_CreateMatchSheet> createState() => _CreateMatchSheetState();
}

class _CreateMatchSheetState extends ConsumerState<_CreateMatchSheet> {
  String? _homeId;
  String? _awayId;
  String? _date; // yyyy-MM-dd
  String? _time; // HH:mm
  bool _usesHalves = true;
  final _halfMinutes = TextEditingController(text: '45');
  bool _allowExtraTime = true;
  final _extraHalf = TextEditingController(text: '15');
  bool _allowPenalties = true;
  String? _officiantId;
  String _officiantLabel = '';
  final _search = TextEditingController();
  Timer? _debounce;
  List<GroupMemberItem> _results = const [];
  bool _searching = false;
  bool _saving = false;

  bool get _isSoccer {
    final c = widget.category;
    if (c == null) return false;
    final emoji = parseStr(c['emoji']);
    final name = parseStr(c['name']) ?? '';
    return emoji == '⚽' ||
        RegExp('soccer|football', caseSensitive: false).hasMatch(name);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _halfMinutes.dispose();
    _extraHalf.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (q.trim().length < 2) {
        if (mounted) setState(() => _results = const []);
        return;
      }
      setState(() => _searching = true);
      try {
        final r =
            await ref.read(groupsRepositoryProvider).searchUsers(q.trim());
        if (mounted) setState(() => _results = r);
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (d != null) {
      setState(() => _date =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
        context: context, initialTime: const TimeOfDay(hour: 16, minute: 0));
    if (t != null) {
      setState(() => _time =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _submit() async {
    final isMulti = widget.teams != null;
    final messenger = ScaffoldMessenger.of(context);
    if (isMulti) {
      if (_homeId == null || _awayId == null) {
        messenger
            .showSnackBar(const SnackBar(content: Text('Pick both teams')));
        return;
      }
      if (_homeId == _awayId) {
        messenger.showSnackBar(
            const SnackBar(content: Text("A team can't play itself")));
        return;
      }
    }
    setState(() => _saving = true);
    final body = <String, dynamic>{
      if (isMulti) 'homeTournamentTeamId': _homeId,
      if (isMulti) 'awayTournamentTeamId': _awayId,
      if (_officiantId != null) 'officiantUserId': _officiantId,
      'scheduledDate': _date,
      'scheduledTime': _time,
      if (_isSoccer)
        'lifecycle': {
          'usesHalves': _usesHalves,
          'halfMinutes':
              (int.tryParse(_halfMinutes.text) ?? 45).clamp(1, 180),
          'drawResolutions': [
            if (_allowExtraTime) 'extra_time',
            if (_allowPenalties) 'penalties',
          ],
          'extraTimeHalfMinutes': _allowExtraTime
              ? (int.tryParse(_extraHalf.text) ?? 15).clamp(1, 60)
              : null,
        },
    };
    try {
      await ref
          .read(tournamentsRepositoryProvider)
          .createMatch(widget.eventId, body);
      ref.invalidate(tournamentMatchProvider(widget.eventId));
      ref.invalidate(tournamentGamesProvider(widget.eventId));
      ref.invalidate(tournamentAwardsProvider(widget.eventId));
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(
          const SnackBar(content: Text('Match game created')));
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _check(String label, bool value, void Function(bool) onChanged) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(
            value
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: 20,
            color: value ? p.accent : p.muted,
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: p.ink, fontSize: 13.5)),
        ]),
      ),
    );
  }

  Widget _numField(String label, TextEditingController c) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(left: 28, top: 2, bottom: 6),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: TextStyle(color: p.muted, fontSize: 12.5)),
        ),
        SizedBox(
          width: 72,
          child: TextField(
            controller: c,
            keyboardType: TextInputType.number,
            style: TextStyle(color: p.ink, fontSize: 13.5),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: p.line)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _teamPicker(String label, String? value,
      void Function(String?) onChanged, String? exclude) {
    final p = context.palette;
    final opts = [
      for (final t in widget.teams!)
        if (t.id != exclude) t
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.line),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            hint: Text('Choose team',
                style: TextStyle(color: p.muted, fontSize: 13)),
            items: [
              for (final t in opts)
                DropdownMenuItem(
                  value: t.id,
                  child: Text(t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink, fontSize: 13.5)),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isMulti = widget.teams != null;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Create match game',
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            if (isMulti) ...[
              _teamPicker('Home team', _homeId,
                  (v) => setState(() => _homeId = v), _awayId),
              const SizedBox(height: 10),
              _teamPicker('Away team', _awayId,
                  (v) => setState(() => _awayId = v), _homeId),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Expanded(
                child: _OutlineBtn(
                  label: _date ?? 'Date (optional)',
                  icon: Icons.calendar_today_outlined,
                  expand: true,
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OutlineBtn(
                  label: _time ?? 'Time (optional)',
                  icon: Icons.schedule,
                  expand: true,
                  onTap: _pickTime,
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text('Leave blank to show "TBD". You can set it anytime before kickoff.',
                style: TextStyle(color: p.muted, fontSize: 11)),
            if (_isSoccer) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.line),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Match format',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      _check('Play in halves', _usesHalves,
                          (v) => setState(() => _usesHalves = v)),
                      if (_usesHalves)
                        _numField('Minutes per half', _halfMinutes),
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          border:
                              Border(top: BorderSide(color: p.line)),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('If the match is level at full time',
                                  style: TextStyle(
                                      color: p.muted,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600)),
                              _check('Allow extra time', _allowExtraTime,
                                  (v) =>
                                      setState(() => _allowExtraTime = v)),
                              if (_allowExtraTime)
                                _numField('Minutes per extra-time half',
                                    _extraHalf),
                              _check('Allow penalties', _allowPenalties,
                                  (v) =>
                                      setState(() => _allowPenalties = v)),
                              Text(
                                'The officiant chooses at the draw — only the '
                                'options you enable here are offered.',
                                style: TextStyle(
                                    color: p.muted, fontSize: 11),
                              ),
                            ]),
                      ),
                    ]),
              ),
            ],
            const SizedBox(height: 12),
            Text('Officiant (optional)',
                style: TextStyle(
                    color: p.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            if (_officiantId != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.line),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(_officiantLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.ink, fontSize: 13.5)),
                  ),
                  InkWell(
                    onTap: () => setState(() {
                      _officiantId = null;
                      _officiantLabel = '';
                    }),
                    child: Text('Change',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ),
                ]),
              )
            else ...[
              TextField(
                controller: _search,
                onChanged: _onSearch,
                style: TextStyle(color: p.ink, fontSize: 13.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search anyone by name or @handle',
                  hintStyle: TextStyle(color: p.muted, fontSize: 13),
                  prefixIcon: Icon(Icons.search, size: 18, color: p.muted),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: p.line)),
                ),
              ),
              if (_search.text.trim().length >= 2) ...[
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 170),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: p.line),
                  ),
                  child: _results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text('No one found.',
                              style: TextStyle(
                                  color: p.muted, fontSize: 12)),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final u in _results)
                              ListTile(
                                dense: true,
                                title: Text(u.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.ink, fontSize: 13.5)),
                                subtitle: u.username != null
                                    ? Text('@${u.username}',
                                        style: TextStyle(
                                            color: p.muted,
                                            fontSize: 11))
                                    : null,
                                onTap: () => setState(() {
                                  _officiantId = u.userId;
                                  _officiantLabel = u.username != null
                                      ? '${u.displayName} (@${u.username})'
                                      : u.displayName;
                                  _search.clear();
                                  _results = const [];
                                }),
                              ),
                          ],
                        ),
                ),
              ],
              const SizedBox(height: 4),
              Text("They'll get a request to approve before they can run the game.",
                  style: TextStyle(color: p.muted, fontSize: 11)),
            ],
            const SizedBox(height: 16),
            SpButton(
              label: _saving ? 'Creating…' : 'Create',
              expand: true,
              onTap: _saving ? null : _submit,
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kickoff time sheet — edit the match's scheduled date / time.
// ---------------------------------------------------------------------------

class _ScheduleSheet extends ConsumerStatefulWidget {
  const _ScheduleSheet({
    required this.eventId,
    required this.gameId,
    this.initialDate,
    this.initialTime,
  });
  final String eventId;
  final String gameId;
  final String? initialDate;
  final String? initialTime;

  static void show(BuildContext context,
      {required String eventId,
      required String gameId,
      String? initialDate,
      String? initialTime}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ScheduleSheet(
          eventId: eventId,
          gameId: gameId,
          initialDate: initialDate,
          initialTime: initialTime),
    );
  }

  @override
  ConsumerState<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends ConsumerState<_ScheduleSheet> {
  String? _date;
  String? _time;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _time = widget.initialTime;
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(tournamentsRepositoryProvider).schedule(
          widget.eventId, widget.gameId,
          date: _date, time: _time);
      ref.invalidate(tournamentMatchProvider(widget.eventId));
      if (mounted) Navigator.pop(context);
      messenger
          .showSnackBar(const SnackBar(content: Text('Kickoff updated')));
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child:
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Kickoff time',
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: _OutlineBtn(
                  label: _date ?? 'Date',
                  icon: Icons.calendar_today_outlined,
                  expand: true,
                  onTap: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate:
                          DateTime.tryParse(_date ?? '') ?? now,
                      firstDate: now.subtract(const Duration(days: 1)),
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (d != null) {
                      setState(() => _date =
                          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OutlineBtn(
                  label: _time ?? 'Time',
                  icon: Icons.schedule,
                  expand: true,
                  onTap: () async {
                    final t = await showTimePicker(
                        context: context,
                        initialTime: const TimeOfDay(hour: 16, minute: 0));
                    if (t != null) {
                      setState(() => _time =
                          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                    }
                  },
                ),
              ),
            ]),
            const SizedBox(height: 16),
            SpButton(
              label: _saving ? 'Saving…' : 'Save',
              expand: true,
              onTap: _saving ? null : _save,
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Invite team sheet (multi-team / league) — search by @handle or name.
// ---------------------------------------------------------------------------

class _InviteTeamSheet extends ConsumerStatefulWidget {
  const _InviteTeamSheet({
    required this.eventId,
    required this.categoryId,
    required this.hostGroupId,
    required this.existingTeamIds,
  });
  final String eventId;
  final String? categoryId;
  final String? hostGroupId;
  final List<String> existingTeamIds;

  static void show(BuildContext context,
      {required String eventId,
      required String? categoryId,
      required String? hostGroupId,
      required List<String> existingTeamIds}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _InviteTeamSheet(
          eventId: eventId,
          categoryId: categoryId,
          hostGroupId: hostGroupId,
          existingTeamIds: existingTeamIds),
    );
  }

  @override
  ConsumerState<_InviteTeamSheet> createState() => _InviteTeamSheetState();
}

class _InviteTeamSheetState extends ConsumerState<_InviteTeamSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<TeamSummary> _results = const [];
  bool _searching = false;
  bool _inviting = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (q.trim().length < 2) {
        if (mounted) setState(() => _results = const []);
        return;
      }
      setState(() => _searching = true);
      try {
        final r = await ref.read(manageRepositoryProvider).searchTeams(
            q.trim(),
            categoryId: widget.categoryId,
            excludeGroupId: widget.hostGroupId);
        if (mounted) {
          setState(() => _results = [
                for (final t in r)
                  if (!widget.existingTeamIds.contains(t.id)) t
              ]);
        }
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _invite(TeamSummary t) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _inviting = true);
    try {
      await ref
          .read(tournamentsRepositoryProvider)
          .inviteTeam(widget.eventId, t.id);
      ref.invalidate(tournamentDetailProvider(widget.eventId));
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Invite sent')));
    } catch (e) {
      if (mounted) setState(() => _inviting = false);
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invite a team',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  onChanged: _onSearch,
                  style: TextStyle(color: p.ink, fontSize: 13.5),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search team @handle or name',
                    hintStyle: TextStyle(color: p.muted, fontSize: 13),
                    prefixIcon:
                        Icon(Icons.search, size: 18, color: p.muted),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: p.line)),
                  ),
                ),
                if (_search.text.trim().length >= 2) ...[
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: p.line),
                    ),
                    child: _results.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text('No teams found.',
                                style: TextStyle(
                                    color: p.muted, fontSize: 12)),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final t in _results)
                                ListTile(
                                  dense: true,
                                  leading: Crest(
                                    logoUrl: t.logoUrl,
                                    kitPrimary: t.kitPrimary,
                                    kitSecondary: t.kitSecondary,
                                    label: t.name,
                                    size: 36,
                                  ),
                                  title: Text(t.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: p.ink, fontSize: 13.5)),
                                  subtitle: t.username != null
                                      ? Text('@${t.username}',
                                          style: TextStyle(
                                              color: p.muted,
                                              fontSize: 11))
                                      : null,
                                  trailing: Icon(Icons.add,
                                      size: 18, color: p.muted),
                                  onTap:
                                      _inviting ? null : () => _invite(t),
                                ),
                            ],
                          ),
                  ),
                ],
              ]),
        ),
      ),
    );
  }
}
