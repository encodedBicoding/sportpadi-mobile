import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart'
    show myTournamentInvitesProvider;
import 'package:sportpadi_mobile/data/tournaments/my_team_models.dart';
import 'package:sportpadi_mobile/data/tournaments/squad_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_app_bar.dart'
    show SideMenuButton;
import 'package:sportpadi_mobile/shared/widgets/team_tile.dart'
    show kitGradient;
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Bottom-nav "Tournaments" tab, team first (2026): call-ups waiting for you
/// on top, then one card per team the user plays for (or runs as a group
/// admin). Tapping a card opens that team's tournaments — live, upcoming,
/// invites and past (web: /tournaments).
class MyTournamentsScreen extends ConsumerWidget {
  const MyTournamentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final data = ref.watch(myTeamCardsProvider);
    final invites =
        ref.watch(myTournamentInvitesProvider).valueOrNull?.length ?? 0;
    // Everything on the tab: team cards, call-ups and the invites chip.
    Future<void> refresh() {
      ref.invalidate(myTeamCardsProvider);
      ref.invalidate(myCallsProvider);
      ref.invalidate(myTournamentInvitesProvider);
      return settleAll([
        ref.read(myTeamCardsProvider.future),
        ref.read(myTournamentInvitesProvider.future),
        // Call-ups are only watched (by SquadCallUps) once the cards show.
        if (data.hasValue && !data.hasError) ref.read(myCallsProvider.future),
      ]);
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          // Loading / error aren't scrollable on their own.
          child: _pullable(data, AsyncView(
          value: data,
          onRetry: () => ref.invalidate(myTeamCardsProvider),
          data: (teams) {
            final live = teams.fold<int>(0, (a, t) => a + t.live);
            final upcoming = teams.fold<int>(0, (a, t) => a + t.upcoming);
            return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
                children: [
                  // Tab title, invitations, and the side menu.
                  Row(children: [
                    Expanded(
                      child: Text('Tournaments',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5)),
                    ),
                    if (invites > 0) ...[
                      Material(
                        color: p.orangeTint,
                        shape: const StadiumBorder(),
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: () => context.push('/tournaments/invitations'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 10),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.mail_outline_rounded,
                                  size: 16, color: p.orangeInk),
                              const SizedBox(width: 5),
                              Text('Invites · $invites',
                                  style: TextStyle(
                                      color: p.orangeInk,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const SideMenuButton(),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    teams.isEmpty
                        ? 'Your teams\' fixtures, invites and results.'
                        : [
                            '${teams.length} team${teams.length == 1 ? '' : 's'}',
                            if (live > 0) '$live live',
                            if (upcoming > 0) '$upcoming upcoming',
                          ].join(' · '),
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  const SquadCallUps(),
                  if (teams.isEmpty)
                    GlassCard(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        SpIconTile(Icons.shield_outlined,
                            bg: p.orangeTint,
                            fg: p.orangeInk,
                            size: 60,
                            iconSize: 28),
                        const SizedBox(height: 14),
                        Text('No teams yet',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          'Join a team in one of your groups — or build one from the group\'s Teams tab. Its tournaments show up here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: p.muted, fontSize: 13, height: 1.45),
                        ),
                      ]),
                    )
                  else ...[
                    SpSectionTitle('Your teams', count: teams.length),
                    const SizedBox(height: 10),
                    for (final t in teams)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: TeamSummaryCard(team: t),
                      ),
                  ],
                ],
              );
          },
        )),
        ),
      ),
    );
  }
}

/// [child] as is when [value] renders its (scrollable) data branch, else
/// wrapped so the loader / error can still be pulled.
Widget _pullable(AsyncValue<Object?> value, Widget child) => value.maybeWhen(
      data: (_) => child,
      orElse: () => PullableState(child: child),
    );

Color? hexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// The team's crest: its logo, or initials on its kit colour.
class TeamCrest extends StatelessWidget {
  const TeamCrest({super.key, required this.team, this.size = 48});
  final MyTeamCard team;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final kit = hexColor(team.kitPrimary) ?? p.accent;
    final words = team.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final initials = words.isEmpty
        ? '?'
        : words.length == 1
            ? (words[0].length < 2 ? words[0] : words[0].substring(0, 2))
                .toUpperCase()
            : (words[0][0] + words[1][0]).toUpperCase();
    final ink = kit.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: team.logoUrl != null ? p.surface2 : kit,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: team.logoUrl != null
          ? Image.network(team.logoUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Text(initials,
                  style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)))
          : Text(initials,
              style: TextStyle(
                  color: ink,
                  fontSize: size * 0.34,
                  fontWeight: FontWeight.w800)),
    );
  }
}

