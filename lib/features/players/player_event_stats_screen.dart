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

/// One player's record inside ONE event.
///
/// Tapping an attended event used to open the event page — which, for a
/// finished event, is a scoresheet: "what happened", not "how did I do". This
/// is the second question. The event itself stays one tap away, but only on
/// purpose: the visitor has to choose it.
final playerEventStatsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String userId, String eventId})>(
        (ref, key) async {
  try {
    final res = await ref
        .watch(dioProvider)
        .get('/api/mobile/players/${key.userId}/events/${key.eventId}');
    if (res.data is! Map) {
      throw ApiException('The server returned an empty record.',
          statusCode: 502);
    }
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    throw apiError(e, fallback: 'Could not load their record.');
  }
});

class PlayerEventStatsScreen extends ConsumerWidget {
  const PlayerEventStatsScreen({
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
    final data = ref.watch(playerEventStatsProvider(key));

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Record in event',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(playerEventStatsProvider(key)),
        data: (m) {
          final event = mapOf(m['event']);
          // A tournament has a richer page of its own — hand over to it rather
          // than showing a thinner version here.
          if (event['isTournament'] == true) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                context.pushReplacement(
                    '/players/$userId/tournaments/$eventId');
              }
            });
            return const Center(child: CircularProgressIndicator());
          }

          final player = mapOf(m['player']);
          final aka = parseStr(m['aka']);
          final shownName =
              aka ?? parseStr(player['displayName']) ?? 'Player';
          final first = shownName.split(' ').first;
          final attended = m['attended'] == true;
          final checkedInAt = parseDate(m['checkedInAt']);
          final setup = listOf(m['setup']);
          final fields = listOf(m['fields']);
          final record = mapOf(m['record']);
          final matches = listOf(m['matches']);
          final cat = mapOf(event['category']);
          final when = formatEventTimeJson(event);
          final slug = parseStr(event['slug']) ?? eventId;
          final groupId = parseStr(event['groupId']);
          final status = parseStr(event['status']) ?? '';
          final hasGames = matches.isNotEmpty;

          return RefreshIndicator(
            onRefresh: () => ref.refresh(playerEventStatsProvider(key).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // Who and where — with the event itself as an explicit choice.
                GlassCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () =>
                                    context.push('/players/$userId'),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Wrap(spacing: 5, runSpacing: 4, children: [
                                        if (cat.isNotEmpty)
                                          SpBadge(
                                              '${parseStr(cat['emoji']) ?? ''} ${parseStr(cat['name']) ?? ''}'
                                                  .trim()),
                                        SpBadge(status == 'completed'
                                            ? 'Finished'
                                            : status.replaceAll('_', ' ')),
                                      ]),
                                      const SizedBox(height: 4),
                                      Text(parseStr(event['title']) ?? 'Event',
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
                                          if (parseStr(event['locationName']) !=
                                              null)
                                            event['locationName'] as String,
                                          if (parseStr(event['groupName']) !=
                                              null)
                                            event['groupName'] as String,
                                        ].join(' · '),
                                        style: TextStyle(
                                            color: p.muted, fontSize: 11.5),
                                      ),
                                      if (aka != null)
                                        Text('Known here as $aka',
                                            style: TextStyle(
                                                color: p.muted,
                                                fontSize: 11)),
                                    ]),
                              ),
                            ]),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 6, children: [
                          _chip(p, 'Open event', Icons.north_east_rounded,
                              () => context.push('/events/$slug')),
                          if (groupId != null)
                            _chip(
                                p,
                                'Record in this group',
                                Icons.bar_chart_rounded,
                                () => context
                                    .push('/players/$userId/groups/$groupId')),
                        ]),
                      ]),
                ),

                // Attendance — the one thing that's always true of an attended
                // event.
                if (attended) ...[
                  const SizedBox(height: 12),
                  GlassCard(
                    child: Row(children: [
                      Icon(Icons.event_available_rounded,
                          size: 18, color: p.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(
                              text: 'Checked in',
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                          if (checkedInAt != null)
                            TextSpan(
                                text: ' · ${formatDayYear(checkedInAt)}',
                                style: TextStyle(
                                    color: p.muted, fontSize: 12.5)),
                        ])),
                      ),
                    ]),
                  ),
                ],

                // Their setup for this sport — same card as the profile.
                if (setup.isNotEmpty && cat.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SportSetup(category: {
                    'emoji': cat['emoji'],
                    'name': cat['name'],
                    'setup': setup,
                  }),
                ],

                const SizedBox(height: 12),
                if (!hasGames)
                  GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      Icon(Icons.emoji_events_outlined,
                          size: 28, color: p.muted),
                      const SizedBox(height: 8),
                      Text('No games recorded',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        attended
                            ? '$first was there, but no game with stats was played or recorded at this event.'
                            : "$first didn't feature in any recorded game here.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: p.muted, fontSize: 12, height: 1.35),
                      ),
                    ]),
                  )
                else
                  ScopeBlock(
                    title: "$first's record in this event",
                    tally: record,
                    fields: fields,
                    accent: true,
                    empty: matches.any((x) => parseStr(x['status']) == 'live')
                        ? 'No completed games yet — one is live now.'
                        : 'No completed games yet.',
                  ),

                // Game by game.
                if (hasGames) ...[
                  const SizedBox(height: 12),
                  GlassCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('GAMES (${matches.length})',
                              style: TextStyle(
                                  color: p.muted,
                                  fontSize: 9.5,
                                  letterSpacing: 0.6,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          for (final x in matches)
                            _match(context, p, x, fields),
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
              : 'Not started',
      if (status == 'completed')
        m['started'] == true ? 'started' : 'from the bench',
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
                        '${parseStr(us['name']) ?? 'Us'} vs ${parseStr(them?['name']) ?? 'Field'}',
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
