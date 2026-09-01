import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/games/game_models.dart';
import 'package:sportpadi_mobile/data/games/games_repository.dart';
import 'package:sportpadi_mobile/data/games/live_game_controller.dart';
import 'package:sportpadi_mobile/features/games/officiant_panel.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Live game screen — a faithful port of the web GameClient layout:
/// scoreboard card with the clock strip, draw-resolution + shootout cards,
/// officiants, admin controls, timeline, and side-by-side lineups.
class GameScreen extends ConsumerWidget {
  const GameScreen({super.key, required this.gameId});
  final String gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final game = ref.watch(liveGameProvider(gameId));
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: Text(
          game.valueOrNull?.categoryName != null
              ? '${game.valueOrNull!.categoryEmoji ?? ''} ${game.valueOrNull!.categoryName}'
                  .trim()
              : 'Match',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (game.valueOrNull != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: SpBadge(
                  game.valueOrNull!.status == 'kicked_off'
                      ? 'live'
                      : game.valueOrNull!.status,
                  tone: game.valueOrNull!.isLive ? p.danger : p.muted,
                ),
              ),
            ),
        ],
      ),
      // Semantics for the whole app are excluded at the root (see app.dart)
      // to dodge this Flutter build's '!semantics.parentDataDirty' bug.
      body: AsyncView(
        value: game,
        onRetry: () => ref.invalidate(liveGameProvider(gameId)),
        data: (g) => RefreshIndicator(
          onRefresh: () =>
              ref.read(liveGameProvider(gameId).notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _Scoreboard(game: g),
              if (g.canManage && _awaitingDraw(g)) ...[
                const SizedBox(height: 12),
                _DrawCard(gameId: gameId, game: g),
              ],
              if (_penaltiesAdded(g) && g.isLive) ...[
                const SizedBox(height: 12),
                _ShootoutCard(gameId: gameId, game: g),
              ],
              if (g.officiantNames.isNotEmpty) ...[
                const SizedBox(height: 12),
                GlassCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.verified_user_outlined,
                        size: 14, color: p.accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Officiants: ${g.officiantNames.join(', ')}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: p.muted, fontSize: 12),
                      ),
                    ),
                  ]),
                ),
              ],
              if (g.canManage) ...[
                const SizedBox(height: 12),
                OfficiantPanel(gameId: gameId, game: g),
              ],
              const SizedBox(height: 12),
              _TimelineCard(game: g, gameId: gameId),
              const SizedBox(height: 12),
              _Lineups(game: g),
            ],
          ),
        ),
      ),
    );
  }

  static bool _penaltiesAdded(GameDetail g) =>
      g.lifecycle?.phases.any((ph) => ph.kind == 'shootout') ?? false;

  static bool _awaitingDraw(GameDetail g) {
    final lc = g.lifecycle;
    if (lc == null || !g.isLive) return false;
    final ph = lc.current;
    final inTimed = ph != null && ph.isTimed && ph.status == 'live';
    final regulationDone = !inTimed && lc.nextTimed == null;
    // Web drawOpts: extra time is only an option while it hasn't been played.
    final hasOption =
        (lc.drawResolutions.contains('extra_time') && !lc.hasExtraPhases) ||
            lc.drawResolutions.contains('penalties');
    return regulationDone && g.isDrawn && hasOption && !_penaltiesAdded(g);
  }
}

Color teamColor(String? hex, AppPalette p) {
  if (hex == null || hex.isEmpty) return const Color(0xFF888888);
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFF888888);
}

// ---------------------------------------------------------------------------
// Scoreboard — the web card: two halves with a top colour bar, VS/FT circle,
// then the clock strip on a muted band.
// ---------------------------------------------------------------------------

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.game});
  final GameDetail game;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = game;
    final vsMode = g.teams.length == 2 && g.maxTeamsPerGame <= 2;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 30, 22, 0.06),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(children: [
        if (vsMode)
          IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _ScoreTeam(team: g.teams[0])),
              SizedBox(
                width: 48,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.surface2,
                      border: Border.all(color: p.line),
                    ),
                    child: Text(
                      g.status == 'completed' ? 'FT' : 'VS',
                      style: TextStyle(
                          color: p.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
              Expanded(child: _ScoreTeam(team: g.teams[1])),
            ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              for (final t in g.teams)
                Expanded(child: _ScoreTeam(team: t, compact: true)),
            ]),
          ),
        _ClockStrip(game: g),
      ]),
    );
  }
}

