import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/tournaments/my_team_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournament_models.dart'
    show MyTournamentGame;
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/features/tournaments/invitation_rows.dart';
import 'package:sportpadi_mobile/features/tournaments/my_tournaments_screen.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/team_tile.dart' show kitGradient;
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

const _tabs = <(String, String)>[
  ('all', 'All'),
  ('live', 'Live'),
  ('upcoming', 'Upcoming'),
  ('invited', 'Invites'),
  ('past', 'Past'),
];

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// One team's tournaments, every kind — live, upcoming, invites (group admins
/// answer them here) and past. Opened from a team card on the Tournaments tab
/// (web: /tournaments/teams/:teamId).
///
/// 2026 design: kit banner with round back / team buttons, an identity card
/// overlapping it with the tournament record, pill tabs with counts, dark
/// call-ups, then the tournaments grouped by where they stand.
class MyTeamTournamentsScreen extends ConsumerStatefulWidget {
  const MyTeamTournamentsScreen({super.key, required this.teamId});
  final String teamId;

  @override
  ConsumerState<MyTeamTournamentsScreen> createState() =>
      _MyTeamTournamentsScreenState();
}

class _MyTeamTournamentsScreenState
    extends ConsumerState<MyTeamTournamentsScreen> {
  String _tab = 'all';

  void _back() => context.canPop() ? context.pop() : context.go('/tournaments');

  void _refresh() {
    ref.invalidate(myTeamTournamentsProvider(widget.teamId));
    ref.invalidate(myCallsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final data = ref.watch(myTeamTournamentsProvider(widget.teamId));
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(children: [
        AsyncView(
          value: data,
          onRetry: _refresh,
          data: (v) => _content(context, v),
        ),
        if (!data.hasValue)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SpRoundButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                tooltip: 'Back',
                onTap: _back,
              ),
            ),
          ),
      ]),
    );
  }

  Widget _content(BuildContext context, MyTeamTournamentsView v) {
    final t = v.team;
    int count(String b) => b == 'all'
        ? v.entries.length
        : v.entries.where((e) => e.bucket == b).length;
    final shown = _tab == 'all'
        ? v.entries
        : v.entries.where((e) => e.bucket == _tab).toList();

    final body = <Widget>[];
    if (shown.isEmpty) {
      body.add(_Empty(tab: _tab));
    } else if (_tab == 'all') {
      for (final (bucket, title) in const [
        ('live', 'Live now'),
        ('invited', 'Invitations'),
        ('upcoming', 'Upcoming'),
        ('past', 'Past'),
      ]) {
        final list = shown.where((e) => e.bucket == bucket).toList();
        if (list.isEmpty) continue;
        body
          ..add(Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 10),
            child: SpSectionTitle(title, count: list.length),
          ))
          ..addAll(_entries(list));
      }
    } else {
      body.addAll(_entries(shown));
    }

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Hero(team: t, tournaments: v.entries.length, onBack: _back),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final (id, label) in _tabs)
                      if (!(id == 'invited' && count(id) == 0 && !t.isAdmin))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _PillTab(
                            label: label,
                            count: count(id),
                            selected: _tab == id,
                            live: id == 'live' && count(id) > 0,
                            onTap: () => setState(() => _tab = id),
                          ),
                        ),
                  ]),
                ),
                const SizedBox(height: 16),
                SquadCallUps(teamId: widget.teamId),
                ...body,
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _entries(List<MyTeamTournament> list) {
    final invites = [
      for (final e in list)
        if (e.bucket == 'invited' && e.invite != null) e.invite!,
    ];
    return [
      if (invites.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InvitationListBox(
            invites: invites,
            onDone: () =>
                ref.invalidate(myTeamTournamentsProvider(widget.teamId)),
          ),
        ),
      for (final e in list)
        if (!(e.bucket == 'invited' && e.invite != null))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _EntryCard(e: e),
          ),
    ];
  }
}

