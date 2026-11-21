import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/links/link_resolver.dart' show HomeTab;
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/ads/ad_anchor.dart';
import 'package:sportpadi_mobile/features/highlights/highlights_grid.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/players/profile_header.dart';
import 'package:sportpadi_mobile/features/players/scout_header.dart';
import 'package:sportpadi_mobile/features/profile/social_links.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart'
    show homeTabIndexProvider;
import 'package:sportpadi_mobile/features/sports/sport_record_card.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart'
    show meProvider;
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_tab_track.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/verified_badge.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Public player profile — the scout's view (web /players/[id] twin).
///
/// The question this page exists to answer is "how well is this player doing in
/// this sport", so each sport they've played gets its own card (the Records
/// tab) that opens that sport's record page — designed per sport
/// (docs/design/sport-records.md). Stats are only comparable inside a sport;
/// nothing is summed across them.
///
/// 2026 design, Instagram's layout (owner, 2026-11-19 — no cover banner): a
/// slim row with the back button, then the header (`profile_header.dart`) —
/// photo (earned frame) and Followers · Following, name, @username, byline,
/// bio, links, sport / team chips and the level badge, then Follow / Message /
/// Share — then the group page's tab switch ([SpTabTrack], pinned under the
/// status bar): Highlights / Groups / Records across all sports, Highlights
/// open first. Honours, recent matches and the per-sport rating tiles are in
/// the Records tab. A private adult's profile shows the header and a lock to
/// anyone they haven't accepted; a ward their guardians keep limited, a name
/// and a lock. Tournaments are no longer a tab: each sport's record page
/// lists them.

final playerProfileProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, userId) async {
  try {
    final res = await ref.watch(dioProvider).get('/api/mobile/players/$userId');
    if (res.data is! Map) {
      throw ApiException(l10n.profile_playerNotFound2, statusCode: 404);
    }
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    throw apiError(e, fallback: l10n.profile_couldNotLoadThePlayer);
  }
});

/// The heavier half — per-category record and tournaments
/// (`{ categories, tournaments }`, design/sport-records.md §2). Loaded
/// separately so identity paints straight away. Errors surface (a 403 is a
/// private ward record) — the sport record pages need to tell them apart.
final playerRecordsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, userId) async {
  try {
    final res =
        await ref.watch(dioProvider).get('/api/mobile/players/$userId/stats');
    return res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
  } catch (e) {
    throw apiError(e, fallback: l10n.profile_couldNotLoadTheRecord);
  }
});

/// [playerRecordsProvider] for the profile page, where the numbers are a
/// bonus and never the whole page: a failure reads as "no numbers".
final playerStatsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, userId) async {
  try {
    return await ref.watch(playerRecordsProvider(userId).future);
  } catch (_) {
    return <String, dynamic>{};
  }
});

