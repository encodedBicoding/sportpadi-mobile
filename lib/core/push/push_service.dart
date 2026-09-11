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
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }
      // iOS: FCM can't mint a token until APNs has issued one. Registration is
      // asynchronous after requestPermission, so poll briefly — without this,
      // getToken() throws apns-token-not-set and push silently never enables.
      if (Platform.isIOS) {
        String? apns = await messaging.getAPNSToken();
        for (var i = 0; apns == null && i < 12; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          apns = await messaging.getAPNSToken();
        }
        if (apns == null) {
          if (kDebugMode) {
            // NB: this is the DEVICE token Apple issues at runtime — nothing
            // to do with the APNs .p8 key uploaded to Firebase (that is a
            // server-side credential FCM uses to talk to Apple; it cannot
            // affect this call). Null here means the device never registered:
            //   • running on the iOS Simulator (no real APNs registration), or
            //   • the build's aps-environment doesn't match its provisioning
            //     profile (debug builds need "development"), or
            //   • Push Notifications isn't enabled on the App ID, or
            //   • no network / notification permission was denied.
            debugPrint('[push] APNs device token is null — push disabled. '
                'Run on a REAL device, and check Signing & Capabilities has '
                'Push Notifications enabled for this build configuration.');
          }
          return;
        }
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
