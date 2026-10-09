import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/analytics/analytics_service.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/auth/claim_account_screen.dart';
import 'package:sportpadi_mobile/features/auth/sign_in_screen.dart';
import 'package:sportpadi_mobile/features/auth/forgot_password_screen.dart';
import 'package:sportpadi_mobile/features/auth/verify_email_screen.dart';
import 'package:sportpadi_mobile/features/discussions/discussion_composer_screen.dart';
import 'package:sportpadi_mobile/features/discussions/discussion_screen.dart';
import 'package:sportpadi_mobile/features/discussions/discussions_screen.dart';
import 'package:sportpadi_mobile/features/discussions/my_discussions_screen.dart';
import 'package:sportpadi_mobile/features/events/event_detail_screen.dart';
import 'package:sportpadi_mobile/features/groups/group_detail_screen.dart';
import 'package:sportpadi_mobile/features/join/join_group_screen.dart';
import 'package:sportpadi_mobile/features/notifications/notifications_screen.dart';
import 'package:sportpadi_mobile/features/announcements/announcement_composer_screen.dart';
import 'package:sportpadi_mobile/features/announcements/sent_announcements_screen.dart';
import 'package:sportpadi_mobile/features/inbox/announcement_detail_screen.dart';
import 'package:sportpadi_mobile/features/inbox/conversation_screen.dart';
import 'package:sportpadi_mobile/features/inbox/inbox_screen.dart';
import 'package:sportpadi_mobile/features/groups/group_messages_screen.dart';
import 'package:sportpadi_mobile/features/join/join_team_screen.dart';
import 'package:sportpadi_mobile/features/manage/create_event_screen.dart';
import 'package:sportpadi_mobile/features/manage/create_team_screen.dart';
import 'package:sportpadi_mobile/features/manage/create_tournament_screen.dart';
import 'package:sportpadi_mobile/features/manage/formation_board_screen.dart';
import 'package:sportpadi_mobile/features/games/game_screen.dart';
import 'package:sportpadi_mobile/features/games/officiate_screen.dart';
import 'package:sportpadi_mobile/features/payments/my_fines_screen.dart';
import 'package:sportpadi_mobile/features/players/player_group_stats_screen.dart';
import 'package:sportpadi_mobile/features/players/player_profile_screen.dart';
import 'package:sportpadi_mobile/features/players/player_event_stats_screen.dart';
import 'package:sportpadi_mobile/features/players/player_tournament_stats_screen.dart';
import 'package:sportpadi_mobile/features/groups/group_events_screen.dart';
import 'package:sportpadi_mobile/features/groups/group_leaderboard_screen.dart';
import 'package:sportpadi_mobile/features/progression/progression_screens.dart';
import 'package:sportpadi_mobile/features/groups/group_people_screen.dart';
import 'package:sportpadi_mobile/features/groups/membership_requests_screen.dart';
import 'package:sportpadi_mobile/features/payments/outstanding_tickets_screen.dart';
import 'package:sportpadi_mobile/features/profile/my_qr_screen.dart';
import 'package:sportpadi_mobile/features/profile/my_sports_screen.dart';
import 'package:sportpadi_mobile/features/sports/my_records_screen.dart';
import 'package:sportpadi_mobile/features/sports/sport_record_screen.dart';
import 'package:sportpadi_mobile/features/settings/settings_screen.dart';
import 'package:sportpadi_mobile/features/payments/my_tickets_screen.dart';
import 'package:sportpadi_mobile/features/scan/scan_screen.dart';
import 'package:sportpadi_mobile/features/manage/manage_roster_screen.dart';
import 'package:sportpadi_mobile/features/manage/tournament_invites_screen.dart';
import 'package:sportpadi_mobile/features/manage/group_fines_screen.dart';
import 'package:sportpadi_mobile/features/manage/group_tickets_screen.dart';
import 'package:sportpadi_mobile/features/wallet/group_wallet_screen.dart';
import 'package:sportpadi_mobile/features/wallet/wallet_withdrawals_screen.dart';
import 'package:sportpadi_mobile/features/shell/guest_shell.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart';
import 'package:sportpadi_mobile/features/billing/group_plan_screen.dart';
import 'package:sportpadi_mobile/features/splash/splash_screen.dart';
import 'package:sportpadi_mobile/features/teams/team_detail_screen.dart';
import 'package:sportpadi_mobile/features/tournaments/tournament_invitations_screen.dart';
import 'package:sportpadi_mobile/features/tournaments/my_team_tournaments_screen.dart';
import 'package:sportpadi_mobile/features/tournaments/tournament_detail_screen.dart';
import 'package:sportpadi_mobile/features/tournaments/tournament_team_screen.dart';
import 'package:sportpadi_mobile/features/wards/ward_detail_screen.dart';
import 'package:sportpadi_mobile/features/wards/wards_screen.dart';
import 'package:sportpadi_mobile/features/onboarding/intent_cards.dart'
    show pendingIntentProvider;
