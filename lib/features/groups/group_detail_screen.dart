import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/tournaments/tournament_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/data/billing/iap_repository.dart';
import 'package:sportpadi_mobile/data/wallet/wallet_repository.dart';
import 'package:sportpadi_mobile/features/groups/group_admin_sheets.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart' show ShellBottomBar;
import 'package:url_launcher/url_launcher.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/team_tile.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/core/referral/referral.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/verified_badge.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// Group header geometry: cover banner height and how far the avatar/stats
/// row hangs below it.
const double _kCoverHeight = 210;
const double _kHeaderOverhang = 56;

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupProvider(groupId));
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
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
          AsyncView(
            value: group,
            onRetry: () => ref.invalidate(groupProvider(groupId)),
            data: (g) => DefaultTabController(
              length: 3,
              // The whole page scrolls: a tall header (cover, identity card,
              // tools) glides away and the tab switch pins to the top — so no
              // amount of header content can trap the screen.
              child: NestedScrollView(
                headerSliverBuilder: (context, innerScrolled) => [
                  SliverToBoxAdapter(child: _Header(group: g)),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _PinnedTabBar(
                      backgroundColor: p.bg,
                      child: Container(
                        color: p.bg,
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: dark ? p.surface2 : const Color(0xFFE6EBE8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: TabBar(
                            dividerColor: Colors.transparent,
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              color: p.surface,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: dark
                                  ? null
                                  : const [
                                      BoxShadow(
                                          color: Color(0x140E1411),
                                          blurRadius: 2,
                                          offset: Offset(0, 1))
                                    ],
                            ),
                            labelColor: p.ink,
                            unselectedLabelColor: p.muted,
                            labelStyle: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                            unselectedLabelStyle: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                            overlayColor:
                                WidgetStateProperty.all(Colors.transparent),
                            tabs: const [
                              Tab(height: 38, text: 'Events'),
                              Tab(height: 38, text: 'Teams'),
                              Tab(height: 38, text: 'Tournaments'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                body: TabBarView(children: [
                  _EventsTab(groupId: groupId),
                  _TeamsTab(groupId: groupId, canManage: g.canManage),
                  _TournamentsTab(groupId: groupId, canManage: g.canManage),
                ]),
              ),
            ),
          ),
          // While loading (or on error) there's no cover to carry the back
          // button — keep one on screen regardless.
          if (group.valueOrNull == null)
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

class _HeaderState extends ConsumerState<_Header> {
  String? _uploading; // 'logo' | 'cover'

  GroupDetail get group => widget.group;
  String get groupId => group.id;
  String get name => group.name;
  String? get description => group.description;
  String? get logoUrl => group.logoUrl;
  bool get canManage => group.canManage;

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
      await ref.read(groupsRepositoryProvider).updateGroup(groupId,
          {kind == 'cover' ? 'coverImageUrl' : 'imageUrl': url});
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
    final desc = description?.trim() ?? '';

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
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      const VerifiedBadge(size: 20),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                      group.isOwner
                          ? 'You own this group'
                          : canManage
                              ? 'You manage this group'
                              : group.isMember
                                  ? 'You\'re a member'
                                  : 'Public group',
                      style: TextStyle(color: p.muted, fontSize: 12.5)),
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
            _ManageMenu(groupId: groupId),
          ]),
        ] else if (!group.isMember) ...[
          const SizedBox(height: 14),
          _FollowButton(groupId: groupId),
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
              _OverviewSection(groupId: groupId, canManage: canManage),
              // Group reputation (gamification): level, streak, achievements.
              GroupReputationCard(groupId: groupId),
            ],
          ),
        ),
      ],
    );
  }

  void _openInvite(BuildContext context) {
    showSpSheet<void>(
      context,
      framed: false,
      builder: (_) => _InviteSheet(groupId: groupId),
    );
  }
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
  final canBuyInApp = IapRepository.supportedPlatform;
  if (!canBuyInApp) {
    // Quiet nudge (server-throttled alongside the wallet one), then the modal.
    ref
        .read(walletRepositoryProvider)
        .requestPlanEmail(groupId, topic: 'tournaments');
  }
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Tournaments aren't enabled for this group"),
      content: const Text(
          'Tournament events — brackets, friendlies and inviting teams from '
          "other groups — aren't switched on for this group yet."),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(canBuyInApp ? 'Not now' : 'OK'),
        ),
        if (canBuyInApp)
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.push('/groups/$groupId/plan');
            },
            child: const Text('See plans'),
          ),
      ],
    ),
  );
}

