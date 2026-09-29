import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/verified_badge.dart';

/// Public player profile — the scout's view (web /players/[id] twin).
///
/// The question this page exists to answer is "how well is this player doing in
/// this sport", so the sport is the organising idea: pick one, and everything
/// below is that sport's record. Sports and standings used to live in bottom
/// sheets, which meant the one thing you came for took two taps — and the
/// standings shown were per-group, so tournament form was invisible entirely.
///
/// Stats are only comparable inside a sport; nothing is summed across them.
///
/// 2026 design: dark pitch cover (back round button), identity card with the
/// avatar on its edge (earned frame, @username copy pill, level badge,
/// Sports / Groups / Tournaments tiles), the sport's record, then pill tabs.

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
  int _tab = 0; // 0 groups, 1 tournaments, 2 posts
  String? _catId;

  String get userId => widget.userId;

  void _back() => context.canPop() ? context.pop() : context.go('/home');

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
      body: Stack(children: [
        AsyncView(
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
            // Groups they've actually played this sport in; when none, fall
            // back to every group rather than showing an empty tab.
            final groups = sportGroupIds.isEmpty
                ? allGroups
                : [
                    for (final g in allGroups)
                      if (sportGroupIds.contains(parseStr(g['id']))) g
                  ];
            final groupsAreFiltered = sportGroupIds.isNotEmpty;
            final sportName = parseStr(cat?['name']);

            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(playerStatsProvider(userId));
                return ref.refresh(playerProfileProvider(userId).future);
              },
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _Hero(
                    userId: userId,
                    profile: profile,
                    sports: categories.length,
                    groups: allGroups.length,
                    tournaments: tournaments.length,
                    statsLoaded: stats != null,
                    onBack: _back,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 36),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SpSectionTitle(sportName == null
                            ? 'Record'
                            : '${parseStr(cat?['emoji']) ?? ''} $sportName record'
                                .trim()),
                        const SizedBox(height: 10),
                        if (categories.isNotEmpty) ...[
                          CategoryControl(
                            categories: categories,
                            selectedId: parseStr(cat?['categoryId']),
                            onSelect: (id) => setState(() => _catId = id),
                            playerName:
                                parseStr(profile['displayName']) ?? 'Player',
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (cat != null) ...[
                          if (nothingOnRecord(cat))
                            NothingOnRecord(
                                sportName: sportName ?? 'this sport')
                          else ...[
                            SportSetup(category: cat),
                            const SizedBox(height: 12),
                            ScopeBlock(
                              title:
                                  '${parseStr(cat['emoji']) ?? ''} ${sportName ?? 'Sport'} · local group games',
                              tally: mapOf(cat['local']),
                              fields: listOf(cat['fields']),
                              empty:
                                  'No completed local games in this sport yet.',
                            ),
                            const SizedBox(height: 12),
                            ScopeBlock(
                              title:
                                  '${parseStr(cat['emoji']) ?? ''} ${sportName ?? 'Sport'} · tournaments',
                              tally: mapOf(cat['tournament']),
                              fields: listOf(cat['fields']),
                              accent: true,
                              empty: 'No tournament games in this sport yet.',
                            ),
                          ],
                        ] else if (stats != null)
                          const _Empty(
                            icon: Icons.emoji_events_outlined,
                            title: 'No completed games yet',
                            text:
                                "Their record appears here once they've played a game that finished.",
                          )
                        else
                          GlassCard(
                            child: Text('Loading their record…',
                                style:
                                    TextStyle(color: p.muted, fontSize: 13)),
                          ),
                        const SizedBox(height: 22),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            _PillTab(
                                icon: Icons.groups_outlined,
                                label: 'Groups',
                                count: groups.length,
                                selected: _tab == 0,
                                onTap: () => setState(() => _tab = 0)),
                            _PillTab(
                                icon: Icons.emoji_events_outlined,
                                label: 'Tournaments',
                                count: catTournaments.length,
                                selected: _tab == 1,
                                onTap: () => setState(() => _tab = 1)),
                            _PillTab(
                                icon: Icons.photo_library_outlined,
                                label: 'Posts',
                                count: posts.length,
                                selected: _tab == 2,
                                onTap: () => setState(() => _tab = 2)),
                          ]),
                        ),
                        const SizedBox(height: 12),
                        if (_tab == 0)
                          ..._groups(p, groups,
                              note: groupsAreFiltered && cat != null
                                  ? 'Groups they play ${sportName ?? 'this sport'} in.'
                                  : null)
                        else if (_tab == 1)
                          ..._tournamentsTab(catTournaments, sport: sportName)
                        else
                          ..._posts(p, posts),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (!data.hasValue)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SpRoundButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                tooltip: 'Back',
                onTap: _back,
              ),
            ),
          ),
      ]),
    );
  }

  // ── groups / tournaments / posts ──────────────────────────────────────

  List<Widget> _groups(AppPalette p, List<Map<String, dynamic>> groups,
      {String? note}) {
    if (groups.isEmpty) {
      return const [
        _Empty(icon: Icons.groups_outlined, text: 'Not in any groups yet.'),
      ];
    }
    return [
      if (note != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(note, style: TextStyle(color: p.muted, fontSize: 12)),
        ),
      SpListCard(children: [
        for (final g in groups)
          // Opens THIS PLAYER's record in that group — a scout tapping a
          // group wants their numbers there, not the group itself. The group
          // stays one tap away, as the secondary pill.
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.push('/players/$userId/groups/${g['id']}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Crest(
                      logoUrl: parseStr(g['imageUrl']),
                      label: parseStr(g['name']) ?? 'G',
                      size: 44),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(parseStr(g['name']) ?? 'Group',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                        // Any value but "none" means verified (it's a
                        // string, so the old `== true` never matched).
                        if (isVerifiedBadge(g['verificationBadge']))
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: VerifiedBadge(size: 16),
                          ),
                        if (g['role'] == 'admin') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: p.accentTint,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('Admin',
                                style: TextStyle(
                                    color: p.greenText,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 2),
                      Text('See their record here',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: p.surface2,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => context.push('/groups/${g['id']}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('Group',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 2),
                        Icon(Icons.north_east_rounded, size: 12, color: p.ink),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    ];
  }

  List<Widget> _tournamentsTab(List<Map<String, dynamic>> rows,
      {String? sport}) {
    if (rows.isEmpty) {
      return [
        _Empty(
          icon: Icons.emoji_events_outlined,
          text: sport != null
              ? 'No $sport tournaments yet.'
              : 'No tournaments yet.',
        ),
      ];
    }
    return [TournamentList(rows: rows, playerId: userId)];
  }

  List<Widget> _posts(AppPalette p, List<Map<String, dynamic>> posts) {
    if (posts.isEmpty) {
      return const [
        _Empty(icon: Icons.photo_library_outlined, text: 'No posts yet.'),
      ];
    }
    return [
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        children: [
          for (final post in posts)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: parseStr(post['contentUrl']) != null &&
                      parseStr(post['contentType']) == 'image'
                  ? Image.network(post['contentUrl'] as String,
                      fit: BoxFit.cover)
                  : Container(
                      color: p.surface2,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(8),
                      child: Text(parseStr(post['caption']) ?? 'Post',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.muted, fontSize: 11)),
                    ),
            ),
        ],
      ),
    ];
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────

class _Hero extends ConsumerWidget {
  const _Hero({
    required this.userId,
    required this.profile,
    required this.sports,
    required this.groups,
    required this.tournaments,
    required this.statsLoaded,
    required this.onBack,
  });
  final String userId;
  final Map<String, dynamic> profile;
  final int sports;
  final int groups;
  final int tournaments;
  final bool statsLoaded;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final top = MediaQuery.of(context).padding.top;
    final coverH = top + 132.0;
    const avatar = 104.0;
    const overlap = 34.0;
    final name = parseStr(profile['displayName']) ?? 'Player';
    final username = parseStr(profile['username']);
    // Gamification identity: level (always public), streak (if the player
    // made it public).
    final id = ref.watch(identityProvider(userId)).valueOrNull;

    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: coverH,
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(32)),
          child: CustomPaint(
            painter: _PlayerCover(p.hero, p.accentDeep, p.orange),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, top + 8, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SpRoundButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    iconSize: 18,
                    tooltip: 'Back',
                    onTap: onBack,
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 11),
                      child: Text('Player',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(16, coverH - overlap, 16, 0),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(16, avatar / 2 + 12, 16, 16),
          child: Column(children: [
            Text(name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: p.ink,
                    fontSize: 23,
                    height: 1.15,
                    fontWeight: FontWeight.w800)),
            if (username != null) ...[
              const SizedBox(height: 8),
              Material(
                color: p.surface2,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: username));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('@$username copied.')));
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text('@$username',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.copy_rounded, size: 13, color: p.muted),
                    ]),
                  ),
                ),
              ),
            ],
            if (id != null) ...[
              const SizedBox(height: 10),
              LevelBadge(
                  level: id.level, title: id.title, streak: id.weeklyStreak),
            ],
            // Positions / strong foot are per-sport: they live in the sport's
            // own card below, not up here as one fixed fact.
            const SizedBox(height: 16),
            Row(children: [
              _Stat(value: statsLoaded ? '$sports' : '–', label: 'Sports'),
              const SizedBox(width: 8),
              _Stat(value: '$groups', label: 'Groups'),
              const SizedBox(width: 8),
              _Stat(
                  value: statsLoaded ? '$tournaments' : '–',
                  label: 'Tournaments',
                  accent: true),
            ]),
          ]),
        ),
      ),
      Positioned(
        top: coverH - overlap - avatar / 2,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            width: avatar,
            height: avatar,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.surface,
              boxShadow: const [
                BoxShadow(
                    color: Color(0x2A000000),
                    blurRadius: 18,
                    offset: Offset(0, 6)),
              ],
            ),
            // Earned avatar frame (gamification status perk).
            child: FramedAvatar(
              userId: userId,
              child: ClipOval(
                child: Crest(
                    logoUrl: parseStr(profile['avatarUrl']),
                    label: name,
                    size: avatar - 12),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.accent = false});
  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: accent ? p.accentTint : p.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  color: accent ? p.greenText : p.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 11)),
        ]),
      ),
    );
  }
}

