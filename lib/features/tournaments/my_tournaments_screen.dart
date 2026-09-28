import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/tournaments/my_team_models.dart';
import 'package:sportpadi_mobile/data/tournaments/squad_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_app_bar.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Bottom-nav "Tournaments" tab, team first: one summary card per team the
/// user plays for (or runs as a group admin). Tapping a card opens that team's
/// tournaments — live, upcoming, invites and past (web: /tournaments).
class MyTournamentsScreen extends ConsumerWidget {
  const MyTournamentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final data = ref.watch(myTeamCardsProvider);
    Future<void> refresh() async {
      ref.invalidate(myTeamCardsProvider);
      ref.invalidate(myCallsProvider);
      await ref.read(myTeamCardsProvider.future).catchError((_) => <MyTeamCard>[]);
    }

    return Scaffold(
      appBar: const SpAppBar(),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(myTeamCardsProvider),
        data: (teams) => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Text('My tournaments',
                  style: TextStyle(
                      color: p.ink, fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(
                'Pick a team to see its tournaments — live, upcoming, invites and past.',
                style: TextStyle(color: p.muted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              if (teams.isEmpty) ...[
                const SizedBox(height: 50),
                Icon(Icons.shield_outlined, size: 44, color: p.muted),
                const SizedBox(height: 12),
                Center(
                  child: Text('No teams yet',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Join a team in one of your groups —\nits tournaments will show up here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
                  ),
                ),
              ] else
                for (final t in teams)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TeamSummaryCard(team: t),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final trim = hexColor(team.kitSecondary);
    final words =
        team.name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.isEmpty
        ? '?'
        : words.length == 1
            ? (words[0].length < 2 ? words[0] : words[0].substring(0, 2)).toUpperCase()
            : (words[0][0] + words[1][0]).toUpperCase();
    final ink = kit.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: team.logoUrl != null ? p.surface2 : kit,
        borderRadius: BorderRadius.circular(size * 0.28),
        border: trim != null ? Border.all(color: trim, width: 2.5) : null,
      ),
      alignment: Alignment.center,
      child: team.logoUrl != null
          ? Image.network(team.logoUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Text(initials,
                  style: TextStyle(color: p.ink, fontWeight: FontWeight.w900)))
          : Text(initials,
              style: TextStyle(
                  color: ink,
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w900)),
    );
  }
}

String? _day(String? ymd) {
  if (ymd == null) return null;
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
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

class TeamSummaryCard extends StatelessWidget {
  const TeamSummaryCard({super.key, required this.team});
  final MyTeamCard team;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = team;
    final n = t.nextUp;
    final kit = hexColor(t.kitPrimary) ?? p.accent;
    final trim = hexColor(t.kitSecondary);
    final when = n == null
        ? null
        : [_day(n.scheduledDate), _hhmm12(n.scheduledTime)]
            .whereType<String>()
            .join(' · ');
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/tournaments/teams/${t.teamId}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.live > 0 ? p.danger.withAlpha(110) : p.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // kit stripe
              Row(children: [
                Expanded(flex: 3, child: Container(height: 4, color: kit)),
                if (trim != null)
                  Expanded(flex: 2, child: Container(height: 4, color: trim)),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      TeamCrest(team: t),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: p.ink,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800)),
                            if (t.subtitle.isNotEmpty)
                              Text(t.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: p.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: p.muted),
                    ]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      if (t.live > 0)
                        _Chip('● ${t.live} live', color: p.danger),
                      if (t.upcoming > 0)
                        _Chip('${t.upcoming} upcoming', color: p.accent),
                      if (t.invited > 0)
                        _Chip('${t.invited} invite${t.invited == 1 ? '' : 's'}',
                            color: p.amber),
                      if (t.callUps > 0)
                        _Chip('Call-up waiting', color: p.amber),
                      if (t.past > 0) _Chip('${t.past} past', color: p.muted),
                      if (t.total == 0)
                        _Chip('No tournaments yet', color: p.muted),
                    ]),
                    if (n != null || t.played > 0) ...[
                      const SizedBox(height: 10),
                      Container(height: 1, color: p.line),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: n == null
                              ? const SizedBox.shrink()
                              : Text(
                                  n.isLive
                                      ? 'LIVE vs ${n.opponentName} · ${n.myScore}–${n.oppScore}'
                                      : 'Next: vs ${n.opponentName}${when != null && when.isNotEmpty ? ' · $when' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: n.isLive ? p.danger : p.muted,
                                      fontSize: 12,
                                      fontWeight: n.isLive
                                          ? FontWeight.w800
                                          : FontWeight.w500),
                                ),
                        ),
                        if (t.played > 0)
                          Text.rich(TextSpan(children: [
                            TextSpan(
                                text: '${t.won}W ',
                                style: TextStyle(color: p.accent)),
                            TextSpan(
                                text: '${t.drawn}D ',
                                style: TextStyle(color: p.muted)),
                            TextSpan(
                                text: '${t.lost}L',
                                style: TextStyle(color: p.danger)),
                          ]),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w800)),
                      ]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final all = ref.watch(myCallsProvider).valueOrNull?.pending ?? const <SquadCall>[];
    final calls = widget.teamId == null
        ? all
        : all.where((c) => c.teamId == widget.teamId).toList();
    if (calls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.campaign_rounded, size: 16, color: p.amber),
          const SizedBox(width: 6),
          Text('CALL-UPS WAITING FOR YOU (${calls.length})',
              style: TextStyle(
                  color: p.amber, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        ]),
        const SizedBox(height: 8),
        for (final c in calls)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.amber.withAlpha(16),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.amber.withAlpha(100)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                InkWell(
                  onTap: c.route != null ? () => context.push(c.route!) : null,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                        widget.teamId != null
                            ? (c.eventTitle ?? 'Tournament')
                            : '${c.teamName ?? 'Your team'} · ${c.eventTitle ?? 'Tournament'}',
                        style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    // A call-up is a commitment — show enough to answer it.
                    Text(
                      [
                        c.when.line,
                        if (c.locationName != null) c.locationName!,
                        if (c.opponentName != null) 'vs ${c.opponentName}',
                      ].join('  ·  '),
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                    if (c.when.viewerTime != null)
                      Text('${c.when.viewerTime} your time',
                          style: TextStyle(color: p.muted, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (c.categoryName != null)
                          '${c.categoryEmoji ?? ''} ${c.categoryName}'.trim(),
                        if (c.hostGroupName != null)
                          'hosted by ${c.hostGroupName}',
                        'called ${timeAgo(c.calledAt)}',
                      ].join(' · '),
                      style: TextStyle(color: p.muted, fontSize: 11.5),
                    ),
                    if (c.callNote != null && c.callNote!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          border:
                              Border(left: BorderSide(color: p.amber, width: 2.5)),
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("COACH'S REMARK",
                                  style: TextStyle(
                                      color: p.muted,
                                      fontSize: 9.5,
                                      letterSpacing: 0.6,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 1),
                              Text(c.callNote!.trim(),
                                  style: TextStyle(
                                      color: p.ink, fontSize: 11.5, height: 1.3)),
                            ]),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text('Accepting locks you to this team for this tournament.',
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                  ]),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: SpButton(
                      label: _busyId == c.squadId ? 'Sending…' : "I'm in",
                      icon: Icons.check_rounded,
                      expand: true,
                      onTap: _busyId != null ? null : () => _respond(c, true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busyId != null ? null : () => _respond(c, false),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text("Can't make it"),
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
