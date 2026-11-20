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

  /// A 401 means two different things, and only the request can tell them
  /// apart: WITH a bearer token it is the server refusing that token (every
  /// UNAUTHORIZED the API throws is "no session", so a token that signed in
  /// never gets one) — the session is over, and [onUnauthorized] says so; with
  /// NO token it is "this needs an account" (a visitor's Following tab, a
  /// write) and changes nothing — the stored token is not touched either.
  /// `/api/auth/` is left alone ENTIRELY: Better Auth answers 401 to a VALID
  /// session there (link-social refusing an account with another address,
  /// a wrong password), so clearing the token on it left a "signed-in" app
  /// with no token (re-review R-MED-1). The one `/api/auth/` 401 that means
  /// the token is dead — the session check's — is `AuthRepository
  /// .currentUser`'s to act on, and it clears the token itself.
  /// (Review highlights-visitors-app.md MED-2, re-review R-MED-1 / R-LOW-1.)
  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode != 401 ||
        err.requestOptions.uri.path.startsWith('/api/auth/')) {
      handler.next(err);
      return;
    }
    final sent = err.requestOptions.headers['Authorization'];
    final hadToken = sent is String && sent.isNotEmpty;
    final current = await _tokens.read();
    // The answer to a request made with an OLDER token — the person signed
    // out and in while it was on its way, or a 401 in flight beside it has
    // already ended the session: it says nothing about the token now held.
    final stale = hadToken && (current == null || sent != 'Bearer $current');
    // A request sent with NO token (made while signed out, landing after a
    // sign-in) or with a stale one: the token now held is not its business.
    if (!hadToken || stale) {
      handler.next(err);
      return;
    }
    await _tokens.clear();
    await onUnauthorized?.call();
    handler.next(err);
  }
}