class _PlayerCover extends CustomPainter {
  _PlayerCover(this.base, this.green, this.warm);
  final Color base;
  final Color green;
  final Color warm;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, green, 0.7)!],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(size.width * 0.05, size.height * 1.05),
      size.height * 0.9,
      Paint()..color = warm.withAlpha(40),
    );
    final line = Paint()
      ..color = const Color(0x1FFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height), line);
    canvas.drawCircle(Offset(size.width / 2, size.height * 0.62), 44, line);
  }

  @override
  bool shouldRepaint(covariant _PlayerCover old) =>
      old.base != base || old.green != green || old.warm != warm;
}

// ─── Tabs & empty ───────────────────────────────────────────────────────────

class _PillTab extends StatelessWidget {
  const _PillTab({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? p.ink : p.surface,
        shape: StadiumBorder(
            side: selected ? BorderSide.none : BorderSide(color: p.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 8, count > 0 ? 8 : 14, 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: selected ? p.bg : p.muted),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: selected ? p.bg : p.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0x33FFFFFF) : p.surface2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('$count',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: selected ? p.bg : p.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, this.title});
  final IconData icon;
  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(children: [
        SpIconTile(icon, bg: p.surface2, fg: p.muted, size: 52, iconSize: 24),
        if (title != null) ...[
          const SizedBox(height: 12),
          Text(title!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
        ],
        const SizedBox(height: 6),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
      ]),
    );
  }
}
