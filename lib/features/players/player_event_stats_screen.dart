import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/shared/format/event_time.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';

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
      body: SafeArea(
        bottom: false,
        child: isPrivateRecordError(data.error)
            ? const PlayerPrivateView(title: 'Record in event')
            : AsyncView(
          value: data,
          onRetry: () => ref.invalidate(playerEventStatsProvider(key)),
          data: (m) {
            final event = mapOf(m['event']);
            // A tournament has a richer page of its own — hand over to it
            // rather than showing a thinner version here.
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
            // The event's sport picks the design (artwork + stats block).
            final family = cat.isEmpty ? null : familyOf(cat);
            final when = formatEventTimeJson(event);
            final slug = parseStr(event['slug']) ?? eventId;
            final groupId = parseStr(event['groupId']);
            final status = parseStr(event['status']) ?? '';
            final hasGames = matches.isNotEmpty;
            final games = statInt(record['games']);

            final statusLabel = status == 'completed'
                ? 'Finished'
                : status == 'kicked_off'
                    ? 'Live'
                    : status.isEmpty
                        ? null
                        : '${status[0].toUpperCase()}${status.substring(1).replaceAll('_', ' ')}';

            return RefreshIndicator(
              onRefresh: () =>
                  ref.refresh(playerEventStatsProvider(key).future),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                children: [
                  SpHeader(
                    title: 'Record in event',
                    subtitle: parseStr(event['title']),
                  ),
                  const SizedBox(height: 16),

                  // Who, where, and the headline numbers.
                  RecordHero(
                    family: family,
                    emoji: parseStr(cat['emoji']),
                    name: shownName,
                    avatarUrl: parseStr(player['avatarUrl']),
                    nameSub: aka != null ? parseStr(player['displayName']) : null,
                    onPlayerTap: () => context.push('/players/$userId'),
                    status: statusLabel,
                    statusLive: status == 'kicked_off',
                    eyebrow: parseStr(cat['name']),
                    title: parseStr(event['title']) ?? 'Event',
                    meta: [
                      when.line,
                      if (parseStr(event['locationName']) != null)
                        event['locationName'] as String,
                      if (parseStr(event['groupName']) != null)
                        event['groupName'] as String,
                    ].join(' · '),
                    stats: hasGames && games > 0
                        ? recordHeroStats(record, fields)
                        : const [],
                    pills: [
                      if (attended)
                        recordHeroPill(
                          checkedInAt != null
                              ? 'Checked in · ${formatDayYear(checkedInAt)}'
                              : 'Checked in',
                          const Color(0x296EDC9E),
                          recordMint,
                          icon: Icons.check_circle_rounded,
                        ),
                    ],
                  ),

                  // The event itself, and the wider record — both on purpose.
                  const SizedBox(height: 12),
                  recordActions([
                    RecordAction(
                        label: 'Open event',
                        icon: Icons.north_east_rounded,
                        onTap: () => context.push('/events/$slug')),
                    if (groupId != null)
                      RecordAction(
                          label: 'In this group',
                          icon: Icons.bar_chart_rounded,
                          onTap: () => context
                              .push('/players/$userId/groups/$groupId')),
                  ]),

                  // Their setup for this sport — same card as the profile.
                  if (setup.isNotEmpty && cat.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    SportSetup(category: {
                      'emoji': cat['emoji'],
                      'name': cat['name'],
                      'setup': setup,
                    }),
                  ],

                  const SizedBox(height: 14),
                  if (!hasGames)
                    RecordEmpty(
                      icon: Icons.emoji_events_outlined,
                      title: 'No games recorded',
                      body: attended
                          ? '$first was there, but no game with stats was played or recorded at this event.'
                          : "$first didn't feature in any recorded game here.",
                    )
                  else
                    ScopeBlock(
                      title: "$first's record in this event",
                      family: family ?? SportFamily.generic,
                      collapseKey: 'event-record',
                      tally: record,
                      fields: fields,
                      accent: true,
                      empty: matches
                              .any((x) => parseStr(x['status']) == 'live')
                          ? 'No completed games yet — one is live now.'
                          : 'No completed games yet.',
                    ),

                  // Game by game.
                  if (hasGames) ...[
                    const SizedBox(height: 22),
                    RecordSectionTitle('Games', count: matches.length),
                    const SizedBox(height: 10),
                    RecordList(children: [
                      for (final x in matches)
                        RecordMatchRow(match: x, fields: fields),
                    ]),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
