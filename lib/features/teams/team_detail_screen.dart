import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/features/manage/add_team_player.dart';
import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart'
    show announcementComposerProvider, pinnedAnnouncementsProvider;
import 'package:sportpadi_mobile/data/discussions/discussions_repository.dart'
    show DiscussionListKey, discussionListProvider, discussionSpacesProvider;
import 'package:sportpadi_mobile/data/groups/groups_repository.dart'
    show teamTalkCountsProvider;
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/messages/messages_repository.dart'
    show messageStartOptionsProvider;
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/data/tournaments/squad_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/groups/members_repository.dart';
import 'package:sportpadi_mobile/features/announcements/announcement_entry_points.dart';
import 'package:sportpadi_mobile/features/groups/group_talk_section.dart';
import 'package:sportpadi_mobile/features/inbox/message_entry_points.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/team_tile.dart'
    show kitGradient;
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';
import 'package:sportpadi_mobile/features/ads/ad_anchor.dart';

/// Team page — mirrors the web team page: header + record, then scrollable
/// tabs: Players (starters/subs, invite, add), Formation, Coaches, Games.
class TeamDetailScreen extends ConsumerStatefulWidget {
  const TeamDetailScreen({super.key, required this.teamId});
  final String teamId;

  @override
  ConsumerState<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends ConsumerState<TeamDetailScreen>
    with WidgetsBindingObserver {
  int _tab = 0; // 0 players, 1 tournaments, 2 coaches, 3 games

  // Back-on-top detection: the router's changes, checked against this
  // page's route once the frame has settled.
  GoRouter? _router;
  ModalRoute<dynamic>? _route;
  bool _onTop = true;

  String get teamId => widget.teamId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final router = GoRouter.of(context);
    if (!identical(router, _router)) {
      _router?.routerDelegate.removeListener(_onRouteChanged);
      _router = router;
      router.routerDelegate.addListener(_onRouteChanged);
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshLive();
  }

  /// The router moved (a push or a pop somewhere): once the frame has
  /// settled, see whether this page just came back on top.
  void _onRouteChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final onTop = _route?.isCurrent ?? true;
      if (onTop && !_onTop) _refreshLive();
      _onTop = onTop;
    });
  }

  /// What can change while the page is out of sight: the Talk badges and
  /// the pinned announcements (opening one marks it seen).
  void _refreshLive() {
    final groupId = ref.read(teamDetailProvider(teamId)).valueOrNull?.groupId;
    if (groupId == null) return;
    ref.invalidate(teamTalkCountsProvider((groupId: groupId, teamId: teamId)));
    ref.invalidate(
        pinnedAnnouncementsProvider((groupId: groupId, teamId: teamId)));
  }

  void _refetch() {
    ref.invalidate(teamDetailProvider(teamId));
    ref.invalidate(teamStatsProvider(teamId));
    ref.invalidate(teamWardInvitesProvider(teamId));
  }

  /// Pull to refresh: everything the page shows — the team and its record,
  /// the pinned announcements, the Talk tiles, "Create team event" and every
  /// tab. The spinner waits for the team, the header and the open tab.
  Future<void> _pullRefresh() {
    final t = ref.read(teamDetailProvider(teamId)).valueOrNull;
    final groupId = t?.groupId;
    // The tabs key their data by the loaded team's id.
    final id = t?.id ?? teamId;
    _refetch(); // team, record, wards waiting for a guardian
    _refreshLive(); // Talk badges, pinned announcements
    ref.invalidate(teamWardInvitesProvider(id));
    ref.invalidate(teamTournamentsProvider(id));
    ref.invalidate(teamCoachesProvider(id));
    ref.invalidate(teamGamesProvider(teamId));
    if (groupId != null) {
      // The Talk tile's "hot" team discussions (GroupTalkSection's key).
      final DiscussionListKey hot = (
        groupId: groupId,
        space: teamId,
        sort: 'hot',
        flair: null,
        status: null,
      );
      ref.invalidate(eventAudiencesProvider(groupId));
      ref.invalidate(announcementComposerProvider(groupId));
      ref.invalidate(messageStartOptionsProvider(groupId));
      ref.invalidate(discussionSpacesProvider(groupId));
      ref.invalidate(discussionListProvider(hot));
    }
    return settleAll([
      ref.read(teamDetailProvider(teamId).future),
      // The rest is only on screen (watched) once the team is.
      if (t != null) ...[
        ref.read(teamStatsProvider(teamId).future),
        if (_tab == 0 && t.canManage)
          ref.read(teamWardInvitesProvider(id).future),
        if (_tab == 1) ref.read(teamTournamentsProvider(id).future),
        if (_tab == 2) ref.read(teamCoachesProvider(id).future),
        if (_tab == 3) ref.read(teamGamesProvider(teamId).future),
        if (groupId != null) ...[
          ref.read(pinnedAnnouncementsProvider(
                  (groupId: groupId, teamId: teamId))
              .future),
          ref.read(teamTalkCountsProvider((groupId: groupId, teamId: teamId))
              .future),
          ref.read(eventAudiencesProvider(groupId).future),
        ],
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final team = ref.watch(teamDetailProvider(teamId));
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          _pullableUnlessData(
            team,
            _pullRefresh,
            AsyncView(
            value: team,
            onRetry: _refetch,
            data: (t) {
              // No general formation any more — formations live per
              // tournament on the squad, which is what the Tournaments tab
              // opens.
              const tabs = ['Players', 'Tournaments', 'Coaches', 'Games'];
              return RefreshIndicator(
                onRefresh: _pullRefresh,
                child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                  SliverToBoxAdapter(child: _Header(team: t, teamId: teamId)),
                  // The team's pinned announcements — their own section,
                  // hidden when there are none — and Talk, as on the group
                  // page: Announcements (Open Inbox; Announce to team / Sent
                  // for its coaches and the group's admins), Messages
                  // (Message coach for its players and their guardians;
                  // Message a player for its staff) and Discussions (the
                  // team's) as tiles with badges, each opening a sheet.
                  if (t.groupId != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GroupPinnedAnnouncementsSection(
                                groupId: t.groupId!, teamId: teamId),
                            GroupTalkSection.team(
                                groupId: t.groupId!,
                                teamId: teamId,
                                teamName: t.name),
                          ],
                        ),
                      ),
                    ),
                  // "Create team event" for the group's admins and this
                  // team's coaches.
                  if (t.groupId != null)
                    SliverToBoxAdapter(
                      child:
                          _TeamEventButton(groupId: t.groupId!, teamId: teamId),
                    ),
                  // Tab chips pin while the header scrolls away.
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _PinnedTeamTabs(
                      child: Container(
                        color: p.bg,
                        padding: const EdgeInsets.fromLTRB(20, 8, 0, 8),
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (var i = 0; i < tabs.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Material(
                                  color: _tab == i ? p.hero : p.surface,
                                  shape: StadiumBorder(
                                      side: _tab == i
                                          ? BorderSide.none
                                          : BorderSide(color: p.line)),
                                  child: InkWell(
                                    customBorder: const StadiumBorder(),
                                    onTap: () => setState(() => _tab = i),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 9),
                                      child: Text(tabs[i],
                                          style: TextStyle(
                                              color:
                                                  _tab == i ? p.onHero : p.ink,
                                              fontSize: 13,
                                              fontWeight: _tab == i
                                                  ? FontWeight.w700
                                                  : FontWeight.w600)),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
                    sliver: SliverList(
                        delegate: SliverChildListDelegate([
                      if (_tab == 0)
                        _PlayersTab(team: t, onChanged: _refetch)
                      else if (_tab == 1)
                        _TournamentsTab(team: t)
                      else if (_tab == 2)
                        _CoachesTab(team: t)
                      else
                        _GamesTab(teamId: teamId),
                    ])),
                  ),
                ]),
              );
            },
          ),
          ),
          if (team.valueOrNull == null)
            Positioned(
              left: 16,
              top: 12,
              child: SpRoundButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                tooltip: 'Back',
                onTap: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
              ),
            ),
        ]),
      ),
    );
  }
}

