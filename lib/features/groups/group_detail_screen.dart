import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/links/web_handoff.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart';
import 'package:sportpadi_mobile/data/discussions/discussions_repository.dart'
    show DiscussionListKey, discussionListProvider, discussionSpacesProvider;
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/groups/membership_requests_repository.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/messages/messages_repository.dart'
    show messageStartOptionsProvider;
import 'package:sportpadi_mobile/data/progression/progression_repository.dart'
    show groupProgressionProvider;
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/features/teams/sport_cards.dart';
import 'package:sportpadi_mobile/features/tournaments/tournament_modes.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_tab_track.dart';
import 'package:sportpadi_mobile/data/billing/iap_repository.dart';
import 'package:sportpadi_mobile/features/announcements/announcement_entry_points.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/ads/ad_anchor.dart';
import 'package:sportpadi_mobile/features/groups/group_admin_sheets.dart';
import 'package:sportpadi_mobile/data/groups/group_admin_repository.dart';
import 'package:sportpadi_mobile/features/groups/group_invitations.dart';
import 'package:sportpadi_mobile/features/groups/group_talk_section.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/groups/plan_gate.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart'
    show ShellBottomBar;
import 'package:url_launcher/url_launcher.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/event_tile.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/core/referral/referral.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/verified_badge.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/sheet_scroll.dart';

/// Group header geometry: cover banner height and how far the avatar/stats
/// row hangs below it.
const double _kCoverHeight = 210;
const double _kHeaderOverhang = 56;

/// Pull to refresh on the group page. A pull on any tab refetches everything
/// the page shows: the group, the header's sections (pinned announcements,
/// overview tiles, Talk tiles, reputation, the requests / invite badges) and
/// every tab's data. The spinner waits for the group, those always-shown
/// sections and the pulled tab's own data ([tab], read after the
/// invalidation so it's the fresh fetch).
Future<void> _refreshGroupPage(
    WidgetRef ref, String groupId, List<Future<Object?>> Function() tab) {
  final PinnedKey pinned = (groupId: groupId, teamId: null);
  // The Talk tile's "hot" discussions (GroupTalkSection's key).
  final DiscussionListKey hot = (
    groupId: groupId,
    space: '',
    sort: 'hot',
    flair: null,
    status: null,
  );
  // Header.
  ref.invalidate(groupProvider(groupId));
  ref.invalidate(eventAudiencesProvider(groupId));
  ref.invalidate(membershipRequestCountProvider(groupId));
  ref.invalidate(groupInviteForProvider(groupId));
  ref.invalidate(pinnedAnnouncementsProvider(pinned));
  ref.invalidate(groupOverviewProvider(groupId));
  ref.invalidate(groupTalkCountsProvider(groupId));
  ref.invalidate(announcementComposerProvider(groupId));
  ref.invalidate(mutedAnnouncementGroupsProvider);
  ref.invalidate(messageStartOptionsProvider(groupId));
  ref.invalidate(discussionSpacesProvider(groupId));
  ref.invalidate(discussionListProvider(hot));
  ref.invalidate(groupProgressionProvider(groupId));
  // Tabs.
  ref.invalidate(groupEventsProvider(groupId));
  ref.invalidate(groupTeamsProvider(groupId));
  ref.invalidate(teamAllowanceProvider(groupId));
  ref.invalidate(groupTournamentsProvider(groupId));
  ref.invalidate(groupLeaguesProvider(groupId));
  ref.invalidate(groupTeamLeaguesProvider(groupId));
  ref.invalidate(groupInvitesProvider(groupId));
  return settleAll([
    ref.read(groupProvider(groupId).future),
    ref.read(pinnedAnnouncementsProvider(pinned).future),
    ref.read(groupOverviewProvider(groupId).future),
    ref.read(groupTalkCountsProvider(groupId).future),
    ref.read(announcementComposerProvider(groupId).future),
    ref.read(messageStartOptionsProvider(groupId).future),
    ref.read(discussionSpacesProvider(groupId).future),
    ref.read(groupProgressionProvider(groupId).future),
    ...tab(),
  ]);
}

/// What a pull on the page refreshes for the OPEN tab, on top of the group
/// itself (the tabs are box slivers in one scroll view now, so there's one
/// RefreshIndicator for the page rather than one per tab).
List<Future<Object?>> _tabRefreshFutures(
        WidgetRef ref, String groupId, int tab, bool canManage) =>
    switch (tab) {
      0 => [ref.read(groupEventsProvider(groupId).future)],
      1 => [
          ref.read(groupTeamsProvider(groupId).future),
          if (canManage) ref.read(teamAllowanceProvider(groupId).future),
        ],
      _ => [
          ref.read(groupTournamentsProvider(groupId).future),
          ref.read(groupLeaguesProvider(groupId).future),
          ref.read(groupTeamLeaguesProvider(groupId).future),
          if (canManage) ref.read(groupInvitesProvider(groupId).future),
        ],
    };

/// Whether [AsyncView] would show its (non-scrolling) loader or error for
/// [value] rather than the data.
bool _bare(AsyncValue<Object?> value) =>
    value.when(data: (_) => false, error: (_, __) => true, loading: () => true);

