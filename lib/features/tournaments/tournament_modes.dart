import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/data/tournaments/tournament_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/features/leagues/league_widgets.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Tournament modes (web `components/tournaments/TournamentModes.tsx`): the
/// group Tournaments tab shows one card per mode — New tournament, 1v1
/// Friendly, Multi-team, League — and each opens its own screen at
/// `/groups/:id/tournaments/mode/:mode` (1v1 | multi-team | league).

const _mint = Color(0xFF6EDC9E);
const _warm = Color(0xFFFFB57D);

enum TMode {
  friendly('1v1', '1v1 Friendly', '1v1 friendlies', 'One match between two teams — yours against a rival, or two teams you bring together.', 'New friendly'),
  multi('multi-team', 'Multi-team', 'Multi-team tournaments',
      'Several invited teams, match games between any of them — with or without a team of your own.', 'New multi-team'),
  league('league', 'League', 'Leagues', 'A season of fixtures — live table, registered rosters, player rankings and match MVPs.', 'New league');

  const TMode(this.slug, this.title, this.plural, this.blurb, this.newLabel);
  final String slug;
  final String title;
  final String plural;
  final String blurb;
  final String newLabel;

  static TMode? fromSlug(String? s) => TMode.values.where((m) => m.slug == s).firstOrNull;
}

String modePath(String groupId, TMode m) => '/groups/$groupId/tournaments/mode/${m.slug}';

/* ── Phases ─────────────────────────────────────────────────────────────── */

enum TPhase { live, upcoming, past }

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Live (kicked off), upcoming (today or later) or past. Event dates are UTC wall-clock days.
TPhase tournamentPhase(TournamentSummary t) {
  if (t.status == 'kicked_off') return TPhase.live;
  if (t.status == 'completed' || t.status == 'cancelled') return TPhase.past;
  final d = t.eventDate;
  if (d == null) return TPhase.upcoming;
  final day = _dayKey(d.toUtc());
  return day.compareTo(_dayKey(DateTime.now())) >= 0 ? TPhase.upcoming : TPhase.past;
}

enum LPhase { running, draft, past }

LPhase leaguePhase(J l) => switch (l.s('status')) {
      'draft' => LPhase.draft,
      'completed' || 'cancelled' => LPhase.past,
      _ => LPhase.running,
    };

/// Live first, upcoming soonest first, then past most recent first.
List<TournamentSummary> sortTournaments(Iterable<TournamentSummary> list) {
  int key(TournamentSummary t) => t.eventDate?.millisecondsSinceEpoch ?? 1 << 52;
  return [...list]..sort((a, b) {
      final pa = tournamentPhase(a), pb = tournamentPhase(b);
      if (pa != pb) return pa.index - pb.index;
      return pa == TPhase.past ? key(b) - key(a) : key(a) - key(b);
    });
}

String _pair(TournamentSummary t) => '${t.hostTeamName ?? 'TBC'} vs ${t.guestTeamName ?? 'TBC'}';
String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/* ── Artwork (painted on a 124 × 56 canvas, like the web SVGs) ─────────── */

class ModeArt extends StatelessWidget {
  const ModeArt(this.mode, {super.key, this.width = 96});
  final TMode mode;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: width,
      height: width * 56 / 124,
      child: CustomPaint(
        painter: switch (mode) {
          TMode.friendly => _FriendlyPainter(p),
          TMode.multi => _BracketPainter(p),
          TMode.league => _TablePainter(),
        },
      ),
    );
  }
}

abstract class _ArtPainter extends CustomPainter {
  void draw(Canvas c);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 124, size.height / 56);
    draw(canvas);
    canvas.restore();
  }

  // Cheap, and the palette changes with the theme.
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

Path _shield() => Path()
  ..moveTo(0, 0)
  ..lineTo(30, 0)
  ..lineTo(30, 21)
  ..cubicTo(30, 33, 22, 40, 15, 44)
  ..cubicTo(8, 40, 0, 33, 0, 21)
  ..close();

