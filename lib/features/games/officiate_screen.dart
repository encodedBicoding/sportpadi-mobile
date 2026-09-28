import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/data/games/game_models.dart';
import 'package:sportpadi_mobile/data/games/games_repository.dart';
import 'package:sportpadi_mobile/data/games/live_game_controller.dart';

/// Officiant mode — one job, one screen.
///
/// The timekeeper's view of a game: a huge clock and ONLY the controls the
/// category needs (kick-off, pause / stop clock, stoppage for soccer, end and
/// start periods, draw deciders, full time). Stats are the scorer's job, so
/// none of that is here.
///
/// It locks itself in: the screen stays awake, system bars are hidden,
/// portrait only, back is swallowed, and on Android the app is pinned
/// (screen pinning / lock task) so Home and Recents can't pull the officiant
/// away. iOS can't pin from an app — the screen points at Guided Access.
/// Leaving is deliberate: press and hold Exit.
class OfficiateScreen extends ConsumerStatefulWidget {
  const OfficiateScreen({super.key, required this.gameId});
  final String gameId;

  @override
  ConsumerState<OfficiateScreen> createState() => _OfficiateScreenState();
}

const _lockChannel = MethodChannel('sportpadi/officiate');

class _OfficiateScreenState extends ConsumerState<OfficiateScreen>
    with WidgetsBindingObserver {
  Timer? _tick;
  bool _busy = false;
  bool _pinned = false;
  bool _leaving = false;
  int? _autoPhase;
  bool _autoDone = false;

  static const _bg = Color(0xFF0A0A0A);
  static const _white = Colors.white;
  static const _dim = Color(0x99FFFFFF);
  static const _faint = Color(0x1AFFFFFF);
  static const _green = Color(0xFF22C55E);
  static const _amber = Color(0xFFFBBF24);
  static const _red = Color(0xFFEF4444);

  GamesRepository get _repo => ref.read(gamesRepositoryProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
    _lockIn();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _release();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back (a call, a notification pulled down): lock straight back in.
    if (state == AppLifecycleState.resumed && !_leaving) _applyChrome();
  }

  Future<void> _applyChrome() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp]);
  }

  Future<void> _lockIn() async {
    await _applyChrome();
    if (Platform.isAndroid) {
      try {
        final ok = await _lockChannel.invokeMethod<bool>('lockIn');
        if (mounted) setState(() => _pinned = ok == true);
      } catch (_) {
        // Pinning is best-effort; the rest of the lock-in still applies.
      }
    }
  }

  Future<void> _release() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const []);
    if (Platform.isAndroid) {
      try {
        await _lockChannel.invokeMethod('release');
      } catch (_) {}
    }
  }

  Future<void> _exit() async {
    _leaving = true;
    HapticFeedback.heavyImpact();
    await _release();
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/games/${widget.gameId}');
    }
  }

  Future<void> _run(Future<void> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      await op();
      await ref.read(liveGameProvider(widget.gameId).notifier).refresh();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  DateTime _now(GameDetail g) {
    final offset = (g.serverNow != null && g.fetchedAt != null)
        ? g.serverNow!.difference(g.fetchedAt!)
        : Duration.zero;
    return DateTime.now().add(offset);
  }

  // Auto-end at full time — the same rule as the web game page, so a
  // timekeeper alone in officiant mode still ends halves / the match on time.
  void _autoEnd(GameDetail g) {
    if (!g.isLive || !g.canTime || _busy) return;
    final now = _now(g);
    final lc = g.lifecycle;
    if (lc != null) {
      final ph = lc.current;
      if (ph == null ||
          !ph.isTimed ||
          ph.status != 'live' ||
          ph.startedAt == null ||
          ph.timer.pausedAt != null) {
        return;
      }
      final el = now.difference(ph.startedAt!).inMilliseconds - ph.timer.pausedMs;
      if (el >= (ph.nominalMinutes! + ph.timer.stoppageMin) * 60000 &&
          _autoPhase != lc.currentPhaseIndex) {
        _autoPhase = lc.currentPhaseIndex;
        HapticFeedback.vibrate();
        _run(() => _repo.phase(widget.gameId, 'endPhase'));
      }
      return;
    }
    final d = g.durationMinutes;
    if (d == null || g.startedAt == null || g.timer.pausedAt != null || _autoDone) {
      return;
    }
    final el = now.difference(g.startedAt!).inMilliseconds - g.timer.pausedMs;
    if (el >= (d + g.timer.stoppageMin) * 60000) {
      _autoDone = true;
      HapticFeedback.vibrate();
      _run(() => _repo.complete(widget.gameId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(liveGameProvider(widget.gameId));
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _snack('Officiant mode is on — press and hold Exit to leave.');
      },
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: game.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: _white)),
            error: (e, _) => _message(
              'Couldn\'t load the game',
              '$e',
            ),
            data: (g) {
              if (!g.canTime) {
                return _message(
                  'Officiant mode is for the timekeeper',
                  g.officiating.role == 'scorer'
                      ? 'You\'re the scorer on this game — record the stats from the game page.'
                      : 'Only group admins and this game\'s timekeeper can run the clock.',
                );
              }
              WidgetsBinding.instance.addPostFrameCallback((_) => _autoEnd(g));
              return _body(g);
            },
          ),
        ),
      ),
    );
  }

  Widget _message(String title, String body) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline_rounded, color: _dim, size: 36),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _dim, fontSize: 13.5)),
            const SizedBox(height: 20),
            _BigButton(
              label: 'Back to the game',
              color: _white,
              textColor: _bg,
              height: 52,
              onTap: _exit,
            ),
          ],
        ),
      );

  Widget _body(GameDetail g) {
    final prof = g.profile;
    final lc = g.lifecycle;
    final now = _now(g);
    final ph = lc?.current;
    final inTimed = ph != null && ph.isTimed && ph.status == 'live';
    final next = lc?.nextTimed;
    final over = g.status == 'completed' || g.status == 'abandoned';

    // -- the clock ----------------------------------------------------------
    var clockMs = 0;
    var paused = false;
    var stoppage = 0;
    int? targetMs;
    var label = '';
    if (lc != null && ph != null) {
      label = ph.label;
      if (ph.isTimed) {
        paused = ph.timer.pausedAt != null;
        stoppage = ph.timer.stoppageMin;
        final s = ph.startedAt;
        if (s != null) {
          final e = ph.status == 'ended' && ph.endedAt != null
              ? ph.endedAt!
              : (ph.timer.pausedAt ?? now);
          final el = e.difference(s).inMilliseconds - ph.timer.pausedMs;
          clockMs = ph.nominalOffset * 60000 + (el < 0 ? 0 : el);
        } else {
          clockMs = ph.nominalOffset * 60000;
        }
        targetMs = (ph.nominalOffset + ph.nominalMinutes!) * 60000;
      }
    } else if (g.startedAt != null) {
      paused = g.timer.pausedAt != null;
      stoppage = g.timer.stoppageMin;
      final e = g.timer.pausedAt ??
          (g.isLive ? now : (g.endedAt ?? now));
      final el = e.difference(g.startedAt!).inMilliseconds - g.timer.pausedMs;
      clockMs = el < 0 ? 0 : el;
      if (g.durationMinutes != null) targetMs = g.durationMinutes! * 60000;
    }
    final overTime = targetMs != null && clockMs > targetMs && !paused;

    // -- what the timekeeper can do now --------------------------------------
    final clockRunning = lc != null ? inTimed : g.isLive;
    final regulationDone = lc != null && !inTimed && next == null;
    final etAdded = lc?.hasExtraPhases ?? false;
    final pensAdded = lc?.hasShootout ?? false;
    final draws = lc?.drawResolutions ?? const <String>[];
    final awaitingDraw = g.isLive &&
        regulationDone &&
        g.isDrawn &&
        !pensAdded &&
        ((draws.contains('extra_time') && !etAdded) ||
            draws.contains('penalties'));
    final showFullTime =
        lc != null ? (g.isLive && regulationDone && !awaitingDraw) : g.isLive;

    final a = g.teams.isNotEmpty ? g.teams[0] : null;
    final b = g.teams.length > 1 ? g.teams[1] : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // top bar
          Row(children: [
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _faint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '⏱️ OFFICIANT MODE${g.categoryName != null ? ' · ${g.categoryName!.toUpperCase()}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6),
                ),
              ),
            ),
            const SizedBox(width: 10),
            _HoldButton(
              label: 'Hold to exit',
              holdingLabel: 'Keep holding…',
              onConfirmed: _exit,
            ),
          ]),
          if (Platform.isIOS && !over) ...[
            const SizedBox(height: 6),
            const Text(
              'Tip: triple-click the side button for Guided Access to keep SportPadi locked on screen.',
              style: TextStyle(color: _dim, fontSize: 11),
            ),
          ] else if (Platform.isAndroid && _pinned && !over) ...[
            const SizedBox(height: 6),
            const Text(
              'SportPadi is pinned — Home and Recents are off until you exit.',
              style: TextStyle(color: _dim, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),

          // score strip (read-only)
          if (a != null && b != null && g.teams.length == 2)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0x0DFFFFFF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _white, fontWeight: FontWeight.w700)),
                ),
                Text('${a.score}–${b.score}',
                    style: const TextStyle(
                        color: _white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        fontFeatures: [FontFeature.tabularFigures()])),
                Expanded(
                  child: Text(b.name,
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: _white, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),

          // the clock
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  (g.isScheduled
                          ? 'Ready'
                          : over
                              ? 'Full time'
                              : label.isNotEmpty
                                  ? label
                                  : prof.clock == 'elapsed'
                                      ? 'Elapsed'
                                      : 'Match time')
                      .toUpperCase(),
                  style: const TextStyle(
                      color: _dim,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.4),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _fmt(clockMs),
                    style: TextStyle(
                      color: paused
                          ? const Color(0x66FFFFFF)
                          : overTime
                              ? _amber
                              : _white,
                      fontSize: 120,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (targetMs != null && !g.isScheduled)
                    Text('of ${_fmt(targetMs)}',
                        style: const TextStyle(color: _dim, fontSize: 14)),
                  if (stoppage > 0) ...[
                    const SizedBox(width: 8),
                    _Pill("+$stoppage'", color: _amber),
                  ],
                  if (paused) ...[
                    const SizedBox(width: 8),
                    _Pill(
                        prof.pauseLabel == 'Stop clock'
                            ? 'Clock stopped'
                            : 'Paused',
                        color: _white),
                  ],
                ]),
                if (pensAdded && g.isLive) ...[
                  const SizedBox(height: 10),
                  const Text('Penalty shootout — the scorer records each kick.',
                      style: TextStyle(color: _dim, fontSize: 13)),
                ],
              ],
            ),
          ),

          // controls
          if (g.isScheduled)
            _BigButton(
              label: 'Kick off',
              icon: Icons.play_arrow_rounded,
              color: _green,
              textColor: _bg,
              height: 84,
              fontSize: 26,
              onTap: _busy ? null : () => _run(() => _repo.start(widget.gameId)),
            ),
          if (clockRunning && prof.has('pause')) ...[
            _BigButton(
              label: paused ? prof.resumeLabel : prof.pauseLabel,
              icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: paused ? _green : _white,
              textColor: _bg,
              height: 96,
              fontSize: 30,
              onTap: _busy
                  ? null
                  : () => _run(() => _repo.timer(
                      widget.gameId, paused ? 'resume' : 'pause')),
            ),
            const SizedBox(height: 12),
          ],
          if (clockRunning && prof.has('stoppage') && prof.addsTime) ...[
            const Text('ADD STOPPAGE',
                style: TextStyle(
                    color: _dim,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const SizedBox(height: 6),
            Row(children: [
              for (final m in prof.stoppagePresets) ...[
                if (m != prof.stoppagePresets.first) const SizedBox(width: 8),
                Expanded(
                  child: _BigButton(
                    label: "+$m'",
                    color: const Color(0x26FBBF24),
                    textColor: _amber,
                    height: 56,
                    fontSize: 18,
                    onTap: _busy
                        ? null
                        : () => _run(() => _repo.timer(
                            widget.gameId, 'stoppage',
                            minutes: m)),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 12),
          ],
          if (lc != null && g.isLive) ...[
            if (inTimed && prof.has('periods')) ...[
              _BigButton(
                label: 'End ${ph.label}',
                icon: Icons.flag_rounded,
                color: _faint,
                textColor: _white,
                height: 56,
                onTap: _busy
                    ? null
                    : () => _run(() => _repo.phase(widget.gameId, 'endPhase')),
              ),
              const SizedBox(height: 12),
            ],
            if (!inTimed && next != null) ...[
              _BigButton(
                label: 'Start ${next.label}',
                icon: Icons.play_arrow_rounded,
                color: _green,
                textColor: _bg,
                height: 64,
                fontSize: 18,
                onTap: _busy
                    ? null
                    : () =>
                        _run(() => _repo.phase(widget.gameId, 'startNext')),
              ),
              const SizedBox(height: 12),
            ],
            if (awaitingDraw) ...[
              Row(children: [
                if (draws.contains('extra_time') && !etAdded)
                  Expanded(
                    child: _BigButton(
                      label: 'Extra time',
                      icon: Icons.timer_outlined,
                      color: _white,
                      textColor: _bg,
                      height: 56,
                      onTap: _busy
                          ? null
                          : () => _run(
                              () => _repo.phase(widget.gameId, 'extraTime')),
                    ),
                  ),
                if (draws.contains('extra_time') &&
                    !etAdded &&
                    draws.contains('penalties'))
                  const SizedBox(width: 8),
                if (draws.contains('penalties'))
                  Expanded(
                    child: _BigButton(
                      label: 'Penalties',
                      icon: Icons.sports_soccer_rounded,
                      color: _faint,
                      textColor: _white,
                      height: 56,
                      onTap: _busy
                          ? null
                          : () => _run(
                              () => _repo.phase(widget.gameId, 'penalties')),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              _HoldButton(
                label: 'Hold to end as a draw',
                holdingLabel: 'Keep holding…',
                expand: true,
                onConfirmed: () => _run(() => _repo.complete(widget.gameId)),
              ),
              const SizedBox(height: 12),
            ],
          ],
          if (showFullTime && prof.has('complete'))
            _HoldButton(
              label: 'Hold for full time',
              holdingLabel: 'Keep holding…',
              expand: true,
              color: _red,
              onConfirmed: () => _run(() => _repo.complete(widget.gameId)),
            ),
          if (over)
            _BigButton(
              label: 'Done — back to the game',
              color: _white,
              textColor: _bg,
              height: 56,
              onTap: _exit,
            ),
          if (!over) ...[
            const SizedBox(height: 8),
            Text(
              g.canScore
                  ? 'Stats are recorded from the game page — or hand them to a scorer.'
                  : 'The scorer records the stats — you just keep time.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  static String _fmt(int ms) {
    final total = ms ~/ 1000;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(40),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w800)),
      );
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
    this.icon,
    this.height = 56,
    this.fontSize = 16,
  });
  final String label;
  final IconData? icon;
  final Color color;
  final Color textColor;
  final double height;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: textColor, size: fontSize + 6),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: textColor,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A button that only fires after a deliberate press-and-hold (~1.2 s), with
/// a fill that shows the hold progressing. Used for Exit and Full time.
class _HoldButton extends StatefulWidget {
  const _HoldButton({
    required this.label,
    required this.holdingLabel,
    required this.onConfirmed,
    this.expand = false,
    this.color = const Color(0x33FFFFFF),
  });
  final String label;
  final String holdingLabel;
  final VoidCallback onConfirmed;
  final bool expand;
  final Color color;

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _c.reset();
        widget.onConfirmed();
      }
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.expand ? 56.0 : 34.0;
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.selectionClick();
        _c.forward();
      },
      onTapUp: (_) => _c.reverse(),
      onTapCancel: () => _c.reverse(),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => ClipRRect(
          borderRadius: BorderRadius.circular(widget.expand ? 22 : 999),
          child: SizedBox(
            height: height,
            width: widget.expand ? double.infinity : null,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(child: ColoredBox(color: widget.color)),
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _c.value,
                    child: const ColoredBox(color: Color(0x40FFFFFF)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    _c.value > 0 ? widget.holdingLabel : widget.label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.expand ? 16 : 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