class _ScoreTeam extends StatelessWidget {
  const _ScoreTeam({required this.team, this.compact = false});
  final GameTeam team;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = team;
    final won = t.result == 'win';
    final lost = t.result == 'loss';
    return Container(
      color: won ? const Color.fromRGBO(23, 166, 94, 0.05) : null,
      child: Column(children: [
        Container(height: 4, color: teamColor(t.color, p)),
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: 10, vertical: compact ? 10 : 18),
          child: Column(children: [
            Text(
              t.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: lost ? p.muted : p.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${t.score}',
              style: TextStyle(
                color: lost ? p.muted : p.ink,
                fontSize: compact ? 30 : 38,
                fontWeight: FontWeight.w900,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (t.result != null) ...[
              const SizedBox(height: 3),
              Text(
                t.result!.toUpperCase(),
                style: TextStyle(
                  color: won
                      ? p.accent
                      : lost
                          ? p.danger
                          : p.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// The muted clock band under the scores — timer, +stoppage, Paused, phase.
class _ClockStrip extends StatefulWidget {
  const _ClockStrip({required this.game});
  final GameDetail game;
  @override
  State<_ClockStrip> createState() => _ClockStripState();
}

class _ClockStripState extends State<_ClockStrip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick =
        Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = widget.game;
    if (g.startedAt == null) return const SizedBox.shrink();
    final info = clockInfo(g);
    if (info == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: p.surface2,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.timer_outlined,
              size: 15, color: info.paused ? p.muted : p.accent),
          const SizedBox(width: 6),
          Text(
            info.display,
            style: TextStyle(
              color: info.paused ? p.muted : p.ink,
              fontSize: 19,
              fontWeight: FontWeight.w900,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (info.paused) ...[
            const SizedBox(width: 8),
            SpBadge('Paused', tone: p.muted),
          ],
        ]),
        if (info.label != null)
          Text(
            info.label!.toUpperCase(),
            style: TextStyle(
              color: p.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
      ]),
    );
  }
}
class ClockInfo {
  const ClockInfo(this.display, {this.label, this.paused = false});
  final String display;
  final String? label;
  final bool paused;
}

/// Shared clock math (also used to stamp minutes on recorded activities).
ClockInfo? clockInfo(GameDetail g) {
  if (!g.isLive) {
    if (g.status == 'completed') return const ClockInfo('FT');
    return null;
  }
  // Offset anchored at FETCH time (serverNow vs fetchedAt) — computing it
  // against the current instant would freeze the clock at the fetch moment.
  final offset = (g.serverNow != null && g.fetchedAt != null)
      ? g.serverNow!.difference(g.fetchedAt!)
      : Duration.zero;
  final now = DateTime.now().add(offset);

  final lc = g.lifecycle;
  if (lc != null) {
    final ph = lc.current;
    if (ph == null) return null;
    if (ph.kind == 'shootout') {
      return const ClockInfo('PENS', label: 'Penalty shootout');
    }
    if (ph.kind == 'interval' || ph.status != 'live') {
      return ClockInfo('--:--', label: ph.label, paused: true);
    }
    final anchor = ph.startedAt;
    if (anchor == null) return ClockInfo('00:00', label: ph.label);
    final end = ph.timer.pausedAt ?? now;
    var elapsed =
        end.difference(anchor).inMilliseconds - ph.timer.pausedMs;
    if (elapsed < 0) elapsed = 0;
    final total = ph.nominalOffset * 60000 + elapsed;
    return ClockInfo(
      _fmt(total),
      label: ph.timer.stoppageMin > 0
          ? "${ph.label} · +${ph.timer.stoppageMin}'"
          : ph.label,
      paused: ph.timer.pausedAt != null,
    );
  }

  final started = g.startedAt;
  if (started == null) return null;
  final end = g.timer.pausedAt ?? now;
  var elapsed = end.difference(started).inMilliseconds - g.timer.pausedMs;
  if (elapsed < 0) elapsed = 0;
  return ClockInfo(
    _fmt(elapsed),
    label: g.timer.stoppageMin > 0 ? "+${g.timer.stoppageMin}' stoppage" : null,
    paused: g.timer.pausedAt != null,
  );
}

/// Minute to stamp on an activity right now: null for phased games (the
/// server derives it from the phase), 1-based elapsed minutes otherwise.
int? activityMinute(GameDetail g) {
  if (g.lifecycle != null) return null;
  final started = g.startedAt;
  if (started == null || !g.isLive) return null;
  final offset = (g.serverNow != null && g.fetchedAt != null)
      ? g.serverNow!.difference(g.fetchedAt!)
      : Duration.zero;
  final now = DateTime.now().add(offset);
  final end = g.timer.pausedAt ?? now;
  var elapsed = end.difference(started).inMilliseconds - g.timer.pausedMs;
  if (elapsed < 0) elapsed = 0;
  final min = (elapsed / 60000).ceil();
  return min < 1 ? 1 : min;
}

String _fmt(int ms) {
  final totalSec = ms ~/ 1000;
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}


// ---------------------------------------------------------------------------
// Draw resolution — offered when a knockout ends level (amber card).
// ---------------------------------------------------------------------------

class _DrawCard extends ConsumerWidget {
  const _DrawCard({required this.gameId, required this.game});
  final String gameId;
  final GameDetail game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final lc = game.lifecycle!;
    final etAdded = lc.hasExtraPhases;
    Future<void> act(String action) async {
      try {
        await ref.read(gamesRepositoryProvider).phase(gameId, action);
        await ref.read(liveGameProvider(gameId).notifier).refresh();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color.fromRGBO(245, 167, 10, 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Level at ${etAdded ? 'the end of extra time' : 'full time'}',
            style: TextStyle(
                color: p.ink, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          Text('Choose how to decide the tie.',
              style: TextStyle(color: p.muted, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (lc.drawResolutions.contains('extra_time') && !etAdded)
              SpButton(
                label: 'Extra time',
                icon: Icons.timelapse_rounded,
                onTap: () => act('extraTime'),
              ),
            if (lc.drawResolutions.contains('penalties'))
              SpButton(
                label: 'Straight to penalties',
                icon: Icons.flag_outlined,
                onTap: () => act('penalties'),
              ),
            // Always offered: accept the level scoreline and finish the match.
            SpButton(
              label: 'End as draw',
              icon: Icons.handshake_outlined,
              onTap: () async {
                try {
                  await ref.read(gamesRepositoryProvider).complete(gameId);
                  await ref.read(liveGameProvider(gameId).notifier).refresh();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
            ),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Penalty shootout — web card: per-team rows, "to take" highlight, inline
// Scored / Missed / Undo with strict alternation.
// ---------------------------------------------------------------------------

class _ShootoutCard extends ConsumerWidget {
  const _ShootoutCard({required this.gameId, required this.game});
  final String gameId;
  final GameDetail game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final g = game;
    final lc = g.lifecycle!;
    final tally = lc.shootoutTally;
    final order = lc.shootoutOrder;
    final history = lc.shootoutHistory;
    final turnTeam =
        order.length == 2 ? order[history.length % 2] : null;
    final lastTaker =
        history.isNotEmpty ? history.last.teamId : null;

    Future<void> attempt(String teamId, String outcome) async {
      try {
        await ref
            .read(gamesRepositoryProvider)
            .shootout(gameId, teamId, outcome);
        await ref.read(liveGameProvider(gameId).notifier).refresh();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }

    Widget mini(String label, VoidCallback? onTap, {bool outline = false}) {
      return Material(
        color: onTap == null
            ? p.surface2
            : outline
                ? p.surface
                : p.accent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: outline
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: p.line),
                  )
                : null,
            child: Text(
              label,
              style: TextStyle(
                color: onTap == null
                    ? p.muted
                    : outline
                        ? p.ink
                        : Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.flag_outlined, size: 15, color: p.accent),
            const SizedBox(width: 6),
            Text('Penalty shootout',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          if (turnTeam == null)
            Text(
              'Record the first penalty to set the order — then they alternate.',
              style: TextStyle(color: p.muted, fontSize: 11.5),
            ),
          const SizedBox(height: 8),
          for (final t in g.teams)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: turnTeam == t.teamId
                    ? const Color.fromRGBO(23, 166, 94, 0.06)
                    : null,
                border: turnTeam == t.teamId
                    ? Border.all(
                        color: const Color.fromRGBO(23, 166, 94, 0.3))
                    : null,
              ),
              child: Row(children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: teamColor(t.color, p),
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(children: [
                    Flexible(
                      child: Text(t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (turnTeam == t.teamId)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text('TO TAKE',
                            style: TextStyle(
                                color: p.accent,
                                fontSize: 9,
                                fontWeight: FontWeight.w800)),
                      ),
                  ]),
                ),
                Text('${tally[t.teamId]?.scored ?? 0}',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w900)),
                const SizedBox(width: 4),
                Text('of ${tally[t.teamId]?.taken ?? 0}',
                    style: TextStyle(color: p.muted, fontSize: 10.5)),
                if (g.canManage) ...[
                  const SizedBox(width: 8),
                  mini(
                      'Scored',
                      (turnTeam == null || turnTeam == t.teamId)
                          ? () => attempt(t.teamId, 'scored')
                          : null),
                  const SizedBox(width: 4),
                  mini(
                      'Missed',
                      (turnTeam == null || turnTeam == t.teamId)
                          ? () => attempt(t.teamId, 'missed')
                          : null,
                      outline: true),
                  const SizedBox(width: 4),
                  mini(
                      'Undo',
                      lastTaker == t.teamId
                          ? () => attempt(t.teamId, 'undo')
                          : null,
                      outline: true),
                ],
              ]),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline — web rows: minute, icon, team dot, "#7 Name — Goal (with #10)".
// ---------------------------------------------------------------------------

class _TimelineCard extends ConsumerWidget {
  const _TimelineCard({required this.game, required this.gameId});
  final GameDetail game;
  final String gameId;

  String _jn(int? jersey) => jersey != null ? '#$jersey ' : '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final g = game;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Timeline',
              style: TextStyle(
                  color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (g.activities.isEmpty)
            Text('No activity yet.',
                style: TextStyle(color: p.muted, fontSize: 13))
          else
            for (final a in g.activities) _row(context, ref, a),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, GameActivity a) {
    final p = context.palette;
    final g = game;
    final def = g.defFor(a.type);
    final team = g.teams.where((t) => t.teamId == a.teamId).toList();
    final isSub = a.type == 'substitution';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            child: Text(
              a.minute != null ? "${a.minute}'" : (a.phase ?? ''),
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: p.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(width: 8),
          Text(def?.icon ?? '•', style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 7),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: teamColor(
                    team.isNotEmpty ? team.first.color : null, p),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Plain wrapped Texts — inline TextSpans trip this Flutter build's
          // semantics compiler (same family as Badge / *.icon buttons).
          Expanded(
            child: isSub
                ? Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${_jn(a.jersey)}${a.playerName}',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(' ▲ on',
                          style: TextStyle(
                              color: p.accent, fontSize: 13)),
                      if (a.relatedPlayerName != null) ...[
                        Text(' · ',
                            style: TextStyle(
                                color: p.muted, fontSize: 13)),
                        Text(a.relatedPlayerName!,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        Text(' ▼ off',
                            style: TextStyle(
                                color: p.danger, fontSize: 13)),
                      ],
                    ],
                  )
                : Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${_jn(a.jersey)}${a.playerName}',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(' — ${def?.label ?? a.type}',
                          style: TextStyle(
                              color: p.muted, fontSize: 13)),
                      if (a.relatedPlayerName != null)
                        Text(' (with ${a.relatedPlayerName})',
                            style: TextStyle(
                                color: p.muted, fontSize: 13)),
                    ],
                  ),
          ),
          if (g.canManage && (g.isLive || g.status == 'completed'))
            InkWell(
              onTap: () => _void(context, ref, a),
              child: Padding(
                padding: const EdgeInsets.only(left: 6, top: 1),
                child: Icon(Icons.undo_rounded, size: 15, color: p.muted),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _void(
      BuildContext context, WidgetRef ref, GameActivity a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Void this entry?'),
        content: Text(
            '"${game.defFor(a.type)?.label ?? a.type} — ${a.playerName}" is removed and the score recomputed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Void')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(gamesRepositoryProvider).voidActivity(gameId, a.id);
      await ref.read(liveGameProvider(gameId).notifier).refresh();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Lineups — the web's side-by-side team cards: "On the pitch" and
// "Bench & out", with ▲ On / ▼ Subbed off / Sent off / SUB badges.
// ---------------------------------------------------------------------------

class _Lineups extends StatelessWidget {
  const _Lineups({required this.game});
  final GameDetail game;

  @override
  Widget build(BuildContext context) {
    final g = game;
    // Pre-kickoff the roster is the lineup; after, the participant snapshot.
    final started = !g.isScheduled;
    final subbedIn = <String>{};
    final subbedOff = <String>{};
    for (final a in g.activities) {
      if (a.type == 'substitution') {
        subbedIn.add(a.playerId);
        if (a.relatedPlayerId != null) subbedOff.add(a.relatedPlayerId!);
      }
    }
    final cards = [
      for (final t in g.teams)
        Expanded(
          child: _LineupCard(
            game: g,
            team: t,
            started: started,
            subbedIn: subbedIn,
            subbedOff: subbedOff,
          ),
        ),
    ];
    if (cards.length <= 2) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i < cards.length - 1) const SizedBox(width: 10),
          ],
        ],
      );
    }
    return Column(children: [
      for (final t in g.teams)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _LineupCard(
            game: g,
            team: t,
            started: started,
            subbedIn: subbedIn,
            subbedOff: subbedOff,
          ),
        ),
    ]);
  }
}

class _LineupCard extends StatelessWidget {
  const _LineupCard({
    required this.game,
    required this.team,
    required this.started,
    required this.subbedIn,
    required this.subbedOff,
  });
  final GameDetail game;
  final GameTeam team;
  final bool started;
  final Set<String> subbedIn;
  final Set<String> subbedOff;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = game;
    final t = team;
    final lineup = started
        ? g.participants.where((x) => x.teamId == t.teamId).toList()
        : [
            for (final r
                in g.roster.where((r) => r.teamId == t.teamId))
              GamePlayer(
                playerId: r.playerId,
                teamId: r.teamId,
                displayName: r.displayName,
                onField: !r.isSub,
                avatarUrl: r.avatarUrl,
                jersey: r.jersey,
              ),
          ];
    final onPitch =
        lineup.where((x) => x.onField && !x.sentOff).toList();
    final offPitch =
        lineup.where((x) => !(x.onField && !x.sentOff)).toList();

    Widget badge(String text, Color tone) => Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: tone),
          ),
          child: Text(text,
              style: TextStyle(
                  color: tone,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800)),
        );

    Widget row(GamePlayer x) {
      final dimmed =
          x.sentOff || (!x.onField && subbedOff.contains(x.playerId));
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(children: [
          Expanded(
            child: Text(
              '${x.jersey != null ? '#${x.jersey} ' : ''}${x.displayName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dimmed ? p.muted : p.ink,
                fontSize: 12,
                decoration:
                    x.sentOff ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (x.onField && !x.sentOff && subbedIn.contains(x.playerId))
            badge('▲ ON', p.accent)
          else if (x.sentOff)
            badge('SENT OFF', p.danger)
          else if (!x.onField && subbedOff.contains(x.playerId))
            badge('▼ OFF', p.muted)
          else if (!x.onField)
            badge('SUB', p.muted),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: t.groupTeamId != null
                ? () => context.push('/teams/${t.groupTeamId}')
                : null,
            child: Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: teamColor(t.color, p),
                    shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(t.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Text('ON THE PITCH (${onPitch.length})',
              style: TextStyle(
                  color: p.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6)),
          const SizedBox(height: 3),
          if (onPitch.isEmpty)
            Text('No one on yet.',
                style: TextStyle(color: p.muted, fontSize: 11))
          else
            for (final x in onPitch) row(x),
          if (offPitch.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('BENCH & OUT (${offPitch.length})',
                style: TextStyle(
                    color: p.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6)),
            const SizedBox(height: 3),
            for (final x in offPitch) row(x),
          ],
        ],
      ),
    );
  }
}