class _ManageMenu extends ConsumerWidget {
  const _ManageMenu({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: p.surface2,
        shape: BoxShape.circle,
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Manage',
        icon: Icon(Icons.more_horiz_rounded, color: p.ink),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        color: p.surface,
        onSelected: (v) {
          switch (v) {
            case 'link':
              final base = ref.read(appConfigProvider).apiBaseUrl;
              final me = ref.read(meProvider).valueOrNull?.userId;
              Clipboard.setData(ClipboardData(
                  text: withRef('$base/join/$groupId', me, 'group', groupId)));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Membership link copied — anyone with it can join.')));
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
              final base = ref.read(appConfigProvider).apiBaseUrl;
              launchUrl(Uri.parse('$base/groups/$groupId/upgrade'),
                  mode: LaunchMode.inAppBrowserView);
              break;
            case 'promo':
              showPromoCodesSheet(context, groupId);
              break;
            case 'transfer':
              showTransferOwnershipSheet(context, groupId);
              break;
          }
        },
        itemBuilder: (_) {
          final ov = ref.read(groupOverviewProvider(groupId)).valueOrNull;
          final isOwner = ref.read(groupProvider(groupId)).valueOrNull?.isOwner ?? false;
          // Fail open while the overview loads — the server still enforces.
          final canTournaments = ov?.canCreateTournaments ?? true;
          // Team building: plan OR promo code (same rule as web + server).
          final canTeams =
              ref.read(teamAllowanceProvider(groupId)).valueOrNull?.canBuild ??
                  true;
          final ios = IapRepository.supportedPlatform;
          // The web menu, with two App Store exceptions: "Payment methods" is
          // the Stripe card for the plan (Apple bills the plan on iOS) and a
          // promo code that unlocks paid features is a 3.1.1 problem, so
          // both are Android-only; the plan itself is the in-app purchase.
          return [
            _menuItem('link', Icons.link_rounded, 'Copy membership link'),
            _menuItem('edit', Icons.edit_outlined, 'Edit group'),
            _menuItem('wallet', Icons.account_balance_wallet_outlined, 'Wallet'),
            _menuItem('fines', Icons.gavel_rounded, 'Fines'),
            if (ios)
              _menuItem('plan', Icons.workspace_premium_outlined, 'Group plan')
            else
              _menuItem('upgrade', Icons.workspace_premium_outlined, 'Upgrade plan'),
            if (!ios)
              _menuItem('promo', Icons.confirmation_number_outlined, 'Promo codes'),
            if (isOwner)
              _menuItem('transfer', Icons.swap_horiz_rounded, 'Transfer ownership'),
            const PopupMenuDivider(),
            if (canTeams)
              _menuItem('team', Icons.shield_outlined, 'New team'),
            // Tournaments are a plan feature. On a tier without them the
            // item is offered only where tapping it can lead somewhere — the
            // in-app plans screen on iOS. Elsewhere it's hidden, same as the
            // web tab hides its button.
            if (canTournaments || IapRepository.supportedPlatform)
              _menuItem('tournament', Icons.emoji_events_outlined,
                  canTournaments ? 'New tournament' : 'New tournament · plan'),
            _menuItem('invites', Icons.mail_outline_rounded, 'Tournament invites'),
          ];
        },
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(label),
      ]),
    );
  }
}

class _EventsTab extends ConsumerWidget {
  const _EventsTab({required this.groupId});
  final String groupId;

  static const _wd = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(groupEventsProvider(groupId));
    final p = context.palette;
    return AsyncView(
      value: events,
      onRetry: () => ref.invalidate(groupEventsProvider(groupId)),
      data: (list) => list.isEmpty
          ? const _Empty('No upcoming events.', Icons.event_outlined)
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                SpListCard(children: [
                  for (final e in list)
                    Builder(builder: (context) {
                      final d = e.eventDate?.toUtc();
                      final live = e.isLive || e.status == 'kicked_off';
                      final sub = [
                        if (formatClock(e.startTime) != null)
                          formatClock(e.startTime)!,
                        if (e.locationName != null) e.locationName!,
                      ].join(' · ');
                      return InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => e.isTournament
                            ? context.push('/tournaments/${e.id}')
                            : context.push(
                                '/events/${e.slug.isNotEmpty ? e.slug : e.id}'),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          child: Row(children: [
                            Container(
                              width: 46,
                              height: 50,
                              decoration: BoxDecoration(
                                color: live
                                    ? p.hero
                                    : e.isTournament
                                        ? p.orangeTint
                                        : p.surface2,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(d != null ? _wd[d.weekday - 1] : '—',
                                        style: TextStyle(
                                            color: live
                                                ? p.heroMuted
                                                : e.isTournament
                                                    ? p.orangeInk
                                                    : p.muted,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700)),
                                    Text(d != null ? '${d.day}' : '—',
                                        style: TextStyle(
                                            color: live
                                                ? p.onHero
                                                : e.isTournament
                                                    ? p.orangeInk
                                                    : p.ink,
                                            fontSize: 19,
                                            height: 1.05,
                                            fontWeight: FontWeight.w800)),
                                  ]),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${e.categoryEmoji != null ? '${e.categoryEmoji} ' : ''}${e.title}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: p.ink,
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700)),
                                    if (sub.isNotEmpty)
                                      Text(sub,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: p.muted, fontSize: 12)),
                                  ]),
                            ),
                            const SizedBox(width: 8),
                            if (live)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: p.danger,
                                    borderRadius: BorderRadius.circular(999)),
                                child: const Text('LIVE',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800)),
                              )
                            else
                              Icon(Icons.chevron_right_rounded,
                                  size: 20, color: p.muted),
                          ]),
                        ),
                      );
                    }),
                ]),
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

