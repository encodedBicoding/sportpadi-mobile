import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/data/games/games_repository.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Keeps a tournament's scores live.
///
/// Realtime path: one SSE ping stream per live game (the same feed the match
/// screen uses) — every goal, card, timer or phase change refetches the
/// tournament's match queries, so the cards track the scoresheet without the
/// user pulling to refresh. Safety nets, because a phone loses its stream all
/// the time: reconnect with backoff per game, and a 15s poll while anything is
/// live in case pings are missed entirely.
///
/// Renders nothing — drop it at the top of the tournament screen's list.
class LiveScoresSync extends ConsumerStatefulWidget {
  const LiveScoresSync({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<LiveScoresSync> createState() => _LiveScoresSyncState();
}

class _LiveScoresSyncState extends ConsumerState<LiveScoresSync> {
  final Map<String, StreamSubscription<void>> _subs = {};
  final Map<String, Timer> _reconnects = {};
  final Map<String, int> _backoff = {};
  Timer? _poll;
  bool _closed = false;

  @override
  void dispose() {
    _closed = true;
    for (final s in _subs.values) {
      s.cancel();
    }
    for (final t in _reconnects.values) {
      t.cancel();
    }
    _poll?.cancel();
    super.dispose();
  }

  /// Refetch everything a score touches: the match list, the friendly match,
  /// and the awards that are computed from them.
  void _refresh() {
    if (_closed) return;
    ref.invalidate(tournamentGamesProvider(widget.eventId));
    ref.invalidate(tournamentMatchProvider(widget.eventId));
    ref.invalidate(tournamentAwardsProvider(widget.eventId));
  }

  void _listen(String gameId) {
    _subs.remove(gameId)?.cancel();
    _subs[gameId] = ref
        .read(gamesRepositoryProvider)
        .pings(gameId)
        .listen(
          (_) {
            _backoff[gameId] = 2; // healthy stream — reset backoff
            _refresh();
          },
          onError: (_) => _scheduleReconnect(gameId),
          onDone: () => _scheduleReconnect(gameId),
          cancelOnError: true,
        );
  }

  void _scheduleReconnect(String gameId) {
    if (_closed || !_subs.containsKey(gameId)) return;
    _reconnects.remove(gameId)?.cancel();
    final wait = _backoff[gameId] ?? 2;
    _reconnects[gameId] = Timer(Duration(seconds: wait), () {
      if (_closed || !_subs.containsKey(gameId)) return;
      _backoff[gameId] = (wait * 2).clamp(2, 30);
      _listen(gameId);
    });
  }

  /// Match the open streams to the games that are live right now.
  void _sync(Set<String> live) {
    if (_closed) return;
    for (final id in _subs.keys.toList()) {
      if (!live.contains(id)) {
        _subs.remove(id)?.cancel();
        _reconnects.remove(id)?.cancel();
        _backoff.remove(id);
      }
    }
    for (final id in live) {
      if (!_subs.containsKey(id)) {
        _backoff[id] = 2;
        _listen(id);
      }
    }
    if (live.isEmpty) {
      _poll?.cancel();
      _poll = null;
    } else {
      _poll ??= Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final games =
        ref.watch(tournamentGamesProvider(widget.eventId)).valueOrNull ??
            const <Map<String, dynamic>>[];
    final live = <String>{
      for (final g in games)
        if (parseStr(g['status']) == 'live' && parseStr(g['gameId']) != null)
          parseStr(g['gameId'])!,
    };
    // Streams are started off-frame: _refresh() invalidates providers, which
    // must not happen while this build is running.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync(live);
    });
    return const SizedBox.shrink();
  }
}

/// "45+2'" / "Half-time" — whatever the board says right now, from the
/// `clock` blob the tournament API returns for a live game.
String? matchClockText(dynamic clock) {
  if (clock is! Map) return null;
  final m = Map<String, dynamic>.from(clock);
  final minute = parseInt(m['minute']);
  if (minute == null) return parseStr(m['label']);
  final overflow = parseInt(m['overflow']) ?? 0;
  return overflow > 0 ? "$minute+$overflow'" : "$minute'";
}

/// Pulsing dot that marks a score as live.
class LivePip extends StatefulWidget {
  const LivePip({super.key, required this.color, this.size = 6});

  final Color color;
  final double size;

  @override
  State<LivePip> createState() => _LivePipState();
}

class _LivePipState extends State<LivePip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: (1 - _c.value).clamp(0.0, 1.0) * 0.7,
              child: Container(
                width: widget.size * (1 + _c.value),
                height: widget.size * (1 + _c.value),
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Container(
              width: widget.size,
              height: widget.size,
              decoration:
                  BoxDecoration(color: widget.color, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}
