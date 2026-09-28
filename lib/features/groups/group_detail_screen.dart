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
import 'package:url_launcher/url_launcher.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/emoji_badge.dart';
import 'package:sportpadi_mobile/shared/widgets/entity_row.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/core/referral/referral.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart';

/// Group header geometry: cover banner height and how far the avatar/stats
/// row hangs below it.
const double _kCoverHeight = 140;
const double _kHeaderOverhang = 34;

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupProvider(groupId));
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
      ),
      body: AsyncView(
        value: group,
        onRetry: () => ref.invalidate(groupProvider(groupId)),
        data: (g) => DefaultTabController(
          length: 3,
          // The whole page scrolls: a tall header (cover, description, stats,
          // admin cards) glides away and the tab bar pins to the top — so no
          // amount of header content can trap the screen.
          child: NestedScrollView(
            headerSliverBuilder: (context, innerScrolled) => [
              SliverToBoxAdapter(child: _Header(group: g)),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedTabBar(
                  backgroundColor: p.bg,
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.bg,
                      border: Border(bottom: BorderSide(color: p.line)),
                    ),
                    child: TabBar(
                      labelColor: p.accent,
                      unselectedLabelColor: p.muted,
                      indicatorColor: p.accent,
                      indicatorSize: TabBarIndicatorSize.label,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      tabs: const [
                        Tab(text: 'Events'),
                        Tab(text: 'Teams'),
                        Tab(text: 'Tournaments'),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            body: TabBarView(children: [
              _EventsTab(groupId: groupId),
              _TeamsTab(groupId: groupId),
              _TournamentsTab(groupId: groupId, canManage: g.canManage),
            ]),
          ),
        ),
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
      color: p.accent,
      shape: const CircleBorder(),
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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Server counts, falling back to the events feed length while loading.
    final eventsCount = group.eventsCount ??
        ref.watch(groupEventsProvider(groupId)).valueOrNull?.length;
    final memberCount = group.memberCount;
    final followerCount = group.followerCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cover banner + overlapping avatar & stats. The stack is sized to
        // include the avatar/stats overhang: a Stack only hit-tests inside
        // its own bounds, so a row hanging below the cover via a negative
        // `bottom` never received taps on its lower half.
        SizedBox(
          height: _kCoverHeight + _kHeaderOverhang,
          width: double.infinity,
          child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _kCoverHeight,
              child: Stack(fit: StackFit.expand, children: [
                group.coverImageUrl != null
                    ? Image.network(group.coverImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const _CoverWash())
                    : const _CoverWash(),
                // Same treatment as the web cover: a bottom-up fade into the
                // page background so the photo melts into the screen instead
                // of cutting across it.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.30, 0.72, 1.0],
                      colors: [
                        Colors.transparent,
                        p.bg.withAlpha(96),
                        p.bg,
                      ],
                    ),
                  ),
                ),
              ]),
            ),
            if (canManage)
              Positioned(
                top: 8,
                right: 12,
                child: _cameraBadge('cover', size: 30),
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: Stack(children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: p.bg, width: 4),
                          boxShadow: const [
                            BoxShadow(color: Color.fromRGBO(15, 30, 22, 0.14), blurRadius: 12, offset: Offset(0, 4)),
                          ],
                        ),
                        child: ClipOval(child: Crest(logoUrl: logoUrl, label: name, size: 72)),
                      ),
                      if (canManage)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: _cameraBadge('logo', size: 26),
                        ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _stat(
                            eventsCount?.toString() ?? '–',
                            'Events',
                            onTap: () =>
                                context.push('/groups/$groupId/events'),
                          ),
                          _stat(
                            memberCount?.toString() ?? '–',
                            'Members',
                            onTap: () =>
                                context.push('/groups/$groupId/members'),
                          ),
                          _stat(
                            followerCount?.toString() ?? '–',
                            'Followers',
                            onTap: canManage
                                ? () => context
                                    .push('/groups/$groupId/followers')
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                if (group.isVerified) ...[
                  const SizedBox(width: 5),
                  Icon(Icons.verified_rounded, size: 18, color: p.accent),
                ],
              ]),
              if (description != null && description!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
              ],
              if (!group.isMember) ...[
                const SizedBox(height: 12),
                _FollowButton(groupId: groupId),
              ],
              if (canManage) ...[
                const SizedBox(height: 12),
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
              ],
              const SizedBox(height: 12),
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _InviteSheet(groupId: groupId),
    );
  }

  Widget _stat(String value, String label, {VoidCallback? onTap}) {
    return Expanded(
      child: Builder(builder: (context) {
        final p = context.palette;
        // Full-width, ≥44pt tall tap target per stat.
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 17)),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 11)),
            ]),
          ),
        );
      }),
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
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
      ),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded),
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
              showModalBottomSheet<void>(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(groupEventsProvider(groupId));
    return AsyncView(
      value: events,
      onRetry: () => ref.invalidate(groupEventsProvider(groupId)),
      data: (list) => list.isEmpty
          ? const _Empty('No upcoming events.')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final e = list[i];
                return EntityRow(
                  leading: EmojiBadge(emoji: e.categoryEmoji),
                  title: e.title,
                  subtitle: [
                    formatDay(e.eventDate),
                    if (e.locationName != null) e.locationName!,
                  ].where((s) => s.isNotEmpty).join('  ·  '),
                  onTap: () => context.push('/events/${e.slug}'),
                );
              },
            ),
    );
  }
}

