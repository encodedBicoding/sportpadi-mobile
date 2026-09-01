import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/data/games/game_models.dart';
import 'package:sportpadi_mobile/data/games/games_repository.dart';

/// Live state for one game.
///
/// Realtime path: subscribe to the game's SSE ping stream and refetch on every
/// ping (the same invalidate-on-publish model the web client uses). Safety
/// nets: reconnect with backoff when the stream drops, and a slow poll (15s
/// live / 45s otherwise) in case pings are missed entirely.
class LiveGameController
    extends AutoDisposeFamilyAsyncNotifier<GameDetail, String> {
  StreamSubscription<void>? _sub;
  Timer? _poll;
  Timer? _reconnect;
  int _backoffSec = 2;
  bool _closed = false;

  @override
  Future<GameDetail> build(String arg) async {
    _closed = false;
    ref.onDispose(() {
      _closed = true;
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
    _sub = ref
        .read(gamesRepositoryProvider)
        .pings(arg)
        .listen(
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
    final every = Duration(seconds: game.isLive ? 15 : 45);
    _poll = Timer.periodic(every, (_) => refresh());
  }

  /// Refetch the game and publish the fresh state.
  Future<void> refresh() async {
    if (_closed) return;
    try {
      final game = await ref.read(gamesRepositoryProvider).game(arg);
      if (_closed) return;
      state = AsyncData(game);
      _schedulePoll(game);
    } catch (_) {
      // Keep showing the last good state; the poll/stream will retry.
    }
  }
}

final liveGameProvider = AsyncNotifierProvider.autoDispose
    .family<LiveGameController, GameDetail, String>(LiveGameController.new);
