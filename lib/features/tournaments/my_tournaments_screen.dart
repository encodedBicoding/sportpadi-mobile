import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_models.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/tournaments/squad_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournament_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/features/tournaments/invitation_rows.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_app_bar.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Bottom-nav "Tournaments" tab: every tournament the user is part of through
/// a team roster spot, grouped by team. Tapping an entry opens the tournament.
class MyTournamentsScreen extends ConsumerWidget {
  const MyTournamentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final data = ref.watch(myTournamentsProvider);
    return Scaffold(
      appBar: const SpAppBar(),
      body: AsyncView(
        value: data,
        onRetry: () {
          ref.invalidate(myTournamentsProvider);
          ref.invalidate(myTournamentInvitesProvider);
        },
        data: (entries) {
          if (entries.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
              ref.invalidate(myTournamentsProvider);
              ref.invalidate(myTournamentInvitesProvider);
            },
              child: ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  const _Invitations(),
                  const _CallUps(),
                  const SizedBox(height: 60),
                  Icon(Icons.emoji_events_outlined, size: 44, color: p.muted),
                  const SizedBox(height: 12),
                  Center(
                    child: Text('No tournaments yet',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'When one of your teams joins a tournament,\nit shows up here.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: p.muted, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            );
          }
          // Group by team, preserving server order.
          final byTeam = <String, List<MyTournamentEntry>>{};
          for (final e in entries) {
            byTeam.putIfAbsent(e.teamId, () => []).add(e);
          }
          final sections = byTeam.values.toList();
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myTournamentsProvider);
              ref.invalidate(myTournamentInvitesProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: sections.length + 1,
              itemBuilder: (_, i) => i == 0
                  ? const Column(children: [_Invitations(), _CallUps()])
                  : _TeamSection(entries: sections[i - 1]),
            ),
          );
        },
      ),
    );
  }
}

class _TeamSection extends StatelessWidget {
  const _TeamSection({required this.entries});
  final List<MyTournamentEntry> entries;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = entries.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (t.teamLogoUrl != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CircleAvatar(
                  radius: 12,
                  backgroundImage: NetworkImage(t.teamLogoUrl!),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.shield_outlined, size: 20, color: p.accent),
              ),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: t.teamName,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                  if (t.teamGroupName != null)
                    TextSpan(
                        text: '  ·  ${t.teamGroupName}',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 10),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TournamentEntryCard(e: e),
            ),
        ],
      ),
    );
  }
}

