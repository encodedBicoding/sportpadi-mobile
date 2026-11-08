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
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

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
      throw ApiException(l10n.profile_theServerReturnedAnEmptyRecord,
          statusCode: 502);
    }
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    throw apiError(e, fallback: l10n.profile_couldNotLoadTheirRecord);
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

    // A pull refetches the record and keeps the spinner until it's back.
    Future<void> refresh() {
      ref.invalidate(playerTournamentStatsProvider(key));
      return settleAll([ref.read(playerTournamentStatsProvider(key).future)]);
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: isPrivateRecordError(data.error)
            ? RefreshIndicator(
                onRefresh: refresh,
                child: _alwaysPullable(
                    context, PlayerPrivateView(title: context.l10n.profile_record)),
              )
            : _pullableUnlessData(
                data,
                refresh,
                AsyncView(
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
                  final first = (parseStr(player['displayName']) ?? context.l10n.profile_player)
                      .split(' ')
                      .first;
                  final mode = parseStr(event['mode']);
                  final kind = mode == 'league'
                      ? context.l10n.profile_kindLeagueLower
                      : mode == 'multi_team'
                          ? context.l10n.profile_tournament3
                          : context.l10n.profile_kindFriendlyLower;
                  final hostGroupId = parseStr(event['hostGroupId']);
                  final when = formatEventTimeJson(event);
                  final cat = mapOf(event['category']);
                  // The tournament's sport picks the design (artwork + stats block).
                  final family = cat.isEmpty ? null : familyOf(cat);

                  final kindTitle = mode == 'league'
                      ? context.l10n.profile_kindLeague
                      : mode == 'multi_team'
                          ? context.l10n.profile_tournament
                          : context.l10n.profile_kindFriendly;
                  final jersey =
                      squad == null ? null : parseInt(squad['jerseyNumber']);

                  String pendingLabel(Map<String, dynamic> x) => parseStr(
                              x['scheduledDate']) !=
                          null
                      ? '${x['scheduledDate']}${parseStr(x['scheduledTime']) != null ? ' · ${formatTime12(x['scheduledTime'] as String)}' : ''}'
                      : context.l10n.profile_notScheduled;

                  return RefreshIndicator(
                    onRefresh: refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                      children: [
                        SpHeader(
                          title: context.l10n.profile_recordIn2(kind),
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
                          title: parseStr(event['title']) ?? context.l10n.profile_tournament,
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
                              recordHeroPill(context.l10n.profile_startingLineUp,
                                  const Color(0x296EDC9E), recordMint,
                                  icon: Icons.check_circle_rounded),
                          ],
                        ),

                        // The tournament itself and the squad — both on purpose.
                        if (hostGroupId != null) ...[
                          const SizedBox(height: 12),
                          recordActions([
                            RecordAction(
                                label: context.l10n.profile_open4(kind),
                                icon: Icons.north_east_rounded,
                                onTap: () => context.push(
                                    '/groups/$hostGroupId/tournaments/$eventId')),
                            if (team != null)
                              RecordAction(
                                  label: context.l10n.profile_squad,
                                  icon: Icons.groups_2_outlined,
                                  onTap: () => context.push(
                                      '/groups/$hostGroupId/tournaments/$eventId/teams/${team['id']}')),
                          ]),
                        ],

                        // Their place in the squad.
                        const SizedBox(height: 22),
                        RecordSectionTitle(context.l10n.profile_squadPlace),
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
                                                    context.l10n.profile_team,
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
                                              Text(context.l10n.profile_shirt,
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
                                      _tag(p, context.l10n.profile_starter, true),
                                    if (parseDate(squad['acceptedAt']) != null)
                                      _tag(
                                          p,
                                          context.l10n.profile_joined2(formatDayYear(squad['acceptedAt']), (squad['joinedAfterKickoff'] == true ? context.l10n.profile_afterKickOff2 : '')),
                                          false),
                                  ]),
                                ]),
                          )
                        else
                          RecordEmpty(
                            icon: Icons.groups_2_outlined,
                            title: context.l10n.profile_notInASquad,
                            body: context.l10n.profile_isntInASquadFor2(first, kind, matches.isNotEmpty ? context.l10n.profile_butAppearedInItsGames : '.'),
                          ),

                        // The tally.
                        const SizedBox(height: 14),
                        ScopeBlock(
                          title: context.l10n.profile_sRecordInThis2(first, kind),
                          family: family ?? SportFamily.generic,
                          collapseKey: 'tournament-record',
                          tally: record,
                          fields: fields,
                          accent: true,
                          empty: matches
                                  .any((x) => parseStr(x['status']) == 'live')
                              ? context.l10n.profile_noCompletedGamesYetOne
                              : context.l10n.profile_noCompletedGamesYet,
                        ),

                        // Match by match.
                        if (matches.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          RecordSectionTitle(context.l10n.profile_matches, count: matches.length),
                          const SizedBox(height: 10),
                          RecordList(children: [
                            for (final x in matches)
                              RecordMatchRow(
                                match: x,
                                fields: fields,
                                pendingLabel: pendingLabel(x),
                                opponentFallback: context.l10n.profile_tbd,
                              ),
                          ]),
                        ],
                      ],
                    ),
                  );
                },
              ),
              ),
      ),
    );
  }

  static String _statusLabel(String? status) {
    final s = status ?? '';
    return switch (s) {
      'accepted' => l10n.profile_inTheSquad,
      'pending' || 'invited' => l10n.profile_callUpPending,
      'declined' => l10n.profile_declined,
      'removed' => l10n.profile_removed2,
      '' => l10n.profile_squad,
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

/// Loading / error aren't scrollable on their own, so they get a pullable
/// wrapper; once the data shows, its own RefreshIndicator takes over.
Widget _pullableUnlessData(
        AsyncValue<Object?> v, Future<void> Function() onRefresh, Widget child) =>
    v.hasValue && !v.hasError
        ? child
        : RefreshIndicator(
            onRefresh: onRefresh, child: PullableState(child: child));

/// A scroll view that may be too short to scroll can still start a pull.
Widget _alwaysPullable(BuildContext context, Widget child) =>
    ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        physics: AlwaysScrollableScrollPhysics(
            parent: ScrollConfiguration.of(context).getScrollPhysics(context)),
      ),
      child: child,
    );
