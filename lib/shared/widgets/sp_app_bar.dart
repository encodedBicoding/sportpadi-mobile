import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/notifications/notifications_repository.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
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
          tooltip: 'Notifications',
          onPressed: () => context.push('/notifications'),
          icon: NotificationBell(count: unread, color: p.danger),
        ),
        IconButton(
          tooltip: 'Menu',
          onPressed: () => showSideMenu(context),
          icon: const Icon(Icons.menu_rounded),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// The side menu, sliding in from the right (2026): who you are on a dark
/// card, quick actions, the main destinations and your own pages, and sign
/// out pinned to the bottom.
Future<void> showSideMenu(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Menu',
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
    final me = ref.watch(meProvider).valueOrNull;
    final tab = ref.watch(homeTabIndexProvider);
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final width = MediaQuery.sizeOf(context).width;

    void go(String v) {
      Navigator.pop(context); // close the menu first
      if (v.startsWith('tab:')) {
        ref.read(homeTabIndexProvider.notifier).state =
            int.parse(v.substring(4));
      } else {
        context.push(v);
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: p.danger,
                    borderRadius: BorderRadius.circular(999)),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                      tooltip: 'Close',
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
                      onTap: () => go('tab:4'),
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
                                Text(me?.displayName ?? 'Welcome to SportPadi',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.onHero,
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.w700)),
                                Text(
                                    me != null
                                        ? '@${me.username} · View profile'
                                        : 'View profile',
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
                    quick(Icons.qr_code_scanner_rounded, 'Scan QR', '/scan',
                        dark: true),
                    const SizedBox(width: 10),
                    quick(Icons.qr_code_2_rounded, 'My QR', '/my-qr'),
                  ]),

                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Eyebrow('Explore'),
                  ),
                  SpListCard(children: [
                    item(Icons.space_dashboard_outlined, 'Home', 'tab:0',
                        active: tab == 0),
                    item(Icons.explore_outlined, 'Browse', 'tab:1',
                        active: tab == 1),
                    item(Icons.groups_outlined, 'Groups', 'tab:2',
                        active: tab == 2),
                    item(Icons.emoji_events_outlined, 'Tournaments', 'tab:3',
                        active: tab == 3),
                  ]),

                  const SizedBox(height: 18),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Eyebrow('You'),
                  ),
                  SpListCard(children: [
                    item(Icons.notifications_none_rounded, 'Notifications',
                        '/notifications',
                        badge: unread),
                    item(Icons.confirmation_num_outlined, 'My purchases',
                        '/tickets'),
                    item(Icons.receipt_long_outlined, 'My fines', '/fines'),
                    item(Icons.settings_outlined, 'Settings', '/settings'),
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
                          Icon(Icons.logout_rounded,
                              size: 18, color: p.danger),
                          const SizedBox(width: 8),
                          Text('Sign out',
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
              child: Text('SPORTPADI BY CLAIMTANK TECHNOLOGY LTD',
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
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
            child: Text(
              count > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
