import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/games/game_models.dart';

/// Team timeouts (basketball + volleyball) and the basketball shot clock.
/// Web twin: components/games/timeouts.tsx.

Color _teamColor(String? hex) {
  if (hex == null || hex.isEmpty) return const Color(0xFF888888);
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFF888888);
}

typedef TimeoutAction = void Function(String teamId, String action);

/// Timeouts left per team with a "Timeout" button each, and — while one runs
/// — the countdown with End / Undo. [onAction] null = read-only.
class TimeoutBar extends StatefulWidget {
  const TimeoutBar({super.key, required this.game, this.onAction, this.busy = false, this.dark = false});
  final GameDetail game;
  final TimeoutAction? onAction;
  final bool busy;
  final bool dark;

  @override
  State<TimeoutBar> createState() => _TimeoutBarState();
}

class _TimeoutBarState extends State<TimeoutBar> {
  Timer? _tick;

  ActiveTimeout? get _active =>
      widget.game.basketball?.activeTimeout ?? widget.game.volleyball?.activeTimeout;

  void _sync() {
    final on = _active != null;
    if (on && _tick == null) {
      _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) setState(() {});
      });
    } else if (!on && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant TimeoutBar old) {
    super.didUpdateWidget(old);
    _sync();
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
    final bb = g.basketball;
    final vb = g.volleyball;
    if ((bb == null && vb == null) || !g.isLive || g.teams.length < 2) return const SizedBox.shrink();
    final left = bb?.timeoutsLeft ?? vb?.timeoutsLeft ?? const <String, int>{};
    final period = bb != null ? bb.timeoutPeriodLabel : 'Set ${vb!.currentSet}';
    final active = _active;
    final muted = widget.dark ? p.heroMuted : p.muted;
    final ink = widget.dark ? p.onHero : p.ink;
    var secs = 0;
    if (active != null) {
      final end = active.at.add(Duration(seconds: active.seconds));
      secs = (end.difference(g.serverClock).inMilliseconds / 1000).ceil();
      if (secs < 0) secs = 0;
      if (secs > active.seconds) secs = active.seconds;
    }
    final activeTeam = active == null ? null : g.teams.where((t) => t.teamId == active.teamId).firstOrNull;
    final onAction = widget.onAction;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.dark ? p.onHero.withAlpha(15) : p.surface2,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (active != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: secs == 0 ? p.liveTint : p.orangeTint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(Icons.back_hand_rounded, size: 18, color: secs == 0 ? p.danger : p.orangeInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Timeout · ${activeTeam?.name ?? 'Team'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: secs == 0 ? p.danger : p.orangeInk, fontSize: 13, fontWeight: FontWeight.w800)),
                ),
                Text(secs > 0 ? '0:${secs.toString().padLeft(2, '0')}' : 'Time',
                    style: TextStyle(
                      color: secs == 0 ? p.danger : p.orangeInk,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ]),
              if (onAction != null) ...[
                const SizedBox(height: 8),
                Row(children: [
                  FilledButton(
                    onPressed: widget.busy ? null : () => onAction(active.teamId, 'end'),
                    style: FilledButton.styleFrom(backgroundColor: p.ink, foregroundColor: p.bg),
                    child: const Text('End timeout'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: widget.busy ? null : () => onAction(active.teamId, 'undo'),
                    icon: const Icon(Icons.undo_rounded, size: 16),
                    label: const Text('Undo'),
                  ),
                ]),
                if (bb != null)
                  Text('The clock is stopped. Start it again when play resumes.',
                      style: TextStyle(color: p.muted, fontSize: 11)),
              ],
            ]),
          ),
          const SizedBox(height: 10),
        ],
        Row(children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: Builder(builder: (context) {
                final t = g.teams[i];
                final n = left[t.teamId] ?? 0;
                return Row(children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: _teamColor(t.color), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('TIMEOUTS${period != null ? ' · ${period.toUpperCase()}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 9.5, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      n == 0
                          ? Text('None left', style: TextStyle(color: muted, fontSize: 12))
                          : Row(children: [
                              for (var k = 0; k < n; k++)
                                Container(
                                  width: 14,
                                  height: 7,
                                  margin: const EdgeInsets.only(right: 3),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFFFB57D), borderRadius: BorderRadius.circular(99)),
                                ),
                            ]),
                    ]),
                  ),
                  if (onAction != null)
                    TextButton(
                      onPressed: widget.busy || n == 0 || active != null
                          ? null
                          : () => onAction(t.teamId, 'call'),
                      style: TextButton.styleFrom(
                        foregroundColor: ink,
                        backgroundColor: widget.dark ? p.onHero.withAlpha(25) : p.surface,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('Timeout', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                ]);
              }),
            ),
          ],
        ]),
      ]),
    );
  }
}

