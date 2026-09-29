import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/games/game_models.dart';
import 'package:sportpadi_mobile/data/games/games_repository.dart';
import 'package:sportpadi_mobile/data/games/live_game_controller.dart';
import 'package:sportpadi_mobile/features/games/game_screen.dart'
    show activityMinute;
import 'package:sportpadi_mobile/features/games/stoppage_pad.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// Scorekeeper controls: kickoff, clock/phase control, stat recording,
/// substitutions, shootout tallying and finishing the match. Stat writes
/// auto-claim the scoresheet server-side; a 409 offers a takeover.
class OfficiantPanel extends ConsumerStatefulWidget {
  const OfficiantPanel({super.key, required this.gameId, required this.game});
  final String gameId;
  final GameDetail game;

  @override
  ConsumerState<OfficiantPanel> createState() => _OfficiantPanelState();
}

class _OfficiantPanelState extends ConsumerState<OfficiantPanel> {
  bool _busy = false;

  GameDetail get g => widget.game;

  /// Stoppage already added to the current period (phased) or the game.
  int _stoppageNow(GameDetail g) =>
      g.lifecycle?.current?.timer.stoppageMin ?? g.timer.stoppageMin;
  GamesRepository get repo => ref.read(gamesRepositoryProvider);

  Future<void> _run(Future<void> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
      await ref.read(liveGameProvider(widget.gameId).notifier).refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        _offerTakeover(e.message);
      } else {
        _snack(e.message);
      }
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _offerTakeover(String msg) async {
    final take = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Someone else is scoring'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('OK')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Take over')),
        ],
      ),
    );
    if (take == true) {
      await _run(() => repo.takeover(widget.gameId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lc = g.lifecycle;
    final phase = lc?.current;
    final inShootout = g.isLive && phase?.kind == 'shootout';
    final inTimedPhase = phase != null && phase.isTimed && phase.status == 'live';
    final paused = lc != null
        ? (phase?.timer.pausedAt != null)
        : (g.timer.pausedAt != null);
    // Web gating: Complete only once regulation is done and no draw decision
    // is pending; during a shootout it stays visible but disabled until the
    // kicks are decisive. No Abandon on the web at all.
    final regulationDone = lc != null && !inTimedPhase && lc.nextTimed == null;
    final pensAdded = lc?.hasShootout ?? false;
    final etAdded = lc?.hasExtraPhases ?? false;
    final drawOption = lc != null &&
        ((lc.drawResolutions.contains('extra_time') && !etAdded) ||
            lc.drawResolutions.contains('penalties'));
    final awaitingDraw =
        g.isLive && regulationDone && g.isDrawn && drawOption && !pensAdded;
    var maxScored = 0;
    var anyKicks = false;
    for (final t in g.teams) {
      final tl = lc?.shootoutTally[t.teamId];
      if ((tl?.scored ?? 0) > maxScored) maxScored = tl?.scored ?? 0;
      if ((tl?.taken ?? 0) > 0) anyKicks = true;
    }
    final pkLeaders = [
      for (final t in g.teams)
        if ((lc?.shootoutTally[t.teamId]?.scored ?? 0) == maxScored) t
    ].length;
    final pensDecisive = pensAdded && anyKicks && pkLeaders == 1;
    final showComplete =
        lc != null ? (regulationDone && !awaitingDraw) : g.isLive;
    final completeEnabled = !pensAdded || pensDecisive;
    // Web parity: recording (and the clock) is only live during a timed phase
    // (or for non-phased games while live) — never while a lifecycle decision
    // (draw resolution, phase break) is pending.
    final showPlay = g.isLive && (lc == null || inTimedPhase);
    // The final whistle isn't a hard stop: admins / assigned officiants can
    // still record stats on a completed game (results re-finalize server-side).
    final showAmend = g.status == 'completed' && g.canScore;
    // Split jobs: the timekeeper runs the clock (officiant mode), the scorer
    // records stats. Admins and "both" officiants see everything.
    final canTime = g.canTime;
    final canScore = g.canScore;
    final prof = g.profile;
    final showStartNext =
        g.isLive && lc != null && !inTimedPhase && lc.nextTimed != null;
    // Nothing to offer (e.g. level at full time, decision pending): the draw
    // card is the actionable element — hide the panel entirely, like the web.
    final hasControls = (g.isScheduled && canTime) ||
        inShootout ||
        (showPlay && (canTime || canScore)) ||
        showAmend ||
        (showStartNext && canTime) ||
        (showComplete && canTime);
    if (!hasControls) return const SizedBox.shrink();

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Eyebrow('Officiate')),
              if (_busy)
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 10),

          // -- Officiant mode: the distraction-free clock screen ----------
          if (canTime && (g.isScheduled || g.isLive)) ...[
            _OfficiantModeTile(
              subtitle: 'Full-screen clock: ${g.isScheduled ? 'kick-off, ' : ''}'
                  '${prof.pauseLabel.toLowerCase()}'
                  '${prof.addsTime ? ', stoppage' : ''}'
                  '${prof.has('periods') ? ', ${prof.periodWord}s' : ''}'
                  ' and full time — the app stays locked on screen.',
              onTap: () => context.push('/games/${widget.gameId}/officiate'),
            ),
            const SizedBox(height: 10),
          ],

          // -- Scheduled: kickoff ------------------------------------------
          if (g.isScheduled && canTime)
            SpButton(
              label: 'Kick off',
              icon: Icons.play_arrow_rounded,
              expand: true,
              onTap: _busy ? null : () => _run(() => repo.start(widget.gameId)),
            ),

          // -- Live: clock + phase controls --------------------------------
          if (g.isLive) ...[
            if (inShootout)
              Text(
                'Penalty shootout in progress — record kicks on the shootout card above.',
                style: TextStyle(color: p.muted, fontSize: 12),
              )
            else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canTime && (lc == null || inTimedPhase)) ...[
                    _MiniAction(
                      label: paused ? prof.resumeLabel : prof.pauseLabel,
                      icon: paused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      onTap: _busy
                          ? null
                          : () => _run(() => repo.timer(widget.gameId,
                              paused ? 'resume' : 'pause')),
                    ),
                    if (prof.addsTime)
                      _MiniAction(
                        label: 'Stoppage',
                        icon: Icons.more_time_rounded,
                        onTap: _busy
                            ? null
                            : () => showSpSheet<void>(
                                  context,
                                  builder: (ctx) => Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const SpSheetHeader(
                                        icon: Icons.more_time_rounded,
                                        title: 'Stoppage time',
                                        subtitle: 'Add any amount up to 120\', or correct the total.',
                                      ),
                                      StoppagePad(
                                        dark: false,
                                        startExpanded: true,
                                        current: _stoppageNow(g),
                                        presets: prof.stoppagePresets,
                                        onAdd: (m) {
                                          Navigator.of(ctx).pop();
                                          _run(() => repo.timer(widget.gameId, 'stoppage', minutes: m));
                                        },
                                        onSet: (m) {
                                          Navigator.of(ctx).pop();
                                          _run(() => repo.timer(widget.gameId, 'setStoppage', minutes: m));
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                      ),
                  ],
                  if (canTime && lc != null && inTimedPhase)
                    _MiniAction(
                      label: 'End ${phase.label}',
                      icon: Icons.flag_rounded,
                      onTap: _busy
                          ? null
                          : () => _run(
                              () => repo.phase(widget.gameId, 'endPhase')),
                    ),
                  if (showStartNext && canTime)
                    _MiniAction(
                      label: 'Start ${lc.nextTimed!.label}',
                      icon: Icons.play_arrow_rounded,
                      onTap: _busy
                          ? null
                          : () => _run(
                              () => repo.phase(widget.gameId, 'startNext')),
                    ),
                ],
              ),
              if (showPlay && canScore) ...[
                const SizedBox(height: 12),
                const Eyebrow('Record'),
                const SizedBox(height: 8),
                // One row of event types (web layout): pick the event, then
                // the team, the player — and the assist when it's a goal.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final def in g.schema)
                      if (def.type != 'substitution')
                        _MiniAction(
                          label:
                              '${def.icon != null ? '${def.icon} ' : ''}${def.label}',
                          onTap: _busy ? null : () => _recordActivity(def),
                        ),
                    _MiniAction(
                      label: '🔁 Sub',
                      onTap: _busy ? null : _substituteFlow,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ],
            if (showComplete && canTime) ...[
              const SizedBox(height: 4),
              SpButton(
                label: 'Complete match',
                icon: Icons.check_rounded,
                expand: true,
                onTap:
                    _busy || !completeEnabled ? null : _confirmComplete,
              ),
            ],
          ],

          // -- Completed: post-match corrections ---------------------------
          if (showAmend) ...[
            const Eyebrow('Amend stats'),
            const SizedBox(height: 4),
            Text(
              'Something happened right at the end? Record it here — the '
              'final score and result update automatically. Undo a mistake '
              'from the timeline below.',
              style: TextStyle(color: p.muted, fontSize: 11.5),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final def in g.schema)
                  if (def.type != 'substitution')
                    _MiniAction(
                      label:
                          '${def.icon != null ? '${def.icon} ' : ''}${def.label}',
                      onTap: _busy ? null : () => _recordActivity(def),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // -- Record an activity (web dialog flow: team → player → assist) --------

  Future<void> _recordActivity(ActivityDef def) async {
    final result = await showSpSheet<
        ({String teamId, String playerId, String? relatedId})>(
      context,
      framed: false,
      builder: (_) => _RecordSheet(game: g, def: def),
    );
    if (result == null) return;
    await _run(() => repo.addActivity(
          widget.gameId,
          teamId: result.teamId,
          type: def.type,
          playerId: result.playerId,
          relatedPlayerId: result.relatedId,
          minute: activityMinute(g),
        ));
  }

  // -- Substitution --------------------------------------------------------

  Future<void> _substituteFlow() async {
    if (g.teams.length == 1) {
      await _substitute(g.teams.first);
      return;
    }
    final p = context.palette;
    final team = await showSpSheet<GameTeam>(
      context,
      builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Which team?',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            for (final t in g.teams)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(t.name, style: TextStyle(color: p.ink)),
                onTap: () => Navigator.pop(ctx, t),
              ),
          ],
        ),
    );
    if (team != null) await _substitute(team);
  }

  Future<void> _substitute(GameTeam team) async {
    final onField = g.onFieldFor(team.teamId);
    final bench = g.benchFor(team.teamId);
    if (onField.isEmpty || bench.isEmpty) {
      _snack('Need a player on the pitch and one on the bench.');
      return;
    }
    final off = await _pickPlayer(
        'Coming off — ${team.name}',
        onField
            .map((x) => _Pick(x.playerId, x.displayName, x.jersey))
            .toList());
    if (off == null) return;
    final on = await _pickPlayer(
        'Coming on — ${team.name}',
        bench
            .where((x) => x.playerId != off)
            .map((x) => _Pick(x.playerId, x.displayName, x.jersey))
            .toList());
    if (on == null) return;
    await _run(() => repo.substitute(
          widget.gameId,
          teamId: team.teamId,
          playerOffId: off,
          playerOnId: on,
          minute: activityMinute(g),
        ));
  }

  // -- Finish --------------------------------------------------------------

  Future<void> _confirmComplete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete the match?'),
        content: const Text(
            'Final scores are locked in and results are recorded.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not yet')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Complete')),
        ],
      ),
    );
    if (ok == true) await _run(() => repo.complete(widget.gameId));
  }


  // -- Player picker sheet --------------------------------------------------

  Future<String?> _pickPlayer(String title, List<_Pick> players,
      {bool allowSkip = false}) {
    final p = context.palette;
    return showSpSheet<String>(
      context,
      framed: false,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(title,
                style: TextStyle(
                    color: p.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final x in players)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 15,
                        backgroundColor: p.surface2,
                        child: Text(
                          x.jersey != null
                              ? '${x.jersey}'
                              : (x.name.isNotEmpty ? x.name[0] : '?'),
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Text(x.name,
                          style: TextStyle(color: p.ink, fontSize: 14)),
                      onTap: () => Navigator.pop(ctx, x.id),
                    ),
                ],
              ),
            ),
            if (allowSkip)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Skip'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pick {
  const _Pick(this.id, this.name, this.jersey);
  final String id;
  final String name;
  final int? jersey;
}