String? _day(String? ymd) {
  if (ymd == null) return null;
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mo = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${wd[d.weekday - 1]} ${d.day} ${mo[d.month - 1]}';
}

String? _hhmm12(String? hhmm) {
  if (hhmm == null) return null;
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts[1];
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:$m ${h < 12 ? 'AM' : 'PM'}';
}

/// A small tinted pill.
Widget tournamentPill(String label, Color bg, Color fg, {bool dot = false}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 5),
        ],
        Text(label,
            style: TextStyle(
                color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ]),
    );

/// One team on the Tournaments tab (2026): the kit as a banner with the
/// crest overlapping it, the team, where its tournaments stand, and what's
/// next (or live) with its record.
class TeamSummaryCard extends StatelessWidget {
  const TeamSummaryCard({super.key, required this.team});
  final MyTeamCard team;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = team;
    final n = t.nextUp;
    final when = n == null
        ? null
        : [_day(n.scheduledDate), _hhmm12(n.scheduledTime)]
            .whereType<String>()
            .join(' · ');
    return GlassCard(
      onTap: () => context.push('/tournaments/teams/${t.teamId}'),
      padding: const EdgeInsets.all(6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 88,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              bottom: 20,
              child: Container(
                decoration: BoxDecoration(
                  gradient: kitGradient(t.kitPrimary, t.kitSecondary),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            if (t.isAdmin || t.isMember)
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xEBFFFFFF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(t.isAdmin ? 'You manage' : 'You play',
                      style: const TextStyle(
                          color: Color(0xFF0E1411),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            Positioned(
              left: 12,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.surface, width: 3),
                ),
                child: TeamCrest(team: t, size: 50),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      if (t.subtitle.isNotEmpty)
                        Text(t.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.muted, fontSize: 12.5)),
                    ]),
              ),
              if (t.played > 0)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${t.won}-${t.drawn}-${t.lost}',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  Text('W-D-L',
                      style: TextStyle(color: p.muted, fontSize: 10.5)),
                ]),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (t.live > 0)
                tournamentPill('${t.live} live', p.liveTint, p.danger,
                    dot: true),
              if (t.upcoming > 0)
                tournamentPill(
                    '${t.upcoming} upcoming', p.accentTint, p.greenText),
              if (t.invited > 0)
                tournamentPill(
                    '${t.invited} invite${t.invited == 1 ? '' : 's'}',
                    p.orangeTint,
                    p.orangeInk),
              if (t.callUps > 0)
                tournamentPill('Call-up waiting', p.orangeTint, p.orangeInk),
              if (t.past > 0)
                tournamentPill('${t.past} past', p.surface2, p.muted),
              if (t.total == 0)
                tournamentPill('No tournaments yet', p.surface2, p.muted),
            ]),
            if (n != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: n.isLive ? p.liveTint : p.surface2,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(children: [
                  Icon(n.isLive ? Icons.sensors_rounded : Icons.event_outlined,
                      size: 18, color: n.isLive ? p.danger : p.greenText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(n.isLive ? 'Live now' : 'Next up',
                              style: TextStyle(
                                  color: n.isLive ? p.danger : p.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                          Text('vs ${n.opponentName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                        ]),
                  ),
                  const SizedBox(width: 8),
                  Text(
                      n.isLive
                          ? '${n.myScore}–${n.oppScore}'
                          : (when == null || when.isEmpty ? 'TBC' : when),
                      style: TextStyle(
                          color: n.isLive ? p.danger : p.ink,
                          fontSize: n.isLive ? 17 : 12.5,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Pending call-ups: a coach wants you for a specific tournament. Accept /
/// decline right here; tap the card for the squad page. [teamId] narrows it
/// to one team (the team's tournaments screen).
class SquadCallUps extends ConsumerStatefulWidget {
  const SquadCallUps({super.key, this.teamId});
  final String? teamId;
  @override
  ConsumerState<SquadCallUps> createState() => _SquadCallUpsState();
}

class _SquadCallUpsState extends ConsumerState<SquadCallUps> {
  String? _busyId;

  Future<void> _respond(SquadCall c, bool accept) async {
    final eventId = c.eventId;
    if (eventId == null) return;
    setState(() => _busyId = c.squadId);
    try {
      await ref
          .read(tournamentsRepositoryProvider)
          .respondCall(eventId, c.squadId, accept: accept);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(accept ? "You're in the squad" : 'Response sent')));
      }
      ref.invalidate(myCallsProvider);
      ref.invalidate(myTournamentsProvider);
      ref.invalidate(myTeamCardsProvider);
      if (widget.teamId != null) {
        ref.invalidate(myTeamTournamentsProvider(widget.teamId!));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final all =
        ref.watch(myCallsProvider).valueOrNull?.pending ?? const <SquadCall>[];
    final calls = widget.teamId == null
        ? all
        : all.where((c) => c.teamId == widget.teamId).toList();
    if (calls.isEmpty) return const SizedBox.shrink();

    Widget detail(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 15, color: p.heroMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: p.onHero,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SpSectionTitle('Call-ups for you', count: calls.length),
        const SizedBox(height: 10),
        for (final c in calls)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: p.hero,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    InkWell(
                      onTap:
                          c.route != null ? () => context.push(c.route!) : null,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const SpIconTile(Icons.campaign_rounded,
                                  bg: Color(0x29FFB57D),
                                  fg: Color(0xFFFFB57D),
                                  size: 40,
                                  iconSize: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(c.eventTitle ?? 'Tournament',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: p.onHero,
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w800)),
                                      Text(
                                          [
                                            if (widget.teamId == null)
                                              c.teamName ?? 'Your team',
                                            'called ${timeAgo(c.calledAt)}',
                                          ].join(' · '),
                                          style: TextStyle(
                                              color: p.heroMuted,
                                              fontSize: 12)),
                                    ]),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            // A call-up is a commitment — show enough to answer it.
                            detail(
                                Icons.event_outlined,
                                c.when.viewerTime != null
                                    ? '${c.when.line} (${c.when.viewerTime} your time)'
                                    : c.when.line),
                            if (c.locationName != null)
                              detail(Icons.place_outlined, c.locationName!),
                            if (c.opponentName != null)
                              detail(Icons.sports_kabaddi_outlined,
                                  'vs ${c.opponentName}'),
                            if (c.hostGroupName != null ||
                                c.categoryName != null)
                              detail(
                                  Icons.groups_outlined,
                                  [
                                    if (c.categoryName != null)
                                      '${c.categoryEmoji ?? ''} ${c.categoryName}'
                                          .trim(),
                                    if (c.hostGroupName != null)
                                      'hosted by ${c.hostGroupName}',
                                  ].join(' · ')),
                            if (c.callNote != null &&
                                c.callNote!.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: p.onHero.withAlpha(18),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text("Coach's remark",
                                          style: TextStyle(
                                              color: Color(0xFFFFB57D),
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 3),
                                      Text(c.callNote!.trim(),
                                          style: TextStyle(
                                              color: p.onHero,
                                              fontSize: 13,
                                              height: 1.4)),
                                    ]),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                                'Accepting locks you to this team for this tournament.',
                                style: TextStyle(
                                    color: p.heroMuted, fontSize: 12)),
                          ]),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: Material(
                          color: _busyId != null
                              ? p.onHero.withAlpha(30)
                              : Colors.white,
                          shape: const StadiumBorder(),
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: _busyId != null
                                ? null
                                : () => _respond(c, true),
                            child: SizedBox(
                              height: 48,
                              child: Center(
                                child: Text(
                                    _busyId == c.squadId
                                        ? 'Sending…'
                                        : "I'm in",
                                    style: TextStyle(
                                        color: _busyId != null
                                            ? p.heroMuted
                                            : const Color(0xFF0E1411),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Material(
                          color: p.onHero.withAlpha(24),
                          shape: const StadiumBorder(),
                          child: InkWell(
                            customBorder: const StadiumBorder(),
                            onTap: _busyId != null
                                ? null
                                : () => _respond(c, false),
                            child: SizedBox(
                              height: 48,
                              child: Center(
                                child: Text("Can't make it",
                                    style: TextStyle(
                                        color: p.onHero,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ]),
            ),
          ),
      ]),
    );
  }
}