/// The whole group page while it shows a loader or an error (no tabs yet to
/// pull on): still pullable.
Widget _pullablePage(WidgetRef ref, String groupId, AsyncValue<Object?> group,
        Widget view) =>
    _bare(group)
        ? RefreshIndicator(
            onRefresh: () => _refreshGroupPage(ref, groupId, () => []),
            child: PullableState(child: view),
          )
        : view;

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId, this.initialTab});
  final String groupId;

  /// `?tab=teams|tournaments|leagues` (notification deep links).
  final String? initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupProvider(groupId));
    final p = context.palette;
    // Leagues (organised, and the ones the group's teams play in) live under
    // Tournaments → League now; an old ?tab=leagues lands on Tournaments.
    const tabCount = 3;
    final startTab = switch (initialTab) {
      'teams' => 1,
      'tournaments' || 'leagues' => 2,
      _ => 0,
    };
    return Scaffold(
      backgroundColor: p.bg,
      // Keep the dock in reach here: Groups is lit, and any tab jumps back
      // to the shell on that tab.
      bottomNavigationBar: ShellBottomBar(
        index: 2,
        onSelect: (i) => ShellBottomBar.goToTab(context, ref, i),
      ),
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          _pullablePage(
              ref,
              groupId,
              group,
              AsyncView(
                value: group,
                onRetry: () => ref.invalidate(groupProvider(groupId)),
                data: (g) => DefaultTabController(
                  key: const ValueKey('group-tabs-$tabCount'),
                  length: tabCount,
                  initialIndex: startTab,
                  // ONE scroll view for the whole page: header (cover,
                  // identity card, tools), the pinned tab switch, then the
                  // open tab's content as an ordinary box sliver. The page
                  // is exactly as tall as what's on it — a tab with one card
                  // ends after that card instead of pinning the tabs at the
                  // top over a screen of nothing (what NestedScrollView +
                  // TabBarView did: its body is always viewport-tall).
                  // Same shape as the profile screen.
                  child: Builder(builder: (context) {
                    final tabs = DefaultTabController.of(context);
                    return AnimatedBuilder(
                      animation: tabs,
                      builder: (context, _) => RefreshIndicator(
                        onRefresh: () => _refreshGroupPage(
                            ref,
                            groupId,
                            () => _tabRefreshFutures(
                                ref, groupId, tabs.index, g.canManage)),
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverToBoxAdapter(child: _Header(group: g)),
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _PinnedTabBar(
                                backgroundColor: p.bg,
                                child: Container(
                                  color: p.bg,
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 6, 20, 6),
                                  // Scrolls sideways only when the tabs
                                  // don't fit (e.g. Leagues on a narrow
                                  // phone); otherwise they share the width.
                                  child: const SpTabTrack(labels: [
                                    'Events',
                                    'Teams',
                                    'Tournaments',
                                  ]),
                                ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: switch (tabs.index) {
                                0 => _EventsTab(groupId: groupId),
                                1 => _TeamsTab(
                                    groupId: groupId, canManage: g.canManage),
                                _ => _TournamentsTab(
                                    groupId: groupId, canManage: g.canManage),
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              )),
          // While loading (or on error) there's no cover to carry the back
          // button — keep one on screen regardless.
          if (_bare(group))
            Positioned(
              left: 16,
              top: 12,
              child: SpRoundButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                tooltip: 'Back',
                onTap: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
              ),
            ),
        ]),
      ),
    );
  }
}

class _Header extends ConsumerStatefulWidget {
  const _Header({required this.group});
  final GroupDetail group;

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> with WidgetsBindingObserver {
  String? _uploading; // 'logo' | 'cover'

  // Back-on-top detection: the router's changes, checked against this
  // page's route once the frame has settled.
  GoRouter? _router;
  ModalRoute<dynamic>? _route;
  bool _onTop = true;

  GroupDetail get group => widget.group;
  String get groupId => group.id;
  String get name => group.name;
  String? get description => group.description;
  String? get logoUrl => group.logoUrl;
  bool get canManage => group.canManage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final router = GoRouter.of(context);
    if (!identical(router, _router)) {
      _router?.routerDelegate.removeListener(_onRouteChanged);
      _router = router;
      router.routerDelegate.addListener(_onRouteChanged);
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshLive();
  }

  /// The router moved (a push or a pop somewhere): once the frame has
  /// settled, see whether this page just came back on top.
  void _onRouteChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final onTop = _route?.isCurrent ?? true;
      if (onTop && !_onTop) _refreshLive();
      _onTop = onTop;
    });
  }

  /// What can change while the page is out of sight: the Talk badges, the
  /// pinned announcements (opening one marks it seen), the owner's pending
  /// requests — and, while my own request is pending, the group itself
  /// (an approval makes me a member).
  void _refreshLive() {
    ref.invalidate(groupTalkCountsProvider(groupId));
    ref.invalidate(
        pinnedAnnouncementsProvider((groupId: groupId, teamId: null)));
    if (group.isOwner) {
      ref.invalidate(membershipRequestCountProvider(groupId));
    }
    if (group.hasPendingRequest) ref.invalidate(groupProvider(groupId));
  }

  Future<void> _pickAndUpload(String kind) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: kind == 'cover' ? 1800 : 800,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _uploading = kind);
    try {
      final bytes = await picked.readAsBytes();
      final url = await ref.read(eventsRepositoryProvider).uploadImage(
            bytes,
            picked.mimeType ?? 'image/jpeg',
            assetType: 'groupImage',
            scopeId: groupId,
          );
      await ref.read(groupsRepositoryProvider).updateGroup(
          groupId, {kind == 'cover' ? 'coverImageUrl' : 'imageUrl': url});
      ref.invalidate(groupProvider(groupId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Widget _cameraBadge(String kind, {double size = 28}) {
    final p = context.palette;
    return Material(
      color: p.hero,
      shape: CircleBorder(side: BorderSide(color: p.surface, width: 2)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _uploading != null ? null : () => _pickAndUpload(kind),
        child: SizedBox(
          width: size,
          height: size,
          child: _uploading == kind
              ? const Padding(
                  padding: EdgeInsets.all(7),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Icon(Icons.photo_camera_rounded,
                  size: size * 0.5, color: Colors.white),
        ),
      ),
    );
  }

  void _share() {
    final base = ref.read(appConfigProvider).apiBaseUrl;
    final me = ref.read(meProvider).valueOrNull?.userId;
    Clipboard.setData(ClipboardData(
        text: withRef('$base/groups/$groupId', me, 'group', groupId)));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Group link copied')));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Server counts, falling back to the events feed length while loading.
    final eventsCount = group.eventsCount ??
        ref.watch(groupEventsProvider(groupId)).valueOrNull?.length;
    final memberCount = group.memberCount;
    final followerCount = group.followerCount;
    final canPop = context.canPop() || Navigator.of(context).canPop();
    final signedIn =
        ref.watch(authControllerProvider).valueOrNull?.isAuthenticated ?? false;
    final desc = description?.trim() ?? '';
    // Coaches (members who don't manage the group) can create events for
    // the teams they coach.
    final coachCanCreate = !canManage &&
        group.isMember &&
        (ref.watch(eventAudiencesProvider(groupId)).valueOrNull?.canCreate ??
            false);

    final cover = ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: SizedBox(
        height: _kCoverHeight,
        width: double.infinity,
        child: Stack(fit: StackFit.expand, children: [
          group.coverImageUrl != null
              ? Image.network(group.coverImageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const _CoverWash())
              : const _CoverWash(),
          // Shade the top so the round buttons read on any photo.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x59000000), Color(0x00000000)],
                  stops: [0.0, 0.5],
                ),
              ),
            ),
          ),
        ]),
      ),
    );

    Widget stat(String value, String label, {VoidCallback? onTap}) => Expanded(
          child: Material(
            color: p.surface2,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Column(children: [
                  Text(value,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 19,
                          height: 1.1,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 11)),
                ]),
              ),
            ),
          ),
        );

    final identity = GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: p.surface, width: 3),
                ),
                child: Crest(logoUrl: logoUrl, label: name, size: 64),
              ),
              if (canManage)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _cameraBadge('logo', size: 26),
                ),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 20,
                          height: 1.2,
                          letterSpacing: -0.2,
                          fontWeight: FontWeight.w800)),
                ),
                if (group.isVerified) ...[
                  const SizedBox(width: 5),
                  VerifiedBadgeButton(size: 20, groupName: name),
                ],
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(
                  child: Text(
                      group.isOwner
                          ? 'You own this group'
                          : canManage
                              ? 'You manage this group'
                              : group.isMember
                                  ? 'You\'re a member'
                                  : group.isFollower
                                      ? 'You follow this group'
                                      : 'Public group',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 12.5)),
                ),
                // Members (not staff — theirs is in the ⋯ menu) can leave.
                if (group.isMember && !canManage && !group.isOwner)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => confirmLeaveGroup(context, ref, groupId, name),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
                      child: Text('· Leave',
                          style: TextStyle(
                              color: p.danger,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ]),
          ),
        ]),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(desc,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.5)),
        ],
        const SizedBox(height: 14),
        Row(children: [
          stat(eventsCount?.toString() ?? '–', 'Events',
              onTap: () => context.push('/groups/$groupId/events')),
          const SizedBox(width: 8),
          stat(memberCount?.toString() ?? '–', 'Members',
              onTap: () => context.push('/groups/$groupId/members')),
          const SizedBox(width: 8),
          stat(followerCount?.toString() ?? '–', 'Followers',
              onTap: canManage
                  ? () => context.push('/groups/$groupId/followers')
                  : null),
        ]),
        if (canManage) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: SpButton(
                label: 'New event',
                icon: Icons.add_rounded,
                expand: true,
                onTap: () => context.push('/groups/$groupId/new-event'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _OutlineButton(
                label: 'Invite',
                icon: Icons.person_add_alt_rounded,
                onTap: () => _openInvite(context),
              ),
            ),
            const SizedBox(width: 8),
            _ManageMenu(groupId: groupId, isOwner: group.isOwner),
          ]),
        ] else if (coachCanCreate) ...[
          const SizedBox(height: 14),
          SpButton(
            label: 'New team event',
            icon: Icons.add_rounded,
            expand: true,
            onTap: () => context.push('/groups/$groupId/new-event'),
          ),
        ] else if (!group.isMember) ...[
          // Invited by an admin: accept / decline right here.
          if (signedIn) GroupInviteBanner(groupId: groupId),
          const SizedBox(height: 14),
          _FollowButton(groupId: groupId, initialFollowing: group.isFollower),
          // Followers (and visitors) can ask the owner to let them in.
          if (signedIn) ...[
            const SizedBox(height: 10),
            _JoinRequestControl(group: group),
          ],
        ],
        // An owner who doesn't manage the group still decides who joins
        // (managers find it in the ⋯ menu).
        if (group.isOwner && !canManage) ...[
          const SizedBox(height: 10),
          _MembershipRequestsButton(groupId: groupId),
        ],
      ]),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(children: [
          Positioned(left: 0, right: 0, top: 0, child: cover),
          Positioned(
            left: 16,
            top: 12,
            child: SpRoundButton(
              icon: canPop
                  ? Icons.arrow_back_ios_new_rounded
                  : Icons.home_outlined,
              iconSize: canPop ? 18 : 21,
              tooltip: canPop ? 'Back' : 'Home',
              onTap: () =>
                  context.canPop() ? context.pop() : context.go('/home'),
            ),
          ),
          Positioned(
            right: 16,
            top: 12,
            child: Row(children: [
              if (canManage) ...[
                _cameraBadge('cover', size: 44),
                const SizedBox(width: 8),
              ],
              // Members: mute this group's announcements (and, for staff,
              // compose / sent).
              if (group.isMember || canManage) ...[
                GroupAnnouncementsButton(groupId: groupId, groupName: name),
                const SizedBox(width: 8),
              ],
              SpRoundButton(
                  icon: Icons.ios_share_rounded,
                  tooltip: 'Share',
                  onTap: _share),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                16, _kCoverHeight - _kHeaderOverhang, 16, 0),
            child: identity,
          ),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Pinned announcements first — above the overview tiles
              // (Leaderboard, Wallet…) — for members and followers alike (the
              // server decides what each one gets). At most two; the rest
              // behind "See all".
              GroupPinnedAnnouncementsSection(
                groupId: groupId,
                padding: const EdgeInsets.only(top: 4, bottom: 18),
              ),
              _OverviewSection(groupId: groupId, canManage: canManage),
              // Talk: Announcements (Open Inbox, Announce / Sent, mute),
              // Messages (Contact the admins / Message coach / Message a
              // member / Conversations) and Discussions as three tiles with
              // notification badges, each opening a sheet — so they don't
              // crowd the page. Messages and Discussions are for members.
              GroupTalkSection(
                groupId: groupId,
                groupName: name,
                isMember: group.isMember || canManage,
              ),
              // Owner-console ad spot (anchor "group.detail_bottom"); nothing unless set.
              const AdAnchor(
                  anchor: 'group.detail_bottom',
                  padding: EdgeInsets.only(top: 14)),
              // Group reputation (gamification): level, streak, achievements.
              GroupReputationCard(groupId: groupId),
            ],
          ),
        ),
      ],
    );
  }

  void _openInvite(BuildContext context) =>
      showGroupInviteSheet(context, groupId);
}

