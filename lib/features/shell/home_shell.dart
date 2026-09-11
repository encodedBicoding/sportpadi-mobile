import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/analytics/analytics_service.dart';
import 'package:sportpadi_mobile/core/push/push_service.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart'
    show myTournamentsActiveProvider;
import 'package:sportpadi_mobile/data/notifications/notifications_repository.dart'
    show notificationsFeedProvider, unreadCountProvider;
import 'package:sportpadi_mobile/features/home/home_screen.dart';
import 'package:sportpadi_mobile/features/browse/browse_screen.dart';
import 'package:sportpadi_mobile/features/groups/groups_list_screen.dart';
import 'package:sportpadi_mobile/features/profile/profile_screen.dart';
import 'package:sportpadi_mobile/features/tournaments/my_tournaments_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

final homeTabIndexProvider = StateProvider<int>((_) => 0);

class _HomeShellState extends ConsumerState<HomeShell> {

  @override
  void initState() {
    super.initState();
    // Register this device for push (quietly does nothing until Firebase is
    // configured). Foreground pushes refresh the notification feed/badge.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pushServiceProvider).init(onMessage: () {
        ref.invalidate(notificationsFeedProvider);
        ref.invalidate(unreadCountProvider);
      });
    });
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