class PlayerProfileScreen extends ConsumerStatefulWidget {
  const PlayerProfileScreen({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<PlayerProfileScreen> createState() =>
      _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends ConsumerState<PlayerProfileScreen>
    with SingleTickerProviderStateMixin {
  /// 0 highlights, 1 groups, 2 records — the order of the track's labels.
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)..addListener(_onTab);
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get userId => widget.userId;

  void _back() => context.canPop() ? context.pop() : context.go('/home');

  /// Pull to refresh: the profile, the record (sports / tournaments) and the
  /// level badge + avatar frame — the spinner stays until what's shown is back.
  Future<void> _refresh() {
    final profile = ref.read(playerProfileProvider(userId));
    // Same condition as build(): stats and identity are only on screen then.
    final shown =
        profile.hasValue && profile.valueOrNull?['restricted'] != true;
    ref.invalidate(playerProfileProvider(userId));
    ref.invalidate(playerRecordsProvider(userId));
    ref.invalidate(identityProvider(userId));
    ref.invalidate(playerHonoursProvider(userId));
    ref.invalidate(followStateProvider(userId));
    ref.invalidate(canMessageProvider(userId));
    // The highlights grid pages with its own state, not a provider.
    reloadHighlightGrids();
    return settleAll([
      ref.read(playerProfileProvider(userId).future),
      if (shown) ref.read(playerStatsProvider(userId).future),
      if (shown) ref.read(identityProvider(userId).future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final data = ref.watch(playerProfileProvider(userId));
    // Whether I follow / asked to / may ask, whether they follow me — the
    // pills and the lock's wording (follows.state).
    final fs = ref.watch(followStateProvider(userId)).valueOrNull;
    // Watched here, not in the header's builders (they run inside
    // AsyncView's build): who I am, and — only once the profile is open —
    // the level badge and whether I may message them.
    final me = ref.watch(meProvider).valueOrNull?.userId;
    final shown = data.hasValue && data.valueOrNull?['restricted'] != true;
    final identity =
        shown ? ref.watch(identityProvider(userId)).valueOrNull : null;
    final canMessage = shown && me != null
        ? ref.watch(canMessageProvider(userId)).valueOrNull
        : null;
    // A follow that opens a private profile (or an unfollow that locks it
    // again — or their accept, seen on a refresh): re-read what the page
    // may show.
    ref.listen<AsyncValue<FollowState>>(followStateProvider(userId),
        (prev, next) {
      final was = prev?.valueOrNull?.canSeeProfile;
      final now = next.valueOrNull?.canSeeProfile;
      if (was != null && now != null && was != now) {
        ref.invalidate(playerProfileProvider(userId));
        ref.invalidate(playerRecordsProvider(userId));
        ref.invalidate(playerHonoursProvider(userId));
      }
    });
    // A ward whose guardians keep their profile private from this viewer:
    // short name, no photo, no numbers — and the stats routes would refuse,
    // so they're only asked for once the profile says it's open.
    final restricted = data.valueOrNull?['restricted'] == true;
    // …or a player who made their own profile private: their name, @handle
    // and photo, and a lock.
    final privateProfile = data.valueOrNull?['privateProfile'] == true;
    final stats = data.hasValue && !restricted
        ? ref.watch(playerStatsProvider(userId)).valueOrNull
        : null;

    final categories = listOf(stats?['categories']);
    // The scouting header (honours, recent matches, average rating) — the
    // slowest read, so it lands last and never holds the page.
    final honours = data.hasValue && !restricted
        ? ref.watch(playerHonoursProvider(userId)).valueOrNull
        : null;
    // A failed honours read: the cards' rating corners say "–" (not a
    // placeholder forever).
    final honoursFailed = data.hasValue &&
        !restricted &&
        ref.watch(playerHonoursProvider(userId)).hasError;
    // The sport they play most leads the header; stats never cross sports.
    final sorted = [...categories]
      ..sort((a, b) => (parseInt(mapOf(b['overall'])['games']) ?? 0)
          .compareTo(parseInt(mapOf(a['overall'])['games']) ?? 0));
    final primary = sorted.isEmpty ? null : sorted.first;

    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        _pullableUnlessData(
          data,
          _refresh,
          AsyncView(
            value: data,
            onRetry: () {
              ref.invalidate(playerProfileProvider(userId));
              ref.invalidate(playerRecordsProvider(userId));
            },
            data: (m) {
              final profile = mapOf(m['profile']);
              final name = parseStr(profile['displayName']) ?? 'Player';
              final username = parseStr(profile['username']);
              final avatarUrl = parseStr(profile['avatarUrl']);
              final topBar = ProfileTopBar(
                title: context.l10n.profile_player,
                left: SpRoundButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  iconSize: 18,
                  tooltip: context.l10n.profile_back,
                  onTap: _back,
                ),
              );
              // A ward whose guardians keep the profile private from this
              // viewer: initials, the short name and a lock — their
              // guardians' rules, unchanged (no photo, handle, counts or
              // follow; the server sends none of them).
              if (restricted && !privateProfile) {
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 36),
                    children: [
                      topBar,
                      ProfileHeader(
                        avatar: ProfileAvatar(
                            photo: ClipOval(
                                child: Crest(
                                    logoUrl: null,
                                    label: name,
                                    size: kProfileAvatar - 10))),
                        name: name,
                        badges: const [WardBadge()],
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 18, 16, 0),
                        child: WardPrivateNote(),
                      ),
                    ],
                  ),
                );
              }
              // A private adult's profile, seen by anyone they haven't
              // accepted: Instagram's header — photo, counts (not opening the
              // lists, which are refused), name, @username, bio, links — then
              // Follow / Requested and the lock. No tabs.
              if (restricted) {
                // "Follow this account…" only once the follow state says a
                // Follow (or request) is on offer; while it loads, if it
                // failed (no pill then — and a retry), or for a viewer who
                // can't ask (a child, a managed account): the neutral line,
                // which doesn't say "private" twice (review LOWs).
                final fsFailed =
                    ref.read(followStateProvider(userId)).hasError &&
                        fs == null;
                final lockText = fs?.requested == true
                    ? context.l10n.profile_privateAccountRequestedText
                    : fs != null && (fs.canFollow || fs.canRequest)
                        ? context.l10n.profile_privateAccountFollowText
                        : context.l10n.profile_privateAccountApprovedOnlyText;
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 36),
                    children: [
                      topBar,
                      ProfileHeader(
                        avatar: ProfileAvatar(
                            photo: ClipOval(
                                child: Crest(
                                    logoUrl: avatarUrl,
                                    label: name,
                                    size: kProfileAvatar - 10))),
                        name: name,
                        username: username,
                        isPrivate: true,
                        badges: [
                          if (fs?.followsMe == true)
                            ProfileBadge(context.l10n.profile_followsYou),
                        ],
                        bio: parseStr(profile['bio']),
                        links: SocialLink.listFrom(m['links']),
                        counts: ProfileCounts(userId: userId, open: false),
                        actions: _actions(fs,
                            me: me,
                            canMessage: null,
                            name: name,
                            username: username,
                            avatarUrl: avatarUrl),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                        child: ProfileLockCard(
                            title: context.l10n.profile_privateAccountTitle,
                            text: lockText,
                            action: fsFailed
                                ? Align(
                                    alignment:
                                        AlignmentDirectional.centerStart,
                                    child: ProfilePill(
                                      label: context.l10n.profile_tryAgain,
                                      icon: Icons.refresh_rounded,
                                      compact: true,
                                      onTap: () => ref.invalidate(
                                          followStateProvider(userId)),
                                    ),
                                  )
                                : null),
                      ),
                    ],
                  ),
                );
              }
              // No sport picker any more (2026 sport records): the tabs list
              // everything, across all sports.
              final groups = listOf(m['groups']);
              // Photos they posted in their groups (older than Highlights);
              // shown under the highlights grid, as on the web.
              final posts = listOf(m['posts']);

              return RefreshIndicator(
                onRefresh: _refresh,
                child: SpPinnedTabsScrollView(
                  header: [
                    SliverToBoxAdapter(child: topBar),
                    SliverToBoxAdapter(
                        child: _header(
                      fs,
                      me: me,
                      identity: identity,
                      canMessage: canMessage,
                      profile: profile,
                      name: name,
                      username: username,
                      avatarUrl: avatarUrl,
                      primary: primary,
                      sports: listOf(m['sports']),
                      teams: listOf(m['teams']),
                      playsIn: parseStr(m['playsIn']),
                      links: SocialLink.listFrom(m['links']),
                    )),
                    // Owner-console ad spot (anchor "player.profile_bottom")
                    // under the header, above the tabs; nothing unless set.
                    // Honours and recent matches that sat here are in the
                    // Records tab.
                    const SliverToBoxAdapter(
                      child: AdAnchor(
                          anchor: 'player.profile_bottom',
                          padding: EdgeInsets.fromLTRB(20, 14, 20, 0)),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  ],
                  // The group page's tab switch; it pins under the status
                  // bar while the header scrolls away. No counts, as there.
                  track: SpTabTrack(labels: [
                    context.l10n.profile_highlights,
                    context.l10n.profile_groups,
                    context.l10n.profile_records,
                  ], controller: _tabs),
                  body: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_tabs.index == 0)
                              // Highlights about this player (reels), newest
                              // first; a tile opens the post.
                              ...[
                                HighlightsGrid(userId: userId),
                                if (posts.isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  Eyebrow(context.l10n.highlights_groupPostsTitle),
                                  const SizedBox(height: 8),
                                  _posts(p, posts),
                                ],
                              ]
                            else if (_tabs.index == 1)
                              ..._groups(p, groups)
                            else ...[
                              // Their honours and latest matches, then ONE
                              // sport card per sport, its rating in the
                              // card's corner (owner, 2026-11-20: the
                              // separate rating tiles are gone), each
                              // opening that sport's own record page.
                              // Honours and matches sat in the old cover
                              // header.
                              HonoursSection(
                                  honours: listOf(honours?['honours']),
                                  loading: honours == null),
                              RecentMatchesSection(
                                  recent: listOf(honours?['recent']),
                                  loading: honours == null,
                                  playerId: userId),
                              const SizedBox(height: 18),
                              PlayerRecordsSection(
                                userId: userId,
                                categories: categories,
                                loaded: stats != null,
                                ratings: honours != null
                                    ? listOf(honours['ratingsByCategory'])
                                    : honoursFailed
                                        ? const <Map<String, dynamic>>[]
                                        : null,
                              ),
                            ],
                            // The page's foot on every tab: it vouches for
                            // the honours, matches and ratings as much as
                            // for the records.
                            RecordFootnote(games: parseInt(honours?['games'])),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (!data.hasValue)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SpRoundButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                tooltip: context.l10n.profile_back,
                onTap: _back,
              ),
            ),
          ),
      ]),
    );
  }

  // ── header ────────────────────────────────────────────────────────────────

  /// The full view's header: identity only — the record is the Records tab.
  Widget _header(
    FollowState? fs, {
    required String? me,
    required Identity? identity,
    required Map<String, dynamic>? canMessage,
    required Map<String, dynamic> profile,
    required String name,
    required String? username,
    required String? avatarUrl,
    required Map<String, dynamic>? primary,
    required List<Map<String, dynamic>> sports,
    required List<Map<String, dynamic>> teams,
    required String? playsIn,
    required List<SocialLink> links,
  }) {
    // Gamification identity ([identity]): level (always public), streak (if
    // the player made it public).
    final id = identity;
    final isMe = fs?.isMe == true || me == userId;
    final scout = ScoutByline(
        primary: primary,
        sports: sports,
        teams: teams,
        playsIn: playsIn,
        alignStart: true,
        showByline: false);
    return ProfileHeader(
      // Earned avatar frame (gamification status perk) — drawn inside the
      // same box as on your own profile, so the counts never shift.
      avatar: ProfileAvatar(
        photo: ClipOval(
            child: Crest(
                logoUrl: avatarUrl, label: name, size: kProfileAvatar - 10)),
        ring: id == null ? null : frameColor(id.frame),
      ),
      name: name,
      username: username,
      isPrivate: fs?.isPrivate == true,
      badges: [
        if (!isMe && fs?.followsMe == true)
          ProfileBadge(context.l10n.profile_followsYou),
      ],
      byline: scout.byline,
      bio: parseStr(profile['bio']),
      links: links,
      // Sport · team · level — the chips a scout scans first.
      chips: [
        scout,
        if (id != null) ...[
          const SizedBox(height: 10),
          LevelBadge(level: id.level, title: id.title, streak: id.weeklyStreak),
        ],
      ],
      // "N highlights": the Highlights tab, scrolled to.
      counts: ProfileCounts(
        userId: userId,
        onHighlights: (ctx) {
          _tabs.animateTo(0);
          SpPinnedTabsScrollView.revealTabs(ctx);
        },
      ),
      actions: _actions(fs,
          me: me,
          canMessage: canMessage,
          name: name,
          username: username,
          avatarUrl: avatarUrl),
    );
  }

  /// The pills row. My own page: Edit profile (the Profile tab) · Share.
  /// Someone else's: Follow / Following / Requested · Message (only when
  /// messaging allows it — [canMessage], `{ ok }`; null on a locked private
  /// profile, which can't be messaged) · Share. A pill the rules hide leaves
  /// no gap.
  Widget _actions(
    FollowState? fs, {
    required String? me,
    required Map<String, dynamic>? canMessage,
    required String name,
    required String? username,
    required String? avatarUrl,
  }) {
    final isMe = fs?.isMe == true || me == userId;
    if (isMe) {
      return Row(children: [
        Expanded(
          child: ProfilePill(
            label: context.l10n.profile_editProfile,
            icon: Icons.edit_outlined,
            expand: true,
            onTap: () {
              // Edit profile lives on the Profile tab.
              ref.read(homeTabIndexProvider.notifier).state = HomeTab.profile;
              context.go('/home');
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ShareProfilePill(
              userId: userId,
              name: name,
              username: username,
              avatarUrl: avatarUrl,
              expand: true),
        ),
      ]);
    }
    final share = ShareProfilePill(
        userId: userId,
        name: name,
        username: username,
        avatarUrl: avatarUrl,
        iconOnly: true);
    final showFollow = fs != null &&
        (fs.following || fs.requested || fs.canFollow || fs.canRequest);
    final showMessage = canMessage != null && canMessage['ok'] == true;
    if (!showFollow && !showMessage) {
      return Align(alignment: AlignmentDirectional.centerStart, child: share);
    }
    return Row(children: [
      if (showFollow)
        Expanded(child: FollowButton(userId: userId, name: name, expand: true)),
      if (showFollow && showMessage) const SizedBox(width: 8),
      if (showMessage)
        Expanded(child: MessageButton(userId: userId, name: name, expand: true)),
      const SizedBox(width: 8),
      share,
    ]);
  }

  // ── highlights / groups / records ──────────────────────────────────────────

  List<Widget> _groups(AppPalette p, List<Map<String, dynamic>> groups) {
    if (groups.isEmpty) {
      return [
        _Empty(icon: Icons.groups_outlined, text: context.l10n.profile_notInAnyGroupsYet),
      ];
    }
    return [
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
                          child: Text(parseStr(g['name']) ?? context.l10n.profile_group,
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
                            child: Text(context.l10n.profile_admin,
                                style: TextStyle(
                                    color: p.greenText,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 2),
                      Text(context.l10n.profile_seeTheirRecordHere,
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
                        Text(context.l10n.profile_group,
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

  /// Group posts (`posts` on the profile payload): a plain grid, not opened.
  Widget _posts(AppPalette p, List<Map<String, dynamic>> posts) {
    return GridView.count(
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
                    child: Text(
                        parseStr(post['caption']) ??
                            context.l10n.profile_highlight,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.muted, fontSize: 11)),
                  ),
          ),
      ],
    );
  }
}

// ─── Empty ───────────────────────────────────────────────────────────

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(children: [
        SpIconTile(icon, bg: p.surface2, fg: p.muted, size: 52, iconSize: 24),
        const SizedBox(height: 6),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
      ]),
    );
  }
}

/// Loading / error aren't scrollable on their own, so they get a pullable
/// wrapper; once the data shows, its own RefreshIndicator takes over.
Widget _pullableUnlessData(AsyncValue<Object?> v,
        Future<void> Function() onRefresh, Widget child) =>
    v.hasValue && !v.hasError
        ? child
        : RefreshIndicator(
            onRefresh: onRefresh, child: PullableState(child: child));