/// The admin's "Invite people" sheet (group page and the Members page).
void showGroupInviteSheet(BuildContext context, String groupId) {
  showSpSheet<void>(
    context,
    framed: false,
    builder: (_) => _InviteSheet(groupId: groupId),
  );
}

/// "+ New tournament" for every group. Entitled groups go straight to the
/// creation flow (same behaviour as web).
///
/// A gated group gets an explainer. On iOS that explainer offers the plan,
/// because the plan is now an in-app purchase and pointing at it is exactly
/// what Apple wants. On other platforms there is nothing to sell in-app, so it
/// stays neutral and the server emails the admin out of band. Server-side
/// enforcement still guards actual creation either way.
void _handleNewTournament(BuildContext context, WidgetRef ref, String groupId) {
  final ov = ref.read(groupOverviewProvider(groupId)).valueOrNull;
  // Fail open when the overview hasn't resolved — the server still enforces.
  final allowed = ov?.canCreateTournaments ?? true;
  if (allowed) {
    context.push('/groups/$groupId/new-tournament');
    return;
  }
  // No tournaments on the plan, but leagues are: straight to New league.
  final leaguesOn =
      ref.read(leagueSetupProvider(groupId)).valueOrNull?.b('enabled') ?? false;
  if (leaguesOn) {
    context.push('/groups/$groupId/new-league');
    return;
  }
  showPlanLockedDialog(context, ref, groupId,
      title: "Tournaments aren't enabled for this group",
      body: 'Tournament events — brackets, friendlies and inviting teams from '
          "other groups — aren't switched on for this group yet.");
}