/// A group's teams (2026): a group can field a team — or several — in each
/// sport it plays. Sport chips filter; each sport is its own section of
/// kit-banner tiles, and admins can add a team right under a sport (the
/// create form opens with that sport picked) or for a new sport up top.
class _TeamsTabState extends ConsumerState<_TeamsTab> {
  String? _sport; // category name; null = all

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
    final canMany = allow?.canBuildMultiple ?? false;
    final locked = widget.canManage && allow != null && !allow.canBuild;
    Widget lockCard() => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.orangeTint,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(children: [
            SpIconTile(Icons.lock_outline_rounded,
                bg: p.surface, fg: p.orangeInk, size: 38, iconSize: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Team building is a plan feature',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text(
                        'Upgrade, or redeem a promo code, to build one team per sport — or several.',
                        style: TextStyle(color: p.orangeInk, fontSize: 11.5)),
                  ]),
            ),
          ]),
        );
    return AsyncView(
      value: teams,
      onRetry: () => ref.invalidate(groupTeamsProvider(widget.groupId)),
      data: (list) {
        if (list.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              if (locked) lockCard(),
              GlassCard(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  SpIconTile(Icons.shield_outlined,
                      bg: p.accentTint, fg: p.greenText, size: 56, iconSize: 26),
                  const SizedBox(height: 12),
                  Text('No teams yet',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    widget.canManage
                        ? 'Build a team for any sport this group plays — football, basketball, and more. Teams are what you enter into tournaments.'
                        : 'This group hasn\'t built any teams yet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 13, height: 1.45),
                  ),
                  if (canBuild) ...[
                    const SizedBox(height: 16),
                    SpButton(
                      label: 'Create a team',
                      icon: Icons.add_rounded,
                      onTap: _newTeam,
                    ),
                  ],
                ]),
              ),
            ],
          );
        }
        // Grouped by sport, in first-seen order.
        final bySport = <String, List<TeamSummary>>{};
        for (final t in list) {
          bySport.putIfAbsent(t.categoryName ?? 'Other', () => []).add(t);
        }
        final sports = bySport.keys.toList();
        final shown = _sport != null && bySport.containsKey(_sport)
            ? {_sport!: bySport[_sport]!}
            : bySport;

        Widget chip(String label, bool active, VoidCallback onTap) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Material(
                color: active ? p.hero : p.surface,
                shape: StadiumBorder(
                    side: active ? BorderSide.none : BorderSide(color: p.line)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onTap,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                    child: Text(label,
                        style: TextStyle(
                            color: active ? p.onHero : p.ink,
                            fontSize: 12.5,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w600)),
                  ),
                ),
              ),
            );

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            if (locked) lockCard(),
            Row(children: [
              Expanded(
                child: Text(
                    '${list.length} team${list.length == 1 ? '' : 's'} · ${sports.length} sport${sports.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              if (canBuild)
                Material(
                  color: p.hero,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: _newTeam,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add_rounded, size: 17, color: p.onHero),
                        const SizedBox(width: 4),
                        Text('New team',
                            style: TextStyle(
                                color: p.onHero,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
            ]),
            if (sports.length > 1) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    chip('All · ${list.length}', _sport == null,
                        () => setState(() => _sport = null)),
                    for (final sp in sports)
                      chip(
                        '${bySport[sp]!.first.categoryEmoji != null ? '${bySport[sp]!.first.categoryEmoji} ' : ''}$sp · ${bySport[sp]!.length}',
                        _sport == sp,
                        () => setState(() => _sport = _sport == sp ? null : sp),
                      ),
                  ],
                ),
              ),
            ],
            for (final entry in shown.entries) ...[
              const SizedBox(height: 18),
              SpSectionTitle(
                '${entry.value.first.categoryEmoji != null ? '${entry.value.first.categoryEmoji} ' : ''}${entry.key}',
                count: entry.value.length,
                // A one-team-per-sport plan can't add a second team here.
                trailing: canBuild && canMany
                    ? GestureDetector(
                        onTap: () => _newTeam(entry.value.first.categoryId),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.add_rounded, size: 16, color: p.greenText),
                          Text('Add',
                              style: TextStyle(
                                  color: p.greenText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700)),
                        ]),
                      )
                    : null,
              ),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 172,
                ),
                itemCount: entry.value.length,
                itemBuilder: (_, i) => TeamTile(team: entry.value[i]),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TournamentsTab extends ConsumerWidget {
  const _TournamentsTab({required this.groupId, this.canManage = false});
  final String groupId;
  final bool canManage;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(groupTournamentsProvider(groupId));
    final body = AsyncView(
      value: t,
      onRetry: () => ref.invalidate(groupTournamentsProvider(groupId)),
      data: (list) => list.isEmpty
          ? const _Empty('No tournaments yet.', Icons.emoji_events_outlined)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _TournamentCard(t: list[i]),
            ),
    );
    if (!canManage) return body;
    // Web shows pending invites inline on this tab; on mobile they live on
    // their own screen, so at least say how many are waiting — otherwise the
    // only way to find them is a popup menu item with no badge on it.
    final pending =
        ref.watch(groupInvitesProvider(groupId)).valueOrNull ?? const [];
    // Every tier sees the button; _handleNewTournament decides what a tap
    // does (create flow vs neutral gated modal + quiet email nudge).
    return Column(children: [
      if (pending.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _PendingInvitesStrip(
              groupId: groupId, count: pending.length),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        // SpButton, not FilledButton.icon (semantics assertion — see
        // SpButton).
        child: SpButton(
          label: 'New tournament',
          icon: Icons.add_rounded,
          expand: true,
          onTap: () => _handleNewTournament(context, ref, groupId),
        ),
      ),
      Expanded(child: body),
    ]);
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

