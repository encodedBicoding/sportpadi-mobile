import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/network/auth_interceptor.dart';
import 'package:sportpadi_mobile/core/storage/token_storage.dart';

/// The single configured Dio instance, keyed to the active flavor's base URL.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final tokens = ref.watch(tokenStorageProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: const {'Accept': 'application/json'},
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