class _ManageMenu extends ConsumerWidget {
  const _ManageMenu({required this.groupId, required this.isOwner});
  final String groupId;

  /// The creator: transfer ownership, and the membership-requests queue.
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    // Requests waiting on the owner: a badge on the menu and on its item.
    final pending = isOwner
        ? ref.watch(membershipRequestCountProvider(groupId)).valueOrNull ?? 0
        : 0;
    // The profile page's menu: a bottom sheet (the popup used to clip
    // against the screen edge lower down the page).
    final menu = SpRoundButton(
      icon: Icons.more_horiz_rounded,
      tooltip: 'Manage',
      onTap: () => showSpSheet<void>(
        context,
        framed: false,
        builder: (ctx) => _ManageMenuSheet(
          groupId: groupId,
          isOwner: isOwner,
          pending: pending,
          onPick: (v) {
            Navigator.pop(ctx);
            _act(context, ref, v);
          },
        ),
      ),
    );
    return Stack(clipBehavior: Clip.none, children: [
      menu,
      if (pending > 0)
        Positioned(
          top: -4,
          right: -4,
          child: IgnorePointer(
            child: _CountBadge(count: pending, border: p.surface),
          ),
        ),
    ]);
  }

  void _act(BuildContext context, WidgetRef ref, String v) {
    switch (v) {
      case 'link':
        final base = ref.read(appConfigProvider).apiBaseUrl;
        final me = ref.read(meProvider).valueOrNull?.userId;
        Clipboard.setData(ClipboardData(
            text: withRef('$base/join/$groupId', me, 'group', groupId)));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Membership link copied — anyone with it can join.')));
        break;
      case 'edit':
        showSpSheet<void>(
          context,
          framed: false,
          builder: (_) => _EditGroupSheet(groupId: groupId),
        );
        break;
      case 'wallet':
        context.push('/groups/$groupId/wallet');
        break;
      case 'plan':
        context.push('/groups/$groupId/plan');
        break;
      case 'team':
        context.push('/groups/$groupId/new-team');
        break;
      case 'tournament':
        _handleNewTournament(context, ref, groupId);
        break;
      case 'invites':
        context.push('/groups/$groupId/invites');
        break;
      case 'fines':
        context.push('/groups/$groupId/fines');
        break;
      case 'upgrade':
        // Android: the plan is bought on the web (Stripe). Opened in a
        // Custom Tab so the return trip lands back in the app.
        // Signed in already (one-tap hand-off), no second login.
        signedInWebUriFor(ref, webPayPath(groupId, 'upgrade')).then(
            (url) => launchUrl(url, mode: LaunchMode.inAppBrowserView));
        break;
      case 'promo':
        showPromoCodesSheet(context, groupId);
        break;
      case 'pro':
        showProOfferSheet(context, groupId,
            ref.read(groupProvider(groupId)).valueOrNull?.name ?? 'your group');
        break;
      case 'transfer':
        showTransferOwnershipSheet(context, groupId);
        break;
      case 'leave':
        if (isOwner) {
          showTransferOwnershipSheet(context, groupId);
        } else {
          confirmLeaveGroup(context, ref, groupId,
              ref.read(groupProvider(groupId)).valueOrNull?.name ?? 'this group');
        }
        break;
      case 'requests':
        context.push('/groups/$groupId/requests');
        break;
    }
  }
}

