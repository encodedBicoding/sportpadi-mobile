import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/ads/admob.dart';
import 'package:sportpadi_mobile/features/ads/popup_messages.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_dock.dart';
import 'package:sportpadi_mobile/core/analytics/analytics_service.dart';
import 'package:sportpadi_mobile/core/push/push_alert.dart';
import 'package:sportpadi_mobile/core/push/push_service.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart'
    show myTournamentsActiveProvider;
import 'package:sportpadi_mobile/data/notifications/notifications_repository.dart'
    show notificationsFeedProvider, unreadCountProvider;
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart'
    show announcementsInboxProvider, announcementsUnreadProvider;
import 'package:sportpadi_mobile/data/messages/messages_repository.dart'
    show conversationProvider, messagesListProvider, messagesUnreadProvider;
import 'package:sportpadi_mobile/data/attention/attention_repository.dart'
    show attentionProvider;
import 'package:sportpadi_mobile/core/links/deep_links.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/home/home_screen.dart';
import 'package:sportpadi_mobile/features/notifications/notification_permission_sheet.dart';
import 'package:sportpadi_mobile/features/settings/timezone_provider.dart';
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
    // Then — once the explainer (if any) is out of the way — any pop-up
    // message for this person (PopupMessages: on open and on sign-in).
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _initPush().whenComplete(_maybePopup));
    // Deep links, started after the first frame so there's a router to push
    // onto when the link is the one that launched the app.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initDeepLinks());
    // Timestamps in the viewer's zone: load their setting and, on automatic,
    // tell the server the phone's zone (this mount is also "just signed in").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(timezoneControllerProvider.notifier).sync();
    });
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

  /// When the app went to the background (for "opening it again" later).
  DateTime? _awaySince;

  void _maybePopup() {
    if (!mounted) return;
    // ignore: discarded_futures
    PopupMessages.maybeShow(context, ref);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Settings (or anywhere): pick up a permission change and
    // register the device if notifications were just turned on.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _awaySince ??= DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      // Back after a long while counts as opening the app again.
      final away = _awaySince;
      _awaySince = null;
      if (away != null &&
          DateTime.now().difference(away) >= PopupMessages.resumeAfter) {
        _maybePopup();
      }
      // A push that arrived while backgrounded doesn't hit onMessage — refresh
      // the bell and feed the moment the app is back in front.
      ref.invalidate(unreadCountProvider);
      ref.invalidate(notificationsFeedProvider);
      // Same for the Inbox badges (announcements and messages).
      ref.invalidate(announcementsUnreadProvider);
      ref.invalidate(messagesUnreadProvider);
      // And the side-menu button's dot (everything waiting, in one call).
      ref.invalidate(attentionProvider);
      // Crossed a border while away? Re-read the phone's zone.
      // ignore: discarded_futures
      ref.read(timezoneControllerProvider.notifier).sync();
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
      onMessage: (data) {
        if (!mounted) return;
        ref.invalidate(notificationsFeedProvider);
        ref.invalidate(unreadCountProvider);
        // An announcement push: the Inbox badge and list are stale too.
        ref.invalidate(announcementsUnreadProvider);
        ref.invalidate(announcementsInboxProvider);
        ref.invalidate(attentionProvider);
        if (data['category'] == 'message') {
          // A message: the Messages badge and list, and — if that thread is
          // the one on screen — the thread itself (no banner is shown then).
          ref.invalidate(messagesUnreadProvider);
          ref.invalidate(messagesListProvider);
          final id = data['conversationId'];
          if (id is String && id == push.activeConversationId) {
            // ignore: discarded_futures
            ref.read(conversationProvider(id).notifier).refreshLatest();
          }
        }
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
      if (prev != next) {
        ref.invalidate(unreadCountProvider);
        ref.invalidate(announcementsUnreadProvider);
        ref.invalidate(messagesUnreadProvider);
        ref.invalidate(attentionProvider);
      }
      const names = ['/tab/home', '/tab/browse', '/tab/groups', '/tab/tournaments', '/tab/profile'];
      if (next >= 0 && next < names.length) {
        ref.read(analyticsServiceProvider).logScreen(names[next]);
      }
    });
    final index = ref.watch(homeTabIndexProvider);
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.bg,
      body: _tab(index),
      bottomNavigationBar: ShellBottomBar(
        index: index,
        onSelect: (i) => ref.read(homeTabIndexProvider.notifier).state = i,
      ),
    );
  }
}


/// The app's bottom bar: the floating dock on the page canvas, then the
/// anchored ad strip under it (it collapses to nothing until an ad loads).
/// The system inset goes under the ad, not between the dock and the ad.
///
/// Used by the shell, and by pushed screens that should keep the dock in
/// reach (the group page) — those pass [onSelect] to jump back to a tab.
class ShellBottomBar extends ConsumerWidget {
  const ShellBottomBar({super.key, required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  /// For a pushed screen: select the tab, then return to the shell.
  static void goToTab(BuildContext context, WidgetRef ref, int i) {
    ref.read(homeTabIndexProvider.notifier).state = i;
    context.go('/home');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Dot on the Tournaments tab when a live/upcoming tournament involves one
    // of the user's teams — an invitation to look, never a number.
    final tournamentDot =
        ref.watch(myTournamentsActiveProvider).valueOrNull ?? false;
    final p = context.palette;
    return ColoredBox(
      color: p.bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SpDock(
            index: index,
            onSelect: onSelect,
            items: [
              const SpDockItem(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: 'Home',
              ),
              const SpDockItem(
                icon: Icons.explore_outlined,
                selectedIcon: Icons.explore_rounded,
                label: 'Browse',
              ),
              const SpDockItem(
                icon: Icons.groups_outlined,
                selectedIcon: Icons.groups_rounded,
                label: 'Groups',
              ),
              SpDockItem(
                icon: Icons.emoji_events_outlined,
                selectedIcon: Icons.emoji_events_rounded,
                label: 'Tournaments',
                dot: tournamentDot,
              ),
              const SpDockItem(
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                label: 'Profile',
              ),
            ],
          ),
          const AdMobBannerBar(),
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }
}