class _FriendlyPainter extends _ArtPainter {
  _FriendlyPainter(this.p);
  final AppPalette p;
  @override
  void draw(Canvas c) {
    void shield(double dx, double angle, Color fill, void Function() stripe) {
      c.save();
      c.translate(dx, 6);
      c.translate(15, 22);
      c.rotate(angle);
      c.translate(-15, -22);
      c.drawPath(_shield(), Paint()..color = fill);
      c.clipPath(_shield());
      stripe();
      c.restore();
    }

    shield(6, -0.105, p.accent, () => c.drawLine(const Offset(15, 0), const Offset(15, 44), Paint()..color = Colors.white.withAlpha(90)..strokeWidth = 5));
    shield(88, 0.105, p.ink, () => c.drawLine(const Offset(0, 14), const Offset(30, 14), Paint()..color = _mint..strokeWidth = 5));
    final rays = Paint()
      ..color = p.greenText.withAlpha(140)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in const [((40.0, 18.0), (46.0, 22.0)), ((40.0, 38.0), (46.0, 34.0)), ((84.0, 18.0), (78.0, 22.0)), ((84.0, 38.0), (78.0, 34.0))]) {
      c.drawLine(Offset(a.$1, a.$2), Offset(b.$1, b.$2), rays);
    }
    c.drawCircle(const Offset(62, 28), 15, Paint()..color = p.surface);
    final tp = TextPainter(
      text: TextSpan(text: 'VS', style: TextStyle(color: p.greenText, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(62 - tp.width / 2, 28 - tp.height / 2));
  }
}

class _BracketPainter extends _ArtPainter {
  _BracketPainter(this.p);
  final AppPalette p;
  @override
  void draw(Canvas c) {
    RRect pill(double x, double y, double w) => RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, 8), const Radius.circular(4));
    final strong = Paint()..color = p.orange.withAlpha(153);
    final soft = Paint()..color = p.orange.withAlpha(90);
    for (final (i, y) in const [6.0, 20.0, 36.0, 50.0].indexed) {
      c.drawRRect(pill(2, y - 4, 30), i.isOdd ? soft : strong);
    }
    c.drawRRect(pill(50, 9, 24), strong);
    c.drawRRect(pill(50, 39, 24), soft);
    final line = Paint()
      ..color = p.orangeInk.withAlpha(178)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    c.drawPath(Path()..moveTo(32, 6)..lineTo(40, 6)..lineTo(40, 20)..lineTo(32, 20)..moveTo(40, 13)..lineTo(50, 13), line);
    c.drawPath(Path()..moveTo(32, 36)..lineTo(40, 36)..lineTo(40, 50)..lineTo(32, 50)..moveTo(40, 43)..lineTo(50, 43), line);
    c.drawPath(Path()..moveTo(74, 13)..lineTo(82, 13)..lineTo(82, 43)..lineTo(74, 43)..moveTo(82, 28)..lineTo(92, 28), line);
    c.drawCircle(const Offset(106, 28), 14, Paint()..color = p.orange);
    final cup = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    c.drawPath(
        Path()
          ..moveTo(100, 21)
          ..lineTo(112, 21)
          ..lineTo(112, 25)
          ..arcToPoint(const Offset(100, 25), radius: const Radius.circular(6))
          ..close()
          ..moveTo(106, 31)
          ..lineTo(106, 35)
          ..moveTo(102, 36)
          ..lineTo(110, 36),
        cup);
  }
}