/// The group's manage menu as a bottom sheet — same design as the profile
/// menu: the group's crest and name, three quick actions, then grouped rows.
/// The web menu, with two App Store exceptions: "Upgrade plan" (web) is
/// "Group plan" (in-app purchase) on iOS, and promo codes that unlock paid
/// features are Android-only (3.1.1).
class _ManageMenuSheet extends ConsumerWidget {
  const _ManageMenuSheet({
    required this.groupId,
    required this.isOwner,
    required this.pending,
    required this.onPick,
  });
  final String groupId;
  final bool isOwner;
  final int pending;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final group = ref.watch(groupProvider(groupId)).valueOrNull;
    final ov = ref.watch(groupOverviewProvider(groupId)).valueOrNull;
    // Fail open while the overview loads — the server still enforces.
    final canTournaments = ov?.canCreateTournaments ?? true;
    // Team building: plan OR promo code (same rule as web + server).
    final canTeams =
        ref.watch(teamAllowanceProvider(groupId)).valueOrNull?.canBuild ?? true;
    final ios = IapRepository.supportedPlatform;
    // The Free plan's "Try Pro features for free" (Android; not once on).
    final offer = ios ? null : ref.watch(freeOfferProvider(groupId)).valueOrNull;
    final showOffer = offer != null && !offer.isOn;

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
            Color fg,
            {int badge = 0}) =>
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
              if (badge > 0) ...[
                _CountBadge(count: badge),
                const SizedBox(width: 6),
              ],
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
              const SpGrabber(),
              const SizedBox(height: 16),
              Row(children: [
                ClipOval(
                  child: Crest(
                      logoUrl: group?.logoUrl,
                      label: group?.name ?? 'Group',
                      size: 46),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group?.name ?? 'Group',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      Text(isOwner ? 'Owner · manage this group' : 'Admin · manage this group',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                SpRoundButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Close',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                quick('wallet', Icons.account_balance_wallet_outlined, 'Wallet'),
                const SizedBox(width: 8),
                quick('fines', Icons.gavel_rounded, 'Fines'),
                const SizedBox(width: 8),
                quick(ios ? 'plan' : 'upgrade', Icons.workspace_premium_outlined,
                    ios ? 'Plan' : 'Upgrade'),
              ]),
              const SizedBox(height: 18),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Eyebrow('Group'),
              ),
              SpListCard(children: [
                if (showOffer)
                  row(
                      'pro',
                      Icons.auto_awesome_rounded,
                      offer.status == 'opted_out'
                          ? 'Switch Pro features back on'
                          : 'Try Pro features for free',
                      'Free while SportPadi runs the offer',
                      p.accentTint,
                      p.greenText),
                row('edit', Icons.edit_outlined, 'Edit group',
                    'Name, logo, description and settings', p.surface2, p.ink),
                row('link', Icons.link_rounded, 'Copy membership link',
                    'Anyone with it can join', p.accentTint, p.greenText),
                if (!ios)
                  row('promo', Icons.confirmation_number_outlined,
                      'Promo codes', 'Apply a code to this group',
                      p.orangeTint, p.orangeInk),
                if (isOwner)
                  row('requests', Icons.how_to_reg_outlined,
                      'Membership requests',
                      pending > 0
                          ? '$pending waiting for you'
                          : 'People asking to join',
                      p.surface2, p.ink,
                      badge: pending),
                if (isOwner)
                  row('transfer', Icons.swap_horiz_rounded,
                      'Transfer ownership', 'Hand the group to another admin',
                      p.surface2, p.ink),
              ]),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Eyebrow('Teams & tournaments'),
              ),
              SpListCard(children: [
                if (canTeams)
                  row('team', Icons.shield_outlined, 'New team',
                      'Build a team from your members', p.accentTint,
                      p.greenText),
                // Tournaments are a plan feature. On a tier without them the
                // row is offered only where tapping it can lead somewhere —
                // the in-app plans screen on iOS. Elsewhere it's hidden,
                // same as the web tab hides its button.
                if (canTournaments || ios)
                  row(
                      'tournament',
                      Icons.emoji_events_outlined,
                      'New tournament',
                      canTournaments
                          ? 'Brackets, friendlies and leagues'
                          : 'Not on this plan',
                      p.orangeTint,
                      p.orangeInk),
                row('invites', Icons.mail_outline_rounded,
                    'Tournament invites', 'Invitations from other groups',
                    p.surface2, p.ink),
              ]),
              const SizedBox(height: 16),
              // The owner hands the group over before leaving.
              SpListCard(children: [
                row(
                    'leave',
                    Icons.logout_rounded,
                    'Leave group',
                    isOwner
                        ? 'Transfer ownership first'
                        : 'Stop being a member',
                    p.liveTint,
                    p.danger),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// A notification-style count pill ("9+" above 9).
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.border});
  final int count;

  /// A ring in the surface colour, when the pill sits on another widget.
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ring = border;
    return Container(
      height: 20,
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: p.accentDeep,
        borderRadius: BorderRadius.circular(10),
        border: ring != null ? Border.all(color: ring, width: 2) : null,
      ),
      child: Text(count > 9 ? '9+' : '$count',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w800)),
    );
  }
}

/// The group page's Events tab (web: the group page's events tab): an
/// "Upcoming · N" title with New (admins, and coaches for their teams) and
/// View all, then the 2026 event tiles in two columns — the same tile as
/// Browse. No upcoming events: say so, with a way to the past ones.
class _EventsTab extends ConsumerWidget {
  const _EventsTab({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final events = ref.watch(groupEventsProvider(groupId));
    final group = ref.watch(groupProvider(groupId)).valueOrNull;
    final canCreate = group?.canManage == true ||
        (group?.isMember == true &&
            (ref
                    .watch(eventAudiencesProvider(groupId))
                    .valueOrNull
                    ?.canCreate ??
                false));
    final list = events.valueOrNull;

    final header = SpSectionTitle(
      'Upcoming',
      count: list?.length,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (canCreate) ...[
          SpPill(
            label: 'New',
            icon: Icons.add_rounded,
            height: 32,
            onTap: () => context.push('/groups/$groupId/new-event'),
          ),
          const SizedBox(width: 4),
        ],
        TextButton(
          onPressed: () => context.push('/groups/$groupId/events'),
          style: TextButton.styleFrom(
              foregroundColor: p.greenText,
              visualDensity: VisualDensity.compact),
          child: const Text('View all',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ]),
    );

    Widget body;
    if (list == null && events.isLoading) {
      body = Row(children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 230,
              decoration: BoxDecoration(
                  color: p.surface2, borderRadius: BorderRadius.circular(22)),
            ),
          ),
        ],
      ]);
    } else if (list == null) {
      body = GlassCard(
        child: Column(children: [
          Text('Could not load events.',
              style: TextStyle(color: p.muted, fontSize: 13.5)),
          TextButton(
              onPressed: () => ref.invalidate(groupEventsProvider(groupId)),
              child: const Text('Try again')),
        ]),
      );
    } else if (list.isEmpty) {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SpEmpty(
          icon: Icons.calendar_today_outlined,
          text: canCreate
              ? 'No upcoming events — create one to get started.'
              : 'No upcoming events.',
        ),
        const SizedBox(height: 10),
        Center(
          child: SpPill(
            label: 'Past events',
            tone: SpPillTone.soft,
            height: 34,
            onTap: () => context.push('/groups/$groupId/events'),
          ),
        ),
      ]);
    } else {
      body = EventTileGrid(events: list, showGroup: false);
    }

    // A box, not a scroll view: the page's CustomScrollView does the
    // scrolling and the pull-to-refresh.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 10),
          body,
        ],
      ),
    );
  }
}

