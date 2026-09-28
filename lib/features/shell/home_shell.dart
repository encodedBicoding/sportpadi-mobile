import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/analytics/analytics_service.dart';
import 'package:sportpadi_mobile/core/push/push_alert.dart';
import 'package:sportpadi_mobile/core/push/push_service.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart'
    show myTournamentsActiveProvider;
import 'package:sportpadi_mobile/data/notifications/notifications_repository.dart'
    show notificationsFeedProvider, unreadCountProvider;
import 'package:sportpadi_mobile/core/links/deep_links.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/home/home_screen.dart';
import 'package:sportpadi_mobile/features/notifications/notification_permission_sheet.dart';
import 'package:sportpadi_mobile/features/shell/notification_target.dart';
import 'package:sportpadi_mobile/features/browse/browse_screen.dart';
import 'package:sportpadi_mobile/features/groups/groups_list_screen.dart';
import 'package:sportpadi_mobile/features/profile/profile_screen.dart';
import 'package:sportpadi_mobile/features/tournaments/my_tournaments_screen.dart';
import 'package:sportpadi_mobile/core/referral/referral.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

final homeTabIndexProvider = StateProvider<int>((_) => 0);

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Register this device for push if the OS already allows it (quietly does
    // nothing until Firebase is configured). Foreground pushes refresh the
    // notification feed/badge. The OS permission dialog is never fired cold:
    // once the shell has settled we show the in-app explainer first, and only
    // ask the OS if the user says yes.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initPush());
    // Deep links, started after the first frame so there's a router to push
    // onto when the link is the one that launched the app.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDeepLinks());
  }

  /// Universal Links / App Links. Same resolver as push notifications, so a
  /// shared URL and a tapped notification land on the same screen.
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
          if (mounted) ref.read(homeTabIndexProvider.notifier).state = tab;
        },
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Settings (or anywhere): pick up a permission change and
    // register the device if notifications were just turned on.
    if (state == AppLifecycleState.resumed) {
      // A push that arrived while backgrounded doesn't hit onMessage — refresh
      // the bell and feed the moment the app is back in front.
      ref.invalidate(unreadCountProvider);
      ref.invalidate(notificationsFeedProvider);
      ref.read(pushServiceProvider).onAppResumed().then((s) {
        if (mounted) ref.read(pushStatusProvider.notifier).state = s;
      });
    }
  }

  /// On every mount of the signed-in shell — first launch, and again the
  /// moment someone signs in — this settles three questions in order:
  ///   1. can this device receive pushes? (`init` reads the OS status)
  ///   2. if yes: is the server's row for THIS user on THIS device right?
  ///      (`init` re-registers the token; the server upserts it)
  ///   3. if no: ask — the explainer then the OS dialog when never asked, or
  ///      the explainer then Settings when refused — and, once allowed,
  ///      register (the resume hook handles the Settings round trip).
  Future<void> _initPush() async {
    final push = ref.read(pushServiceProvider);
    // A new account on this device gets a fresh soft-ask budget.
    final userId = ref.read(authControllerProvider).valueOrNull?.user?.id;
    if (userId != null) await push.noteSignedInUser(userId);
    // Opened from someone's share link before signing in? Record who brought
    // this player (gamification: community XP; server ignores regulars).
    if (userId != null) {
      // ignore: discarded_futures
      ref.read(referralStoreProvider).claim(ref.read(dioProvider), userId);
    }
    final status = await push.init(
      onMessage: () {
        ref.invalidate(notificationsFeedProvider);
        ref.invalidate(unreadCountProvider);
      },
      // Tapped: its page if it names one, otherwise the Notifications inbox.
      onOpened: (url) {
        if (mounted) openNotificationTarget(ref, url);
      },
      // Arrived while the app is open: the OS shows nothing, so hand it to
      // the in-app banner (PushBannerHost, wrapped around the whole app).
      onForeground: (alert) =>
          ref.read(foregroundPushProvider.notifier).state = alert,
    );
    if (!mounted) return;
    ref.read(pushStatusProvider.notifier).state = status;
    if (kDebugMode) {
      // One line that answers "why isn't this phone getting pushes":
      // registered / ask / denied / unavailable.
      debugPrint('[push] device readiness: ${await push.readiness()}');
    }
    // Let the first screen land before the soft ask, per the platform
    // guidelines (explain in context, don't ambush on launch).
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    final after = await NotificationPermissionSheet.maybeShow(context, ref);
    if (after != null && mounted) {
      ref.read(pushStatusProvider.notifier).state = after;
    }
  }

  Widget _tab(int i) {
    switch (i) {
      case 1:
        return const BrowseScreen();
      case 2:
        return const GroupsListScreen();
      case 3:
        return const MyTournamentsScreen();
      case 4:
        return const ProfileScreen();
      default:
        return const HomeScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Bottom-tab switches don't touch the router — log them as screens too.
    ref.listen<int>(homeTabIndexProvider, (prev, next) {
      // Cheap and keeps the bell honest between polls.
      if (prev != next) ref.invalidate(unreadCountProvider);
      const names = ['/tab/home', '/tab/browse', '/tab/groups', '/tab/tournaments', '/tab/profile'];
      if (next >= 0 && next < names.length) {
        ref.read(analyticsServiceProvider).logScreen(names[next]);
      }
    });
    final index = ref.watch(homeTabIndexProvider);
    // Dot on the Tournaments tab when a live/upcoming tournament involves one
    // of the user's teams — an invitation to look, never a number.
    final tournamentDot =
        ref.watch(myTournamentsActiveProvider).valueOrNull ?? false;
    return Scaffold(
      body: _tab(index),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(homeTabIndexProvider.notifier).state = i,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Browse',
          ),
          const NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: 'Groups',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: tournamentDot,
              smallSize: 8,
              backgroundColor: const Color(0xFFF0821E),
              child: const Icon(Icons.emoji_events_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: tournamentDot,
              smallSize: 8,
              backgroundColor: const Color(0xFFF0821E),
              child: const Icon(Icons.emoji_events_rounded),
            ),
            label: 'Tournaments',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
