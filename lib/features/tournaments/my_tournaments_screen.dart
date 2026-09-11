import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/tournaments/tournament_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
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
        onRetry: () => ref.invalidate(myTournamentsProvider),
        data: (entries) {
          if (entries.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(myTournamentsProvider),
              child: ListView(
                padding: const EdgeInsets.all(32),
                children: [
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
            onRefresh: () async => ref.invalidate(myTournamentsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: sections.length,
              itemBuilder: (_, i) => _TeamSection(entries: sections[i]),
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
              SpBadge(
                done
                    ? e.tournamentStatus
                    : (e.entryStatus == 'pending'
                        ? 'Invite pending'
                        : e.tournamentStatus.replaceAll('_', ' ')),
                tone: done
                    ? p.muted
                    : (e.entryStatus == 'pending' ? p.amber : p.accent),
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
          ],
        ),
      ),
    );
  }
}
