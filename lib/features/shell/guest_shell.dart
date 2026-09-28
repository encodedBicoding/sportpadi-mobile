import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/analytics/analytics_service.dart';
import 'package:sportpadi_mobile/core/links/deep_links.dart';
import 'package:sportpadi_mobile/features/browse/browse_screen.dart';
import 'package:sportpadi_mobile/features/home/guest_home_screen.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart'
    show homeTabIndexProvider;

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

    return Scaffold(
      body: _tab(index),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          if (i == _signInTab) {
            // Not a tab with a body: the selection stays where it is and the
            // sign-in page opens on top, so "back" returns to browsing.
            context.push('/sign-in');
            return;
          }
          ref.read(homeTabIndexProvider.notifier).state = i;
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Icon(Icons.login_rounded),
            selectedIcon: Icon(Icons.login_rounded),
            label: 'Sign in',
          ),
        ],
      ),
    );
  }
}
