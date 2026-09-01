import 'package:dio/dio.dart';

import 'package:sportpadi_mobile/core/storage/token_storage.dart';

/// Attaches the bearer token to every request and clears it on a hard 401.
/// Token refresh/retry is a later concern (Phase 1) — for now a 401 signs out.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._tokens, {this.onUnauthorized});

  final TokenStorage _tokens;
  final Future<void> Function()? onUnauthorized;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokens.read();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      await _tokens.clear();
      await onUnauthorized?.call();
    }
    handler.next(err);
  }
}
