import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/shared/format/event_time.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// One player's record inside ONE tournament.
///
/// The tournaments tab used to hand a visitor straight to the tournament,
/// which answers "what was this tournament" — not "how did THIS player do in
/// it". This is the second question. The tournament itself and their squad
/// page stay one tap away.
final playerTournamentStatsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String userId, String eventId})>(
        (ref, key) async {
  try {
    final res = await ref
        .watch(dioProvider)
        .get('/api/mobile/players/${key.userId}/tournaments/${key.eventId}');
    if (res.data is! Map) {
      // A 200 that isn't an object means the bridge route didn't run this
      // procedure — say so distinctly rather than looking like a 404.
      throw ApiException('The server returned an empty record.', statusCode: 502);
    }
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    throw apiError(e, fallback: 'Could not load their record.');
  }
});

class PlayerTournamentStatsScreen extends ConsumerWidget {
  const PlayerTournamentStatsScreen({
    super.key,
    required this.userId,
    required this.eventId,
  });
  final String userId;
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final key = (userId: userId, eventId: eventId);
    final data = ref.watch(playerTournamentStatsProvider(key));

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Record in tournament',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(playerTournamentStatsProvider(key)),
        data: (m) {
          final player = mapOf(m['player']);
          final event = mapOf(m['event']);
          final squad = m['squad'] is Map ? mapOf(m['squad']) : null;
          final team = squad == null ? null : mapOf(squad['team']);
          final fields = listOf(m['fields']);
          final record = mapOf(m['record']);
          final matches = listOf(m['matches']);
          final first =
              (parseStr(player['displayName']) ?? 'Player').split(' ').first;
          final mode = parseStr(event['mode']);
          final kind = mode == 'league'
              ? 'league'
              : mode == 'multi_team'
                  ? 'tournament'
                  : 'friendly';
          final hostGroupId = parseStr(event['hostGroupId']);
          final when = formatEventTimeJson(event);
          final cat = mapOf(event['category']);

          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(playerTournamentStatsProvider(key).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // Who, where, and the way out to the tournament itself.
                GlassCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          InkWell(
                            onTap: () => context.push('/players/$userId'),
                            child: ClipOval(
                              child: Crest(
                                  logoUrl: parseStr(player['avatarUrl']),
                                  label: first,
                                  size: 42),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Wrap(spacing: 5, runSpacing: 4, children: [
                                    SpBadge(kind[0].toUpperCase() + kind.substring(1),
                                        icon: Icons.emoji_events_outlined),
                                    if (cat.isNotEmpty)
                                      SpBadge(
                                          '${parseStr(cat['emoji']) ?? ''} ${parseStr(cat['name']) ?? ''}'
                                              .trim()),
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(parseStr(event['title']) ?? 'Tournament',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: p.ink,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                      when.line,
                                      if (parseStr(event['locationName']) != null)
                                        event['locationName'] as String,
                                      if (parseStr(event['hostGroupName']) != null)
                                        'hosted by ${event['hostGroupName']}',
                                    ].join(' · '),
                                    style: TextStyle(color: p.muted, fontSize: 11.5),
                                  ),
                                  if (when.viewerTime != null)
                                    Text('${when.viewerTime} your time',
                                        style: TextStyle(color: p.muted, fontSize: 11)),
                                ]),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 6, children: [
                          if (hostGroupId != null)
                            _chip(p, 'Open $kind', Icons.north_east_rounded,
                                () => context.push(
                                    '/groups/$hostGroupId/tournaments/$eventId')),
                          if (hostGroupId != null && team != null)
                            _chip(
                                p,
                                '${parseStr(team['name']) ?? 'Team'} squad',
                                Icons.groups_2_outlined,
                                () => context.push(
                                    '/groups/$hostGroupId/tournaments/$eventId/teams/${team['id']}')),
                        ]),
                      ]),
                ),
                const SizedBox(height: 12),

                // Their place in the squad.
                if (squad != null && team != null)
                  GlassCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SQUAD PLACE',
                              style: TextStyle(
                                  color: p.muted,
                                  fontSize: 9.5,
                                  letterSpacing: 0.6,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text.rich(TextSpan(children: [
                            TextSpan(
                                text: 'Team ',
                                style: TextStyle(color: p.muted, fontSize: 12.5)),
                            TextSpan(
                                text: parseStr(team['name']) ?? 'Team',
                                style: TextStyle(
                                    color: p.ink,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700)),
                            if (parseStr(team['groupName']) != null)
                              TextSpan(
                                  text: ' · ${team['groupName']}',
                                  style: TextStyle(color: p.muted, fontSize: 12.5)),
                            if (parseInt(squad['jerseyNumber']) != null)
                              TextSpan(
                                  text: '   Shirt #${squad['jerseyNumber']}',
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)),
                          ])),
                          const SizedBox(height: 2),
                          Text(
                            [
                              'Status: ${parseStr(squad['status']) ?? '—'}',
                              if (squad['isStarter'] == true) 'in the starting line-up',
                              if (parseDate(squad['acceptedAt']) != null)
                                'joined ${formatDayYear(squad['acceptedAt'])}'
                                    '${squad['joinedAfterKickoff'] == true ? ' (after kick-off)' : ''}',
                            ].join(' · '),
                            style: TextStyle(color: p.muted, fontSize: 12),
                          ),
                        ]),
                  )
                else
                  GlassCard(
                    child: Text(
                      "$first isn't in a squad for this $kind"
                      "${matches.isNotEmpty ? ', but appeared in its games.' : '.'}",
                      style: TextStyle(color: p.muted, fontSize: 12.5),
                    ),
                  ),
                const SizedBox(height: 12),

                // The tally.
                ScopeBlock(
                  title: "$first's record in this $kind",
                  tally: record,
                  fields: fields,
                  accent: true,
                  empty: matches.any((x) => parseStr(x['status']) == 'live')
                      ? 'No completed games yet — one is live now.'
                      : 'No completed games yet.',
                ),

                // Match by match.
                if (matches.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  GlassCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('MATCHES (${matches.length})',
                              style: TextStyle(
                                  color: p.muted,
                                  fontSize: 9.5,
                                  letterSpacing: 0.6,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          for (final x in matches) _match(context, p, x, fields),
                        ]),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _chip(AppPalette p, String label, IconData icon, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: p.muted),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: p.ink, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _match(BuildContext context, AppPalette p, Map<String, dynamic> m,
      List<Map<String, dynamic>> fields) {
    final us = mapOf(m['us']);
    final them = m['them'] is Map ? mapOf(m['them']) : null;
    final status = parseStr(m['status']) ?? 'scheduled';
    final result = parseStr(m['result']);
    final counts = mapOf(m['counts']);
    final contrib = [
      for (final f in fields)
        if (statInt(counts[parseStr(f['key'])]) > 0)
          '${parseStr(f['icon']) ?? ''}${statInt(counts[parseStr(f['key'])])}'
    ].join('  ');
    final tone = result == 'win'
        ? const Color(0xFF16A34A)
        : result == 'loss'
            ? p.danger
            : p.muted;
    final sub = [
      status == 'completed'
          ? 'Full time'
          : status == 'live'
              ? 'Live now'
              : (parseStr(m['scheduledDate']) != null
                  ? '${m['scheduledDate']}${parseStr(m['scheduledTime']) != null ? ' · ${formatTime12(m['scheduledTime'] as String)}' : ''}'
                  : 'Not scheduled'),
      if (status == 'completed') m['started'] == true ? 'started' : 'from the bench',
      if (contrib.isNotEmpty) contrib,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => context.push('/games/${m['gameId']}'),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.line),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        '${parseStr(us['name']) ?? 'Us'} vs ${parseStr(them?['name']) ?? 'TBD'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 11)),
                  ]),
            ),
            const SizedBox(width: 8),
            Text(
                status == 'scheduled'
                    ? '–'
                    : '${statInt(us['score'])}–${statInt(them?['score'])}',
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w900)),
            if (result != null) ...[
              const SizedBox(width: 8),
              SpBadge(result.toUpperCase(), tone: tone),
            ],
          ]),
        ),
      ),
    );
  }
}
