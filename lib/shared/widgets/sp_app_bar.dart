import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/attention/attention_repository.dart';
import 'package:sportpadi_mobile/data/notifications/notifications_repository.dart';
import 'package:sportpadi_mobile/features/groups/my_groups_menu.dart';
import 'package:sportpadi_mobile/features/inbox/inbox_button.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/data/wards/wards_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/core/links/link_resolver.dart' show HomeTab;
import 'package:sportpadi_mobile/features/shell/home_shell.dart'
    show homeTabIndexProvider;
import 'package:sportpadi_mobile/shared/widgets/app_logo.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The web TopNav: glass header with the logo on the left and, on the right,
/// a notification bell (with unread bubble) and the hamburger side menu.
class SpAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const SpAppBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final p = context.palette;
    return AppBar(
      titleSpacing: 16,
      title: const AppLogo(height: 34),
      actions: [
        IconButton(
          tooltip: context.l10n.menu_inbox,
          onPressed: () => context.push('/inbox'),
          icon: const InboxIcon(),
        ),
        IconButton(
          tooltip: context.l10n.menu_notifications,
          onPressed: () => context.push('/notifications'),
          icon: NotificationBell(count: unread, color: p.danger),
        ),
        IconButton(
          tooltip: context.l10n.common_menu,
          onPressed: () => showSideMenu(context),
          // What's waiting inside the menu, on the button that opens it.
          icon: const Stack(clipBehavior: Clip.none, children: [
            Icon(Icons.menu_rounded),
            Positioned(top: -1, right: -1, child: SideMenuAttentionCount()),
          ]),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// The side menu, sliding in from the right (2026): who you are on a dark
/// card, quick actions, the main destinations and your own pages (each with
/// what's waiting there — [attentionProvider], re-read as it opens), and sign
/// out pinned to the bottom.
Future<void> showSideMenu(BuildContext context) {
  ProviderScope.containerOf(context, listen: false)
      .invalidate(attentionProvider);
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.l10n.common_menu,
    barrierColor: Colors.black45,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) => const Align(
      alignment: Alignment.centerRight,
      child: _SideMenu(),
    ),
    transitionBuilder: (_, anim, __, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _SideMenu extends ConsumerWidget {
  const _SideMenu();

  static const _mint = Color(0xFF6EDC9E);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final l = context.l10n;
    final me = ref.watch(meProvider).valueOrNull;
    final tab = ref.watch(homeTabIndexProvider);
    // What's waiting where, in one call: Inbox (unread announcements +
    // conversations), Notifications, Discussions, fines and tournament
    // requests (invites to my groups + squad call-ups).
    final waiting = ref.watch(attentionProvider).valueOrNull;
    // My wards: co-guardian invites + team invitations waiting on me.
    final wardsO = ref.watch(myWardsProvider).valueOrNull;
    final wardTeamInvites = (wardsO?.wards.isNotEmpty ?? false)
        ? ref.watch(wardTeamInvitesProvider('')).valueOrNull?.length ?? 0
        : 0;
    final wardBadge = (wardsO?.invites.length ?? 0) + wardTeamInvites;
    final width = MediaQuery.sizeOf(context).width;

    // Outlives the menu: a page opened from it can clear what's waiting
    // (reading the inbox, paying a fine), so the badges are re-read once it
    // closes.
    final container = ProviderScope.containerOf(context, listen: false);

    void go(String v) {
      Navigator.pop(context); // close the menu first
      if (v.startsWith('tab:')) {
        ref.read(homeTabIndexProvider.notifier).state =
            int.parse(v.substring(4));
      } else {
        unawaited(context
            .push<Object?>(v)
            .whenComplete(() => container.invalidate(attentionProvider)));
      }
    }

    Widget item(IconData icon, String label, String dest,
        {int? badge, bool active = false}) {
      return InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => go(dest),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(children: [
            SpIconTile(icon,
                size: 38,
                iconSize: 19,
                bg: active ? p.accentTint : p.surface2,
                fg: active ? p.greenText : p.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600)),
            ),
            if (badge != null && badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: p.danger, borderRadius: BorderRadius.circular(999)),
                child: Text(badge > 99 ? '99+' : '$badge',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              )
            else if (active)
              Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: p.accent, shape: BoxShape.circle),
              )
            else
              Icon(Icons.chevron_right_rounded, size: 18, color: p.muted),
          ]),
        ),
      );
    }

    Widget quick(IconData icon, String label, String dest,
            {bool dark = false}) =>
        Expanded(
          child: Material(
            color: dark ? p.hero : p.surface,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => go(dest),
              child: Container(
                height: 58,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: dark ? null : cardShadow(context),
                ),
                child: Row(children: [
                  Icon(icon, size: 20, color: dark ? _mint : p.greenText),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: dark ? p.onHero : p.ink,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
            ),
          ),
        );

    return Material(
      color: p.bg,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        left: false,
        right: false,
        child: SizedBox(
          width: width * 0.86 > 320 ? 320 : width * 0.86,
          height: double.infinity,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  // Just the close button up here — the profile card below
                  // opens the drawer.
                  Row(children: [
                    const Spacer(),
                    SpRoundButton(
                      icon: Icons.close_rounded,
                      tooltip: l.nav_close,
                      onTap: () => Navigator.pop(context),
                    ),
                  ]),
                  const SizedBox(height: 14),

                  // Who you are.
                  Material(
                    color: p.hero,
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => go('tab:${HomeTab.profile}'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: _mint, width: 2),
                            ),
                            child: CircleAvatar(
                              radius: 22,
                              backgroundColor: p.onHero.withAlpha(30),
                              backgroundImage: me?.avatarUrl != null
                                  ? NetworkImage(me!.avatarUrl!)
                                  : null,
                              child: me?.avatarUrl == null
                                  ? Icon(Icons.person_rounded,
                                      color: p.onHero, size: 22)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(me?.displayName ?? context.l10n.common_welcomeToSportPadi,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.onHero,
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700)),
                                Text(
                                    me != null
                                        ? '@${me.username} · ${l.menu_viewProfile}'
                                        : l.menu_viewProfile,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.heroMuted, fontSize: 12)),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              size: 20, color: p.heroMuted),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    quick(Icons.qr_code_scanner_rounded, l.menu_scanQr, '/scan',
                        dark: true),
                    const SizedBox(width: 10),
                    quick(Icons.qr_code_2_rounded, l.menu_myQr, '/my-qr'),
                  ]),

                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Eyebrow(l.menu_explore),
                  ),
                  SpListCard(children: [
                    item(Icons.space_dashboard_outlined, l.nav_home, 'tab:0',
                        active: tab == 0),
                    item(Icons.explore_outlined, l.nav_browse, 'tab:1',
                        active: tab == 1),
                    item(Icons.emoji_events_outlined, l.nav_tournaments,
                        'tab:${HomeTab.tournaments}',
                        badge: waiting?.tournaments.total,
                        active: tab == HomeTab.tournaments),
                  ]),

                  // Groups left the dock: yours are listed here, invites too.
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Eyebrow(l.menu_myGroups),
                  ),
                  MyGroupsMenu(onGo: go),

                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Eyebrow(l.menu_you),
                  ),
                  SpListCard(children: [
                    item(Icons.campaign_outlined, l.menu_inbox, '/inbox',
                        badge: waiting?.inbox.total),
                    item(Icons.notifications_none_rounded, l.menu_notifications,
                        '/notifications',
                        badge: waiting?.notifications),
                    item(Icons.forum_outlined, l.menu_discussions, '/discussions',
                        badge: waiting?.discussions),
                    item(Icons.supervisor_account_rounded, l.menu_myWards,
                        '/profile/wards',
                        badge: wardBadge),
                    item(Icons.sports_soccer_outlined, l.menu_mySports,
                        '/profile/sports'),
                    item(Icons.insights_rounded, l.menu_myRecords,
                        '/profile/records'),
                    item(Icons.confirmation_num_outlined, l.menu_myPurchases,
                        '/tickets'),
                    item(Icons.receipt_long_outlined, l.menu_myFines, '/fines',
                        badge: waiting?.fines),
                    item(Icons.settings_outlined, l.menu_settings, '/settings'),
                  ]),
                ],
              ),
            ),

            // Sign out — pinned to the bottom.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Material(
                color: p.liveTint,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () async {
                    Navigator.pop(context);
                    await ref.read(authControllerProvider.notifier).signOut();
                  },
                  child: SizedBox(
                    height: 50,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.logout_rounded, size: 18, color: p.danger),
                          const SizedBox(width: 8),
                          Text(l.nav_signOut,
                              style: TextStyle(
                                  color: p.danger,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                        ]),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(l.menu_madeBy.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: p.muted.withAlpha(150),
                      fontSize: 9.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The round Menu button on the tab pages' headers, with a dot when anything
/// in the menu is waiting ([SideMenuAttentionCount]), placed like the bell's.
class SideMenuButton extends StatelessWidget {
  const SideMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      SpRoundButton(
        icon: Icons.menu_rounded,
        tooltip: context.l10n.common_menu,
        onTap: () => showSideMenu(context),
      ),
      // Inside the button, where the bell's dot sits.
      Positioned(
        top: 10,
        right: 11,
        child: SideMenuAttentionCount(border: context.palette.surface),
      ),
    ]);
  }
}