// ─── Header ─────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero(
      {required this.team, required this.tournaments, required this.onBack});
  final MyTeamCard team;
  final int tournaments;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = team;
    final top = MediaQuery.of(context).padding.top;
    final bannerH = top + 176;
    final sub = [
      if ((t.groupName ?? '').isNotEmpty) t.groupName!,
      if ((t.categoryName ?? '').isNotEmpty)
        '${t.categoryEmoji ?? ''} ${t.categoryName}'.trim(),
    ].join(' · ');
    final winRate =
        t.played > 0 ? '${(t.won * 100 / t.played).round()}%' : '—';

    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: bannerH,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
          child: DecoratedBox(
            decoration: BoxDecoration(
                gradient: kitGradient(t.kitPrimary, t.kitSecondary)),
            child: CustomPaint(
              painter: _KitStripes(),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, top + 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      SpRoundButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        iconSize: 18,
                        tooltip: 'Back',
                        onTap: onBack,
                      ),
                      const Spacer(),
                      SpRoundButton(
                        icon: Icons.shield_outlined,
                        tooltip: 'Team page',
                        onTap: () => context.push('/teams/${t.teamId}'),
                      ),
                    ]),
                    const SizedBox(height: 18),
                    const Text('TOURNAMENTS',
                        style: TextStyle(
                            color: Color(0xD9FFFFFF),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.6)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(16, bannerH - 56, 16, 0),
        child: GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                TeamCrest(team: t, size: 56),
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
                              fontSize: 21,
                              height: 1.15,
                              fontWeight: FontWeight.w800)),
                      if (sub.isNotEmpty || t.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(sub.isNotEmpty ? sub : t.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.muted, fontSize: 12.5)),
                      ],
                    ],
                  ),
                ),
              ]),
              if (t.isAdmin || t.isMember) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  tournamentPill(t.isAdmin ? 'You manage' : 'You play',
                      p.accentTint, p.greenText),
                  if (t.live > 0)
                    tournamentPill('${t.live} live', p.liveTint, p.danger,
                        dot: true),
                  if (t.callUps > 0)
                    tournamentPill(
                        'Call-up waiting', p.orangeTint, p.orangeInk),
                ]),
              ],
              const SizedBox(height: 14),
              Row(children: [
                _Stat(value: '$tournaments', label: 'Tournaments'),
                const SizedBox(width: 8),
                _Stat(value: '${t.played}', label: 'Played'),
                const SizedBox(width: 8),
                _Stat(
                    value: t.played > 0
                        ? '${t.won}-${t.drawn}-${t.lost}'
                        : '—',
                    label: 'W-D-L'),
                const SizedBox(width: 8),
                _Stat(value: winRate, label: 'Win rate', accent: true),
              ]),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.accent = false});
  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: accent ? p.accentTint : p.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(
                    color: accent ? p.greenText : p.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 10.5)),
        ]),
      ),
    );
  }
}

class _KitStripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 18;
    final d = size.height + size.width;
    for (double x = -size.height; x < d; x += 48) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
    // Soft glow in the top-right, like the other 2026 covers.
    canvas.drawCircle(
      Offset(size.width * 0.9, size.height * 0.1),
      math.max(size.width, size.height) * 0.45,
      Paint()..color = const Color(0x12FFFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Tabs & empty ───────────────────────────────────────────────────────────

class _PillTab extends StatelessWidget {
  const _PillTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.live = false,
  });
  final String label;
  final int count;
  final bool selected;
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected ? p.bg : p.ink;
    return Material(
      color: selected ? p.ink : p.surface,
      shape: StadiumBorder(
          side: selected ? BorderSide.none : BorderSide(color: p.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (live) ...[
              Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: p.danger, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 22),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: selected ? const Color(0x33FFFFFF) : p.surface2,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('$count',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: selected ? p.bg : p.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.tab});
  final String tab;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, text) = switch (tab) {
      'live' => (Icons.sensors_rounded, 'Nothing live right now.'),
      'upcoming' => (Icons.event_outlined, 'No upcoming tournaments.'),
      'invited' => (Icons.mail_outline_rounded, 'No invitations waiting.'),
      'past' => (Icons.history_rounded, 'No past tournaments yet.'),
      _ => (
          Icons.emoji_events_outlined,
          "This team hasn't played in a tournament yet."
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(children: [
        SpIconTile(icon, bg: p.surface2, fg: p.muted, size: 56, iconSize: 26),
        const SizedBox(height: 12),
        Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13.5)),
      ]),
    );
  }
}

