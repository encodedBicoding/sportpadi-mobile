import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/network/auth_interceptor.dart';
import 'package:sportpadi_mobile/core/storage/token_storage.dart';

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

  dio.interceptors.add(AuthInterceptor(tokens));
  if (!config.isProd && kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(requestBody: true, responseBody: true, error: true),
    );
  }
  return dio;
});