class _TeamsTab extends ConsumerStatefulWidget {
  const _TeamsTab({required this.groupId, this.canManage = false});
  final String groupId;
  final bool canManage;

  @override
  ConsumerState<_TeamsTab> createState() => _TeamsTabState();
}

/// A group's teams (2026): like the Tournaments tab, a grid of cards — New
/// team (admins), then one card per sport the group has a team in — each
/// opening that sport's screen of teams with search
/// (features/teams/sport_cards.dart; web components/groups/SportCards.tsx).
class _TeamsTabState extends ConsumerState<_TeamsTab> {
  void _newTeam([String? categoryId]) => context.push(
      '/groups/${widget.groupId}/new-team${categoryId != null ? '?category=$categoryId' : ''}');

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(groupTeamsProvider(widget.groupId));
    final p = context.palette;
    // Plan OR promo code decides what admins may build (same rule as web and
    // the server): nothing, one team per sport, or many.
    final allow = widget.canManage
        ? ref.watch(teamAllowanceProvider(widget.groupId)).valueOrNull
        : null;
    final canBuild = widget.canManage && (allow?.canBuild ?? false);
    final locked = widget.canManage && allow != null && !allow.canBuild;
    final view = AsyncView(
      value: teams,
      onRetry: () => ref.invalidate(groupTeamsProvider(widget.groupId)),
      data: (list) {
        final sports = {for (final t in list) t.categoryId}.length;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (list.isNotEmpty) ...[
              Text(
                  '${list.length} team${list.length == 1 ? '' : 's'} · $sports sport${sports == 1 ? '' : 's'}',
                  style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
            ],
            SportCardsGrid(
              groupId: widget.groupId,
              teams: list,
              onNew: widget.canManage ? () => _newTeam() : null,
              locked: locked && !canBuild,
              onLocked: () => context.push('/groups/${widget.groupId}/plan'),
            ),
          ]),
        );
      },
    );
    // A box, not a scroll view — see _EventsTab.
    return view;
  }
}

class _TournamentsTab extends ConsumerWidget {
  const _TournamentsTab({required this.groupId, this.canManage = false});
  final String groupId;
  final bool canManage;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the league plan check warm for "New tournament" (league option).
    if (canManage) ref.watch(leagueSetupProvider(groupId));
    // Admins whose plan has neither tournaments nor leagues see a locked card
    // (its tap explains / offers the plan — _handleNewTournament).
    final ov = ref.watch(groupOverviewProvider(groupId)).valueOrNull;
    final leaguesOn = ref.watch(leagueSetupProvider(groupId)).valueOrNull?.b('enabled') ?? false;
    final locked = canManage && ov != null && !ov.canCreateTournaments && !leaguesOn;
    // Web shows pending invites inline on this tab; on mobile they live on
    // their own screen, so at least say how many are waiting.
    final pending = canManage
        ? ref.watch(groupInvitesProvider(groupId)).valueOrNull ?? const []
        : const [];
    // A box, not a scroll view — see _EventsTab.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (pending.isNotEmpty) ...[
          _PendingInvitesStrip(groupId: groupId, count: pending.length),
          const SizedBox(height: 12),
        ],
        // One card per mode — New tournament, 1v1 Friendly, Multi-team,
        // League — each opening its own screen (tournament_modes.dart).
        TournamentModeCards(
          groupId: groupId,
          locked: locked,
          onNew: canManage ? () => _handleNewTournament(context, ref, groupId) : null,
        ),
      ]),
    );
  }
}

/// "3 invitations waiting · Review" — the group Tournaments tab's pointer to
/// the invites screen.
class _PendingInvitesStrip extends StatelessWidget {
  const _PendingInvitesStrip({required this.groupId, required this.count});
  final String groupId;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: () => context.push('/groups/$groupId/invites'),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.orangeTint,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(children: [
          SpIconTile(Icons.mark_email_unread_outlined,
              bg: p.surface, fg: p.orangeInk, size: 38, iconSize: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count tournament invitation${count == 1 ? '' : 's'} waiting',
              style: TextStyle(
                  color: p.ink, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          Text('Review',
              style: TextStyle(
                  color: p.orangeInk,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
          Icon(Icons.chevron_right_rounded, size: 18, color: p.orangeInk),
        ]),
      ),
    );
  }
}

/// Brand gradient cover fallback.
class _CoverWash extends StatelessWidget {
  const _CoverWash();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E6B45), Color(0xFF17A65E)],
        ),
      ),
    );
  }
}

