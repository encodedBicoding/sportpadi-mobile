// Smartwatch officiant mode — the phone's half of pairing (Phase 1;
// docs/design/watch-officiant.md "Pairing", 2026-redesign.md row 177).
//
// The watch never signs in. The phone hands it everything it needs to call
// the API as this user — the bearer token, the API base URL, who they are —
// plus a hint of the match being officiated right now, over the platform's
// own pairing channel:
//   iOS      WatchConnectivity application context   (ios/Runner/WatchBridge.swift)
//   Android  Wear OS Data Layer item at /sportpadi/context (…/WatchBridge.kt)
//
// Both are "latest value wins" stores the watch can read whenever it wakes,
// so the phone just re-sends the whole context whenever anything changes:
// sign-in, sign-out, token refresh, app resume, opening / leaving officiant
// mode. Signed out = an empty context, which the watch shows as "Open
// SportPadi on your phone".
//
// The watch can also talk back (native → this class → the app):
//   needsContext   it woke without one — re-send now
//   openGame       the user tapped a match on the watch — open it here too
//
// No watch, no WatchConnectivity support, or an old OS: every call is a
// quiet no-op. Nothing here ever throws into the app.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/analytics/device_id.dart';
import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/storage/token_storage.dart';
import 'package:sportpadi_mobile/data/auth/auth_models.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';

const _channel = MethodChannel('sportpadi/watch');

/// Context version — bump when the keys change so a watch app built against
/// an older phone build can say "update the phone app" instead of guessing.
const kWatchContextVersion = 1;

class WatchBridge with WidgetsBindingObserver {
  WatchBridge(this._ref);
  final Ref _ref;

  bool _started = false;
  String? _currentGameId;
  Timer? _debounce;

  /// Asked once from the router provider; safe to call again.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_fromWatch);
    sync();
  }

  /// The match being officiated on this phone right now (null = none). The
  /// watch opens straight onto it.
  void setCurrentGame(String? gameId) {
    if (_currentGameId == gameId) return;
    _currentGameId = gameId;
    sync();
  }

  /// Re-send the whole context (debounced — several triggers fire together).
  void sync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => unawaited(_send()));
  }

  Future<void> _send() async {
    try {
      final session = _ref.read(authControllerProvider).valueOrNull;
      final user = session?.user;
      final token = user == null ? null : await _ref.read(tokenStorageProvider).read();
      final config = _ref.read(appConfigProvider);
      final ctx = <String, Object?>{
        'version': kWatchContextVersion,
        'apiBaseUrl': config.apiBaseUrl,
        'signedIn': token != null,
        if (token != null) 'token': token,
        if (user != null) 'userId': user.id,
        if (user != null) 'userName': user.name,
        'deviceId': DeviceId.value ?? await DeviceId.load(),
        'currentGameId': _currentGameId,
        'sentAt': DateTime.now().toUtc().toIso8601String(),
      };
      await _channel.invokeMethod<void>('updateContext', ctx);
    } on MissingPluginException {
      // No native bridge on this platform / build — nothing to pair with.
    } catch (e) {
      if (kDebugMode) debugPrint('[watch] context sync failed: $e');
    }
  }

  /// Messages from the watch, relayed by the native side.
  Future<dynamic> _fromWatch(MethodCall call) async {
    switch (call.method) {
      case 'needsContext':
        await _send();
        return true;
      case 'openGame':
        final gameId = call.arguments is Map ? '${(call.arguments as Map)['gameId'] ?? ''}' : '';
        if (gameId.isNotEmpty) _openGame?.call(gameId);
        return true;
      case 'reachability':
        // Informational (watch reachable / not). Nothing to do yet.
        return true;
      default:
        return null;
    }
  }

  /// Set by the router: how to open a match the watch tapped.
  void Function(String gameId)? _openGame;
  // ignore: avoid_setters_without_getters
  set onOpenGame(void Function(String gameId) fn) => _openGame = fn;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming to the front: the token may have been refreshed while away.
    if (state == AppLifecycleState.resumed) sync();
  }

  void dispose() {
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

final watchBridgeProvider = Provider<WatchBridge>((ref) {
  final b = WatchBridge(ref);
  // Whenever the session changes (sign-in, sign-out, token refresh), the
  // watch gets the new picture.
  ref.listen<AsyncValue<SessionState>>(authControllerProvider, (_, __) => b.sync());
  ref.onDispose(b.dispose);
  return b;
});
