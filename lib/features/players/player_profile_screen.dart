import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart';

/// Public player profile — the scout's view (web /players/[id] twin).
///
/// The question this page exists to answer is "how well is this player doing in
/// this sport", so the sport is the organising idea: pick one, and everything
/// below is that sport's record. Sports and standings used to live in bottom
/// sheets, which meant the one thing you came for took two taps — and the
/// standings shown were per-group, so tournament form was invisible entirely.
///
/// Stats are only comparable inside a sport; nothing is summed across them.

final playerProfileProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, userId) async {
  try {
    final res = await ref.watch(dioProvider).get('/api/mobile/players/$userId');
    if (res.data is! Map) {
      throw ApiException('Player not found.', statusCode: 404);
    }
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    throw apiError(e, fallback: 'Could not load the player.');
  }
});

/// The heavier half — per-category record and tournaments. Loaded separately so
/// identity paints straight away.
final playerStatsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, userId) async {
  try {
    final res =
        await ref.watch(dioProvider).get('/api/mobile/players/$userId/stats');
    return res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{}; // numbers are a bonus, never the whole page
  }
});


class PlayerProfileScreen extends ConsumerStatefulWidget {
  const PlayerProfileScreen({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<PlayerProfileScreen> createState() =>
      _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends ConsumerState<PlayerProfileScreen> {
  int _tab = 0; // 0 groups, 1 posts
  String? _catId;

  String get userId => widget.userId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final data = ref.watch(playerProfileProvider(userId));
    final stats = ref.watch(playerStatsProvider(userId)).valueOrNull;

    final categories = listOf(stats?['categories']);
    final tournaments = listOf(stats?['tournaments']);
    // The sport is a PAGE-LEVEL setting, not a widget's: once chosen, the
    // record, the tournaments tab and the groups tab all narrow to it.
    final selected = _catId ?? defaultCategoryId(categories);
    final cat = categories.isEmpty
        ? null
        : categories.firstWhere(
            (c) => parseStr(c['categoryId']) == selected,
            orElse: () => categories.first,
          );

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Player',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: AsyncView(
        value: data,
        onRetry: () {
          ref.invalidate(playerProfileProvider(userId));
          ref.invalidate(playerStatsProvider(userId));
        },
        data: (m) {
          final profile = mapOf(m['profile']);
          final allGroups = listOf(m['groups']);
          final posts = listOf(m['posts']);
          // Everything below the picker is scoped to the chosen sport.
          final catTournaments = cat == null
              ? tournaments
              : [
                  for (final t in tournaments)
                    if (parseStr(t['categoryId']) ==
                        parseStr(cat['categoryId']))
                      t
                ];
          final sportGroupIds = <String>{
            for (final g in listOf(cat?['groups']))
              if (parseStr(g['id']) != null) parseStr(g['id'])!
          };
          // Groups they've actually played this sport in; when none, fall back
          // to every group rather than showing an empty tab.
          final groups = sportGroupIds.isEmpty
              ? allGroups
              : [
                  for (final g in allGroups)
                    if (sportGroupIds.contains(parseStr(g['id']))) g
                ];
          final groupsAreFiltered = sportGroupIds.isNotEmpty;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(playerStatsProvider(userId));
              return ref.refresh(playerProfileProvider(userId).future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _identity(p, profile),
                if (categories.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  CategoryControl(
                    categories: categories,
                    selectedId: parseStr(cat?['categoryId']),
                    onSelect: (id) => setState(() => _catId = id),
                    playerName: parseStr(profile['displayName']) ?? 'Player',
                  ),
                ],
                if (cat != null) ...[
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
                ] else if (stats != null) ...[
                  const SizedBox(height: 12),
                  GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(children: [
                      Icon(Icons.emoji_events_outlined, size: 30, color: p.muted),
                      const SizedBox(height: 8),
                      Text('No completed games yet',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        "Their record appears here once they've played a game that finished.",
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: p.muted, fontSize: 12, height: 1.35),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  _tabBtn(p, 0, Icons.groups_outlined, 'Groups', groups.length),
                  _tabBtn(p, 1, Icons.emoji_events_outlined, 'Tournaments',
                      catTournaments.length),
                  _tabBtn(p, 2, Icons.photo_library_outlined, 'Posts',
                      posts.length),
                ]),
                const SizedBox(height: 10),
                if (_tab == 0)
                  ..._groups(p, groups,
                      note: groupsAreFiltered && cat != null
                          ? 'Groups they play ${parseStr(cat['name']) ?? 'this sport'} in.'
                          : null)
                else if (_tab == 1)
                  ..._tournamentsTab(p, catTournaments,
                      sport: parseStr(cat?['name']))
                else
                  ..._posts(p, posts),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── header ────────────────────────────────────────────────────────────

  Widget _identity(AppPalette p, Map<String, dynamic> profile) {
    return GlassCard(
      child: Row(children: [
        // Earned avatar frame (gamification status perk).
        FramedAvatar(
          userId: widget.userId,
          child: ClipOval(
            child: Crest(
                logoUrl: parseStr(profile['avatarUrl']),
                label: parseStr(profile['displayName']) ?? 'P',
                size: 64),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(parseStr(profile['displayName']) ?? 'Player',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
              if (parseStr(profile['username']) != null)
                Text('@${profile['username']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 13)),
              // Gamification identity: level (always public), streak (if
              // the player made it public).
              Builder(builder: (_) {
                final id = ref.watch(identityProvider(widget.userId)).valueOrNull;
                if (id == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: LevelBadge(level: id.level, title: id.title, streak: id.weeklyStreak),
                );
              }),
              // Positions / strong foot are per-sport: they live in the
              // sport's own profile card, not up here as one fixed fact.
            ],
          ),
        ),
      ]),
    );
  }

  // ── groups / posts ────────────────────────────────────────────────────

  Widget _tabBtn(AppPalette p, int i, IconData icon, String label, int count) {
    final active = _tab == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: active ? p.accent : Colors.transparent, width: 2),
            ),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 15, color: active ? p.accent : p.muted),
            const SizedBox(width: 5),
            Flexible(
              child: Text(label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: active ? p.accent : p.muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4)),
            ),
            if (count > 0)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Text('$count',
                    style: TextStyle(color: p.muted, fontSize: 10)),
              ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _groups(AppPalette p, List<Map<String, dynamic>> groups,
      {String? note}) {
    if (groups.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text('Not in any groups yet.',
                style: TextStyle(color: p.muted, fontSize: 12.5)),
          ),
        ),
      ];
    }
    return [
      if (note != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(note, style: TextStyle(color: p.muted, fontSize: 11)),
        ),
      for (final g in groups)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          // Opens THIS PLAYER's record in that group — a scout tapping a
          // group wants their numbers there, not the group itself. The group
          // stays one tap away, as the secondary chip.
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.line),
            ),
            child: Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () =>
                      context.push('/players/$userId/groups/${g['id']}'),
                  child: Row(children: [
                    ClipOval(
                      child: Crest(
                          logoUrl: parseStr(g['imageUrl']),
                          label: parseStr(g['name']) ?? 'G',
                          size: 32),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(parseStr(g['name']) ?? 'Group',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.ink,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                              ),
                              if (g['verificationBadge'] == true)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Icon(Icons.verified_rounded,
                                      size: 14, color: p.accent),
                                ),
                            ]),
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.bar_chart_rounded,
                                  size: 12, color: p.muted),
                              const SizedBox(width: 3),
                              Text('See their record here',
                                  style: TextStyle(
                                      color: p.muted, fontSize: 11)),
                            ]),
                          ]),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: p.muted),
                  ]),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => context.push('/groups/${g['id']}'),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: p.line),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Group',
                        style: TextStyle(
                            color: p.muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700)),
                    Icon(Icons.north_east_rounded, size: 11, color: p.muted),
                  ]),
                ),
              ),
            ]),
          ),
        ),
    ];
  }

  List<Widget> _tournamentsTab(AppPalette p, List<Map<String, dynamic>> rows,
      {String? sport}) {
    if (rows.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text(
                sport != null ? 'No $sport tournaments yet.' : 'No tournaments yet.',
                style: TextStyle(color: p.muted, fontSize: 12.5)),
          ),
        ),
      ];
    }
    return [TournamentList(rows: rows, playerId: userId)];
  }

  List<Widget> _posts(AppPalette p, List<Map<String, dynamic>> posts) {
    if (posts.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text('No posts yet.',
                style: TextStyle(color: p.muted, fontSize: 12.5)),
          ),
        ),
      ];
    }
    return [
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        children: [
          for (final post in posts)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: parseStr(post['contentUrl']) != null &&
                      parseStr(post['contentType']) == 'image'
                  ? Image.network(post['contentUrl'] as String,
                      fit: BoxFit.cover)
                  : Container(
                      color: p.surface,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(6),
                      child: Text(parseStr(post['caption']) ?? 'Post',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.muted, fontSize: 10.5)),
                    ),
            ),
        ],
      ),
    ];
  }
}