class _TeamsTab extends ConsumerWidget {
  const _TeamsTab({required this.groupId});
  final String groupId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(groupTeamsProvider(groupId));
    return AsyncView(
      value: teams,
      onRetry: () => ref.invalidate(groupTeamsProvider(groupId)),
      data: (list) {
        if (list.isEmpty) return const _Empty('No teams yet.');
        // Grouped by sport with an emoji header — the web TeamsTab layout.
        final bySport = <String, List<TeamSummary>>{};
        for (final t in list) {
          bySport.putIfAbsent(t.categoryName ?? 'Other', () => []).add(t);
        }
        final p = context.palette;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final entry in bySport.entries) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${entry.value.first.categoryEmoji ?? '🏅'}  ${entry.key.toUpperCase()}',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8),
                ),
              ),
              for (final t in entry.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TeamCard(team: t),
                ),
              const SizedBox(height: 6),
            ],
          ],
        );
      },
    );
  }
}

/// The web team card: kit-coloured logo box, name + @username, grade badge,
/// member count and the two-swatch kit chip.
class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.team});
  final TeamSummary team;

  Color? _hex(String? v) {
    if (v == null || v.isEmpty) return null;
    var h = v.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    final n = int.tryParse(h, radix: 16);
    return n == null ? null : Color(n);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = team;
    final kit1 = _hex(t.kitPrimary);
    final kit2 = _hex(t.kitSecondary);
    return GlassCard(
      onTap: () => context.push('/teams/${t.id}'),
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kit1 ?? const Color.fromRGBO(23, 166, 94, 0.15),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: p.line),
          ),
          child: t.logoUrl != null
              ? Image.network(t.logoUrl!,
                  fit: BoxFit.cover,
                  width: 44,
                  height: 44,
                  errorBuilder: (_, __, ___) => Icon(Icons.shield_outlined,
                      size: 20, color: kit2 ?? p.accent))
              : Icon(Icons.shield_outlined,
                  size: 20, color: kit2 ?? p.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              if (t.username != null)
                Text('@${t.username}',
                    style: TextStyle(color: p.muted, fontSize: 11)),
              const SizedBox(height: 4),
              Row(children: [
                SpBadge(t.grade == 'kids' ? 'Kids' : 'Adults'),
                const SizedBox(width: 6),
                Icon(Icons.groups_outlined, size: 13, color: p.muted),
                const SizedBox(width: 3),
                Text('${t.memberCount ?? 0}',
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
                if (kit1 != null || kit2 != null) ...[
                  const SizedBox(width: 8),
                  // Two-swatch kit chip.
                  Container(
                    width: 22,
                    height: 12,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: p.line),
                    ),
                    child: Row(children: [
                      Expanded(
                          child:
                              Container(color: kit1 ?? p.surface2)),
                      Expanded(
                          child:
                              Container(color: kit2 ?? p.surface2)),
                    ]),
                  ),
                ],
              ]),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 18, color: p.muted),
      ]),
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
          ? const _Empty('No tournaments yet.')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _PendingInvitesStrip(
              groupId: groupId, count: pending.length),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: () => _handleNewTournament(context, ref, groupId),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New tournament'),
          ),
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.amber.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.amber.withAlpha(100)),
        ),
        child: Row(children: [
          Icon(Icons.mark_email_unread_outlined, size: 18, color: p.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count tournament invitation${count == 1 ? '' : 's'} waiting',
              style: TextStyle(
                  color: p.ink, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          Text('Review',
              style: TextStyle(
                  color: p.muted, fontSize: 12, fontWeight: FontWeight.w700)),
          Icon(Icons.chevron_right_rounded, size: 18, color: p.muted),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text, style: TextStyle(color: context.palette.muted)),
        ),
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
          colors: [
            Color.fromRGBO(23, 166, 94, 0.22),
            Color.fromRGBO(235, 240, 237, 0.4),
            Color.fromRGBO(245, 167, 10, 0.14),
          ],
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
      color: following ? p.surface2 : p.accent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy || _following == null ? null : _toggle,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          child: Text(
            following ? 'Following' : 'Follow',
            style: TextStyle(
              color: following ? p.ink : Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
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
              icon: Icons.emoji_events_outlined,
              iconTone: p.amber,
              title: 'Leaderboard',
              subtitle: 'Rankings & records',
              onTap: () => context.push('/groups/$groupId/leaderboard'),
            ),
          ),
          if (ov != null && ov.outstandingCount > 0) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _quickCard(
                context,
                icon: Icons.credit_card_rounded,
                iconTone: p.amber,
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
          const SizedBox(height: 8),
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
                        ? p.amber
                        : p.accent,
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
            const SizedBox(width: 8),
            Expanded(
              child: _quickCard(
                context,
                icon: Icons.confirmation_number_outlined,
                iconTone: const Color(0xFF0EA5E9),
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
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: highlighted ? iconTone.withAlpha(115) : p.line),
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: iconTone.withAlpha(36),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 18, color: iconTone),
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
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: p.muted, fontSize: 10.5)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: p.muted),
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
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: maxed
                ? const Color.fromRGBO(222, 33, 33, 0.4)
                : p.line),
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
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: p.accent),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
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

  static const double _height = 47;

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