/// What's waiting in the side menu, for whatever opens it: a small dot, like
/// the notification bell's — not a count. Shown when anything in the menu
/// wants attention ([attentionProvider] plus My wards' invitations); red
/// while an urgent announcement is waiting. Nothing when nothing is waiting.
class SideMenuAttentionCount extends ConsumerWidget {
  const SideMenuAttentionCount({super.key, this.border});

  /// A ring in the colour behind it, so it reads on top of a button or an
  /// avatar.
  final Color? border;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(attentionProvider).valueOrNull;
    // My wards' row has its own badge in the menu; it counts here too.
    final wardsO = ref.watch(myWardsProvider).valueOrNull;
    final wardTeamInvites = (wardsO?.wards.isNotEmpty ?? false)
        ? ref.watch(wardTeamInvitesProvider('')).valueOrNull?.length ?? 0
        : 0;
    final wardInvites = (wardsO?.invites.length ?? 0) + wardTeamInvites;
    final waiting = (a?.total ?? 0) + wardInvites;
    if (waiting <= 0) return const SizedBox.shrink();
    final p = context.palette;
    final urgent = a?.urgent ?? false;
    return Semantics(
      label:
          urgent ? context.l10n.common_somethingUrgentInTheMenu : context.l10n.common_somethingNewInTheMenu,
      excludeSemantics: true,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: urgent ? p.danger : p.orange,
          shape: BoxShape.circle,
          border: Border.all(color: border ?? p.surface, width: 2),
        ),
      ),
    );
  }
}

/// Bell icon with a small unread-count bubble.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const bell = Icon(Icons.notifications_none_rounded);
    if (count <= 0) return bell;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        bell,
        Positioned(
          right: -4,
          top: -3,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            constraints: const BoxConstraints(minWidth: 15),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(999)),
            child: Text(
              count > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
