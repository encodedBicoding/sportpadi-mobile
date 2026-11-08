import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/aka_card.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// One player's record inside ONE group, per sport.
///
/// Tapping a group on a public profile used to open the group itself, which
/// answers a different question — someone scouting a player wants to know how
/// THAT player performs there. The group stays one tap away as a secondary
/// link.
final playerGroupStatsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String userId, String groupId})>(
        (ref, key) async {
  try {
    final res = await ref
        .watch(dioProvider)
        .get('/api/mobile/players/${key.userId}/groups/${key.groupId}');
    if (res.data is! Map) {
      throw ApiException(l10n.profile_nothingToShowHere, statusCode: 404);
    }
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    throw apiError(e, fallback: l10n.profile_couldNotLoadTheirRecord);
  }
});

class PlayerGroupStatsScreen extends ConsumerStatefulWidget {
  const PlayerGroupStatsScreen({
    super.key,
    required this.userId,
    required this.groupId,
  });
  final String userId;
  final String groupId;

  @override
  ConsumerState<PlayerGroupStatsScreen> createState() =>
      _PlayerGroupStatsScreenState();
}

class _PlayerGroupStatsScreenState
    extends ConsumerState<PlayerGroupStatsScreen> {
  String? _catId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final key = (userId: widget.userId, groupId: widget.groupId);
    final data = ref.watch(playerGroupStatsProvider(key));

    // A pull refetches the record and keeps the spinner until it's back.
    Future<void> refresh() {
      ref.invalidate(playerGroupStatsProvider(key));
      return settleAll([ref.read(playerGroupStatsProvider(key).future)]);
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: isPrivateRecordError(data.error)
            ? RefreshIndicator(
                onRefresh: refresh,
                child: _alwaysPullable(context,
                    PlayerPrivateView(title: context.l10n.profile_recordInGroup)),
              )
            : _pullableUnlessData(
                data,
                refresh,
                AsyncView(
                value: data,
                onRetry: () => ref.invalidate(playerGroupStatsProvider(key)),
                data: (m) {
                  final group = mapOf(m['group']);
                  final player = mapOf(m['player']);
                  // The name this group knows them by, when they've set one — and
                  // whether the person looking is the player (only they can set it).
                  final aka = parseStr(m['aka']);
                  final isMe = m['isMe'] == true;
                  final shownName =
                      aka ?? parseStr(player['displayName']) ?? 'Player';
                  final cats = listOf(m['categories']);
                  final tournaments = listOf(m['tournaments']);
                  // Soccer by default, same rule as the profile.
                  final selected = _catId ?? defaultCategoryId(cats);
                  final cat = cats.isEmpty
                      ? null
                      : cats.firstWhere(
                          (c) => parseStr(c['categoryId']) == selected,
                          orElse: () => cats.first,
                        );
                  final catTournaments = cat == null
                      ? tournaments
                      : [
                          for (final t in tournaments)
                            if (parseStr(t['categoryId']) ==
                                parseStr(cat['categoryId']))
                              t
                        ];

                  final groupName = parseStr(group['name']) ?? 'Group';
                  final local = cat == null
                      ? const <String, dynamic>{}
                      : mapOf(cat['local']);
                  final fields = cat == null
                      ? const <Map<String, dynamic>>[]
                      : listOf(cat['fields']);
                  final rank = cat == null
                      ? const <String, dynamic>{}
                      : mapOf(cat['rank']);
                  // The chosen sport's design (artwork + stats blocks).
                  final family = cat == null ? null : familyOf(cat);

                  return RefreshIndicator(
                    onRefresh: refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                      children: [
                        SpHeader(title: context.l10n.profile_recordInGroup, subtitle: groupName),
                        const SizedBox(height: 16),

                        // Who, which group, and the local-games headline for the
                        // chosen sport. Local only: tournaments get their own card.
                        RecordHero(
                          family: family,
                          emoji: parseStr(cat?['emoji']),
                          name: shownName,
                          avatarUrl: parseStr(player['avatarUrl']),
                          nameSub: aka != null
                              ? parseStr(player['displayName'])
                              : null,
                          onPlayerTap: () =>
                              context.push('/players/${widget.userId}'),
                          eyebrow: cat == null
                              ? context.l10n.profile_groupRecord
                              : context.l10n.profile_localGames2(parseStr(cat['name']) ?? 'Sport'),
                          title: groupName,
                          stats: statInt(local['games']) > 0
                              ? recordHeroStats(local, fields)
                              : const [],
                          pills: [
                            if (rank.isNotEmpty)
                              recordHeroPill(
                                  '#${statInt(rank['rank'])} of ${statInt(rank['of'])} on the board',
                                  const Color(0x29F4781F),
                                  const Color(0xFFFFB57D),
                                  icon: Icons.leaderboard_rounded),
                            if (statInt(local['games']) > 0)
                              recordHeroPill(
                                  '${statInt(local['games'])} game${statInt(local['games']) == 1 ? '' : 's'} · ${statInt(local['winRate'])}% wins',
                                  p.onHero.withAlpha(28),
                                  p.onHero),
                          ],
                        ),
                        const SizedBox(height: 12),
                        recordActions([
                          RecordAction(
                              label: context.l10n.profile_openGroup,
                              icon: Icons.north_east_rounded,
                              onTap: () =>
                                  context.push('/groups/${widget.groupId}')),
                          if (rank.isNotEmpty)
                            RecordAction(
                                label: context.l10n.profile_leaderboard,
                                icon: Icons.leaderboard_outlined,
                                onTap: () => context.push(
                                    '/groups/${widget.groupId}/leaderboard')),
                        ]),
                        if (isMe) ...[
                          const SizedBox(height: 14),
                          AkaCard(
                            groupId: widget.groupId,
                            groupName: parseStr(group['name']) ?? 'this group',
                            aka: aka,
                            onSaved: () =>
                                ref.invalidate(playerGroupStatsProvider(key)),
                          ),
                        ],
                        if (cats.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          CategoryControl(
                            categories: cats,
                            selectedId: parseStr(cat?['categoryId']),
                            onSelect: (id) => setState(() => _catId = id),
                            playerName: shownName,
                          ),
                        ],
                        if (cat == null) ...[
                          const SizedBox(height: 14),
                          RecordEmpty(
                            icon: Icons.emoji_events_outlined,
                            title: context.l10n.profile_noCompletedGamesWithThis,
                            body:
                                context.l10n.profile_areAMemberButHavent(parseStr(player['displayName']) ?? 'They'),
                          ),
                        ] else ...[
                          const SizedBox(height: 14),
                          if (nothingOnRecord(cat))
                            NothingOnRecord(
                                sportName:
                                    parseStr(cat['name']) ?? 'this sport')
                          else ...[
                            SportSetup(category: cat),
                            const SizedBox(height: 12),
                            ScopeBlock(
                              title: context.l10n.profile_localGroupGames3,
                              family: family ?? SportFamily.generic,
                              tally: local,
                              fields: fields,
                              empty:
                                  context.l10n.profile_noCompletedLocalGamesIn,
                              rank: rank,
                            ),
                            const SizedBox(height: 12),
                            ScopeBlock(
                              title: context.l10n.profile_tournaments,
                              family: family ?? SportFamily.generic,
                              tally: mapOf(cat['tournament']),
                              fields: fields,
                              accent: true,
                              empty: context.l10n.profile_noTournamentGamesInThis,
                            ),
                          ],
                          if (catTournaments.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            TournamentList(
                                rows: catTournaments,
                                title: context.l10n.profile_tournamentsWithThisGroup,
                                playerId: widget.userId),
                          ],
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
