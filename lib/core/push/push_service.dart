import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/dio_client.dart';

/// Push notifications (FCM), fully guarded: until Firebase is configured for
/// this app (run `flutterfire configure`, which drops google-services.json /
/// GoogleService-Info.plist), [init] fails quietly and the app runs without
/// push. Once configured it just works — no code changes needed.
///
/// Flow: init Firebase → ask permission → register the device token with the
/// backend (POST /api/mobile/push-token) → re-register on token refresh.
/// Background/terminated pushes are shown by the OS; foreground pushes just
/// trigger the caller's [onMessage] hook (e.g. refresh the notifications
/// feed).
class PushService {
  PushService(this._dio);
  final Dio _dio;

  bool _initialized = false;
  String? _token;

  Future<void> init({void Function()? onMessage}) async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // Not configured yet — normal until `flutterfire configure` is run.
      if (kDebugMode) {
        debugPrint('[push] Firebase not configured, push disabled: $e');
      }
      return;
    }
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }
      _token = await messaging.getToken();
      if (_token != null) await _register(_token!);
      messaging.onTokenRefresh.listen((t) {
        _token = t;
        _register(t);
      });
      FirebaseMessaging.onMessage.listen((_) => onMessage?.call());
      _initialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[push] init failed: $e');
    }
  }

  Future<void> _register(String token) async {
    try {
      await _dio.post('/api/mobile/push-token', data: {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[push] register failed: $e');
    }
  }

  /// Best-effort: forget this device on sign-out.
  Future<void> unregister() async {
    final t = _token;
    if (t == null) return;
    try {
      await _dio.delete('/api/mobile/push-token', data: {'token': t});
    } catch (_) {
      /* signing out anyway */
    }
  }
}

final pushServiceProvider =
    Provider<PushService>((ref) => PushService(ref.watch(dioProvider)));
