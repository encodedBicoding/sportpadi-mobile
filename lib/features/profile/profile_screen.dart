import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart'
    show eventsRepositoryProvider;
import 'package:sportpadi_mobile/data/profile/profile_models.dart';
import 'package:sportpadi_mobile/features/profile/social_links.dart';
import 'package:sportpadi_mobile/features/players/scout_header.dart';
import 'package:sportpadi_mobile/features/sports/sport_record_card.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/groups/my_groups_menu.dart';
import 'package:sportpadi_mobile/features/highlights/highlights_grid.dart';
import 'package:sportpadi_mobile/core/links/link_resolver.dart' show HomeTab;
import 'package:sportpadi_mobile/features/players/aka_card.dart';
import 'package:sportpadi_mobile/features/players/profile_header.dart';
import 'package:sportpadi_mobile/shared/format/bio.dart';
import 'package:sportpadi_mobile/features/players/player_profile_screen.dart'
    show playerRecordsProvider, playerStatsProvider;
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_dock.dart';
import 'package:sportpadi_mobile/shared/widgets/sheet_scroll.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_tab_track.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart'
    show frameColor;
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/data/wards/wards_repository.dart'
    show myWardsProvider;
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/features/ads/ad_anchor.dart';

/// Profile (2026) — Instagram's layout (owner, 2026-11-19 — no cover
/// banner): a slim row with the QR / menu round buttons, then the header
/// (`profile_header.dart`) — photo (upload, frame) and Highlights ·
/// Followers · Following (the highlights count opens the Highlights tab),
/// name, @username (copy), bio, links, then Edit profile · Share
/// profile — "Follow requests" while anyone waits, the Wards card, then the
/// group page's tab switch ([SpTabTrack], pinned under the status bar):
/// Highlights / Groups / Records across all sports, Highlights open first.
/// Your top honours, latest matches and sport record cards (each with that
/// sport's rating) are the Records tab. Tournaments are no
/// longer a tab: each sport's record page lists them, and the dock has
/// Tournaments. My sports and My records live on their own pages, under the
/// menu's "Activity & stats".
/// The menu is a bottom sheet: quick tab tiles, then personal pages as icon
/// rows.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  /// 0 highlights, 1 groups, 2 records — the order of [_tabLabels].
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

  List<String> _tabLabels(BuildContext context) => [
        context.l10n.profile_highlights,
        context.l10n.profile_groups,
        context.l10n.profile_records,
      ];

  /// Pull to refresh: everything the page shows — the profile, the record
  /// (sports / tournaments), groups and the names they know you by, the
  /// avatar frame, wards, progression and the events tab — and the spinner
  /// stays until what's on screen is back.
  Future<void> _refresh() {
    final profile = ref.read(meProvider).valueOrNull;
    final userId = profile?.userId;
    ref.invalidate(meProvider);
    // The records provider is the cache; the stats one follows it.
    if (userId != null) ref.invalidate(playerRecordsProvider(userId));
    ref.invalidate(myGroupsProvider);
    ref.invalidate(myGroupAkasProvider);
    ref.invalidate(identityProvider(userId ?? ''));
    ref.invalidate(myWardsProvider);
    if (userId != null) ref.invalidate(playerHonoursProvider(userId));
    if (userId != null) ref.invalidate(followStateProvider(userId));
    // The highlights grid pages with its own state, not a provider.
    reloadHighlightGrids();
    return settleAll([
      ref.read(meProvider.future),
      // The rest is only on screen (watched) once the profile is.
      if (profile != null) ...[
        if (userId != null) ref.read(playerStatsProvider(userId).future),
        ref.read(myGroupsProvider.future),
        ref.read(myGroupAkasProvider.future),
        ref.read(identityProvider(userId ?? '').future),
        ref.read(myWardsProvider.future),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final p = context.palette;
    void openMenu(Profile profile) {
      showSpSheet<void>(
        context,
        framed: false,
        builder: (ctx) => _ProfileMenuSheet(
          profile: profile,
          // Requests waiting for me — the menu row's count.
          requestCount: profile.userId == null
              ? 0
              : ref
                      .read(followStateProvider(profile.userId!))
                      .valueOrNull
                      ?.requestCount ??
                  0,
          onPick: (v) {
            Navigator.pop(ctx);
            // Main destinations are bottom tabs here, so they switch tabs.
            if (v.startsWith('tab:')) {
              ref.read(homeTabIndexProvider.notifier).state =
                  int.parse(v.substring(4));
            } else {
              context.push(v);
            }
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: _pullableUnlessData(
        context,
        me,
        _refresh,
        AsyncView(
        value: me,
        onRetry: () => ref.invalidate(meProvider),
        data: (profile) {
          if (profile == null) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: PullableState(
                  bottomPadding: SpDock.spaceBelow(context),
                  child: Text(context.l10n.profile_noProfileFound)),
            );
          }
          final userId = profile.userId;
          final stats = userId == null
              ? null
              : ref.watch(playerStatsProvider(userId)).valueOrNull;
          final categories = listOf(stats?['categories']);
          // Your top honours and latest matches — the same read a scout gets
          // (docs/design/scouting-profile.md); progress lives under the menu.
          final honours = userId == null
              ? null
              : ref.watch(playerHonoursProvider(userId)).valueOrNull;
          final allHonours = listOf(honours?['honours']);
          // A failed honours read: the cards' rating corners say "–" (not a
          // placeholder forever).
          final honoursFailed = userId != null &&
              ref.watch(playerHonoursProvider(userId)).hasError;
          // My counts, whether my profile is private (the lock by my
          // @username) and the follow requests waiting for me.
          final follow = userId == null
              ? null
              : ref.watch(followStateProvider(userId)).valueOrNull;
          // No sport picker here any more: the tabs cover every sport.
          final groupsAsync = ref.watch(myGroupsProvider);
          final groups = groupsAsync.valueOrNull ?? const <GroupSummary>[];
          final akas = ref.watch(myGroupAkasProvider).valueOrNull ??
              const <String, String>{};

          return RefreshIndicator(
            onRefresh: _refresh,
            child: SpPinnedTabsScrollView(
              header: [
              SliverList(
                  delegate: SliverChildListDelegate([
                _Hero(
                  profile: profile,
                  onMenu: () => openMenu(profile),
                  isPrivate: follow?.isPrivate == true,
                  // "N highlights": the Highlights tab, scrolled to.
                  onHighlights: (ctx) {
                    _tabs.animateTo(0);
                    SpPinnedTabsScrollView.revealTabs(ctx);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Requests to follow my private profile (Instagram
                      // keeps them in the activity feed; the notification
                      // opens the same screen). Nothing while none wait.
                      if ((follow?.requestCount ?? 0) > 0) ...[
                        FollowRequestsRow(count: follow!.requestCount),
                        const SizedBox(height: 12),
                      ],
                      // Guardians: their wards and any co-guardian invites,
                      // right under the header (nothing for everyone else).
                      WardsProfileCard(
                          onOpen: () => context.push('/profile/wards')),
                      // Honours, recent matches and the rating tiles that
                      // sat here are the Records tab now.
                      // Owner-console ad spot right above the tabs, as on
                      // a player's profile: anchor "profile.mid", or the
                      // public profile's "player.profile_bottom" fill while
                      // that is unset (one setting covers both profiles).
                      const AdAnchor(
                          anchor: 'profile.mid',
                          fallback: 'player.profile_bottom',
                          padding: EdgeInsets.only(top: 14)),
                    ],
                  ),
                ),
              ])),
              ],
              // The group page's tab switch; it pins under the status bar
              // while the cover scrolls away. No counts, as there.
              track: SpTabTrack(
                  labels: _tabLabels(context), controller: _tabs),
              body: [
              SliverPadding(
                // The last sliver: air under the last card, above the
                // dock's band.
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16, SpDock.spaceBelowList(context)),
                sliver: SliverList(
                    delegate: SliverChildListDelegate([
                  if (_tabs.index == 0)
                    // Highlights about me (reels), newest first; a tile
                    // opens the post. "Post a highlight" sits above the
                    // tiles and in the empty state (the web profile's pill).
                    HighlightsGrid(userId: userId ?? '', mine: true)
                  else if (_tabs.index == 1)
                    _MyGroupsList(
                      groups: groups,
                      akas: akas,
                      userId: userId,
                      // A list still loading, or one that failed, is not an
                      // empty one: neither says "You're not in any groups".
                      loading: !groupsAsync.hasValue && !groupsAsync.hasError,
                      failed: !groupsAsync.hasValue && groupsAsync.hasError,
                      // A retry keeps the error (riverpod keeps it while it
                      // re-reads), so the pill shows the re-read itself.
                      retrying: groupsAsync.isLoading,
                      onRetry: () => ref.invalidate(myGroupsProvider),
                    )
                  else ...[
                    // Records — your top three honours and last five
                    // matches across all sports (what a scout sees first),
                    // then ONE card per sport, as on the public profile,
                    // its rating in the card's corner (owner, 2026-11-20:
                    // the separate rating tiles are gone); each opens your
                    // own record for that sport. Honours and matches sat in
                    // the old cover header (owner, 2026-11-19).
                    HonoursSection(
                      honours: allHonours.take(3).toList(),
                      loading: honours == null,
                      total: allHonours.length,
                      onMore: userId == null
                          ? null
                          : () => context.push('/players/$userId'),
                    ),
                    RecentMatchesSection(
                      recent: listOf(honours?['recent']).take(5).toList(),
                      loading: honours == null,
                      playerId: userId ?? '',
                    ),
                    const SizedBox(height: 18),
                    PlayerRecordsSection(
                      userId: userId ?? '',
                      categories: categories,
                      loaded: stats != null,
                      mine: true,
                      trailing: TextButton(
                        onPressed: () => context.push('/profile/records'),
                        child: Text(context.l10n.profile_allRecords),
                      ),
                      ratings: honours != null
                          ? listOf(honours['ratingsByCategory'])
                          : honoursFailed
                              ? const <Map<String, dynamic>>[]
                              : null,
                    ),
                  ],
                ])),
              ),
              ],
            ),
          );
        },
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero — the QR / menu row, then the Instagram-style header: avatar with
// camera upload and counts, name / @username, bio, links, Edit · Share.
// ---------------------------------------------------------------------------

class _Hero extends ConsumerStatefulWidget {
  const _Hero({
    required this.profile,
    required this.onMenu,
    this.isPrivate = false,
    this.onHighlights,
  });
  final Profile profile;
  final VoidCallback onMenu;

  /// The highlights count's tap (see [ProfileCounts.onHighlights]).
  final void Function(BuildContext context)? onHighlights;

  /// My "private profile" is on: the lock beside my @username.
  final bool isPrivate;

  @override
  ConsumerState<_Hero> createState() => _HeroState();
}

class _HeroState extends ConsumerState<_Hero> {
  bool _uploading = false;

  Future<void> _changeAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await ref.read(eventsRepositoryProvider).uploadImage(
            bytes,
            picked.mimeType ?? 'image/jpeg',
            assetType: 'avatar',
          );
      await ref.read(profileRepositoryProvider).updateMe({'avatarUrl': url});
      ref.invalidate(meProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _editProfile() async {
    final saved = await showSpSheet<bool>(
      context,
      framed: false,
      builder: (_) => _EditProfileSheet(profile: widget.profile),
    );
    if (saved == true) ref.invalidate(meProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final profile = widget.profile;
    final userId = profile.userId;
    // Earned avatar frame (gamification) replaces the default green ring
    // once the player reaches Regular.
    final frame = frameColor(
            ref.watch(identityProvider(userId ?? '')).valueOrNull?.frame ??
                'none') ??
        p.accent;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ProfileTopBar(
        title: context.l10n.profile_profile,
        left: SpRoundButton(
          icon: Icons.qr_code_2_rounded,
          tooltip: context.l10n.profile_myQrCode,
          onTap: () => context.push('/my-qr'),
        ),
        right: SpRoundButton(
          icon: Icons.more_horiz_rounded,
          tooltip: context.l10n.profile_menu,
          onTap: widget.onMenu,
        ),
      ),
      ProfileHeader(
        avatar: ProfileAvatar(
          photo: ClipOval(
            child: Crest(
                logoUrl: profile.avatarUrl,
                label: profile.displayName,
                size: kProfileAvatar - 10),
          ),
          ring: frame,
          onCamera: _changeAvatar,
          uploading: _uploading,
        ),
        name: profile.displayName,
        // Tap to copy — the username is the handle friends use to buy
        // tickets for you.
        username: profile.username,
        copiedText: l10n.profile_usernameCopiedShareItSo,
        isPrivate: widget.isPrivate,
        bio: profile.bio,
        links: SocialLink.listFrom(profile.links),
        counts: userId == null
            ? null
            : ProfileCounts(userId: userId, onHighlights: widget.onHighlights),
        actions: Row(children: [
          Expanded(
            child: ProfilePill(
              label: context.l10n.profile_editProfile,
              icon: Icons.edit_outlined,
              expand: true,
              onTap: _editProfile,
            ),
          ),
          if (userId != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: ShareProfilePill(
                  userId: userId,
                  name: profile.displayName,
                  username: profile.username,
                  avatarUrl: profile.avatarUrl,
                  expand: true),
            ),
          ],
        ]),
      ),
    ]);
  }
}

/// Sheet handle.
class _Grabber extends StatelessWidget {
  const _Grabber();
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: context.palette.line,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// Icon tile + line — the 2026 empty state.
class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.icon, required this.text});
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

// ---------------------------------------------------------------------------
// Menu — bottom sheet: who you are, quick tab tiles, then your pages.
// ---------------------------------------------------------------------------

class _ProfileMenuSheet extends StatelessWidget {
  const _ProfileMenuSheet(
      {required this.profile, required this.onPick, this.requestCount = 0});
  final Profile profile;
  final ValueChanged<String> onPick;

  /// Follow requests waiting for me (the "Follow requests" row's count).
  final int requestCount;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    Widget quick(String value, IconData icon, String label) => Expanded(
          child: Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onPick(value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(children: [
                  SpIconTile(icon, bg: p.accentTint, fg: p.greenText, size: 40),
                  const SizedBox(height: 8),
                  Text(label,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        );

    Widget row(String value, IconData icon, String label, String sub, Color bg,
            Color fg, {int count = 0}) =>
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onPick(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(children: [
              SpIconTile(icon, bg: bg, fg: fg, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ],
                ),
              ),
              if (count > 0)
                Container(
                  margin: const EdgeInsetsDirectional.only(end: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: p.orange,
                      borderRadius: BorderRadius.circular(999)),
                  child: Text('$count',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              Icon(Icons.chevron_right_rounded, color: p.muted),
            ]),
          ),
        );

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SheetScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Grabber(),
              const SizedBox(height: 16),
              Row(children: [
                ClipOval(
                  child: Crest(
                      logoUrl: profile.avatarUrl,
                      label: profile.displayName,
                      size: 46),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      Text('@${profile.username}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                SpRoundButton(
                  icon: Icons.close_rounded,
                  tooltip: l.nav_close,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                quick('tab:0', Icons.space_dashboard_outlined, l.menu_dashboard),
                const SizedBox(width: 8),
                quick('tab:1', Icons.explore_outlined, l.menu_discover),
                const SizedBox(width: 8),
                quick('tab:${HomeTab.tournaments}',
                    Icons.emoji_events_outlined, l.nav_tournaments),
              ]),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Eyebrow(l.menu_checkInPayments),
              ),
              SpListCard(children: [
                row('/scan', Icons.qr_code_scanner_rounded, l.menu_scanToCheckIn,
                    l.menu_scanToCheckInSub, p.accentTint, p.greenText),
                row('/my-qr', Icons.qr_code_2_rounded, l.menu_myQrCode,
                    l.menu_myQrCodeSub, p.surface2, p.ink),
                row('/tickets', Icons.confirmation_num_outlined, l.menu_myPurchases,
                    l.menu_myPurchasesSub, p.orangeTint, p.orangeInk),
                row('/leagues/mine', Icons.format_list_numbered_rounded,
                    l.menu_myLeagues, l.menu_myLeaguesSub,
                    p.accentTint, p.greenText),
                row('/fines', Icons.receipt_long_outlined, l.menu_myFines,
                    l.menu_myFinesSub, p.liveTint, p.danger),
              ]),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Eyebrow(l.menu_myGroups),
              ),
              MyGroupsMenu(onGo: onPick),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Eyebrow(l.menu_activityStats),
              ),
              SpListCard(children: [
                row('/profile/sports', Icons.sports_soccer_outlined,
                    l.menu_mySports, l.menu_mySportsSub, p.accentTint, p.greenText),
                row('/profile/records', Icons.insights_rounded, l.menu_myRecords,
                    l.menu_myRecordsSub, p.orangeTint, p.orangeInk),
                row('/profile/progress', Icons.trending_up_rounded,
                    l.menu_progress, l.menu_progressSub,
                    p.accentTint, p.greenText),
              ]),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Eyebrow(l.menu_you),
              ),
              SpListCard(children: [
                row('/profile/links', Icons.link_rounded, l.menu_socialLinks,
                    l.menu_socialLinksSub, p.surface2, p.ink),
                // Always here (review profile-header MED-1): the way to the
                // requests waiting for me AND to the ones I sent (Sent tab),
                // even while nobody is asking.
                row(
                    '/profile/follow-requests',
                    Icons.person_add_alt_1_rounded,
                    l.profile_followRequests,
                    requestCount > 0
                        ? l.profile_followRequestsWaiting(requestCount)
                        : l.profile_followRequestsMenuSub,
                    p.accentTint,
                    p.greenText,
                    count: requestCount),
                WardsMenuRow(onTap: () => onPick('/profile/wards')),
                row('/notifications', Icons.notifications_outlined,
                    l.menu_notifications, l.menu_notificationsSub, p.surface2, p.ink),
                row('/settings', Icons.settings_outlined, l.menu_settings,
                    l.menu_settingsSub, p.surface2, p.ink),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edit profile: display name, username and the bio (docs/design/
/// scouting-profile.md "The profile header" — up to 150 characters of plain
/// text; a supervised account has none, so the field is a note there and
/// the server refuses one anyway).
class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});
  final Profile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.profile.displayName);
  late final TextEditingController _username =
      TextEditingController(text: widget.profile.username);
  late final TextEditingController _bio =
      TextEditingController(text: widget.profile.bio ?? '');
  bool _busy = false;
  String? _error;

  /// What the server will count: code points of the bio as it will store it
  /// (`shared/format/bio.dart`, the twin of the server's cleaning — review
  /// profile-header LOW: counting the raw text blocked Save early).
  int get _bioLength => bioLength(normalizeBio(_bio.text) ?? '');

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  /// [withBio]: the field was shown (the privacy answer is known and the
  /// account isn't supervised) — only then may a bio be sent.
  Future<void> _save(bool withBio) async {
    final name = _name.text.trim();
    final username = _username.text.trim().toLowerCase();
    if (name.isEmpty) {
      setState(() => _error = l10n.profile_displayNameIsRequired);
      return;
    }
    // Only a bio that changed is sent (never from a supervised account, nor
    // before we know whether it is one), so a name change can't be held up
    // by it.
    final bio = normalizeBio(_bio.text);
    final bioChanged = withBio && bio != normalizeBio(widget.profile.bio);
    if (bioChanged && _bioLength > bioMax) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).updateMe({
        'displayName': name,
        if (username.isNotEmpty && username != widget.profile.username)
          'username': username,
        if (bioChanged) 'bio': bio,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    // The bio field only once we KNOW the account isn't supervised (review
    // LOW: while the privacy answer loads, or if it failed, a supervised teen
    // got the field, and saving a bio then failed the whole edit).
    final privacy = ref.watch(myPrivacyProvider);
    final supervised = privacy.valueOrNull?.applies == true;
    final withBio = privacy.hasValue && !privacy.hasError && !supervised;
    final over = withBio && _bioLength > bioMax;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Grabber(),
            const SizedBox(height: 16),
            Text(context.l10n.profile_editProfile,
                style: TextStyle(
                    color: p.ink, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: context.l10n.profile_displayName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              decoration: InputDecoration(
                labelText: context.l10n.profile_username,
                prefixText: '@',
                helperText: context.l10n.profile_lettersNumbersUnderscores,
              ),
            ),
            const SizedBox(height: 12),
            if (!withBio && !supervised)
              const SizedBox.shrink()
            else if (supervised)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                    color: p.surface, borderRadius: BorderRadius.circular(16)),
                child: Text(context.l10n.profile_bioSupervisedNote,
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
              )
            else
              // No maxLength: it counts what a person sees as one character
              // and the server counts code points (mobile-app.md) — our own
              // counter instead, red past the limit, and Save waits.
              TextField(
                controller: _bio,
                minLines: 2,
                maxLines: 4,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.l10n.profile_bio,
                  hintText: context.l10n.profile_bioPlaceholder,
                  alignLabelWithHint: true,
                  counterText: '$_bioLength/$bioMax',
                  counterStyle: TextStyle(
                      color: over ? p.danger : p.muted, fontSize: 11.5),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
            ],
            const SizedBox(height: 16),
            SpButton(
              label: _busy ? context.l10n.profile_saving : context.l10n.profile_save,
              expand: true,
              onTap: _busy || over ? null : () => _save(withBio),
            ),
            const SizedBox(height: 10),
            // Social links save on their own (docs/design/scouting-profile.md),
            // so a handle typo never blocks a name change.
            Material(
              color: p.surface,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).pop();
                  context.push('/profile/links');
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    Icon(Icons.link_rounded, size: 20, color: p.ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.l10n.profile_socialLinks,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          Text(
                              widget.profile.links.isEmpty
                                  ? context.l10n.profile_instagramTikTokXFacebookThreads
                                  : context.l10n.profile_onYourProfile(widget.profile.links.length),
                              style:
                                  TextStyle(color: p.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: p.muted),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// My groups grid — crest, name, member count, role badge.
// ---------------------------------------------------------------------------

/// Your groups, each opening YOUR record in that group — where you also set
/// the name that group knows you by. The group itself stays one tap away, as
/// the chip on the right.
class _MyGroupsList extends StatelessWidget {
  const _MyGroupsList({
    required this.groups,
    required this.akas,
    required this.userId,
    required this.loading,
    required this.failed,
    required this.retrying,
    required this.onRetry,
  });

  final List<GroupSummary> groups;
  final Map<String, String> akas;
  final String? userId;

  /// No answer yet / the request failed (and nothing was loaded before).
  final bool loading;
  final bool failed;

  /// Try again was tapped and the re-read is on its way.
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (loading) {
      return _EmptyNote(
        icon: Icons.groups_outlined,
        text: context.l10n.profile_loading,
      );
    }
    if (failed) {
      return Column(children: [
        _EmptyNote(
          icon: Icons.groups_outlined,
          text: context.l10n.common_couldNotLoadGroups,
        ),
        const SizedBox(height: 10),
        ProfilePill(
          label: context.l10n.profile_tryAgain,
          icon: Icons.refresh_rounded,
          compact: true,
          busy: retrying,
          onTap: onRetry,
        ),
      ]);
    }
    if (groups.isEmpty) {
      return _EmptyNote(
        icon: Icons.groups_outlined,
        text: context.l10n.profile_youreNotInAnyGroups,
      );
    }
    return SpListCard(children: [
      for (final g in groups)
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: userId == null
              ? null
              : () => context.push('/players/$userId/groups/${g.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Crest(logoUrl: g.logoUrl, label: g.name, size: 44),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(g.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                      ),
                      if (g.role == 'admin') ...[
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
                    Text(
                        akas[g.id] != null
                            ? context.l10n.profile_knownHereAs(akas[g.id] ?? '')
                            : context.l10n.profile_seeYourRecordHere,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // The group itself, one tap away.
              Material(
                color: p.surface2,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => context.push('/groups/${g.id}'),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
    ]);
  }
}

/// Loading / error aren't scrollable on their own, so they get a pullable
/// wrapper; once the data shows, its own RefreshIndicator takes over.
Widget _pullableUnlessData(BuildContext context, AsyncValue<Object?> v,
        Future<void> Function() onRefresh, Widget child) =>
    v.hasValue && !v.hasError
        ? child
        : RefreshIndicator(
            onRefresh: onRefresh,
            child: PullableState(
                bottomPadding: SpDock.spaceBelow(context), child: child));