/// Follow / Following for visitors (non-members). Starts from the group's
/// own `isFollower` and confirms it with the follow endpoint.
class _FollowButton extends ConsumerStatefulWidget {
  const _FollowButton({required this.groupId, this.initialFollowing = false});
  final String groupId;
  final bool initialFollowing;

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool? _following;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialFollowing) _following = true;
    _load();
  }

  @override
  void didUpdateWidget(covariant _FollowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The group was re-read (asking to join follows it, for one).
    if (widget.initialFollowing != oldWidget.initialFollowing && !_busy) {
      _following = widget.initialFollowing;
    }
  }

  Future<void> _load() async {
    try {
      final st =
          await ref.read(eventsRepositoryProvider).followState(widget.groupId);
      if (mounted) setState(() => _following = st.following);
    } catch (_) {/* stays unknown */}
  }

  Future<void> _toggle() async {
    final was = _following ?? false;
    setState(() {
      _busy = true;
      _following = !was;
    });
    try {
      await ref.read(eventsRepositoryProvider).setFollow(widget.groupId, !was);
      // The header's "You follow this group" and the follower count.
      if (mounted) ref.invalidate(groupProvider(widget.groupId));
    } catch (e) {
      if (mounted) {
        setState(() => _following = was);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final following = _following ?? false;
    return Material(
      color: following ? p.surface2 : p.hero,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _busy || _following == null ? null : _toggle,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(following ? Icons.check_rounded : Icons.add_rounded,
                size: 18, color: following ? p.ink : p.onHero),
            const SizedBox(width: 6),
            Text(
              following ? 'Following' : 'Follow group',
              style: TextStyle(
                color: following ? p.ink : p.onHero,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "Request to join" for signed-in followers and visitors, and the state of
/// my request: pending → a "Requested" chip and "Cancel request"; declined
/// or cancelled → ask again. An approval makes me a member, which takes
/// this away (the page re-reads the group while a request is pending).
class _JoinRequestControl extends ConsumerStatefulWidget {
  const _JoinRequestControl({required this.group});
  final GroupDetail group;

  @override
  ConsumerState<_JoinRequestControl> createState() =>
      _JoinRequestControlState();
}

class _JoinRequestControlState extends ConsumerState<_JoinRequestControl> {
  bool _busy = false;

  String get _groupId => widget.group.id;

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _request() async {
    final sent = await showSpSheet<bool>(
      context,
      builder: (_) =>
          _RequestToJoinSheet(groupId: _groupId, groupName: widget.group.name),
    );
    if (sent != true || !mounted) return;
    ref.invalidate(groupProvider(_groupId));
    _snack('Request sent — the group owner will review it.');
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await ref.read(membershipRequestsRepositoryProvider).cancel(_groupId);
      if (!mounted) return;
      ref.invalidate(groupProvider(_groupId));
      _snack('Request cancelled.');
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final req = widget.group.membershipRequest;
    if (req != null && req.isPending) {
      return Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: p.accentTint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.hourglass_top_rounded, size: 15, color: p.greenText),
            const SizedBox(width: 6),
            Text('Requested',
                style: TextStyle(
                    color: p.greenText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              req.createdAt != null
                  ? 'Sent ${timeAgo(req.createdAt)}'
                  : 'Waiting for the owner',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 12)),
        ),
        TextButton(
          onPressed: _busy ? null : _cancel,
          child: const Text('Cancel request'),
        ),
      ]);
    }
    final declined = req?.status == 'declined';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OutlineButton(
          label: declined ? 'Request to join again' : 'Request to join',
          icon: Icons.how_to_reg_outlined,
          onTap: _busy ? null : _request,
        ),
        if (declined) ...[
          const SizedBox(height: 6),
          Text("Your last request wasn't approved — you can ask again.",
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 12)),
        ],
      ],
    );
  }
}

/// The ask: an optional note for the owner (≤300 characters). Pops `true`
/// once the request is in.
class _RequestToJoinSheet extends ConsumerStatefulWidget {
  const _RequestToJoinSheet({required this.groupId, required this.groupName});
  final String groupId;
  final String groupName;

  @override
  ConsumerState<_RequestToJoinSheet> createState() =>
      _RequestToJoinSheetState();
}

class _RequestToJoinSheetState extends ConsumerState<_RequestToJoinSheet> {
  static const _maxLength = 300;
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await ref
          .read(membershipRequestsRepositoryProvider)
          .request(widget.groupId, message: _message.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.how_to_reg_outlined,
          title: 'Request to join',
          subtitle: widget.groupName,
        ),
        Text(
            "The group's owner gets your request and decides. You'll follow "
            'the group while you wait.',
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.45)),
        const SizedBox(height: 14),
        TextField(
          controller: _message,
          maxLength: _maxLength,
          minLines: 3,
          maxLines: 5,
          enabled: !_sending,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Message (optional)',
            hintText: 'Say hello, or why you’d like to join',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        SpButton(
          label: _sending ? 'Sending…' : 'Send request',
          icon: Icons.send_rounded,
          expand: true,
          onTap: _sending ? null : _send,
        ),
      ],
    );
  }
}