class _TournamentEntryCard extends StatelessWidget {
  const _TournamentEntryCard({required this.e});
  final MyTournamentEntry e;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final done =
        e.tournamentStatus == 'completed' || e.tournamentStatus == 'cancelled';
    return GestureDetector(
      onTap: () => context.push('/tournaments/${e.eventId}'),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              // No "invite pending" branch here any more: this list is
              // accepted tournaments only, and unanswered invites live in the
              // invitations section above.
              SpBadge(
                done
                    ? e.tournamentStatus
                    : e.tournamentStatus.replaceAll('_', ' '),
                tone: done ? p.muted : p.accent,
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              [
                if (e.category != null) e.category!,
                if (e.hostGroupName != null) 'Hosted by ${e.hostGroupName}',
                if (e.role == 'host') 'Your team hosts',
              ].join(' · '),
              maxLines: 1,
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
                    if (g.status == 'completed')
                      Text('${g.myScore}–${g.oppScore}',
                          style: TextStyle(
                              color: g.result == 'win'
                                  ? p.accent
                                  : g.result == 'loss'
                                      ? p.danger
                                      : p.ink,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800))
                    else
                      Text(
                        g.status == 'live'
                            ? 'LIVE'
                            : (g.scheduledDate ?? 'Not scheduled'),
                        style: TextStyle(
                            color: g.status == 'live' ? p.danger : p.muted,
                            fontSize: 11.5,
                            fontWeight: g.status == 'live'
                                ? FontWeight.w800
                                : FontWeight.w500),
                      ),
                  ]),
                ),
              if (e.games.length > 4)
                Text('+${e.games.length - 4} more games',
                    style: TextStyle(color: p.muted, fontSize: 11)),
            ],
            // The squad page — who's called and the formation for THIS
            // tournament — was reachable only by knowing a team crest deep
            // inside the tournament page was tappable.
            if (e.hostGroupId != null) ...[
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

/// Pending call-ups: a coach wants you for a specific tournament. Accept /
/// decline right here; tap the card for the squad page.
class _CallUps extends ConsumerStatefulWidget {
  const _CallUps();
  @override
  ConsumerState<_CallUps> createState() => _CallUpsState();
}

class _CallUpsState extends ConsumerState<_CallUps> {
  String? _busyId;

  Future<void> _respond(SquadCall c, bool accept) async {
    final eventId = c.eventId;
    if (eventId == null) return;
    setState(() => _busyId = c.squadId);
    try {
      await ref
          .read(tournamentsRepositoryProvider)
          .respondCall(eventId, c.squadId, accept: accept);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(accept ? "You're in the squad" : 'Response sent')));
      }
      ref.invalidate(myCallsProvider);
      ref.invalidate(myTournamentsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final calls = ref.watch(myCallsProvider).valueOrNull?.pending ?? const <SquadCall>[];
    if (calls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.campaign_rounded, size: 16, color: p.amber),
          const SizedBox(width: 6),
          Text('CALL-UPS WAITING FOR YOU (${calls.length})',
              style: TextStyle(
                  color: p.amber, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        ]),
        const SizedBox(height: 8),
        for (final c in calls)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.amber.withAlpha(16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.amber.withAlpha(100)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                InkWell(
                  onTap: c.route != null ? () => context.push(c.route!) : null,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c.teamName ?? 'Your team'} · ${c.eventTitle ?? 'Tournament'}',
                        style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    // A call-up is a commitment — show enough to answer it.
                    Text(
                      [
                        c.when.line,
                        if (c.locationName != null) c.locationName!,
                        if (c.opponentName != null) 'vs ${c.opponentName}',
                      ].join('  ·  '),
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                    if (c.when.viewerTime != null)
                      Text('${c.when.viewerTime} your time',
                          style: TextStyle(color: p.muted, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (c.categoryName != null)
                          '${c.categoryEmoji ?? ''} ${c.categoryName}'.trim(),
                        if (c.hostGroupName != null)
                          'hosted by ${c.hostGroupName}',
                        'called ${timeAgo(c.calledAt)}',
                      ].join(' · '),
                      style: TextStyle(color: p.muted, fontSize: 11.5),
                    ),
                    if (c.callNote != null && c.callNote!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          border:
                              Border(left: BorderSide(color: p.amber, width: 2.5)),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("COACH'S REMARK",
                                  style: TextStyle(
                                      color: p.muted,
                                      fontSize: 9.5,
                                      letterSpacing: 0.6,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 1),
                              Text(c.callNote!.trim(),
                                  style: TextStyle(
                                      color: p.ink, fontSize: 11.5, height: 1.3)),
                            ]),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text('Accepting locks you to this team for this tournament.',
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                  ]),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: SpButton(
                      label: _busyId == c.squadId ? 'Sending…' : "I'm in",
                      icon: Icons.check_rounded,
                      expand: true,
                      onTap: _busyId != null ? null : () => _respond(c, true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busyId != null ? null : () => _respond(c, false),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text("Can't make it"),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// The three soonest invitations, inline.
///
/// Anything beyond that lives on /tournaments/invitations — a club juggling a
/// dozen invites shouldn't have to scroll past all of them to reach the
/// tournaments it already committed to. They sit OUTSIDE the list below on
/// purpose: a tournament nobody has agreed to play isn't a fixture.
const _inlineInvites = 3;

class _Invitations extends ConsumerWidget {
  const _Invitations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final invites =
        ref.watch(myTournamentInvitesProvider).valueOrNull ?? const <TournamentInvite>[];
    if (invites.isEmpty) return const SizedBox.shrink();
    final shown = invites.take(_inlineInvites).toList();
    final rest = invites.length - shown.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.mark_email_unread_outlined, size: 16, color: p.amber),
          const SizedBox(width: 6),
          Expanded(
            child: Text('TOURNAMENT INVITATIONS (${invites.length})',
                style: TextStyle(
                    color: p.amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1)),
          ),
          if (rest > 0)
            InkWell(
              onTap: () => context.push('/tournaments/invitations'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('See all ${invites.length}',
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        InvitationListBox(invites: shown),
        if (rest > 0) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: () => context.push('/tournaments/invitations'),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: p.amber.withAlpha(80)),
              ),
              child: Text(
                '$rest more invitation${rest == 1 ? '' : 's'}',
                style: TextStyle(
                    color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