/// "Create team event" — opens event creation preselected to this team. Shown
/// when the event-audiences endpoint lists the team (admins: every team;
/// coaches: the teams they coach); hidden for everyone else.
class _TeamEventButton extends ConsumerWidget {
  const _TeamEventButton({required this.groupId, required this.teamId});
  final String groupId;
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(eventAudiencesProvider(groupId)).valueOrNull;
    if (options == null || !options.hasTeam(teamId)) {
      return const SizedBox.shrink();
    }
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Material(
        color: p.surface,
        shape: StadiumBorder(side: BorderSide(color: p.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => context.push('/groups/$groupId/new-event?team=$teamId'),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.event_available_outlined, size: 17, color: p.ink),
              const SizedBox(width: 6),
              Flexible(
                child: Text('Create team event',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header (2026) — the kit as an edge-to-edge banner with round back / share,
// and the identity card overlapping it: crest, name, handle, sport, venue,
// the record, and the admin actions.
// ---------------------------------------------------------------------------

class _Header extends ConsumerWidget {
  const _Header({required this.team, required this.teamId});
  final TeamDetail team;
  final String teamId;

  static const double _bannerH = 170;
  static const double _overlap = 50;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final t = team;
    final stats = ref.watch(teamStatsProvider(teamId)).valueOrNull;
    final canPop = context.canPop() || Navigator.of(context).canPop();

    void copyJoin() {
      final base = ref.read(appConfigProvider).apiBaseUrl;
      Clipboard.setData(ClipboardData(text: '$base/join-team/${t.id}'));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Join link copied — share it to invite players')));
    }

    Widget stat(String value, String label, [Color? tone]) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              Text(value,
                  style: TextStyle(
                      color: tone ?? p.ink,
                      fontSize: 18,
                      height: 1.1,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(color: p.muted, fontSize: 11)),
            ]),
          ),
        );

    final gd = stats == null ? 0 : stats.goalsFor - stats.goalsAgainst;
    final card = GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.surface, width: 3),
            ),
            child: Crest(
                logoUrl: t.logoUrl,
                kitPrimary: t.kitPrimary,
                kitSecondary: t.kitSecondary,
                label: t.name,
                size: 64),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 20,
                        height: 1.2,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w800)),
                if (t.username != null)
                  Text('@${t.username}',
                      style: TextStyle(color: p.muted, fontSize: 12.5)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (t.categoryName != null)
            _pill(p, t.categoryName!, p.accentTint, p.greenText),
          _pill(
              p,
              '${t.members.length} player${t.members.length == 1 ? '' : 's'}',
              p.surface2,
              p.ink),
          if (t.grade != null) _pill(p, t.gradeLabel, p.surface2, p.ink),
          if (t.homeVenue != null)
            _pill(p, t.homeVenue!, p.surface2, p.ink,
                icon: Icons.place_outlined),
        ]),
        if ((t.description ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(t.description!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.5)),
        ],
        if (stats != null && stats.played > 0) ...[
          const SizedBox(height: 14),
          Row(children: [
            stat('${stats.played}', 'Played'),
            const SizedBox(width: 8),
            stat('${stats.won}-${stats.drawn}-${stats.lost}', 'W-D-L',
                p.greenText),
            const SizedBox(width: 8),
            stat('${gd > 0 ? '+' : ''}$gd', 'Goal diff',
                gd < 0 ? p.danger : null),
          ]),
        ],
        if (t.canManage) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: SpButton(
                label: 'Add player',
                icon: Icons.person_add_alt_rounded,
                expand: true,
                onTap: () => _PlayersTab.addPlayer(context, ref, t, () {
                  ref.invalidate(teamDetailProvider(teamId));
                  ref.invalidate(teamStatsProvider(teamId));
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Material(
                color: p.surface,
                shape: StadiumBorder(side: BorderSide(color: p.line)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: copyJoin,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.link_rounded, size: 17, color: p.ink),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text('Invite link',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: p.ink,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ]),
                  ),
                ),
              ),
            ),
          ]),
        ],
      ]),
    );

    return Stack(children: [
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(32)),
          child: Container(
            height: _bannerH,
            decoration: BoxDecoration(
              gradient: kitGradient(t.kitPrimary, t.kitSecondary),
            ),
            child: CustomPaint(painter: _StripesPainter()),
          ),
        ),
      ),
      Positioned(
        left: 16,
        top: 12,
        child: SpRoundButton(
          icon: canPop ? Icons.arrow_back_ios_new_rounded : Icons.home_outlined,
          iconSize: canPop ? 18 : 21,
          tooltip: canPop ? 'Back' : 'Home',
          onTap: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      if (t.groupId != null)
        Positioned(
          right: 16,
          top: 12,
          child: Row(children: [
            // Group admins: delete the team (confirmed; the server refuses
            // while it's in an unfinished tournament).
            if (t.canManage) ...[
              SpRoundButton(
                icon: Icons.delete_outline_rounded,
                tooltip: 'Delete team',
                onTap: () => _deleteTeam(context, ref, t),
              ),
              const SizedBox(width: 8),
            ],
            SpRoundButton(
              icon: Icons.groups_outlined,
              tooltip: 'Open group',
              onTap: () => context.push('/groups/${t.groupId}'),
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, _bannerH - _overlap, 16, 8),
        child: card,
      ),
    ]);
  }

  Widget _pill(AppPalette p, String label, Color bg, Color fg,
          {IconData? icon}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}

/// Soft diagonal kit stripes over the banner.
/// "Delete <team>?" → delete → back to the group's Teams. The roster,
/// coaches and team discussions go with it; finished tournaments it played
/// in stop listing it. Refused (with the reason) while it's entered in a
/// tournament that hasn't finished.
Future<void> _deleteTeam(
    BuildContext context, WidgetRef ref, TeamDetail t) async {
  final p = context.palette;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete ${t.name}?'),
      content: const Text(
          'This removes the team, its roster and coaches, and its team '
          'discussions. Finished tournaments it played in will no longer '
          'list it. This cannot be undone.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: p.danger),
            child: const Text('Delete team')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final groupId = t.groupId;
  try {
    await ref.read(manageRepositoryProvider).deleteTeam(t.id);
    messenger.showSnackBar(SnackBar(content: Text('${t.name} deleted')));
    if (groupId != null) {
      // The Teams tab, and the sport is free again on one-per-sport plans.
      container.invalidate(groupTeamsProvider(groupId));
      container.invalidate(teamAllowanceProvider(groupId));
    }
    if (router.canPop()) {
      router.pop();
    } else if (groupId != null) {
      router.go('/groups/$groupId');
    } else {
      router.go('/home');
    }
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

class _StripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 18;
    for (double x = -size.height; x < size.width; x += 56) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ---------------------------------------------------------------------------
// Players tab — starters / subs, invite link + add player (admin), tap a
// player for stats (and admin edits: jersey, positions, starter, captain).
// ---------------------------------------------------------------------------

class _PlayersTab extends ConsumerWidget {
  const _PlayersTab({required this.team, required this.onChanged});
  final TeamDetail team;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    // One roster pool: starters/subs are decided per tournament on the squad.
    final roster = team.members;
    // Admins: wards invited onto the team, waiting for a guardian's yes.
    final waiting = team.canManage
        ? ref.watch(teamWardInvitesProvider(team.id)).valueOrNull ??
            const <TeamWardInvite>[]
        : const <TeamWardInvite>[];
    final waitingSection = waiting.isEmpty
        ? const <Widget>[]
        : <Widget>[
            const SizedBox(height: 22),
            SpSectionTitle('Waiting for a guardian', count: waiting.length),
            const SizedBox(height: 4),
            Text('Wards join once one of their guardians accepts.',
                style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 10),
            SpListCard(children: [
              for (final i in waiting) _waitingRow(context, ref, i),
            ]),
          ];
    if (roster.isEmpty) {
      final empty = GlassCard(
        padding: const EdgeInsets.all(22),
        child: Column(children: [
          const SpIconTile(Icons.groups_outlined, size: 52, iconSize: 24),
          const SizedBox(height: 10),
          Text(
            'No players yet${team.canManage ? ' — add them from your group members.' : '.'}',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13),
          ),
        ]),
      );
      if (waitingSection.isEmpty) return empty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [empty, ...waitingSection],
      );
    }
    // Ads between roster rows — owner console anchor "team.players".
    final ads = AdInterleave.of(ref, 'team.players', roster.length,
        padding: const EdgeInsets.symmetric(vertical: 8));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSectionTitle('Roster', count: roster.length),
        const SizedBox(height: 10),
        SpListCard(children: [
          for (final (i, m) in roster.indexed) ...[
            _memberRow(context, ref, m),
            ...ads.afterRow(i),
          ],
        ]),
        ...waitingSection,
      ],
    );
  }

  Widget _waitingRow(BuildContext context, WidgetRef ref, TeamWardInvite i) {
    final p = context.palette;
    final sub = [
      if (i.positions.isNotEmpty) i.positions.join(' · '),
      if (i.jerseyNumber != null) '#${i.jerseyNumber}',
      'Invited',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: [
        ClipOval(
          child: Crest(logoUrl: i.avatarUrl, label: i.displayName, size: 36),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(i.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
                const WardBadge(),
              ]),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.orangeInk, fontSize: 12)),
            ],
          ),
        ),
        TextButton(
          onPressed: () => _cancelWardInvite(context, ref, i),
          child: const Text('Cancel'),
        ),
      ]),
    );
  }

  Future<void> _cancelWardInvite(
      BuildContext context, WidgetRef ref, TeamWardInvite i) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(manageRepositoryProvider)
          .cancelWardInvite(team.id, i.inviteId);
      ref.invalidate(teamWardInvitesProvider(team.id));
      messenger
          .showSnackBar(const SnackBar(content: Text('Invitation cancelled.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _memberRow(BuildContext context, WidgetRef ref, TeamMember m) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _openPlayer(context, ref, m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              m.jerseyNumber != null ? '${m.jerseyNumber}' : '–',
              style: TextStyle(
                  color: p.ink, fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          ClipOval(
            child: Crest(logoUrl: m.avatarUrl, label: m.displayName, size: 36),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(m.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (m.isCaptain) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                          color: p.hero,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text('C',
                          style: TextStyle(
                              color: p.onHero,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800)),
                    ),
                  ],
                  if (m.isWard) ...[
                    const SizedBox(width: 6),
                    const WardBadge(),
                  ],
                ]),
                if (m.positions.isNotEmpty)
                  Text(m.positions.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 12)),
              ],
            ),
          ),
          // Staff: message the player (a ward: their guardians).
          if (team.groupId != null)
            MessageMemberButton(
              groupId: team.groupId!,
              memberId: m.playerId,
              name: m.displayName,
              isWard: m.isWard,
            ),
          Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
        ]),
      ),
    );
  }

  void _openPlayer(BuildContext context, WidgetRef ref, TeamMember m) {
    showSpSheet<void>(
      context,
      framed: false,
      builder: (_) => _PlayerSheet(team: team, member: m, onChanged: onChanged),
    );
  }

  /// Add a group member to [team] — shared with the header's Add player.
  /// The web's Add player flow: member → positions / jersey → Add (wards:
  /// their guardians are invited). See manage/add_team_player.dart.
  static Future<void> addPlayer(BuildContext context, WidgetRef ref,
          TeamDetail team, VoidCallback onChanged) =>
      addTeamPlayer(context, ref, team, onChanged: onChanged);
}

