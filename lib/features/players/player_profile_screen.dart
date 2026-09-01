import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Public scouting profile for a player (web /players/[id] twin): sports they
/// play, groups they belong to, leaderboard standing in each, recent posts.
final playerProfileProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, userId) async {
  try {
    final res =
        await ref.watch(dioProvider).get('/api/mobile/players/$userId');
    if (res.data is! Map) {
      throw ApiException('Player not found.', statusCode: 404);
    }
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    throw apiError(e, fallback: 'Could not load the player.');
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
  String get userId => widget.userId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final data = ref.watch(playerProfileProvider(userId));
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Player',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(playerProfileProvider(userId)),
        data: (m) {
          final profile = m['profile'] is Map
              ? Map<String, dynamic>.from(m['profile'] as Map)
              : const <String, dynamic>{};
          List<Map<String, dynamic>> section(String key) => m[key] is List
              ? [
                  for (final e in m[key] as List)
                    if (e is Map) Map<String, dynamic>.from(e)
                ]
              : const [];
          final sports = section('sports');
          final groups = section('groups');
          final standings = section('standings');
          final posts = section('posts');

          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(playerProfileProvider(userId).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // Header — avatar, identity, and the Sports / Standings icons.
                GlassCard(
                  child: Row(children: [
                    ClipOval(
                      child: Crest(
                          logoUrl: parseStr(profile['avatarUrl']),
                          label: parseStr(profile['displayName']) ?? 'P',
                          size: 72),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                parseStr(profile['displayName']) ??
                                    'Player',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: p.ink,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800)),
                            if (parseStr(profile['username']) != null)
                              Text('@${parseStr(profile['username'])}',
                                  style: TextStyle(
                                      color: p.muted, fontSize: 13)),
                            const SizedBox(height: 8),
                            Row(children: [
                              _iconChip(
                                p,
                                Icons.emoji_events_outlined,
                                'Sports ${sports.length}',
                                p.amber,
                                () => _openSheet(
                                    'Sports',
                                    Icons.emoji_events_outlined,
                                    p.amber,
                                    sports.isEmpty
                                        ? [
                                            _emptyLine(p,
                                                'No sports on their profile yet.')
                                          ]
                                        : [
                                            for (final s in sports)
                                              _sportRow(p, s)
                                          ]),
                              ),
                              const SizedBox(width: 8),
                              _iconChip(
                                p,
                                Icons.leaderboard_outlined,
                                'Standings ${standings.length}',
                                p.accent,
                                () => _openSheet(
                                    'Leaderboard standings',
                                    Icons.leaderboard_outlined,
                                    p.accent,
                                    standings.isEmpty
                                        ? [
                                            _emptyLine(
                                                p, 'No ranked games yet.')
                                          ]
                                        : [
                                            for (final st in standings)
                                              _standingRow(context, p, st)
                                          ]),
                              ),
                            ]),
                          ]),
                    ),
                  ]),
                ),

                // Groups / Posts tabs.
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: p.line)),
                  ),
                  child: Row(children: [
                    _tabBtn(p, 0, Icons.groups_outlined,
                        'Groups (${groups.length})'),
                    _tabBtn(p, 1, Icons.chat_bubble_outline_rounded,
                        'Posts (${posts.length})'),
                  ]),
                ),
                const SizedBox(height: 12),
                if (_tab == 0) ...[
                  if (groups.isEmpty)
                    GlassCard(
                      child: Center(
                        child: Text('Not a member of any group yet.',
                            style: TextStyle(
                                color: p.muted, fontSize: 13)),
                      ),
                    )
                  else
                    for (final g in groups) _groupRow(context, p, g),
                ] else ...[
                  if (posts.isEmpty)
                    GlassCard(
                      child: Center(
                        child: Text('No posts yet.',
                            style: TextStyle(
                                color: p.muted, fontSize: 13)),
                      ),
                    )
                  else
                    for (final post in posts) _postRow(p, post),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _iconChip(AppPalette p, IconData icon, String label, Color tone,
          VoidCallback onTap) =>
      Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: p.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 15, color: tone),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );

  Widget _tabBtn(AppPalette p, int i, IconData icon, String label) {
    final active = _tab == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? p.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: active ? p.accent : p.muted),
              const SizedBox(width: 5),
              Text(label.toUpperCase(),
                  style: TextStyle(
                      color: active ? p.accent : p.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyLine(AppPalette p, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text,
            style: TextStyle(color: p.muted, fontSize: 12.5)),
      );

  void _openSheet(
      String title, IconData icon, Color tone, List<Widget> children) {
    final p = context.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(icon, size: 17, color: tone),
                    const SizedBox(width: 7),
                    Text(title,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 12),
                  ...children,
                ]),
          ),
        ),
      ),
    );
  }

  Widget _sportRow(AppPalette p, Map<String, dynamic> s) {
    final cat = s['category'] is Map
        ? Map<String, dynamic>.from(s['category'] as Map)
        : null;
    final positions = parseStrList(s['preferredPositions']);
    final foot = parseStr(s['strongFoot']);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            '${cat != null ? parseStr(cat['emoji']) ?? '🏅' : '🏅'} ${cat != null ? parseStr(cat['name']) ?? 'Sport' : 'Sport'}',
            style: TextStyle(
                color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
        if (positions.isNotEmpty || foot != null) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final pos in positions) SpBadge(pos),
            if (foot != null) SpBadge('$foot footed'),
          ]),
        ],
      ]),
    );
  }

  Widget _standingRow(
      BuildContext context, AppPalette p, Map<String, dynamic> st) {
    final tallies = st['tallies'] is Map
        ? Map<String, dynamic>.from(st['tallies'] as Map)
        : const <String, dynamic>{};
    final tallyLine = [
      for (final e in tallies.entries)
        if ((parseInt(e.value) ?? 0) > 0) '${parseInt(e.value)} ${e.key}'
    ].take(4).join(' · ');
    final games = parseInt(st['games']) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context
              .push('/groups/${parseStr(st['groupId'])}/leaderboard'),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.line),
            ),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.accent.withAlpha(26),
                  shape: BoxShape.circle,
                ),
                child: Text('#${parseInt(st['rank']) ?? '—'}',
                    style: TextStyle(
                        color: p.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(parseStr(st['groupName']) ?? 'Group',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700)),
                      Text(
                          '#${parseInt(st['rank'])} of ${parseInt(st['of'])} · ${parseInt(st['points'])} pts · ${parseInt(st['wins'])}W ${parseInt(st['draws'])}D ${parseInt(st['losses'])}L · $games game${games == 1 ? '' : 's'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(color: p.muted, fontSize: 11)),
                      if (tallyLine.isNotEmpty)
                        Text(tallyLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.muted, fontSize: 11)),
                    ]),
              ),
              Icon(Icons.chevron_right, size: 18, color: p.muted),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _groupRow(BuildContext context, AppPalette p, Map<String, dynamic> g) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/groups/${parseStr(g['id'])}'),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.line),
            ),
            child: Row(children: [
              ClipOval(
                child: Crest(
                    logoUrl: parseStr(g['imageUrl']),
                    label: parseStr(g['name']) ?? 'G',
                    size: 32),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(parseStr(g['name']) ?? 'Group',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
              ),
              SpBadge(parseStr(g['role']) ?? 'member'),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: p.muted),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _postRow(AppPalette p, Map<String, dynamic> post) {
    final grp = post['group'] is Map
        ? Map<String, dynamic>.from(post['group'] as Map)
        : null;
    final img = parseStr(post['contentType']) == 'image'
        ? parseStr(post['contentUrl'])
        : null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (img != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(img,
                width: double.infinity,
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
          const SizedBox(height: 8),
        ],
        if (parseStr(post['caption']) != null)
          Text(parseStr(post['caption'])!,
              style: TextStyle(color: p.ink, fontSize: 13.5)),
        const SizedBox(height: 4),
        Text(
            'in ${grp != null ? parseStr(grp['name']) ?? 'a group' : 'a group'} · ${timeAgo(post['createdAt'])}',
            style: TextStyle(color: p.muted, fontSize: 11)),
      ]),
    );
  }
}
