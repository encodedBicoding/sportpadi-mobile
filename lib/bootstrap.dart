import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/app.dart';
import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/firebase_options.dart';
import 'package:sportpadi_mobile/shared/format/event_time.dart';

/// Handles a push that arrives while the app is backgrounded or killed.
///
/// This runs in its own isolate that Flutter spins up for the message, so it
/// must be a TOP-LEVEL function and must be annotated for AOT builds —
/// otherwise tree-shaking drops it and release builds silently lose every
/// background message. It also has no access to the running app's state, so
/// there is nothing to do here beyond letting the isolate boot: the OS draws
/// the notification itself from the `notification` block, and the app reconciles
/// the feed when it next opens.
@pragma('vm:entry-point')
Future<void> onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

/// Shared entrypoint for every flavor.
Future<void> bootstrap(Flavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase comes up BEFORE the first frame. It used to be initialised lazily
  // from PushService once the home shell mounted, which meant a push that
  // launched the app from cold could arrive before Firebase existed, and the
  // background handler below could never be registered in time.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseMessaging.onBackgroundMessage(onBackgroundMessage);
  } catch (e) {
    // Not configured for this flavour yet — the app runs fine without push.
    if (kDebugMode) debugPrint('[push] Firebase init skipped: $e');
  }

  // Load the IANA database and the device's own zone so event times can be
  // shown at the venue's clock and, when the viewer is elsewhere, on theirs.
  // Failure is survivable: the app falls back to venue time only.
  await initEventTime();

  final config = AppConfig.of(flavor);
  runApp(
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(config)],
      child: const SportpadiApp(),
    ),
  );
}