// ---------------------------------------------------------------------------
// Player sheet — tournament stats for everyone; jersey/positions/starter/
// captain/remove for group admins.
// ---------------------------------------------------------------------------

class _PlayerSheet extends ConsumerStatefulWidget {
  const _PlayerSheet(
      {required this.team, required this.member, required this.onChanged});
  final TeamDetail team;
  final TeamMember member;
  final VoidCallback onChanged;

  @override
  ConsumerState<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends ConsumerState<_PlayerSheet> {
  late final TextEditingController _jersey =
      TextEditingController(text: widget.member.jerseyNumber?.toString() ?? '');
  late final List<String> _positions = List.of(widget.member.positions);
  bool _busy = false;

  @override
  void dispose() {
    _jersey.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() op, {bool close = false}) async {
    setState(() => _busy = true);
    try {
      await op();
      widget.onChanged();
      if (close && mounted) {
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = widget.member;
    final card = ref
        .watch(
            playerCardProvider((teamId: widget.team.id, playerId: m.playerId)))
        .valueOrNull;
    // A ward whose guardians keep their card private: short name, no photo.
    final restricted = card?.restricted ?? false;
    final name = restricted ? card!.displayName : m.displayName;
    final avatarUrl = restricted ? null : m.avatarUrl;
    final username = restricted ? null : m.username;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        shrinkWrap: true,
        children: [
          Row(children: [
            ClipOval(
              child: Crest(logoUrl: avatarUrl, label: name, size: 44),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ),
                    if (m.isWard || restricted) ...[
                      const SizedBox(width: 6),
                      const WardBadge(),
                    ],
                  ]),
                  Text(
                    [
                      if (username != null) '@$username',
                      if (m.isCaptain) 'Captain',
                    ].join(' · '),
                    style: TextStyle(color: p.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              // Close the sheet first, then open their profile.
              Navigator.of(context).pop();
              openPlayerProfile(context, ref, m.playerId);
            },
            icon: const Icon(Icons.person_outline_rounded, size: 18),
            label: const Text('View profile'),
          ),
          const SizedBox(height: 14),
          if (card == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (card.restricted)
            const WardPrivateNote(
                text: "Their guardians keep this player's stats private.")
          else ...[
            if (card.setup.isNotEmpty) ...[
              Eyebrow(
                  '${card.categoryEmoji ?? ''} ${card.categoryName ?? 'Sport'} setup'
                      .trim()),
              const SizedBox(height: 6),
              GlassCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(children: [
                  for (final f in card.setup)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(
                          child: Text(f.label,
                              style: TextStyle(color: p.muted, fontSize: 12.5)),
                        ),
                        Flexible(
                          child: Text(f.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            const Eyebrow('Tournament stats'),
            const SizedBox(height: 6),
            if (card.appearances == 0 && card.tallies.isEmpty)
              Text('No games played with this team yet.',
                  style: TextStyle(color: p.muted, fontSize: 12.5))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.surface2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${card.appearances} appearance${card.appearances == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                for (final t in card.tallies)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: p.line),
                    ),
                    child: Text(
                      '${t.icon != null ? '${t.icon} ' : ''}${t.count} ${t.label}',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ]),
          ],
          if (widget.team.canManage) ...[
            const SizedBox(height: 16),
            const Eyebrow('Manage'),
            const SizedBox(height: 8),
            TextField(
              controller: _jersey,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Jersey number'),
            ),
            if (widget.team.positionOptions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Positions (up to 3)',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final o in widget.team.positionOptions)
                  Material(
                    color: _positions.contains(o) ? p.accent : p.surface,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => setState(() {
                        if (_positions.contains(o)) {
                          _positions.remove(o);
                        } else if (_positions.length < 3) {
                          _positions.add(o);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color:
                                  _positions.contains(o) ? p.accent : p.line),
                        ),
                        child: Text(o,
                            style: TextStyle(
                              color:
                                  _positions.contains(o) ? Colors.white : p.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ),
                  ),
              ]),
            ],
            // (No "Starter" switch: starters are picked per tournament on
            // the squad's formation, not on the general roster.)
            const SizedBox(height: 12),
            SpButton(
              label: _busy ? 'Saving…' : 'Save changes',
              expand: true,
              onTap: _busy
                  ? null
                  : () => _run(() async {
                        await ref.read(manageRepositoryProvider).updateMember(
                              m.memberId,
                              jerseyNumber: int.tryParse(_jersey.text.trim()),
                              positions: _positions,
                            );
                      }, close: true),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: _busy
                      ? null
                      : () => _run(() async {
                            await ref.read(manageRepositoryProvider).setCaptain(
                                widget.team.id,
                                m.isCaptain ? null : m.playerId);
                          }, close: true),
                  child: Center(
                    child: Text(
                      m.isCaptain ? 'Remove captaincy' : 'Make captain',
                      style: TextStyle(
                          color: p.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: _busy ? null : () => _confirmRemove(m),
                  child: Center(
                    child: Text('Remove from team',
                        style: TextStyle(
                            color: p.danger,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemove(TeamMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${m.displayName}?'),
        content: const Text('They come off the team roster.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      await _run(
          () => ref.read(manageRepositoryProvider).removeMember(m.memberId),
          close: true);
    }
  }
}

// ---------------------------------------------------------------------------
// Formation tab — preview + open the interactive board.
// ---------------------------------------------------------------------------

class _TournamentsTab extends ConsumerWidget {
  const _TournamentsTab({required this.team});
  final TeamDetail team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final rows = ref.watch(teamTournamentsProvider(team.id));
    return rows.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
            child: Text('Loading…',
                style: TextStyle(color: p.muted, fontSize: 13))),
      ),
      error: (e, _) => Center(
          child: Text('$e', style: TextStyle(color: p.muted, fontSize: 13))),
      data: (list) {
        if (list.isEmpty) {
          return GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Icon(Icons.emoji_events_outlined, size: 32, color: p.muted),
              const SizedBox(height: 8),
              Text('No tournaments yet',
                  style: TextStyle(
                      color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'When this team is invited to a friendly, league or tournament, its squad and formation for that event live here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
              ),
            ]),
          );
        }
        // Ads between tournaments — owner console anchor "team.tournaments".
        final ads = AdInterleave.of(ref, 'team.tournaments', list.length,
            padding: const EdgeInsets.symmetric(vertical: 8));
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SpSectionTitle('Tournaments', count: list.length),
              const SizedBox(height: 4),
              Text(
                'Squads and formations are set per tournament — open one to call players and set the line-up.',
                style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 10),
              SpListCard(children: [
                for (final (i, TeamTournamentEntry r) in list.indexed) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => context.push(
                        '/groups/${r.hostGroupId ?? team.groupId ?? '-'}/tournaments/${r.eventId}/teams/${team.id}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 11),
                      child: Row(children: [
                        SpIconTile(Icons.emoji_events_outlined,
                            bg: p.orangeTint, fg: p.orangeInk),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.eventTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.ink,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700)),
                                Text(
                                  [
                                    r.kind,
                                    if (r.eventDate != null)
                                      formatDayYear(r.eventDate),
                                    r.eventStatus,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      TextStyle(color: p.muted, fontSize: 12),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${r.accepted} in squad'
                                  '${r.pending > 0 ? ' · ${r.pending} awaiting' : ''}'
                                  '${r.formationName != null ? ' · ${r.formationName}' : ''}',
                                  style: TextStyle(
                                      color: p.greenText,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                              ]),
                        ),
                        if (r.status != 'approved' && r.role != 'host') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: p.orangeTint,
                                borderRadius: BorderRadius.circular(999)),
                            child: Text(r.status,
                                style: TextStyle(
                                    color: p.orangeInk,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                        Icon(Icons.chevron_right_rounded,
                            color: p.muted, size: 20),
                      ]),
                    ),
                  ),
                  ...ads.afterRow(i),
                ],
              ]),
            ]);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Coaches tab — staff from group members, admin add/remove with role.
// ---------------------------------------------------------------------------

class _CoachesTab extends ConsumerWidget {
  const _CoachesTab({required this.team});
  final TeamDetail team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final data = ref.watch(teamCoachesProvider(team.id));
    final coaches = data.valueOrNull?.coaches ?? const <TeamCoach>[];
    final roleOptions = data.valueOrNull?.roleOptions ??
        const ['Head coach', 'Assistant coach'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (coaches.isEmpty)
          GlassCard(
            padding: const EdgeInsets.all(22),
            child: Column(children: [
              const SpIconTile(Icons.sports_rounded, size: 52, iconSize: 24),
              const SizedBox(height: 10),
              Text(
                'No coaches yet${team.canManage ? ' — add from your group members.' : '.'}',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 13),
              ),
            ]),
          )
        else ...[
          SpSectionTitle('Coaches', count: coaches.length),
          const SizedBox(height: 10),
          SpListCard(children: [
            for (final c in coaches)
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => openPlayerProfile(context, ref, c.userId),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Row(children: [
                    ClipOval(
                      child: Crest(
                          logoUrl: c.avatarUrl, label: c.displayName, size: 40),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          Text(c.role,
                              style: TextStyle(
                                  color: p.greenText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    if (team.canManage)
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: () async {
                          try {
                            await ref
                                .read(teamsRepositoryProvider)
                                .removeCoach(team.id, c.id);
                            ref.invalidate(teamCoachesProvider(team.id));
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text('$e')));
                            }
                          }
                        },
                        icon:
                            Icon(Icons.close_rounded, size: 18, color: p.muted),
                      ),
                  ]),
                ),
              ),
          ]),
        ],
        if (team.canManage && team.groupId != null) ...[
          const SizedBox(height: 14),
          SpButton(
            label: 'Add coach',
            icon: Icons.sports_rounded,
            expand: true,
            onTap: () => _addCoach(context, ref, roleOptions, coaches),
          ),
        ],
      ],
    );
  }

  Future<void> _addCoach(BuildContext context, WidgetRef ref,
      List<String> roleOptions, List<TeamCoach> existing) async {
    final p = context.palette;
    List<GroupMemberItem> members;
    try {
      final page = await ref.read(groupMembersProvider(team.groupId!).future);
      members = page.items;
    } catch (_) {
      members = const [];
    }
    if (!context.mounted) return;
    final existingIds = existing.map((c) => c.userId).toSet();
    final candidates = members
        .where((m) => !existingIds.contains(m.userId) && !m.isWard)
        .toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Every group member already coaches this team.')));
      return;
    }
    String role = roleOptions.isNotEmpty ? roleOptions.first : 'Coach';
    String? userId;
    final ok = await showSpSheet<bool>(
      context,
      framed: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: ListView(shrinkWrap: true, children: [
            Text('Add a coach',
                style: TextStyle(
                    color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in roleOptions)
                Material(
                  color: role == r ? p.accent : p.surface,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setSheet(() => role = r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border:
                            Border.all(color: role == r ? p.accent : p.line),
                      ),
                      child: Text(r,
                          style: TextStyle(
                            color: role == r ? Colors.white : p.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            for (final m in candidates)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: ClipOval(
                    child: Crest(
                        logoUrl: m.avatarUrl, label: m.displayName, size: 32)),
                title: Text(m.displayName,
                    style: TextStyle(color: p.ink, fontSize: 14)),
                trailing: userId == m.userId
                    ? Icon(Icons.check_circle_rounded,
                        color: p.accent, size: 18)
                    : null,
                onTap: () => setSheet(() => userId = m.userId),
              ),
            const SizedBox(height: 8),
            SpButton(
              label: 'Add coach',
              expand: true,
              onTap: userId != null ? () => Navigator.pop(ctx, true) : null,
            ),
          ]),
        ),
      ),
    );
    if (ok != true || userId == null || !context.mounted) return;
    try {
      await ref.read(teamsRepositoryProvider).addCoach(team.id, userId!, role);
      ref.invalidate(teamCoachesProvider(team.id));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Games tab — the team's matches over the last six months.
// ---------------------------------------------------------------------------

class _GamesTab extends ConsumerWidget {
  const _GamesTab({required this.teamId});
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final games = ref.watch(teamGamesProvider(teamId));
    final list = games.valueOrNull ?? const <TeamGame>[];
    // Ads between games — owner console anchor "team.games".
    final ads = AdInterleave.of(ref, 'team.games', list.length,
        padding: const EdgeInsets.symmetric(vertical: 8));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSectionTitle('Games',
            count: list.isEmpty ? null : list.length,
            trailing: Text('Last 6 months',
                style: TextStyle(color: p.muted, fontSize: 12))),
        const SizedBox(height: 10),
        if (games.isLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (list.isEmpty)
          GlassCard(
            padding: const EdgeInsets.all(22),
            child: Column(children: [
              const SpIconTile(Icons.sports_soccer_rounded,
                  size: 52, iconSize: 24),
              const SizedBox(height: 10),
              Text('No games in the last 6 months.',
                  style: TextStyle(color: p.muted, fontSize: 13)),
            ]),
          )
        else
          SpListCard(children: [
            for (final (i, g) in list.indexed) ...[
              Builder(builder: (context) {
                final live = g.status == 'live';
                final (bg, fg, label) = live
                    ? (p.liveTint, p.danger, 'LIVE')
                    : switch (g.result) {
                        'win' => (p.accentTint, p.greenText, 'W'),
                        'loss' => (p.liveTint, p.danger, 'L'),
                        'draw' => (p.surface2, p.muted, 'D'),
                        _ => (p.surface2, p.muted, '–'),
                      };
                return InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => context.push('/games/${g.id}'),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                    child: Row(children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: bg, borderRadius: BorderRadius.circular(14)),
                        child: Text(label,
                            style: TextStyle(
                                color: fg,
                                fontSize: live ? 10.5 : 15,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('vs ${g.oppName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: p.ink,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700)),
                            Text(
                              [
                                if (g.eventTitle != null) g.eventTitle!,
                                if (g.playedAt != null) formatDay(g.playedAt),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${g.myScore}–${g.oppScore}',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      Icon(Icons.chevron_right_rounded,
                          size: 20, color: p.muted),
                    ]),
                  ),
                );
              }),
              ...ads.afterRow(i),
            ],
          ]),
      ],
    );
  }
}

/// Pins the team tab bar to the top of the scroll view.
class _PinnedTeamTabs extends SliverPersistentHeaderDelegate {
  const _PinnedTeamTabs({required this.child});
  final Widget child;

  static const double _height = 54;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: _height, child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedTeamTabs oldDelegate) =>
      oldDelegate.child != child;
}

/// Loading / error aren't scrollable on their own, so they get a pullable
/// wrapper; once the data shows, its own RefreshIndicator takes over.
Widget _pullableUnlessData(
        AsyncValue<Object?> v, Future<void> Function() onRefresh, Widget child) =>
    v.hasValue && !v.hasError
        ? child
        : RefreshIndicator(
            onRefresh: onRefresh, child: PullableState(child: child));