// ─── Entry card ─────────────────────────────────────────────────────────────

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.e});
  final MyTeamTournament e;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final date = e.eventDate;
    final live = e.bucket == 'live';
    final past = e.bucket == 'past';
    final cancelled = e.tournamentStatus == 'cancelled';
    final vs = e.opponents.isEmpty
        ? null
        : e.opponents.length == 1
            ? 'vs ${e.opponents.first}'
            : '${e.opponents.length + 1} teams';
    final meta = [
      if (e.locationName != null && e.locationName!.isNotEmpty)
        e.locationName!,
      if (vs != null) vs,
      if (e.role != 'host' && e.hostGroupName != null)
        'Hosted by ${e.hostGroupName}',
    ].join(' · ');
    final (pill, pillBg, pillFg) = switch (e.bucket) {
      'live' => ('Live', p.liveTint, p.danger),
      'upcoming' => ('Upcoming', p.accentTint, p.greenText),
      'invited' => ('Invite', p.orangeTint, p.orangeInk),
      _ => ('Past', p.surface2, p.muted),
    };

    return GlassCard(
      onTap: () => context.push('/tournaments/${e.eventId}'),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: live
                    ? p.liveTint
                    : past
                        ? p.surface2
                        : p.accentTint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                Text(date == null ? 'TBC' : _months[date.month - 1].toUpperCase(),
                    style: TextStyle(
                        color: live
                            ? p.danger
                            : past
                                ? p.muted
                                : p.greenText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
                Text(date == null ? '–' : '${date.day}',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 20,
                        height: 1.1,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    tournamentPill(pill, pillBg, pillFg, dot: live),
                    if (e.role == 'host')
                      tournamentPill('Your team hosts', p.surface2, p.ink),
                    if (cancelled)
                      tournamentPill('Cancelled', p.liveTint, p.danger),
                  ]),
                  const SizedBox(height: 6),
                  Text(e.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 16,
                          height: 1.2,
                          fontWeight: FontWeight.w800)),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 12.5)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.chevron_right_rounded, color: p.muted),
            ),
          ]),
          if (e.games.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: [
                for (final (i, g) in e.games.take(4).indexed) ...[
                  if (i > 0) Container(height: 1, color: p.line),
                  _GameRow(g: g),
                ],
                if (e.games.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Text('+${e.games.length - 4} more games',
                        style: TextStyle(
                            color: p.muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
          ],
          if (e.hostGroupId != null && !past && !cancelled) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _ActionPill(
                  icon: Icons.groups_2_outlined,
                  label: 'Squad',
                  onTap: () => context.push(
                      '/groups/${e.hostGroupId}/tournaments/${e.eventId}/teams/${e.teamId}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionPill(
                  icon: Icons.grid_view_rounded,
                  label: 'Formation',
                  onTap: () => context.push(
                      '/groups/${e.hostGroupId}/tournaments/${e.eventId}/teams/${e.teamId}/formation'),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({required this.g});
  final MyTournamentGame g;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final live = g.status == 'live';
    final done = g.status == 'completed';
    final (badge, bg, fg) = live
        ? ('•', p.liveTint, p.danger)
        : !done
            ? ('', p.surface, p.muted)
            : switch (g.result) {
                'win' => ('W', p.accentTint, p.greenText),
                'loss' => ('L', p.liveTint, p.danger),
                _ => ('D', p.surface, p.ink),
              };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: badge.isEmpty
              ? Icon(Icons.schedule_rounded, size: 14, color: fg)
              : Text(badge,
                  style: TextStyle(
                      color: fg, fontSize: 11.5, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text('vs ${g.opponentName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        if (live || done)
          Text('${live ? 'LIVE  ' : ''}${g.myScore}–${g.oppScore}',
              style: TextStyle(
                  color: live ? p.danger : p.ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800))
        else
          Text(g.scheduledDate ?? 'Not scheduled',
              style: TextStyle(color: p.muted, fontSize: 12)),
      ]),
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface2,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: p.ink),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
