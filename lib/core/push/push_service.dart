import 'dart:io' show Platform;
import 'dart:math' show Random;

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/push/push_alert.dart';

/// Push notifications (FCM), fully guarded: until Firebase is configured for
/// this app (run `flutterfire configure`, which drops google-services.json /
/// GoogleService-Info.plist), everything here fails quietly and the app runs
/// without push.
///
/// Permission flow follows the platform guidelines (Apple HIG "Asking
/// permission" / Android 13 POST_NOTIFICATIONS):
///   • never fire the OS dialog cold on launch — [init] only *reads* the
///     current status and registers the token when already allowed;
///   • the UI shows a pre-permission explainer first (see
///     NotificationPermissionSheet) and only then calls [requestPermission],
///     which triggers the one-shot system dialog;
///   • a "Not now" is respected: re-ask after [reaskAfter], at most
///     [maxPrompts] times ([shouldPrompt] / [markPrompted]);
///   • once the OS says denied, the dialog can't be shown again — the UI
///     offers "Open settings" instead, and [onAppResumed] picks up the change
///     when the user comes back.
///
/// Registration: device token → POST /api/mobile/push-token, re-sent on token
/// refresh. Background/terminated pushes are shown by the OS; foreground
/// pushes just trigger the caller's onMessage hook.
class PushService {
  PushService(this._dio, this._storage);
  final Dio _dio;
  final FlutterSecureStorage _storage;

  static const reaskAfter = Duration(days: 7);
  static const maxPrompts = 3;
  static const _kLastPrompt = 'sp_push_prompt_last';
  static const _kPromptCount = 'sp_push_prompt_count';
  static const _kPromptUser = 'sp_push_prompt_user';

  bool _firebaseReady = false;
  bool _listening = false;

  /// System notifications for pushes that arrive while the app is OPEN.
  ///
  /// Neither platform shows anything for a foreground push on its own. iOS
  /// can be told to (setForegroundNotificationPresentationOptions); Android
  /// cannot — the message reaches Dart and nothing else — so on Android the
  /// notification is posted locally, on the same channel and with the same
  /// icon as background pushes, so the two are indistinguishable in the
  /// shade. The in-app banner stays as the fallback for when the system one
  /// can't be shown (notifications denied, or the plugin failed to start).
  static const _channelId = 'sportpadi_high';
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _localReady = false;

  /// The FCM token this device currently holds (for unregister and refresh).
  String? _token;

  /// The token the SERVER was last told about, in this sign-in. Cleared on
  /// sign-out so the next sign-in registers again — this used to be one field
  /// with [_token], which meant that after a sign-out (which deletes the row
  /// server-side) the next sign-in on the same device saw "same token as
  /// before" and never re-registered. That device then got nothing.
  String? _sentToken;
  void Function()? _onMessage;
  void Function(String? url)? _onOpened;
  void Function(PushAlert alert)? _onForeground;

  /// This device's FCM token, once minted (for the diagnostics screen).
  String? get token => _token;

  /// Whether the server has been told about this token in this sign-in.
  bool get registeredWithServer => _sentToken != null && _sentToken == _token;

  /// Last registration error, if the POST failed (401, offline…).
  String? _lastRegisterError;
  String? get lastRegisterError => _lastRegisterError;

  /// Ask the server to push to this account's devices — the whole chain,
  /// end to end, from a button.
  Future<({int devices, int ok, int failed, List<String> errors})>
      sendSelfTest() async {
    final res = await _dio.post('/api/mobile/push-token', data: {'action': 'test'});
    final m = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
    int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return (
      devices: n(m['devices']),
      ok: n(m['ok']),
      failed: n(m['failed']),
      // FCM's verdict per device ("404 UNREGISTERED", "403 SENDER_ID_MISMATCH"…)
      errors: [
        for (final e in (m['errors'] is List ? m['errors'] as List : const []))
          '$e'
      ],
    );
  }

  /// What the server holds for this account.
  Future<({bool serverEnabled, int devices})> serverStatus() async {
    final res = await _dio.get('/api/mobile/push-token');
    final m = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
    return (
      serverEnabled: m['serverEnabled'] == true,
      devices: m['devices'] is num ? (m['devices'] as num).toInt() : 0,
    );
  }