import 'package:sportpadi_mobile/features/onboarding/start_wizard_screen.dart';

/// Declarative routes with an auth-aware redirect. Join links stay reachable
/// while signed out (the join screen prompts sign-in itself), matching the web
/// share flow.
/// Bridges Riverpod auth state into GoRouter's refreshListenable so the router
/// is created ONCE and re-evaluates its redirect when auth changes — instead
/// of being rebuilt (which wipes the navigation stack and every back button's
/// history) every time the auth provider emits.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authControllerProvider, (prev, next) {
      notifyListeners();
      // Signing OUT from a pushed page (Settings, a group, an event…) needs
      // an explicit move: the redirect above only re-evaluates the BASE
      // location of the stack, and /home is open to guests, so the pushed
      // page would simply stay on screen without a session. Land on the
      // guest dashboard, stack cleared, like the web's sign-out.
      final wasIn = prev?.valueOrNull?.isAuthenticated ?? false;
      final isIn = next.valueOrNull?.isAuthenticated ?? false;
      if (wasIn && !isIn) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => router?.go('/home'));
      }
    });
  }

  /// Set once the router exists (it needs this notifier first).
  GoRouter? router;
}

/// Where sign-in should drop the user afterwards, if the `redirect` query
/// parameter names somewhere sane: an in-app path, never an absolute URL
/// (open-redirect hygiene, even inside an app) and never sign-in itself.
String? safeRedirectTarget(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final v = Uri.decodeComponent(raw);
  if (!v.startsWith('/') || v.startsWith('//')) return null;
  final path = Uri.tryParse(v)?.path ?? v;
  if (path == '/' ||
      path == '/sign-in' ||
      path == '/forgot-password' ||
      path == '/verify-email') {
    return null;
  }
  return v;
}