class _TablePainter extends _ArtPainter {
  @override
  void draw(Canvas c) {
    const rows = [(62.0, 255), (54.0, 71), (46.0, 51), (38.0, 36)];
    for (final (i, r) in rows.indexed) {
      final y = 2 + i * 14.0;
      final top = i == 0;
      final tp = TextPainter(
        text: TextSpan(
            text: '${i + 1}',
            style: TextStyle(color: top ? _mint : Colors.white.withAlpha(140), fontSize: 9, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(12 - tp.width, y));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(18, y, r.$1, 10), const Radius.circular(5)),
          Paint()..color = top ? _mint : Colors.white.withAlpha(r.$2));
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(18 + r.$1 + 6, y, 14, 10), const Radius.circular(5)),
          Paint()..color = Colors.white.withAlpha(top ? 90 : 36));
    }
    Paint arrow(Color col) => Paint()
      ..color = col
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    c.drawPath(Path()..moveTo(116, 14)..lineTo(116, 4)..moveTo(112, 8)..lineTo(116, 4)..lineTo(120, 8), arrow(_mint));
    c.drawPath(Path()..moveTo(116, 42)..lineTo(116, 52)..moveTo(112, 48)..lineTo(116, 52)..lineTo(120, 48), arrow(_warm));
  }
}

/* ── The Tournaments tab: one card per mode ────────────────────────────── */

class LiveTag extends StatelessWidget {
  const LiveTag({super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: context.palette.danger, borderRadius: BorderRadius.circular(99)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 6, color: Colors.white),
          SizedBox(width: 4),
          Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.color,
    required this.top,
    required this.title,
    required this.line,
    required this.foot,
    required this.onTap,
    this.titleColor,
    this.lineColor,
    this.footColor,
    this.badge,
    this.border,
  });
  final Color color;
  final Widget top;
  final String title;
  final String line;
  final String foot;
  final VoidCallback onTap;
  final Color? titleColor;
  final Color? lineColor;
  final Color? footColor;
  final Widget? badge;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 172,
          decoration: border == null ? null : BoxDecoration(border: border, borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.all(14),
          child: Stack(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              top,
              const Spacer(),
              Text(title,
                  maxLines: 2,
                  style: TextStyle(color: titleColor ?? p.ink, fontSize: 16, fontWeight: FontWeight.w800, height: 1.15)),
              const SizedBox(height: 2),
              Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: lineColor ?? p.muted, fontSize: 12)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                  child: Text(foot,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: footColor ?? p.ink, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: footColor ?? p.ink),
              ]),
            ]),
            if (badge != null) Positioned(top: 0, right: 0, child: badge!),
          ]),
        ),
      ),
    );
  }
}

/// The 2 × 2 grid on the group Tournaments tab. [onNew] null = no New card
/// (not an admin); [locked] = admin, but tournaments aren't on the plan.
class TournamentModeCards extends ConsumerWidget {
  const TournamentModeCards({super.key, required this.groupId, this.onNew, this.locked = false});
  final String groupId;
  final VoidCallback? onNew;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tq = ref.watch(groupTournamentsProvider(groupId));
    final all = tq.valueOrNull ?? const <TournamentSummary>[];
    final leagues = ref.watch(groupLeaguesProvider(groupId)).valueOrNull ?? const <J>[];
    final loading = tq.isLoading && tq.valueOrNull == null;

    final friendlies = sortTournaments(all.where((t) => !t.isMulti));
    final multis = sortTournaments(all.where((t) => t.isMulti));
    final fLive = friendlies.where((t) => tournamentPhase(t) == TPhase.live).firstOrNull;
    final fNext = friendlies.where((t) => tournamentPhase(t) == TPhase.upcoming).firstOrNull;
    final mLive = multis.any((t) => tournamentPhase(t) == TPhase.live);
    final mNext = multis.where((t) => tournamentPhase(t) != TPhase.past).firstOrNull;
    final running = leagues.where((l) => leaguePhase(l) == LPhase.running).toList();
    final lead = running.firstOrNull ?? leagues.where((l) => leaguePhase(l) == LPhase.draft).firstOrNull ?? leagues.firstOrNull;
    // Leagues the group's teams play in (or are invited to) count here too.
    final entries = [
      for (final t in ref.watch(groupTeamLeaguesProvider(groupId)).valueOrNull?.list('teams') ?? const <J>[]) ...t.list('entries'),
    ];
    final invited = entries.where((e) => e.s('phase') == 'invited').toList();
    final playing = entries.where((e) => e.s('phase') == 'active').toList();
    final seasons = leagues.length + entries.where((e) => e.s('phase') != 'invited').length;
    final runningN = running.length + playing.length;

