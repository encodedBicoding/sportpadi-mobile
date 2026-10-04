import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/data/games/game_models.dart';
import 'package:sportpadi_mobile/data/games/games_repository.dart';

/// Live state for one game.
///
/// Realtime path: subscribe to the game's SSE ping stream and refetch on every
/// ping (the same invalidate-on-publish model the web client uses). Safety
/// nets: reconnect with backoff when the stream drops, a poll (8s live / 30s
/// otherwise) in case pings are missed, and a catch-up when the app returns
/// from the background.
///
/// Refetches are single-flight: pings come in bursts (a goal is an activity
/// + a lock change) and responses used to land out of order, so an older
/// score could overwrite a newer one. Now one request runs at a time, and a
/// ping (or pull) that arrives mid-request runs one more right after it, so
/// the last state shown is always the newest.
class LiveGameController
    extends AutoDisposeFamilyAsyncNotifier<GameDetail, String> {
  StreamSubscription<void>? _sub;
  Timer? _poll;
  Timer? _reconnect;
  int _backoffSec = 2;
  bool _closed = false;
  Future<void>? _inflight;
  bool _again = false;

  @override
  Future<GameDetail> build(String arg) async {
    _closed = false;
    _inflight = null;
    _again = false;
    // Back from the background: the stream was likely closed by the OS.
    final lifecycle = AppLifecycleListener(onResume: () {
      if (_closed) return;
      _listen();
      refresh();
    });
    ref.onDispose(() {
      _closed = true;
      lifecycle.dispose();
      _sub?.cancel();
      _poll?.cancel();
      _reconnect?.cancel();
    });
    final game = await ref.watch(gamesRepositoryProvider).game(arg);
    _listen();
    _schedulePoll(game);
    return game;
  }

  void _listen() {
    _sub?.cancel();
    _sub = ref.read(gamesRepositoryProvider).pings(arg).listen(
      (_) {
        _backoffSec = 2; // healthy stream — reset backoff
        refresh();
      },
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnect?.cancel();
    _reconnect = Timer(Duration(seconds: _backoffSec), () {
      if (_closed) return;
      _backoffSec = (_backoffSec * 2).clamp(2, 30);
      _listen();
    });
  }

  void _schedulePoll(GameDetail game) {
    _poll?.cancel();
    final every = Duration(seconds: game.isLive ? 8 : 30);
    _poll = Timer.periodic(every, (_) => refresh());
  }

  /// Refetch the game and publish the fresh state (single-flight; see the
  /// class doc). The returned future completes once the newest state is in.
  Future<void> refresh() {
    if (_closed) return Future.value();
    final running = _inflight;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _run();
    _inflight = run;
    return run;
  }

  Future<void> _run() async {
    try {
      do {
        _again = false;
        try {
          final game = await ref.read(gamesRepositoryProvider).game(arg);
          if (_closed) return;
          state = AsyncData(game);
          _schedulePoll(game);
        } catch (_) {
          // Keep showing the last good state; the poll/stream will retry.
        }
      } while (_again && !_closed);
    } finally {
      _inflight = null;
    }
  }
}

final liveGameProvider = AsyncNotifierProvider.autoDispose
    .family<LiveGameController, GameDetail, String>(LiveGameController.new);