/// The owner's way into the membership-requests queue (with the pending
/// count) when they don't have the managers' ⋯ menu.
class _MembershipRequestsButton extends ConsumerWidget {
  const _MembershipRequestsButton({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending =
        ref.watch(membershipRequestCountProvider(groupId)).valueOrNull ?? 0;
    return Stack(clipBehavior: Clip.none, children: [
      _OutlineButton(
        label: 'Membership requests',
        icon: Icons.how_to_reg_outlined,
        onTap: () => context.push('/groups/$groupId/requests'),
      ),
      if (pending > 0)
        Positioned(
          top: -6,
          right: 6,
          child: IgnorePointer(
            child: _CountBadge(count: pending, border: context.palette.surface),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Overview — the web group page's extras: unlock-wallet banner, quick-link
// grid (Leaderboard / Outstanding / Wallet / Plan / Tickets) and the monthly
// check-in usage meter.
// ---------------------------------------------------------------------------

class _OverviewSection extends ConsumerWidget {
  const _OverviewSection({required this.groupId, required this.canManage});
  final String groupId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final ov = ref.watch(groupOverviewProvider(groupId)).valueOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No free-tier upsell banner in the app — the Wallet quick card below
        // shows on every plan (a "not on your current plan" state when locked),
        // so admins still discover the wallet; upgrade prompts themselves live
        // on the web / in email (app-store rules; uniform across platforms).
        // Quick links grid.
        Row(children: [
          Expanded(
            child: _quickCard(
              context,
              icon: Icons.leaderboard_outlined,
              iconTone: p.orange,
              title: 'Leaderboard',
              subtitle: 'Rankings & records',
              onTap: () => context.push('/groups/$groupId/leaderboard'),
            ),
          ),
          if (ov != null && ov.outstandingCount > 0) ...[
            const SizedBox(width: 10),
            Expanded(
              child: _quickCard(
                context,
                icon: Icons.credit_card_rounded,
                iconTone: p.orangeInk,
                title: 'Outstanding',
                subtitle:
                    '${ov.outstandingCount} unpaid · ${formatMoney(ov.outstandingTotalMinor, ov.outstandingCurrency, ov.outstandingExponent)}',
                highlighted: true,
                onTap: () => context.push('/groups/$groupId/outstanding'),
              ),
            ),
          ],
        ]),
        if (canManage && ov != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            // Always visible to admins: locked groups get a neutral "not
            // enabled" state so they know the wallet exists. Tapping opens the
            // native wallet screen (its locked state quietly emails the admin).
            Expanded(
              child: _quickCard(
                context,
                icon: Icons.account_balance_wallet_outlined,
                iconTone: ov.showUnlockBanner
                    ? p.muted
                    : (ov.walletFrozen || ov.walletActionNeeded)
                        ? p.orangeInk
                        : p.greenText,
                title: 'Wallet',
                subtitle: ov.showUnlockBanner
                    ? 'Not enabled for this group'
                    : ov.walletFrozen
                        ? 'Paused — view records'
                        : ov.walletActionNeeded
                            ? (ov.walletOnboardingStep == 'verify_identity'
                                ? 'Action needed — verify your identity with Stripe'
                                : 'Action needed — finish Stripe setup')
                            : ov.walletUnderReview
                                ? 'Stripe is reviewing your details'
                                : 'Collect & withdraw',
                highlighted: ov.walletActionNeeded,
                onTap: () => context.push('/groups/$groupId/wallet'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _quickCard(
                context,
                icon: Icons.confirmation_number_outlined,
                iconTone: p.greenText,
                title: 'Tickets',
                subtitle: 'Sell entry & collect',
                onTap: () => context.push('/groups/$groupId/tickets'),
              ),
            ),
          ]),
        ],
        // Monthly check-in usage (free/limited plans only).
        if (canManage &&
            ov != null &&
            !ov.checkinUnlimited &&
            ov.checkinLimit != null) ...[
          const SizedBox(height: 8),
          _CheckinUsageCard(used: ov.checkinUsed ?? 0, limit: ov.checkinLimit!),
        ],
      ],
    );
  }

  Widget _quickCard(
    BuildContext context, {
    required IconData icon,
    required Color iconTone,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool highlighted = false,
  }) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: highlighted ? p.orangeTint : p.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: dark ? Border.all(color: p.line) : null,
            boxShadow: highlighted ? null : cardShadow(context),
          ),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: highlighted ? p.surface : iconTone.withAlpha(30),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 19, color: iconTone),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: highlighted ? p.orangeInk : p.muted,
                          fontSize: 11.5)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CheckinUsageCard extends StatelessWidget {
  const _CheckinUsageCard({required this.used, required this.limit});
  final int used;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final remaining = (limit - used).clamp(0, limit);
    final frac = limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final maxed = remaining == 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: maxed ? p.liveTint : p.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: maxed ? null : cardShadow(context),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: maxed
                ? const Color.fromRGBO(222, 33, 33, 0.12)
                : const Color.fromRGBO(23, 166, 94, 0.14),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(Icons.how_to_reg_rounded,
              size: 18, color: maxed ? p.danger : p.accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text('Check-ins this month',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
                Text('$used/$limit',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 6,
                  backgroundColor: p.surface2,
                  color: maxed ? p.danger : p.accent,
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// The web tournament card: badges row (sport · date · Host/Away), title,
/// then host crest VS guest crest with the invite status.
/// Outline sibling of SpButton for the secondary header action.
class _OutlineButton extends StatelessWidget {
  const _OutlineButton(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface,
      shape: StadiumBorder(side: BorderSide(color: p.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: p.ink),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Invite members — the web AddMemberSearch as a sheet: type a name or
/// @handle, tap Invite.
class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.groupId});
  final String groupId;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<GroupMemberItem> _results = const [];
  final Set<String> _invited = {};
  bool _searching = false;

  @override
  void dispose() {
    _query.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final q = v.trim();
      if (q.length < 2) {
        if (mounted) setState(() => _results = const []);
        return;
      }
      setState(() => _searching = true);
      try {
        final r = await ref.read(groupsRepositoryProvider).searchUsers(q);
        if (mounted) setState(() => _results = r);
      } catch (_) {
        /* keep last results */
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _invite(GroupMemberItem u) async {
    try {
      await ref
          .read(groupsRepositoryProvider)
          .inviteUser(widget.groupId, u.userId);
      if (mounted) setState(() => _invited.add(u.userId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invite members',
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Search by name or @username — they get an invitation.',
                style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                hintText: 'Search people',
                prefixIcon: Icon(Icons.search_rounded, color: p.muted),
                isDense: true,
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final u in _results)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: ClipOval(
                        child: Crest(
                            logoUrl: u.avatarUrl,
                            label: u.displayName,
                            size: 34)),
                    title: Text(u.displayName,
                        style: TextStyle(color: p.ink, fontSize: 14)),
                    subtitle: u.username != null
                        ? Text('@${u.username}',
                            style: TextStyle(color: p.muted, fontSize: 11.5))
                        : null,
                    trailing: _invited.contains(u.userId)
                        ? Icon(Icons.check_circle_rounded,
                            color: p.accent, size: 20)
                        : SpButton(label: 'Invite', onTap: () => _invite(u)),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edit group — name + description (the web edit page's core fields).
class _EditGroupSheet extends ConsumerStatefulWidget {
  const _EditGroupSheet({required this.groupId});
  final String groupId;

  @override
  ConsumerState<_EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends ConsumerState<_EditGroupSheet> {
  TextEditingController? _name;
  TextEditingController? _desc;
  bool _busy = false;

  @override
  void dispose() {
    _name?.dispose();
    _desc?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name?.text.trim() ?? '';
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(groupsRepositoryProvider).updateGroup(widget.groupId, {
        'name': name,
        'description':
            (_desc?.text.trim().isEmpty ?? true) ? null : _desc!.text.trim(),
      });
      ref.invalidate(groupProvider(widget.groupId));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final group = ref.watch(groupProvider(widget.groupId)).valueOrNull;
    _name ??= TextEditingController(text: group?.name ?? '');
    _desc ??= TextEditingController(text: group?.description ?? '');
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit group',
                style: TextStyle(
                    color: p.ink, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Description', alignLabelWithHint: true),
            ),
            const SizedBox(height: 16),
            SpButton(
              label: _busy ? 'Saving…' : 'Save changes',
              expand: true,
              onTap: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pins the group tab bar under the app bar while the header scrolls away.
class _PinnedTabBar extends SliverPersistentHeaderDelegate {
  const _PinnedTabBar({required this.child, required this.backgroundColor});
  final Widget child;
  final Color backgroundColor;

  static const double _height = 58;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: _height, child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedTabBar oldDelegate) =>
      oldDelegate.child != child ||
      oldDelegate.backgroundColor != backgroundColor;
}
