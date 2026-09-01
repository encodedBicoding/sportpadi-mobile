import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/analytics/analytics_service.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/auth/sign_in_screen.dart';
import 'package:sportpadi_mobile/features/events/event_detail_screen.dart';
import 'package:sportpadi_mobile/features/groups/group_detail_screen.dart';
import 'package:sportpadi_mobile/features/join/join_group_screen.dart';
import 'package:sportpadi_mobile/features/notifications/notifications_screen.dart';
import 'package:sportpadi_mobile/features/join/join_team_screen.dart';
import 'package:sportpadi_mobile/features/manage/create_event_screen.dart';
import 'package:sportpadi_mobile/features/manage/create_team_screen.dart';
import 'package:sportpadi_mobile/features/manage/create_tournament_screen.dart';
import 'package:sportpadi_mobile/features/manage/formation_board_screen.dart';
import 'package:sportpadi_mobile/features/games/game_screen.dart';
import 'package:sportpadi_mobile/features/payments/my_fines_screen.dart';
import 'package:sportpadi_mobile/features/players/player_profile_screen.dart';
import 'package:sportpadi_mobile/features/groups/group_events_screen.dart';
import 'package:sportpadi_mobile/features/groups/group_leaderboard_screen.dart';
import 'package:sportpadi_mobile/features/groups/group_people_screen.dart';
import 'package:sportpadi_mobile/features/payments/outstanding_tickets_screen.dart';
import 'package:sportpadi_mobile/features/profile/my_qr_screen.dart';
import 'package:sportpadi_mobile/features/settings/settings_screen.dart';
import 'package:sportpadi_mobile/features/payments/my_tickets_screen.dart';
import 'package:sportpadi_mobile/features/scan/scan_screen.dart';
import 'package:sportpadi_mobile/features/manage/manage_roster_screen.dart';
import 'package:sportpadi_mobile/features/manage/tournament_invites_screen.dart';
import 'package:sportpadi_mobile/features/manage/group_tickets_screen.dart';
import 'package:sportpadi_mobile/features/wallet/group_wallet_screen.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart';
import 'package:sportpadi_mobile/features/splash/splash_screen.dart';
import 'package:sportpadi_mobile/features/teams/team_detail_screen.dart';
import 'package:sportpadi_mobile/features/tournaments/tournament_detail_screen.dart';

/// Declarative routes with an auth-aware redirect. Join links stay reachable
/// while signed out (the join screen prompts sign-in itself), matching the web
/// share flow.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);

  // Google Analytics: fire-and-forget init, then log every navigation as a
  // screen view (quiet no-op until Firebase is configured).
  final analytics = ref.watch(analyticsServiceProvider);
  // ignore: discarded_futures
  analytics.init();

  final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (auth.isLoading || !auth.hasValue) return loc == '/' ? null : '/';
      final signedIn = auth.value?.isAuthenticated ?? false;
      final isJoin = loc.startsWith('/join');
      if (!signedIn) {
        if (loc == '/sign-in' || isJoin) return null;
        return '/sign-in';
      }
      if (loc == '/sign-in' || loc == '/') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeShell()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
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
        builder: (_, s) => FormationBoardScreen(teamId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/new-event',
        builder: (_, s) => CreateEventScreen(groupId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/new-team',
        builder: (_, s) => CreateTeamScreen(groupId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/new-tournament',
        builder: (_, s) => CreateTournamentScreen(groupId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/invites',
        builder: (_, s) => TournamentInvitesScreen(groupId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/scan', builder: (_, __) => const ScanScreen()),
      GoRoute(path: '/tickets', builder: (_, __) => const MyTicketsScreen()),
      GoRoute(path: '/fines', builder: (_, __) => const MyFinesScreen()),
      GoRoute(path: '/my-qr', builder: (_, __) => const MyQrScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: '/groups/:id/events',
        builder: (_, st) =>
            GroupEventsScreen(groupId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/leaderboard',
        builder: (_, st) =>
            GroupLeaderboardScreen(groupId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/wallet',
        builder: (_, st) => GroupWalletScreen(groupId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/groups/:id/tickets',
        builder: (_, st) => GroupTicketsScreen(groupId: st.pathParameters['id']!),
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
      GoRoute(
        path: '/games/:id',
        builder: (_, st) => GameScreen(gameId: st.pathParameters['id']!),
      ),
      GoRoute(
        path: '/events/:slug',
        builder: (_, s) => EventDetailScreen(slug: s.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/tournaments/:id',
        builder: (_, s) =>
            TournamentDetailScreen(eventId: s.pathParameters['id']!),
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
  return router;
});