class _Empty extends StatelessWidget {
  const _Empty(this.text, this.icon);
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        children: [
          Center(child: SpIconTile(icon, size: 56, iconSize: 26)),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.muted, fontSize: 13.5)),
        ],
      );
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

/// Follow / Following for visitors (non-members).
class _FollowButton extends ConsumerStatefulWidget {
  const _FollowButton({required this.groupId});
  final String groupId;

  @override
  ConsumerState<_FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<_FollowButton> {
  bool? _following;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st = await ref
          .read(eventsRepositoryProvider)
          .followState(widget.groupId);
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
      await ref
          .read(eventsRepositoryProvider)
          .setFollow(widget.groupId, !was);
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
                onTap: () =>
                    context.push('/groups/$groupId/outstanding'),
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
          _CheckinUsageCard(
              used: ov.checkinUsed ?? 0, limit: ov.checkinLimit!),
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
class _TournamentCard extends StatelessWidget {
  const _TournamentCard({required this.t});
  final TournamentSummary t;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassCard(
      onTap: () => context.push('/tournaments/${t.eventId}'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (t.categoryName != null)
                SpBadge('${t.categoryEmoji ?? ''} ${t.categoryName}'.trim()),
              if (t.eventDate != null)
                Text(formatDay(t.eventDate),
                    style: TextStyle(color: p.muted, fontSize: 11)),
              SpBadge(t.isHost ? 'Host' : 'Away',
                  tone: t.isHost ? p.accent : p.muted),
            ],
          ),
          const SizedBox(height: 6),
          Text(t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            Crest(
                logoUrl: t.hostTeamLogo,
                kitPrimary: t.hostKitPrimary,
                label: t.hostTeamName ?? '—',
                size: 28),
            const SizedBox(width: 6),
            Flexible(
              child: Text(t.hostTeamName ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('vs',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
            Crest(
                logoUrl: t.guestTeamLogo,
                kitPrimary: t.guestKitPrimary,
                label: t.guestTeamName ?? '—',
                size: 28),
            const SizedBox(width: 6),
            Flexible(
              child: Text(t.guestTeamName ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ),
            const Spacer(),
            if (t.guestStatus != null)
              SpBadge(
                t.guestStatus!,
                tone: t.guestStatus == 'accepted'
                    ? p.accent
                    : t.guestStatus == 'declined'
                        ? p.danger
                        : p.amber,
              ),
          ]),
        ],
      ),
    );
  }
}

/// Outline sibling of SpButton for the secondary header action.
class _OutlineButton extends StatelessWidget {
  const _OutlineButton(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

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
        final r =
            await ref.read(groupsRepositoryProvider).searchUsers(q);
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
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8),
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invite members',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
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
                            child: CircularProgressIndicator(
                                strokeWidth: 2)),
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
                        style:
                            TextStyle(color: p.ink, fontSize: 14)),
                    subtitle: u.username != null
                        ? Text('@${u.username}',
                            style: TextStyle(
                                color: p.muted, fontSize: 11.5))
                        : null,
                    trailing: _invited.contains(u.userId)
                        ? Icon(Icons.check_circle_rounded,
                            color: p.accent, size: 20)
                        : SpButton(
                            label: 'Invite',
                            onTap: () => _invite(u)),
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
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit group',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
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