/// `/home` is the same address whether or not you're signed in; which shell
/// renders there is decided here, live, so signing in (or out) swaps the
/// shell in place without a route change.
class _HomeGate extends ConsumerWidget {
  const _HomeGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn =
        ref.watch(authControllerProvider).valueOrNull?.isAuthenticated ?? false;
    return signedIn ? const HomeShell() : const GuestShell();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  // Google Analytics: fire-and-forget init, then log every navigation as a
  // screen view (quiet no-op until Firebase is configured).
  final analytics = ref.watch(analyticsServiceProvider);
  // ignore: discarded_futures
  analytics.init();

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      if (auth.isLoading || !auth.hasValue) return loc == '/' ? null : '/';
      final session = auth.value;
      final signedIn = session?.isAuthenticated ?? false;
      if (!signedIn) {
        // Signed out is not a wall any more. Home (the guest dashboard),
        // Browse (a tab inside it) and join links are open; the app lands
        // there so a newcomer sees what's on before they're asked for
        // anything. Everything else — an event, a group, a profile — needs
        // an account, and we remember where they were headed so sign-in
        // drops them there rather than back on Home.
        // `/claim/<token>`: a ward taking over their account (Wards 3) has
        // no session yet — the link's token is the credential.
        if (loc == '/sign-in' ||
            loc == '/forgot-password' ||
            loc == '/home' ||
            loc.startsWith('/join') ||
            loc.startsWith('/claim/')) {
          return null;
        }
        if (loc == '/') return '/home';
        return '/sign-in?redirect=${Uri.encodeComponent(state.uri.toString())}';
      }
      // Every account confirms its email before it can use the app (the same
      // rule the web enforces, and the server now refuses create/join/buy
      // calls until it's done).
      if (session?.needsEmailVerification ?? false) {
        return loc == '/verify-email' ? null : '/verify-email';
      }
      if (loc == '/sign-in' ||
          loc == '/forgot-password' ||
          loc == '/' ||
          loc == '/verify-email') {
        // An intent card picked before sign-up: its start wizard comes
        // first (verify-email replaces the stack, so the redirect query
        // alone wouldn't survive).
        final pending = ref.read(pendingIntentProvider);
        return safeRedirectTarget(state.uri.queryParameters['redirect']) ??
            (pending != null ? '/start/$pending' : null) ??
            '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, st) =>
            ForgotPasswordScreen(email: st.uri.queryParameters['email']),
      ),
      GoRoute(
          path: '/verify-email', builder: (_, __) => const VerifyEmailScreen()),
      // A guardian handed this account over: choose a password (public).
      GoRoute(
        path: '/claim/:token',
        builder: (_, st) =>
            ClaimAccountScreen(token: st.pathParameters['token']!),
      ),
      GoRoute(path: '/home', builder: (_, __) => const _HomeGate()),
      // After sign-in with an intent: the steps, then the first relevant page.
      GoRoute(
          path: '/start/:intent',
          builder: (_, st) =>
              StartWizardScreen(intentKey: st.pathParameters['intent']!)),
      GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen()),
      // Inbox: announcements (Messaging 1) and messages (Messaging 2).
      // Announcement pushes deep-link to /inbox/announcements/<id>, message
      // pushes to /inbox/messages/<id>; /inbox?tab=messages opens Messages.
      GoRoute(
        path: '/inbox',
        builder: (_, st) =>
            InboxScreen(initialTab: st.uri.queryParameters['tab']),
      ),
      GoRoute(
        path: '/inbox/announcements/:id',
        builder: (_, st) =>
            AnnouncementDetailScreen(id: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/inbox/messages/:id',
        builder: (_, st) => ConversationScreen(id: st.pathParameters['id']!),
      ),
      // Gamification (docs/gamification/phase-2.md).
      GoRoute(path: '/progress', builder: (_, __) => const ProgressScreen()),
      GoRoute(
          path: '/leaderboards',
          builder: (_, __) => const LeaderboardsScreen()),
      GoRoute(
        path: '/games/:id/summary',
        builder: (_, st) =>
            MatchSummaryScreen(gameId: st.pathParameters['id']!),
      ),
      // Officiant mode: the timekeeper's locked-in, full-screen clock.
      GoRoute(
        path: '/games/:id/officiate',
        builder: (_, st) => OfficiateScreen(gameId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/tournaments/invitations',
        builder: (_, __) => const TournamentInvitationsScreen(),
      ),
      // Declared before /players/:id's own route so the literal segment wins.
      // One sport's record (docs/design/sport-records.md §3).
      GoRoute(
        path: '/players/:id/records/:categoryId',
        builder: (_, st) => SportRecordScreen(
          userId: st.pathParameters['id']!,
          categoryId: st.pathParameters['categoryId']!,
        ),
      ),
      GoRoute(
        path: '/players/:id/tournaments/:eventId',
        builder: (_, st) => PlayerTournamentStatsScreen(
          userId: st.pathParameters['id']!,
          eventId: st.pathParameters['eventId']!,
        ),
      ),
      GoRoute(
        path: '/players/:id/events/:eventId',
        builder: (_, st) => PlayerEventStatsScreen(
          userId: st.pathParameters['id']!,
          eventId: st.pathParameters['eventId']!,
        ),
      ),
      GoRoute(
        path: '/players/:id/groups/:groupId',
        builder: (_, st) => PlayerGroupStatsScreen(
          userId: st.pathParameters['id']!,
          groupId: st.pathParameters['groupId']!,
        ),
      ),
      GoRoute(
        path: '/players/:id',
        builder: (_, st) =>
            PlayerProfileScreen(userId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id',
        builder: (_, s) => GroupDetailScreen(groupId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/teams/:id',
        builder: (_, s) => TeamDetailScreen(teamId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/teams/:id/manage',
        builder: (_, s) => ManageRosterScreen(teamId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/teams/:id/formation',
        builder: (_, s) =>
            FormationBoardScreen(teamId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/new-event',
        // ?team=<id>[,<id>] opens it as a team event for those teams.
        builder: (_, s) => CreateEventScreen(
            groupId: s.pathParameters['id']!,
            initialTeamIds: [
              for (final id in (s.uri.queryParameters['team'] ?? '').split(','))
                if (id.trim().isNotEmpty) id.trim()
            ]),
      ),
      GoRoute(
        path: '/groups/:id/new-team',
        builder: (_, s) => CreateTeamScreen(
            groupId: s.pathParameters['id']!,
            categoryId: s.uri.queryParameters['category']),
      ),
      GoRoute(
        path: '/groups/:id/new-tournament',
        builder: (_, s) =>
            CreateTournamentScreen(groupId: s.pathParameters['id']!),
      ),
      // Announcements for staff: compose (optionally aimed at a team or an
      // event) and the sent list with seen counts.
      GoRoute(
        path: '/groups/:id/announcements/new',
        builder: (_, s) => AnnouncementComposerScreen(
          groupId: s.pathParameters['id']!,
          teamId: s.uri.queryParameters['team'],
          eventId: s.uri.queryParameters['event'],
        ),
      ),
      GoRoute(
        path: '/groups/:id/announcements',
        builder: (_, s) =>
            SentAnnouncementsScreen(groupId: s.pathParameters['id']!),
      ),
      // Admins: every conversation in the group (read-only) and reports.
      GoRoute(
        path: '/groups/:id/messages',
        builder: (_, s) => GroupMessagesScreen(
          groupId: s.pathParameters['id']!,
          initialTab: s.uri.queryParameters['tab'],
        ),
      ),
      // Discussions: a group's list (?team=<teamId|group> opens one space),
      // the composer (?team= preselects where), and one thread — the
      // canonical /discussions/<id> that comment notifications link to.
      GoRoute(
        path: '/groups/:id/discussions',
        builder: (_, s) => DiscussionsScreen(
          groupId: s.pathParameters['id']!,
          initialSpace: s.uri.queryParameters['team'],
        ),
      ),
      GoRoute(
        path: '/groups/:id/discussions/new',
        builder: (_, s) => DiscussionComposerScreen(
          groupId: s.pathParameters['id']!,
          initialSpace: s.uri.queryParameters['team'],
        ),
      ),
      // Every discussion I can see, across all my groups (the side menu).
      GoRoute(
        path: '/discussions',
        builder: (_, __) => const MyDiscussionsScreen(),
      ),
      GoRoute(
        path: '/discussions/:id',
        builder: (_, s) => DiscussionScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/invites',
        builder: (_, s) =>
            TournamentInvitesScreen(groupId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/scan', builder: (_, __) => const ScanScreen()),
      GoRoute(path: '/tickets', builder: (_, __) => const MyTicketsScreen()),
      // One receipt (the "ticket paid" notification and receipt emails link
      // to /tickets/<code>): the list, with that ticket open.
      GoRoute(
        path: '/tickets/:code',
        builder: (_, st) =>
            MyTicketsScreen(openCode: st.pathParameters['code']),
      ),
      GoRoute(path: '/fines', builder: (_, __) => const MyFinesScreen()),
      GoRoute(path: '/my-qr', builder: (_, __) => const MyQrScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      // Activity & stats (profile menu): the sports I play, and my records
      // sport by sport. The own record page is the public one plus the
      // owner's actions.
      GoRoute(
          path: '/profile/sports', builder: (_, __) => const MySportsScreen()),
      GoRoute(
          path: '/profile/records',
          builder: (_, __) => const MyRecordsScreen()),
      GoRoute(
        path: '/profile/records/:categoryId',
        builder: (_, st) => SportRecordScreen(
          userId: ref.read(authControllerProvider).valueOrNull?.user?.id ?? '',
          categoryId: st.pathParameters['categoryId']!,
          isMe: true,
        ),
      ),
      // Wards (players a guardian manages). Co-guardian invite notifications
      // link to /profile/wards.
      GoRoute(path: '/profile/wards', builder: (_, __) => const WardsScreen()),
      GoRoute(
        path: '/profile/wards/:id',
        builder: (_, st) => WardDetailScreen(wardId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/events',
        builder: (_, st) =>
            GroupEventsScreen(groupId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/plan',
        builder: (_, st) => GroupPlanScreen(groupId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/leaderboard',
        builder: (_, st) =>
            GroupLeaderboardScreen(groupId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/wallet',
        builder: (_, st) =>
            GroupWalletScreen(groupId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/wallet/withdrawals',
        builder: (_, st) =>
            WalletWithdrawalsScreen(groupId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/tickets',
        builder: (_, st) =>
            GroupTicketsScreen(groupId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/fines',
        builder: (_, st) => GroupFinesScreen(groupId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/outstanding',
        builder: (_, st) =>
            OutstandingTicketsScreen(groupId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/members',
        builder: (_, st) => GroupPeopleScreen(
            groupId: st.pathParameters['id']!, kind: 'members'),
      ),
      GoRoute(
        path: '/groups/:id/followers',
        builder: (_, st) => GroupPeopleScreen(
            groupId: st.pathParameters['id']!, kind: 'followers'),
      ),
      // The owner's membership requests (the "asked to join" notification).
      GoRoute(
        path: '/groups/:id/requests',
        builder: (_, st) =>
            MembershipRequestsScreen(groupId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/games/:id',
        builder: (_, st) => GameScreen(gameId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/events/:slug',
        builder: (_, s) => EventDetailScreen(slug: s.pathParameters['slug']!),
      ),
      // A team's tournaments (from a team card on the Tournaments tab).
      GoRoute(
        path: '/tournaments/teams/:teamId',
        builder: (_, s) =>
            MyTeamTournamentsScreen(teamId: s.pathParameters['teamId']!),
      ),
      GoRoute(
        path: '/tournaments/:id',
        builder: (_, s) =>
            TournamentDetailScreen(eventId: s.pathParameters['id']!),
      ),
      // Web-shaped tournament URLs (notification deep links + shares).
      GoRoute(
        path: '/groups/:id/tournaments/:eventId',
        builder: (_, s) =>
            TournamentDetailScreen(eventId: s.pathParameters['eventId']!),
      ),
      // The team AS IT IS in one tournament: squad, event formation, games.
      GoRoute(
        path: '/groups/:id/tournaments/:eventId/teams/:teamId',
        builder: (_, s) => TournamentTeamScreen(
          groupId: s.pathParameters['id']!,
          eventId: s.pathParameters['eventId']!,
          teamId: s.pathParameters['teamId']!,
          respond: s.uri.queryParameters['respond'] != null,
        ),
      ),
      GoRoute(
        path: '/groups/:id/tournaments/:eventId/teams/:teamId/formation',
        builder: (_, s) => FormationBoardScreen(
          teamId: s.pathParameters['teamId']!,
          eventId: s.pathParameters['eventId'],
        ),
      ),
      // Deep-link share targets (match the web URLs).
      GoRoute(
        path: '/join/:groupId',
        builder: (_, s) =>
            JoinGroupScreen(groupId: s.pathParameters['groupId']!),
      ),
      GoRoute(
        path: '/join-team/:teamId',
        builder: (_, s) => JoinTeamScreen(teamId: s.pathParameters['teamId']!),
      ),
    ],
  );
  router.routerDelegate.addListener(() {
    analytics
        .logScreen(router.routerDelegate.currentConfiguration.uri.toString());
  });
  refresh.router = router;
  return router;
});