/// The basketball shot clock: big seconds (tenths under 5), buzzes at 0, and
/// the two resets for the timekeeper ([onReset]; `true` = the short reset).
class ShotClockPanel extends StatefulWidget {
  const ShotClockPanel({
    super.key,
    required this.game,
    this.onReset,
    this.busy = false,
    this.dark = false,
    this.large = false,
  });
  final GameDetail game;
  final void Function(bool short)? onReset;
  final bool busy;
  final bool dark;
  final bool large;

  @override
  State<ShotClockPanel> createState() => _ShotClockPanelState();
}

class _ShotClockPanelState extends State<ShotClockPanel> {
  Timer? _tick;
  bool _armed = false;

  ShotClockState? get _sc => widget.game.basketball?.shotClock;

  void _sync() {
    final on = (_sc?.running ?? false) && widget.game.isLive;
    if (on && _tick == null) {
      _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() {});
      });
    } else if (!on && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ShotClockPanel old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _buzz() {
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 250), HapticFeedback.heavyImpact);
    SystemSound.play(SystemSoundType.alert);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = widget.game;
    final sc = _sc;
    final bb = g.basketball;
    if (sc == null || bb == null || !g.isLive) return const SizedBox.shrink();
    final ms = sc.leftMs(g.serverClock);
    final expired = ms <= 0;
    // Buzz once when it runs out on the timekeeper's screen.
    if (sc.running && ms > 0) _armed = true;
    if (expired && _armed) {
      _armed = false;
      if (widget.onReset != null) WidgetsBinding.instance.addPostFrameCallback((_) => _buzz());
    }
    final secs = ms / 1000;
    final label = secs > 0 && secs < 5 ? secs.toStringAsFixed(1) : '${secs.ceil()}';
    final ink = widget.dark ? p.onHero : p.ink;
    final muted = widget.dark ? p.heroMuted : p.muted;

    Widget reset(String text, bool short, {bool primary = false}) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: FilledButton.icon(
            onPressed: widget.busy ? null : () => widget.onReset!(short),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(
              backgroundColor: primary ? p.accentDeep : (widget.dark ? p.onHero.withAlpha(25) : p.surface),
              foregroundColor: primary ? Colors.white : ink,
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: expired ? p.liveTint : (widget.dark ? p.onHero.withAlpha(15) : p.surface2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                color: expired ? p.danger : (secs <= 5 ? const Color(0xFFFFB57D) : ink),
                fontSize: widget.large ? 48 : 30,
                fontWeight: FontWeight.w800,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
          const SizedBox(height: 4),
          Text('SHOT CLOCK${!sc.running && !expired ? ' · STOPPED' : ''}',
              style: TextStyle(
                  color: expired ? p.danger : muted, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
        ]),
        const Spacer(),
        if (widget.onReset != null) ...[
          reset('${bb.rules.shotClock}', false, primary: true),
          reset('${bb.rules.shotClockShort}', true),
        ],
      ]),
    );
  }
}
