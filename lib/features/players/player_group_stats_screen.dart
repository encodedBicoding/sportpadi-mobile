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
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

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
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Record in group',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: AsyncView(
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

          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(playerGroupStatsProvider(key).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                GlassCard(
                  child: Row(children: [
                    ClipOval(
                      child: Crest(
                          logoUrl: parseStr(player['avatarUrl']),
                          label: parseStr(player['displayName']) ?? 'P',
                          size: 40),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                '$shownName at '
                                '${parseStr(group['name']) ?? 'group'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: p.ink,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800)),
                            if (aka != null)
                              Text(parseStr(player['displayName']) ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(color: p.muted, fontSize: 11.5)),
                            const SizedBox(height: 2),
                            InkWell(
                              onTap: () =>
                                  context.push('/groups/${widget.groupId}'),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text('Open group',
                                    style: TextStyle(
                                        color: p.accent,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700)),
                                Icon(Icons.north_east_rounded,
                                    size: 12, color: p.accent),
                              ]),
                            ),
                          ]),
                    ),
                  ]),
                ),
                if (isMe) ...[
                  const SizedBox(height: 12),
                  AkaCard(
                    groupId: widget.groupId,
                    groupName: parseStr(group['name']) ?? 'this group',
                    aka: aka,
                    onSaved: () =>
                        ref.invalidate(playerGroupStatsProvider(key)),
                  ),
                ],
                if (cats.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  CategoryControl(
                    categories: cats,
                    selectedId: parseStr(cat?['categoryId']),
                    onSelect: (id) => setState(() => _catId = id),
                    playerName: shownName,
                  ),
                ],
                if (cat == null) ...[
                  const SizedBox(height: 12),
                  GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      Icon(Icons.emoji_events_outlined,
                          size: 30, color: p.muted),
                      const SizedBox(height: 8),
                      Text('No completed games with this group',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        "${parseStr(player['displayName']) ?? 'They'} are a member, but haven't finished a game here yet.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: p.muted, fontSize: 12, height: 1.35),
                      ),
                    ]),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  if (nothingOnRecord(cat))
                    NothingOnRecord(sportName: parseStr(cat['name']) ?? 'this sport')
                  else ...[
                  SportSetup(category: cat),
                  const SizedBox(height: 12),
                  ScopeBlock(
                    title:
                        '${parseStr(cat['emoji']) ?? ''} ${parseStr(cat['name']) ?? 'Sport'} · local group games',
                    tally: mapOf(cat['local']),
                    fields: listOf(cat['fields']),
                    empty: 'No completed local games in this sport yet.',
                    rank: mapOf(cat['rank']),
                  ),
                  const SizedBox(height: 12),
                  ScopeBlock(
                    title:
                        '${parseStr(cat['emoji']) ?? ''} ${parseStr(cat['name']) ?? 'Sport'} · tournaments',
                    tally: mapOf(cat['tournament']),
                    fields: listOf(cat['fields']),
                    accent: true,
                    empty: 'No tournament games in this sport yet.',
                  ),
                  ],
                  if (mapOf(cat['rank']).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => context
                          .push('/groups/${widget.groupId}/leaderboard'),
                      child: Text(
                          'See the full ${parseStr(cat['name']) ?? ''} leaderboard →',
                          style: TextStyle(
                              color: p.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                  if (catTournaments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    TournamentList(
                        rows: catTournaments,
                        title: 'TOURNAMENTS WITH THIS GROUP',
                        playerId: widget.userId),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