  /// Current OS-level status (null when Firebase isn't configured).
  AuthorizationStatus? _status;
  AuthorizationStatus? get status => _status;
  bool get enabled =>
      _status == AuthorizationStatus.authorized ||
      _status == AuthorizationStatus.provisional;

  Future<bool> _ensureFirebase() async {
    if (_firebaseReady) return true;
    try {
      // bootstrap() normally initialises Firebase before the first frame; only
      // fall back to initialising here if that didn't happen.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebaseReady = true;
    } catch (e) {
      // Not configured yet — normal until `flutterfire configure` is run.
      if (kDebugMode) {
        debugPrint('[push] Firebase not configured, push disabled: $e');
      }
    }
    return _firebaseReady;
  }

  /// Read the current permission state and, if already granted, register the
  /// device. Never shows the OS dialog.
  ///
  /// Registration is (re)sent every time this runs while a user is signed in:
  /// the server call is an idempotent upsert keyed on the token, so the cost
  /// is one small request, and the benefit is that the row for THIS user on
  /// THIS device is verified — created if missing, re-pointed if the device
  /// previously belonged to someone else — on every launch and resume.
  Future<AuthorizationStatus?> init({
    void Function()? onMessage,
    void Function(String? url)? onOpened,
    void Function(PushAlert alert)? onForeground,
  }) async {
    _onMessage = onMessage ?? _onMessage;
    _onOpened = onOpened ?? _onOpened;
    _onForeground = onForeground ?? _onForeground;
    if (!await _ensureFirebase()) return null;
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      _status = settings.authorizationStatus;
      if (enabled) await _registerDevice();
    } catch (e) {
      if (kDebugMode) debugPrint('[push] init failed: $e');
    }
    return _status;
  }

  /// Show the one-shot OS permission dialog (call only after the in-app
  /// explainer). Registers the device on success.
  Future<AuthorizationStatus?> requestPermission() async {
    if (!await _ensureFirebase()) return null;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _status = settings.authorizationStatus;
      if (enabled) await _registerDevice();
    } catch (e) {
      if (kDebugMode) debugPrint('[push] requestPermission failed: $e');
    }
    return _status;
  }

  /// Re-check after the app comes back from Settings; registers if the user
  /// turned notifications on there.
  Future<AuthorizationStatus?> onAppResumed() => init();

  /// Where this device stands for the signed-in user, in one word — what the
  /// shell needs right after sign-in to decide whether to ask for anything.
  ///
  ///   • `registered`  — permission granted and the server has this device.
  ///   • `ask`         — the OS has never been asked: show the explainer,
  ///                     then [requestPermission].
  ///   • `denied`      — the OS was told no; only Settings can change that.
  ///   • `unavailable` — no Firebase config, simulator, or no token yet.
  Future<PushReadiness> readiness() async {
    if (!_firebaseReady) return PushReadiness.unavailable;
    switch (_status) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return _sentToken != null
            ? PushReadiness.registered
            : PushReadiness.unavailable;
      case AuthorizationStatus.notDetermined:
        return PushReadiness.ask;
      case AuthorizationStatus.denied:
        return PushReadiness.denied;
      case null:
        return PushReadiness.unavailable;
    }
  }

  /// A different account on this device starts the soft-ask budget afresh:
  /// the throttle exists so one person isn't nagged, not so the next person
  /// who signs in here inherits the first one's "Not now".
  Future<void> noteSignedInUser(String userId) async {
    try {
      final prev = await _storage.read(key: _kPromptUser);
      if (prev == userId) return;
      await _storage.write(key: _kPromptUser, value: userId);
      await _storage.delete(key: _kLastPrompt);
      await _storage.delete(key: _kPromptCount);
    } catch (_) {
      /* best-effort */
    }
  }

  // ── in-app pre-prompt throttling ───────────────────────────────────────

  /// Whether to show the in-app explainer now: only while the device can't
  /// receive (never asked, or refused — the latter gets the Settings variant
  /// of the sheet), not more than [maxPrompts] times, and at least
  /// [reaskAfter] apart.
  Future<bool> shouldPrompt() async {
    if (_status != AuthorizationStatus.notDetermined &&
        _status != AuthorizationStatus.denied) {
      return false;
    }
    try {
      final count = int.tryParse(await _storage.read(key: _kPromptCount) ?? '') ?? 0;
      if (count >= maxPrompts) return false;
      final last = int.tryParse(await _storage.read(key: _kLastPrompt) ?? '');
      if (last == null) return true;
      final since = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(last));
      return since >= reaskAfter;
    } catch (_) {
      return true;
    }
  }

  Future<void> markPrompted() async {
    try {
      final count = int.tryParse(await _storage.read(key: _kPromptCount) ?? '') ?? 0;
      await _storage.write(
          key: _kLastPrompt,
          value: DateTime.now().millisecondsSinceEpoch.toString());
      await _storage.write(key: _kPromptCount, value: '${count + 1}');
    } catch (_) {
      /* best-effort */
    }
  }

  // ── foreground display ─────────────────────────────────────────────────

  Future<void> _initLocal() async {
    if (_localReady) return;
    try {
      const settings = InitializationSettings(
        // The status-bar icon must be a flat white-on-transparent drawable;
        // this is the one the manifest already gives FCM for background pushes.
        android: AndroidInitializationSettings('ic_stat_sportpadi'),
        // Permission is FCM's job (requestPermission above) — never ask twice.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _local.initialize(
        settings,
        // Tapped a locally-posted foreground notification → same routing
        // as a tapped push.
        // Every tap opens something: the destination, or (no url) the inbox.
        onDidReceiveNotificationResponse: (r) => _onOpened?.call(r.payload),
      );
      // A locally-posted notification tapped after the app was killed
      // relaunches it; the plugin reports that here, not via the callback.
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        _onOpened?.call(launch?.notificationResponse?.payload);
      }
      if (Platform.isAndroid) {
        // Idempotent; MainActivity creates it too. Must match the id the
        // server sends and the manifest's default channel.
        await _local
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(const AndroidNotificationChannel(
              _channelId,
              'SportPadi',
              description: 'Game reminders, team news and updates',
              importance: Importance.high,
            ));
      }
      _localReady = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[push] local notifications unavailable: $e');
    }
  }

  /// Post a foreground push as a system notification (Android). Returns
  /// false when it couldn't, so the caller can fall back to the in-app banner.
  Future<bool> _showLocal(String title, String? body, String? url) async {
    // A failed first init (e.g. Firebase came up before the plugin's
    // resources) is not permanent — try once more before giving up.
    if (!_localReady) await _initLocal();
    if (!_localReady) return false;
    try {
      await _local.show(
        // Unique per message so several can sit in the shade at once.
        DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'SportPadi',
            channelDescription: 'Game reminders, team news and updates',
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_sportpadi',
          ),
        ),
        payload: url,
      );
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[push] local show failed: $e');
      return false;
    }
  }

  // ── registration ───────────────────────────────────────────────────────

  Future<void> _registerDevice() async {
    final messaging = FirebaseMessaging.instance;
    await _initLocal();
    if (Platform.isIOS) {
      // iOS shows the system banner itself for a foreground push once told
      // to; without this call it shows nothing while the app is open.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
    // iOS: FCM can't mint a token until APNs has issued one. Registration is
    // asynchronous after permission is granted, so poll briefly — without
    // this, getToken() throws apns-token-not-set and push silently never
    // enables.
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
    final t = await messaging.getToken();
    if (t != null) {
      // Printed so it can be pasted straight into Firebase Console →
      // Messaging → "Send test message", which is the only reliable way to
      // prove delivery independently of our own backend.
      if (kDebugMode && t != _token) debugPrint('[push] FCM token: $t');
      _token = t;
      await _register(t);
    } else if (kDebugMode) {
      debugPrint('[push] FCM returned no token — device not registered.');
    }
    if (!_listening) {
      _listening = true;
      messaging.onTokenRefresh.listen((t) {
        _token = t;
        _register(t);
      });
      // Foreground message: the OS shows NOTHING for these, so refresh the
      // badge/feed AND hand the app an alert to render itself. Without this a
      // push that lands while someone is using the app is invisible.
      FirebaseMessaging.onMessage.listen((m) async {
        _onMessage?.call();
        final n = m.notification;
        final title = n?.title ?? (m.data['title'] as String?);
        final body = n?.body ?? (m.data['body'] as String?);
        if (kDebugMode) {
          debugPrint('[push] onMessage id=${m.messageId} '
              'notification=${n != null} title=$title data=${m.data} '
              'localReady=$_localReady');
        }
        if (title == null || title.isEmpty) return;
        final url = m.data['url'];
        final link = url is String && url.isNotEmpty ? url : null;
        // iOS: the OS is presenting it (see setForegroundNotification-
        // PresentationOptions), so nothing more to draw. Android: post it
        // ourselves; only if that fails does the in-app banner step in.
        if (Platform.isIOS) return;
        final shown = await _showLocal(title, body, link);
        if (kDebugMode) debugPrint('[push] foreground local shown=$shown');
        if (shown) return;
        _onForeground?.call(PushAlert(title: title, body: body, url: link));
      });
      // Tapped a push while the app was in the background → refresh + open
      // the notification's destination.
      FirebaseMessaging.onMessageOpenedApp.listen((m) {
        _onMessage?.call();
        final url = m.data['url'];
        _onOpened?.call(url is String ? url : null);
      });
      // Tapped a push that launched the app from a cold start.
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        final url = initial.data['url'];
        _onOpened?.call(url is String ? url : null);
      }
    }
  }

  /// A stable id for THIS install, minted once and kept in secure storage.
  /// It lets the server treat a new token from the same phone (reinstall,
  /// FCM rotation, the app-id fix) as a REPLACEMENT of that phone's old row,
  /// rather than a second device — while a second real device (a tablet)
  /// keeps its own row. It is random, not a hardware id: nothing about the
  /// device is disclosed, and it changes when the app is reinstalled.
  static const _kDeviceId = 'sp_push_device_id';
  String? _deviceId;
  Future<String> deviceId() async {
    if (_deviceId != null) return _deviceId!;
    try {
      final saved = await _storage.read(key: _kDeviceId);
      if (saved != null && saved.length >= 16) return _deviceId = saved;
    } catch (_) {}
    final r = Random.secure();
    final id = List.generate(16, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    try {
      await _storage.write(key: _kDeviceId, value: id);
    } catch (_) {}
    return _deviceId = id;
  }

  Future<void> _register(String token) async {
    try {
      await _dio.post('/api/mobile/push-token', data: {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'deviceId': await deviceId(),
      });
      _sentToken = token;
      _lastRegisterError = null;
      if (kDebugMode) debugPrint('[push] device registered with server');
    } catch (e) {
      // A 401 here is the common one: the shell mounted before the session
      // was in place. The next init() (resume, or the next launch) retries.
      _sentToken = null;
      _lastRegisterError = '$e';
      if (kDebugMode) debugPrint('[push] register failed: $e');
    }
  }

  /// Best-effort: forget this device on sign-out. The server row goes, and so
  /// does our memory of having sent it — the next sign-in must register
  /// afresh, whoever it is.
  Future<void> unregister() async {
    final t = _token;
    _sentToken = null;
    if (t == null) return;
    try {
      await _dio.delete('/api/mobile/push-token', data: {'token': t});
    } catch (_) {
      /* signing out anyway */
    }
  }
}

/// See [PushService.readiness].
enum PushReadiness { registered, ask, denied, unavailable }

final pushServiceProvider = Provider<PushService>(
    (ref) => PushService(ref.watch(dioProvider), const FlutterSecureStorage()));

/// OS notification permission as last observed — drives the in-app banner on
/// the Notifications screen. Refreshed by HomeShell on launch and on resume.
final pushStatusProvider = StateProvider<AuthorizationStatus?>((_) => null);
