// First-party usage analytics for the owner console — the app's half
// (web: components/analytics/UsageTracker.tsx; server: packages/api/src/
// analytics/ingest.ts; docs/design/2026-redesign.md row 174).
//
//  • device   — a random id kept in secure storage ([DeviceId]); every API
//               request carries it as `x-sp-device` (dio_client.dart), so the
//               sign-up request says which install made the account.
//  • session  — from launch / resume; a new one after 30 minutes away.
//  • time     — foreground time only.
//  • screens  — each router location is reported when it's left, with its
//               foreground time, so the owner sees the path through the app.
//
// Batches go to POST /api/t every 30 s while open and when the app goes to
// the background. Locations are sent without query strings. Never throws.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/analytics/device_id.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';


class _Page {
  _Page(this.path) : at = DateTime.now();
  final String path;
  DateTime at;
  int ms = 0;
}

class UsageTracker with WidgetsBindingObserver {
  UsageTracker(this._dio);
  final Dio _dio;

  static const _sessionGap = Duration(minutes: 30);
  static const _flushEvery = Duration(seconds: 30);

  bool _started = false;
  String _sessionId = uuidV4();
  DateTime _sessionStart = DateTime.now();
  DateTime? _backgroundSince;
  DateTime? _foregroundSince = DateTime.now();
  int _activeMs = 0;
  _Page? _page;
  final List<Map<String, Object?>> _queue = [];
  Timer? _timer;

  /// Start once (from the router provider): lifecycle + periodic flush.
  void start() {
    if (_started) return;
    _started = true;
    unawaited(DeviceId.load());
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_flushEvery, (_) => _flush());
  }

  /// Foreground time since the last call, added to the session and page.
  void _accrue() {
    final since = _foregroundSince;
    if (since == null) return;
    final now = DateTime.now();
    final ms = now.difference(since).inMilliseconds.clamp(0, 15 * 60 * 1000);
    _foregroundSince = now;
    _activeMs += ms;
    _page?.ms += ms;
  }

  /// A new router location: close the screen we're leaving and open the next.
  void onRoute(String location) {
    final path = location.split('?').first.split('#').first;
    if (path.isEmpty || path == _page?.path) return;
    _accrue();
    _closePage();
    _page = _Page(path);
  }

  void _closePage() {
    final p = _page;
    if (p == null) return;
    _queue.add({
      'kind': 'page',
      'path': p.path,
      'at': p.at.millisecondsSinceEpoch,
      'ms': p.ms,
    });
    if (_queue.length > 60) _queue.removeRange(0, _queue.length - 60);
    _page = null;
  }

  /// A named action worth counting (e.g. 'rsvp', 'share').
  void event(String name, [Map<String, Object?>? props]) {
    _queue.add({
      'kind': 'event',
      'name': name,
      'path': _page?.path ?? '/',
      'at': DateTime.now().millisecondsSinceEpoch,
      if (props != null) 'props': props,
    });
  }

  Future<void> _flush() async {
    _accrue();
    if (_queue.isEmpty && _activeMs < 1000) return;
    final did = DeviceId.value ?? await DeviceId.load();
    final events = List<Map<String, Object?>>.from(_queue);
    _queue.clear();
    final active = _activeMs;
    _activeMs = 0;
    try {
      await _dio.post('/api/t', data: {
        'deviceId': did,
        'sessionId': _sessionId,
        'startedAt': _sessionStart.millisecondsSinceEpoch,
        'activeMs': active,
        'current': _page?.path,
        'tz': DateTime.now().timeZoneName,
        'lang': WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
        'events': events,
      });
    } catch (_) {
      // Offline: drop it — analytics never retries into a user's data plan.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final away = _backgroundSince;
        _backgroundSince = null;
        _foregroundSince = DateTime.now();
        if (away != null && DateTime.now().difference(away) > _sessionGap) {
          // A new visit: fresh session, and the screen on show starts again.
          _sessionId = uuidV4();
          _sessionStart = DateTime.now();
          _page?.at = DateTime.now();
          _page?.ms = 0;
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (_backgroundSince != null) return;
        _accrue();
        _foregroundSince = null;
        _backgroundSince = DateTime.now();
        // Leaving: report the screen on show (it restarts on resume).
        final current = _page?.path;
        _closePage();
        if (current != null) {
          _page = _Page(current);
        }
        unawaited(_flush());
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

final usageTrackerProvider = Provider<UsageTracker>((ref) {
  final t = UsageTracker(ref.watch(dioProvider));
  ref.onDispose(t.dispose);
  return t;
});