/// Small outline action chip (safe hand-rolled button).
class _OfficiantModeTile extends StatelessWidget {
  const _OfficiantModeTile({required this.subtitle, required this.onTap});
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.accent.withAlpha(22),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.accent.withAlpha(90)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Enter officiant mode',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: p.muted, fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.fullscreen_rounded, color: p.accent),
          ]),
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.label, this.icon, required this.onTap});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onTap != null;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 16, color: enabled ? p.accent : p.muted),
                const SizedBox(width: 5),
              ],
              Text(label,
                  style: TextStyle(
                      color: enabled ? p.ink : p.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}


/// The web "add event" dialog as a sheet: pick the team, the player on the
/// pitch, and (for goals / paired events) the assist — then Record.
class _RecordSheet extends StatefulWidget {
  const _RecordSheet({required this.game, required this.def});
  final GameDetail game;
  final ActivityDef def;

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  late String _teamId = widget.game.teams.isNotEmpty
      ? widget.game.teams.first.teamId
      : '';
  String? _playerId;
  String? _relatedId;

  Color _teamColor(GameTeam t, AppPalette p) {
    final hex = t.color;
    if (hex == null || hex.isEmpty) return p.accent;
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFF17A65E);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = widget.game;
    final def = widget.def;
    final onField = g.onFieldFor(_teamId);
    final needsRelated = def.requiresRelated;
    final wantsRelated = def.assistAllowed || needsRelated;
    final canRecord = _playerId != null && (!needsRelated || _relatedId != null);

    Widget playerChip(String id, String name, int? jersey,
        {required bool selected, required VoidCallback onTap}) {
      return Material(
        color: selected ? p.accent : p.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? p.accent : p.line),
            ),
            child: Text(
              '${jersey != null ? '#$jersey ' : ''}$name',
              style: TextStyle(
                color: selected ? Colors.white : p.ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            '${def.icon != null ? '${def.icon} ' : ''}${def.label}',
            style: TextStyle(
                color: p.ink, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Text('TEAM',
              style: TextStyle(
                  color: p.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0)),
          const SizedBox(height: 6),
          Row(children: [
            for (final t in g.teams) ...[
              Expanded(
                child: Material(
                  color: _teamId == t.teamId ? p.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() {
                      _teamId = t.teamId;
                      _playerId = null;
                      _relatedId = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _teamId == t.teamId
                                ? _teamColor(t, p)
                                : p.line,
                            width: _teamId == t.teamId ? 1.6 : 1),
                      ),
                      child: Row(children: [
                        Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                              color: _teamColor(t, p),
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
              if (t != g.teams.last) const SizedBox(width: 8),
            ],
          ]),
          const SizedBox(height: 14),
          Text('PLAYER',
              style: TextStyle(
                  color: p.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0)),
          const SizedBox(height: 6),
          if (onField.isEmpty)
            Text('No players on the pitch for this team.',
                style: TextStyle(color: p.muted, fontSize: 12.5))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final x in onField)
                playerChip(x.playerId, x.displayName, x.jersey,
                    selected: _playerId == x.playerId,
                    onTap: () => setState(() {
                          _playerId = x.playerId;
                          if (_relatedId == x.playerId) _relatedId = null;
                        })),
            ]),
          if (wantsRelated) ...[
            const SizedBox(height: 14),
            Text(
              needsRelated
                  ? 'SECOND PLAYER'
                  : 'ASSIST (OPTIONAL)',
              style: TextStyle(
                  color: p.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final x in onField)
                if (x.playerId != _playerId)
                  playerChip(x.playerId, x.displayName, x.jersey,
                      selected: _relatedId == x.playerId,
                      onTap: () => setState(() => _relatedId =
                          _relatedId == x.playerId ? null : x.playerId)),
            ]),
          ],
          const SizedBox(height: 18),
          SpButton(
            label: 'Record ${def.label.toLowerCase()}',
            expand: true,
            onTap: canRecord
                ? () => Navigator.pop(context, (
                      teamId: _teamId,
                      playerId: _playerId!,
                      relatedId: _relatedId,
                    ))
                : null,
          ),
        ],
      ),
    );
  }
}