    final cards = <Widget>[
      if (onNew != null && !locked)
        _ModeCard(
          color: p.surface,
          border: Border.all(color: p.line, width: 2),
          onTap: onNew!,
          top: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(16)),
            child: Icon(Icons.add_rounded, color: p.bg, size: 28),
          ),
          title: 'New tournament',
          line: 'Friendly, multi-team or league',
          foot: 'Start one',
        ),
      if (onNew != null && locked)
        _ModeCard(
          color: p.orangeTint,
          onTap: onNew!,
          top: SpIconTile(Icons.lock_outline_rounded, size: 48, iconSize: 22, bg: p.surface, fg: p.orangeInk),
          title: 'Host tournaments',
          line: 'A plan feature',
          lineColor: p.orangeInk,
          foot: 'See what you get',
          footColor: p.orangeInk,
        ),
      _ModeCard(
        color: p.accentTint,
        onTap: () => context.push(modePath(groupId, TMode.friendly)),
        top: const ModeArt(TMode.friendly),
        badge: fLive != null ? const LiveTag() : null,
        title: '1v1 Friendly',
        line: loading ? '…' : (friendlies.isEmpty ? 'One match, two teams' : _plural(friendlies.length, 'friendly', 'friendlies')),
        lineColor: p.greenText,
        foot: fLive != null
            ? 'Now: ${_pair(fLive)}'
            : fNext != null
                ? '${fNext.eventDate != null ? formatDay(fNext.eventDate) : 'Next'} · ${_pair(fNext)}'
                : friendlies.isEmpty
                    ? 'Challenge a rival'
                    : 'See all friendlies',
      ),
      _ModeCard(
        color: p.orangeTint,
        onTap: () => context.push(modePath(groupId, TMode.multi)),
        top: const ModeArt(TMode.multi),
        badge: mLive ? const LiveTag() : null,
        title: 'Multi-team',
        line: loading ? '…' : (multis.isEmpty ? 'Many teams, one draw' : _plural(multis.length, 'tournament', 'tournaments')),
        lineColor: p.orangeInk,
        foot: mNext != null
            ? '${mNext.title} · ${mNext.teamsIn}/${mNext.maxTeams} teams'
            : multis.isEmpty
                ? 'Bring teams together'
                : 'See all tournaments',
      ),
      _ModeCard(
        color: p.hero,
        onTap: () => context.push(modePath(groupId, TMode.league)),
        top: const ModeArt(TMode.league),
        badge: invited.isNotEmpty
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: p.orange, borderRadius: BorderRadius.circular(99)),
                child: Text('${invited.length} INVITE${invited.length == 1 ? '' : 'S'}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
              )
            : runningN == 0
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: _mint.withAlpha(50), borderRadius: BorderRadius.circular(99)),
                    child: Text('$runningN RUNNING',
                        style: const TextStyle(color: _mint, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
        title: 'League',
        titleColor: p.onHero,
        line: seasons == 0 ? 'A season with a live table' : _plural(seasons, 'season', 'seasons'),
        lineColor: _mint,
        foot: invited.isNotEmpty
            ? 'Invited: ${invited.first.o('league')?.str('competitionName')}'
            : lead != null
                ? '${lead.str('competitionName')}${lead.i('fixtures') > 0 ? ' · ${lead.i('played')}/${lead.i('fixtures')} played' : lead.s('status') == 'draft' ? ' · setting up' : ''}'
                : playing.isNotEmpty
                    ? 'Playing in ${playing.first.o('league')?.str('competitionName')}'
                    : entries.isNotEmpty
                        ? entries.first.o('league')?.str('competitionName') ?? 'Fixtures, table, MVPs'
                        : 'Fixtures, table, MVPs',
        footColor: p.heroMuted,
      ),
    ];

    // Two per row; an odd last card takes the full width.
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 10));
      rows.add(i + 1 < cards.length
          ? Row(children: [Expanded(child: cards[i]), const SizedBox(width: 10), Expanded(child: cards[i + 1])])
          : cards[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/* ── List cards (mode screens) ─────────────────────────────────────────── */

class TournamentSummaryCard extends StatelessWidget {
  const TournamentSummaryCard({super.key, required this.t});
  final TournamentSummary t;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final phase = tournamentPhase(t);
    final nameStyle = TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w600);
    return GlassCard(
      onTap: () => context.push('/tournaments/${t.eventId}'),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (t.categoryName != null) SpBadge('${t.categoryEmoji ?? ''} ${t.categoryName}'.trim()),
              if (t.eventDate != null) Text(formatDay(t.eventDate), style: TextStyle(color: p.muted, fontSize: 11)),
              SpBadge(t.isHost ? 'Host' : 'Away', tone: t.isHost ? p.accent : p.muted),
            ]),
          ),
          if (phase == TPhase.live)
            const LiveTag()
          else if (phase == TPhase.past)
            Text(t.status == 'cancelled' ? 'Cancelled' : 'Finished',
                style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        Text(t.title,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (t.isMulti)
          Row(children: [
            Icon(Icons.groups_outlined, size: 18, color: p.muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${t.teamsIn} of ${t.maxTeams} teams'),
                    if (t.teamsInvited > 0)
                      TextSpan(text: ' · ${t.teamsInvited} invited', style: TextStyle(color: p.muted, fontWeight: FontWeight.w500)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nameStyle),
            ),
            if (t.organiserOnly && t.isHost) const SpBadge('Organiser'),
          ])
        else
          Row(children: [
            Crest(logoUrl: t.hostTeamLogo, kitPrimary: t.hostKitPrimary, label: t.hostTeamName ?? '—', size: 28),
            const SizedBox(width: 6),
            Flexible(child: Text(t.hostTeamName ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('vs', style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
            Crest(logoUrl: t.guestTeamLogo, kitPrimary: t.guestKitPrimary, label: t.guestTeamName ?? '—', size: 28),
            const SizedBox(width: 6),
            Flexible(child: Text(t.guestTeamName ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle)),
            const Spacer(),
            if (t.guestStatus != null)
              SpBadge(t.guestStatus!,
                  tone: t.guestStatus == 'approved' || t.guestStatus == 'accepted'
                      ? p.accent
                      : t.guestStatus == 'declined' || t.guestStatus == 'rejected'
                          ? p.danger
                          : p.amber),
          ]),
      ]),
    );
  }
}

