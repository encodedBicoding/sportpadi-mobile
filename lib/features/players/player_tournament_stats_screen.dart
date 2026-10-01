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
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
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
      throw ApiException('The server returned an empty record.',
          statusCode: 502);
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
      body: SafeArea(
        bottom: false,
        child: isPrivateRecordError(data.error)
            ? const PlayerPrivateView(title: 'Record')
            : AsyncView(
                value: data,
                onRetry: () =>
                    ref.invalidate(playerTournamentStatsProvider(key)),
                data: (m) {
                  final player = mapOf(m['player']);
                  final event = mapOf(m['event']);
                  final squad = m['squad'] is Map ? mapOf(m['squad']) : null;
                  final team = squad == null ? null : mapOf(squad['team']);
                  final fields = listOf(m['fields']);
                  final record = mapOf(m['record']);
                  final matches = listOf(m['matches']);
                  final first = (parseStr(player['displayName']) ?? 'Player')
                      .split(' ')
                      .first;
                  final mode = parseStr(event['mode']);
                  final kind = mode == 'league'
                      ? 'league'
                      : mode == 'multi_team'
                          ? 'tournament'
                          : 'friendly';
                  final hostGroupId = parseStr(event['hostGroupId']);
                  final when = formatEventTimeJson(event);
                  final cat = mapOf(event['category']);
                  // The tournament's sport picks the design (artwork + stats block).
                  final family = cat.isEmpty ? null : familyOf(cat);

                  final kindTitle = kind[0].toUpperCase() + kind.substring(1);
                  final jersey =
                      squad == null ? null : parseInt(squad['jerseyNumber']);

                  String pendingLabel(Map<String, dynamic> x) => parseStr(
                              x['scheduledDate']) !=
                          null
                      ? '${x['scheduledDate']}${parseStr(x['scheduledTime']) != null ? ' · ${formatTime12(x['scheduledTime'] as String)}' : ''}'
                      : 'Not scheduled';

                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.refresh(playerTournamentStatsProvider(key).future),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                      children: [
                        SpHeader(
                          title: 'Record in $kind',
                          subtitle: parseStr(event['title']),
                        ),
                        const SizedBox(height: 16),

                        // Who, which competition, and the headline numbers.
                        RecordHero(
                          family: family,
                          emoji: parseStr(cat['emoji']),
                          name: parseStr(player['displayName']) ?? 'Player',
                          avatarUrl: parseStr(player['avatarUrl']),
                          onPlayerTap: () => context.push('/players/$userId'),
                          eyebrow: [
                            kindTitle,
                            if (parseStr(cat['name']) != null)
                              parseStr(cat['name'])!,
                          ].join(' · '),
                          title: parseStr(event['title']) ?? 'Tournament',
                          meta: [
                            when.line,
                            if (when.viewerTime != null)
                              '${when.viewerTime} your time',
                            if (parseStr(event['locationName']) != null)
                              event['locationName'] as String,
                            if (parseStr(event['hostGroupName']) != null)
                              'hosted by ${event['hostGroupName']}',
                          ].join(' · '),
                          stats: statInt(record['games']) > 0
                              ? recordHeroStats(record, fields)
                              : const [],
                          pills: [
                            if (team != null)
                              recordHeroPill(
                                  '${parseStr(team['name']) ?? 'Team'}${jersey != null ? ' · #$jersey' : ''}',
                                  const Color(0x29F4781F),
                                  const Color(0xFFFFB57D),
                                  icon: Icons.shield_outlined),
                            if (squad != null && squad['isStarter'] == true)
                              recordHeroPill('Starting line-up',
                                  const Color(0x296EDC9E), recordMint,
                                  icon: Icons.check_circle_rounded),
                          ],
                        ),

                        // The tournament itself and the squad — both on purpose.
                        if (hostGroupId != null) ...[
                          const SizedBox(height: 12),
                          recordActions([
                            RecordAction(
                                label: 'Open $kind',
                                icon: Icons.north_east_rounded,
                                onTap: () => context.push(
                                    '/groups/$hostGroupId/tournaments/$eventId')),
                            if (team != null)
                              RecordAction(
                                  label: 'Squad',
                                  icon: Icons.groups_2_outlined,
                                  onTap: () => context.push(
                                      '/groups/$hostGroupId/tournaments/$eventId/teams/${team['id']}')),
                          ]),
                        ],

                        // Their place in the squad.
                        const SizedBox(height: 22),
                        const RecordSectionTitle('Squad place'),
                        const SizedBox(height: 10),
                        if (squad != null && team != null)
                          GlassCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Crest(
                                        logoUrl: parseStr(team['logoUrl']),
                                        kitPrimary:
                                            parseStr(team['kitPrimary']),
                                        kitSecondary:
                                            parseStr(team['kitSecondary']),
                                        label: parseStr(team['name']) ?? 'T',
                                        size: 46),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                                parseStr(team['name']) ??
                                                    'Team',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    color: p.ink,
                                                    fontSize: 15,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            if (parseStr(team['groupName']) !=
                                                null)
                                              Text(parseStr(team['groupName'])!,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      color: p.muted,
                                                      fontSize: 12)),
                                          ]),
                                    ),
                                    if (jersey != null)
                                      Container(
                                        width: 48,
                                        height: 48,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            color: p.surface2,
                                            borderRadius:
                                                BorderRadius.circular(16)),
                                        child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text('SHIRT',
                                                  style: TextStyle(
                                                      color: p.muted,
                                                      fontSize: 8.5,
                                                      letterSpacing: 0.6,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              Text('$jersey',
                                                  style: TextStyle(
                                                      color: p.ink,
                                                      fontSize: 17,
                                                      height: 1.1,
                                                      fontWeight:
                                                          FontWeight.w800)),
                                            ]),
                                      ),
                                  ]),
                                  const SizedBox(height: 12),
                                  Wrap(spacing: 6, runSpacing: 6, children: [
                                    _tag(
                                        p,
                                        _statusLabel(parseStr(squad['status'])),
                                        parseStr(squad['status']) ==
                                            'accepted'),
                                    if (squad['isStarter'] == true)
                                      _tag(p, 'Starter', true),
                                    if (parseDate(squad['acceptedAt']) != null)
                                      _tag(
                                          p,
                                          'Joined ${formatDayYear(squad['acceptedAt'])}'
                                          '${squad['joinedAfterKickoff'] == true ? ' · after kick-off' : ''}',
                                          false),
                                  ]),
                                ]),
                          )
                        else
                          RecordEmpty(
                            icon: Icons.groups_2_outlined,
                            title: 'Not in a squad',
                            body: "$first isn't in a squad for this $kind"
                                "${matches.isNotEmpty ? ', but appeared in its games.' : '.'}",
                          ),

                        // The tally.
                        const SizedBox(height: 14),
                        ScopeBlock(
                          title: "$first's record in this $kind",
                          family: family ?? SportFamily.generic,
                          collapseKey: 'tournament-record',
                          tally: record,
                          fields: fields,
                          accent: true,
                          empty: matches
                                  .any((x) => parseStr(x['status']) == 'live')
                              ? 'No completed games yet — one is live now.'
                              : 'No completed games yet.',
                        ),

                        // Match by match.
                        if (matches.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          RecordSectionTitle('Matches', count: matches.length),
                          const SizedBox(height: 10),
                          RecordList(children: [
                            for (final x in matches)
                              RecordMatchRow(
                                match: x,
                                fields: fields,
                                pendingLabel: pendingLabel(x),
                                opponentFallback: 'TBD',
                              ),
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

  static String _statusLabel(String? status) {
    final s = status ?? '';
    return switch (s) {
      'accepted' => 'In the squad',
      'pending' || 'invited' => 'Call-up pending',
      'declined' => 'Declined',
      'removed' => 'Removed',
      '' => 'Squad',
      _ => '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}',
    };
  }

  Widget _tag(AppPalette p, String label, bool positive) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: positive ? p.accentTint : p.surface2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                color: positive ? p.greenText : p.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700)),
      );
}
