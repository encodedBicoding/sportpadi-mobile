import 'dart:io' show Platform;

import 'package:dio/dio.dart';

import 'package:sportpadi_mobile/core/i18n/locale_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/analytics/device_id.dart';
import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/location/location_provider.dart';
import 'package:sportpadi_mobile/core/network/auth_interceptor.dart';
import 'package:sportpadi_mobile/core/storage/token_storage.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';

const _buildName =
    String.fromEnvironment('FLUTTER_BUILD_NAME', defaultValue: 'dev');

/// The single configured Dio instance, keyed to the active flavor's base URL.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final tokens = ref.watch(tokenStorageProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Accept': 'application/json',
        // Identify ourselves. Dart's default is "Dart/3.x (dart:io)", which
        // CDN bot rules (Cloudflare Bot Fight Mode and friends) treat as
        // automated traffic and may challenge with an HTML page the app
        // cannot answer — which the user sees as "can't reach the server".
        // Flutter passes FLUTTER_BUILD_NAME (pubspec version) as a define.
        'User-Agent': 'SportPadi/$_buildName '
            '(${Platform.operatingSystem} ${Platform.operatingSystemVersion})',
      },
      contentType: 'application/json',
    ),
  );

  // A token the server refused ends the session in the app too (it is
  // cleared either way): the app then shows the guest shell and the
  // visitor's view honestly, instead of a member's screens fed a stranger's
  // answers (review highlights-visitors-app.md MED-2). Read lazily: the
  // controller depends on this Dio through the auth repository.
  dio.interceptors.add(AuthInterceptor(tokens,
      onUnauthorized: () async {
    ref.read(authControllerProvider.notifier).tokenRejected();
  }));
  // Where the phone IS: once the app has a GPS fix (Discover, the Home
  // weather card), every request carries it so the server can show sport
  // names in that country's words — "football" in Lagos, "soccer" in Surrey
  // (api categories/aliases.ts). Rounded to ~1 km; nothing is sent until the
  // user has granted location, and without it the server uses the IP country.
  dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
    final loc = ref.read(locationProvider).location;
    if (loc != null) {
      options.headers['x-sp-geo'] =
          '${loc.lat.toStringAsFixed(2)},${loc.lng.toStringAsFixed(2)}';
    }
    // This install's analytics id, so a sign-up is tied to the device's
    // earlier visits (core/analytics/usage_tracker.dart).
    final did = DeviceId.value;
    if (did != null) options.headers['x-sp-device'] = did;
    // The language to phrase errors, notifications and emails in.
    options.headers['x-sp-locale'] = currentLocaleCode(ref);
    handler.next(options);
  }));
  if (!config.isProd && kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(requestBody: true, responseBody: true, error: true),
    );
  }
  return dio;
});
