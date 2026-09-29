import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/aka_card.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';

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
      throw ApiException('Nothing to show here.', statusCode: 404);
    }
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    throw apiError(e, fallback: 'Could not load their record.');
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

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: AsyncView(
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
          final local = cat == null ? const <String, dynamic>{} : mapOf(cat['local']);
          final fields = cat == null ? const <Map<String, dynamic>>[] : listOf(cat['fields']);
          final rank = cat == null ? const <String, dynamic>{} : mapOf(cat['rank']);

          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(playerGroupStatsProvider(key).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              children: [
                SpHeader(title: 'Record in group', subtitle: groupName),
                const SizedBox(height: 16),

                // Who, which group, and the local-games headline for the
                // chosen sport. Local only: tournaments get their own card.
                RecordHero(
                  name: shownName,
                  avatarUrl: parseStr(player['avatarUrl']),
                  nameSub: aka != null ? parseStr(player['displayName']) : null,
                  onPlayerTap: () => context.push('/players/${widget.userId}'),
                  eyebrow: cat == null
                      ? 'Group record'
                      : '${parseStr(cat['name']) ?? 'Sport'} · local games',
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
                      label: 'Open group',
                      icon: Icons.north_east_rounded,
                      onTap: () => context.push('/groups/${widget.groupId}')),
                  if (rank.isNotEmpty)
                    RecordAction(
                        label: 'Leaderboard',
                        icon: Icons.leaderboard_outlined,
                        onTap: () => context
                            .push('/groups/${widget.groupId}/leaderboard')),
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
                    title: 'No completed games with this group',
                    body:
                        "${parseStr(player['displayName']) ?? 'They'} are a member, but haven't finished a game here yet.",
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  if (nothingOnRecord(cat))
                    NothingOnRecord(
                        sportName: parseStr(cat['name']) ?? 'this sport')
                  else ...[
                    SportSetup(category: cat),
                    const SizedBox(height: 12),
                    ScopeBlock(
                      title: 'Local group games',
                      tally: local,
                      fields: fields,
                      empty: 'No completed local games in this sport yet.',
                      rank: rank,
                    ),
                    const SizedBox(height: 12),
                    ScopeBlock(
                      title: 'Tournaments',
                      tally: mapOf(cat['tournament']),
                      fields: fields,
                      accent: true,
                      empty: 'No tournament games in this sport yet.',
                    ),
                  ],
                  if (catTournaments.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    TournamentList(
                        rows: catTournaments,
                        title: 'Tournaments with this group',
                        playerId: widget.userId),
                  ],
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
