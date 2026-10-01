import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/analytics/analytics_service.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/core/links/deep_links.dart';
import 'package:sportpadi_mobile/features/ads/popup_messages.dart';
import 'package:sportpadi_mobile/features/browse/browse_screen.dart';
import 'package:sportpadi_mobile/features/home/guest_home_screen.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart'
    show homeTabIndexProvider;
import 'package:sportpadi_mobile/shared/widgets/sp_dock.dart';

/// The app before an account.
///
/// A visitor used to hit a sign-in wall on launch. Now they land here: the
/// same Home and Browse a member gets, minus everything that only makes sense
/// with an account (groups, tournaments, profile, scanning, notifications).
/// The third tab IS sign-in — it doesn't hold a screen, it opens the sign-in
/// page — so the way in is always one tap away without being pushed on
/// anyone. Everything that truly needs an account (opening an event, say)
/// asks for sign-in at that moment, via the router, and returns the user to
/// what they tapped.
///
/// Tab indices match HomeShell's for Home (0) and Browse (1), so the shared
/// `homeTabIndexProvider` and the link resolver's tab targets keep working;
/// a target this shell doesn't have (Groups, Tournaments, Profile) falls back
/// to Home.
class GuestShell extends ConsumerStatefulWidget {
  const GuestShell({super.key});
  @override
  ConsumerState<GuestShell> createState() => _GuestShellState();
}

class _GuestShellState extends ConsumerState<GuestShell> {
  static const _signInTab = 2;

  @override
  void initState() {
    super.initState();
    // A visitor can arrive on a shared link too; the same resolver handles
    // it, and the router turns anything members-only into a sign-in.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDeepLinks());
    // Pop-up messages meant for visitors (audience "signed-out"), once the
    // first screen has landed.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      if (!mounted) return;
      // ignore: discarded_futures
      PopupMessages.maybeShow(context, ref);
    });
  }

  Future<void> _initDeepLinks() async {
    await ref.read(deepLinkServiceProvider).start((uri) {
      if (!mounted) return;
      // ignore: discarded_futures
      handleDeepLink(
        uri,
        push: (route) {
          if (mounted) context.push(route);
        },
        switchTab: (tab) {
          if (!mounted) return;
          ref.read(homeTabIndexProvider.notifier).state = tab <= 1 ? tab : 0;
        },
      );
    });
  }

  Widget _tab(int i) {
    switch (i) {
      case 1:
        return const BrowseScreen();
      default:
        return const GuestHomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(homeTabIndexProvider, (prev, next) {
      const names = ['/tab/home', '/tab/browse'];
      if (prev != next && next >= 0 && next < names.length) {
        ref.read(analyticsServiceProvider).logScreen(names[next]);
      }
    });
    // The provider is shared with the signed-in shell, which has more tabs;
    // anything past Browse means Home here.
    final raw = ref.watch(homeTabIndexProvider);
    final index = raw <= 1 ? raw : 0;

    final p = context.palette;
    return Scaffold(
      backgroundColor: p.bg,
      body: _tab(index),
      // The member dock (2026), with Sign in as its third button.
      bottomNavigationBar: ColoredBox(
        color: p.bg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpDock(
              index: index,
              onSelect: (i) {
                if (i == _signInTab) {
                  // Not a tab with a body: the selection stays where it is
                  // and the sign-in page opens on top, so "back" returns to
                  // browsing.
                  context.push('/sign-in');
                  return;
                }
                ref.read(homeTabIndexProvider.notifier).state = i;
              },
              items: const [
                SpDockItem(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home_rounded,
                  label: 'Home',
                ),
                SpDockItem(
                  icon: Icons.explore_outlined,
                  selectedIcon: Icons.explore_rounded,
                  label: 'Browse',
                ),
                SpDockItem(
                  icon: Icons.login_rounded,
                  selectedIcon: Icons.login_rounded,
                  label: 'Sign in',
                ),
              ],
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }
}
