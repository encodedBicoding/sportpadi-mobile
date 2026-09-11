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

/// The web side menu, sliding in from the right: who you are, the main
/// destinations, and sign out.
Future<void> showSideMenu(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Menu',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 220),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final me = ref.watch(meProvider).valueOrNull;

    void go(String v) {
      Navigator.pop(context); // close the menu first
      if (v.startsWith('tab:')) {
        ref.read(homeTabIndexProvider.notifier).state =
            int.parse(v.substring(4));
      } else {
        context.push(v);
      }
    }

    Widget item(IconData icon, String label, String dest) => InkWell(
          onTap: () => go(dest),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(children: [
              Icon(icon, size: 19, color: p.muted),
              const SizedBox(width: 12),
              Text(label,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        );

    return Material(
      color: p.bg,
      child: SafeArea(
        child: SizedBox(
          width: 288,
          height: double.infinity,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Who you are — mirrors the web sheet header.
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.line)),
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: p.accent.withAlpha(36),
                  backgroundImage: me?.avatarUrl != null
                      ? NetworkImage(me!.avatarUrl!)
                      : null,
                  child: me?.avatarUrl == null
                      ? Icon(Icons.person_rounded, color: p.accent, size: 22)
                      : null,
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
                              color: p.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800)),
                      if (me != null)
                        Text(me.email ?? '@${me.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(color: p.muted, fontSize: 11.5)),
                    ],
                  ),
                ),
              ]),
            ),
            // Destinations — main tabs first, then personal pages (web parity).
            Expanded(
              child: ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: [
                item(Icons.space_dashboard_outlined, 'Dashboard', 'tab:0'),
                item(Icons.explore_outlined, 'Discover', 'tab:1'),
                item(Icons.groups_outlined, 'Groups', 'tab:2'),
                item(Icons.emoji_events_outlined, 'Tournaments', 'tab:3'),
                item(Icons.confirmation_num_outlined, 'My purchases', '/tickets'),
                item(Icons.receipt_long_outlined, 'My fines', '/fines'),
                item(Icons.qr_code_2_rounded, 'My QR code', '/my-qr'),
                item(Icons.qr_code_scanner_rounded, 'Scan QR', '/scan'),
                item(Icons.person_outline_rounded, 'Profile', 'tab:4'),
                item(Icons.settings_outlined, 'Settings', '/settings'),
              ]),
            ),
            // Sign out — pinned to the bottom like the web sheet.
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: InkWell(
                onTap: () async {
                  Navigator.pop(context);
                  await ref.read(authControllerProvider.notifier).signOut();
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                  child: Row(children: [
                    Icon(Icons.logout_rounded, size: 19, color: p.danger),
                    const SizedBox(width: 12),
                    Text('Sign out',
                        style: TextStyle(
                            color: p.danger,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
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
