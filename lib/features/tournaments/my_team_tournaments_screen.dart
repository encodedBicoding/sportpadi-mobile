import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/tournaments/my_team_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/features/tournaments/invitation_rows.dart';
import 'package:sportpadi_mobile/features/tournaments/my_tournaments_screen.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

const _tabs = <(String, String)>[
  ('all', 'All'),
  ('live', 'Live'),
  ('upcoming', 'Upcoming'),
  ('invited', 'Invites'),
  ('past', 'Past'),
];

/// One team's tournaments, every kind — live, upcoming, invites (group admins
/// answer them here) and past. Opened from a team card on the Tournaments tab
/// (web: /tournaments/teams/:teamId).
class MyTeamTournamentsScreen extends ConsumerStatefulWidget {
  const MyTeamTournamentsScreen({super.key, required this.teamId});
  final String teamId;

  @override
  ConsumerState<MyTeamTournamentsScreen> createState() =>
      _MyTeamTournamentsScreenState();
}

class _MyTeamTournamentsScreenState
    extends ConsumerState<MyTeamTournamentsScreen> {
  String _tab = 'all';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final data = ref.watch(myTeamTournamentsProvider(widget.teamId));
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: Text(data.valueOrNull?.team.name ?? 'Team',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: AsyncView(
        value: data,
        onRetry: () =>
            ref.invalidate(myTeamTournamentsProvider(widget.teamId)),
        data: (v) {
          final t = v.team;
          int count(String b) =>
              b == 'all' ? v.entries.length : v.entries.where((e) => e.bucket == b).length;
          final shown = _tab == 'all'
              ? v.entries
              : v.entries.where((e) => e.bucket == _tab).toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myTeamTournamentsProvider(widget.teamId));
              ref.invalidate(myCallsProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                Row(children: [
                  TeamCrest(team: t, size: 60),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 20,
                                fontWeight: FontWeight.w900)),
                        if (t.subtitle.isNotEmpty)
                          Text(t.subtitle,
                              style: TextStyle(color: p.muted, fontSize: 12.5)),
                        if (t.played > 0)
                          Text(
                              'Tournament record: ${t.won}W ${t.drawn}D ${t.lost}L',
                              style: TextStyle(
                                  color: p.muted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final (id, label) in _tabs)
                      if (!(id == 'invited' && count(id) == 0 && !t.isAdmin))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text('$label  ${count(id)}'),
                            selected: _tab == id,
                            onSelected: (_) => setState(() => _tab = id),
                          ),
                        ),
                  ]),
                ),
                const SizedBox(height: 12),
                SquadCallUps(teamId: widget.teamId),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        switch (_tab) {
                          'live' => 'Nothing live right now.',
                          'upcoming' => 'No upcoming tournaments.',
                          'invited' => 'No invitations waiting.',
                          'past' => 'No past tournaments yet.',
                          _ => "This team hasn't played in a tournament yet.",
                        },
                        style: TextStyle(color: p.muted),
                      ),
                    ),
                  )
                else
                  for (final e in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: e.bucket == 'invited' && e.invite != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const _BucketLabel('invited'),
                                const SizedBox(height: 6),
                                InvitationListBox(
                                  invites: [e.invite!],
                                  onDone: () => ref.invalidate(
                                      myTeamTournamentsProvider(widget.teamId)),
                                ),
                              ],
                            )
                          : _EntryCard(e: e),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BucketLabel extends StatelessWidget {
  const _BucketLabel(this.bucket);
  final String bucket;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (label, color) = switch (bucket) {
      'live' => ('● LIVE', p.danger),
      'upcoming' => ('UPCOMING', p.accent),
      'invited' => ('INVITE', p.amber),
      _ => ('PAST', p.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8)),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.e});
  final MyTeamTournament e;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final vs = e.opponents.isEmpty
        ? null
        : e.opponents.length == 1
            ? 'vs ${e.opponents.first}'
            : '${e.opponents.length + 1} teams';
    final date = e.eventDate;
    return GestureDetector(
      onTap: () => context.push('/tournaments/${e.eventId}'),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BucketLabel(e.bucket),
            const SizedBox(height: 6),
            Text(e.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(
              [
                if (date != null) '${date.day}/${date.month}/${date.year}',
                if (e.locationName != null) e.locationName!,
                if (vs != null) vs,
                if (e.role == 'host')
                  'Your team hosts'
                else if (e.hostGroupName != null)
                  'Hosted by ${e.hostGroupName}',
                if (e.tournamentStatus == 'cancelled') 'Cancelled',
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
            if (e.games.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(height: 1, color: p.line),
              const SizedBox(height: 8),
              for (final g in e.games.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Expanded(
                      child: Text('vs ${g.opponentName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12.5)),
                    ),
                    if (g.status == 'completed' || g.status == 'live')
                      Text(
                          '${g.status == 'live' ? 'LIVE ' : ''}${g.myScore}–${g.oppScore}',
                          style: TextStyle(
                              color: g.status == 'live'
                                  ? p.danger
                                  : g.result == 'win'
                                      ? p.accent
                                      : g.result == 'loss'
                                          ? p.danger
                                          : p.ink,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800))
                    else
                      Text(g.scheduledDate ?? 'Not scheduled',
                          style: TextStyle(color: p.muted, fontSize: 11.5)),
                  ]),
                ),
              if (e.games.length > 4)
                Text('+${e.games.length - 4} more games',
                    style: TextStyle(color: p.muted, fontSize: 11)),
            ],
            if (e.hostGroupId != null && e.bucket != 'past') ...[
              const SizedBox(height: 10),
              Container(height: 1, color: p.line),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(
                        '/groups/${e.hostGroupId}/tournaments/${e.eventId}/teams/${e.teamId}'),
                    icon: const Icon(Icons.groups_2_outlined, size: 16),
                    label: const Text('Squad'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(
                        '/groups/${e.hostGroupId}/tournaments/${e.eventId}/teams/${e.teamId}/formation'),
                    icon: const Icon(Icons.grid_view_rounded, size: 16),
                    label: const Text('Formation'),
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