class LeagueSummaryCard extends StatelessWidget {
  const LeagueSummaryCard({super.key, required this.l, required this.groupId, required this.canManage});
  final J l;
  final String groupId;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fixtures = l.i('fixtures');
    final played = l.i('played');
    return GlassCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push(canManage ? '/groups/$groupId/leagues/${l.str('id')}' : '/leagues/${l.str('slug')}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SpBadge('League', icon: Icons.format_list_numbered_rounded, tone: p.ink),
          Text(l.str('season'), style: TextStyle(color: p.muted, fontSize: 11)),
          if (l.s('division') != null) SpBadge(l.str('division')),
          SpBadge(leagueStatusLabel[l.s('status')] ?? l.str('status'), tone: l.s('status') == 'draft' ? p.orangeInk : p.greenText),
        ]),
        const SizedBox(height: 6),
        Text(l.str('competitionName'), style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w800)),
        Text(l.str('format'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 11.5)),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.groups_rounded, size: 16, color: p.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
                '${l.i('teamsIn')} team${l.i('teamsIn') == 1 ? '' : 's'}'
                '${l.i('teamsInvited') > 0 ? ' · ${l.i('teamsInvited')} invited' : ''}',
                style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          if (fixtures > 0) ...[
            SizedBox(
              width: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: played / fixtures,
                  minHeight: 6,
                  backgroundColor: p.surface2,
                  valueColor: AlwaysStoppedAnimation(p.accent),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text('$played/$fixtures', style: TextStyle(color: p.muted, fontSize: 11.5)),
          ],
        ]),
      ]),
    );
  }
}
