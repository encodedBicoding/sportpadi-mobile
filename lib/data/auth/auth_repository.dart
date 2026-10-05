import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/storage/token_storage.dart';
import 'package:sportpadi_mobile/data/auth/auth_models.dart';

/// Talks to Better Auth. NOTE: requires the backend to enable the **bearer**
/// plugin so a native client can hold a token (the web app uses cookies). The
/// token is read from the `set-auth-token` response header (bearer plugin) or a
/// `token` field in the body, whichever the backend returns.
class AuthRepository {
  AuthRepository(this._dio, this._tokens);

  final Dio _dio;
  final TokenStorage _tokens;

  Future<AuthUser?> currentUser() async {
    final token = await _tokens.read();
    if (token == null || token.isEmpty) return null;
    try {
      final res = await _dio.get('/api/auth/get-session');
      return _extractUser(res.data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return null;
      throw _err(e);
    }
  }

  Future<AuthUser> signIn(
      {required String email, required String password}) async {
    try {
      final res = await _dio.post(
        '/api/auth/sign-in/email',
        data: {'email': email, 'password': password},
      );
      await _persistToken(res);
      final user = _extractUser(res.data);
      if (user == null) throw ApiException('Could not sign you in.');
      return user;
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<AuthUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final res = await _dio.post(
        '/api/auth/sign-up/email',
        data: {'name': name, 'email': email, 'password': password},
      );
      await _persistToken(res);
      final user = _extractUser(res.data);
      if (user == null) throw ApiException('Could not create your account.');
      return user;
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// Google / Apple: the native button's ID token goes to Better Auth's
  /// `/sign-in/social`, which verifies it against the provider's keys, finds
  /// or creates the account (linking by verified email), and mints our
  /// session — same bearer token as an email sign-in.
  Future<AuthUser> signInWithIdToken({
    required String provider,
    required String idToken,
    String? nonce,
    String? accessToken,
  }) async {
    try {
      final res = await _dio.post(
        '/api/auth/sign-in/social',
        data: {
          'provider': provider,
          'idToken': {
            'token': idToken,
            if (nonce != null) 'nonce': nonce,
            if (accessToken != null) 'accessToken': accessToken,
          },
        },
      );
      await _persistToken(res);
      final user = _extractUser(res.data);
      if (user == null) throw ApiException('Could not sign you in.');
      return user;
    } on DioException catch (e) {
      throw _err(e, social: provider);
    }
  }

  /// Settings → Sign-in methods: attach Google / Apple to the signed-in
  /// account (same ID-token route, Better Auth `/link-social`). The
  /// provider's email must match the account's.
  Future<void> linkWithIdToken({
    required String provider,
    required String idToken,
    String? nonce,
    String? accessToken,
  }) async {
    try {
      await _dio.post('/api/auth/link-social', data: {
        'provider': provider,
        'idToken': {
          'token': idToken,
          if (nonce != null) 'nonce': nonce,
          if (accessToken != null) 'accessToken': accessToken,
        },
      });
    } on DioException catch (e) {
      throw _err(e, social: provider);
    }
  }

  /// Detach a provider. The server refuses to remove the last way in.
  Future<void> unlinkProvider(String provider) async {
    try {
      await _dio.post('/api/auth/unlink-account',
          data: {'providerId': provider});
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// The ways into this account (password? which providers?), plus which
  /// providers this server can link.
  Future<SignInMethods> signInMethods() async {
    try {
      final res = await _dio.get('/api/mobile/sign-in-methods');
      return SignInMethods.fromJson(
          Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// Give an SSO-only account a password (refused when one exists).
  Future<void> setPassword(String newPassword) async {
    try {
      await _dio.post('/api/mobile/sign-in-methods',
          data: {'action': 'set-password', 'newPassword': newPassword});
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// Email verification (Better Auth email-otp plugin). Sends the 4-digit
  /// code to the address on the account.
  Future<void> sendVerificationCode(String email) async {
    try {
      await _dio.post('/api/auth/email-otp/send-verification-otp',
          data: {'email': email, 'type': 'email-verification'});
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// Confirms the code. Returns the refreshed user (emailVerified = true).
  Future<AuthUser?> verifyEmail({
    required String email,
    required String otp,
  }) async {
    try {
      await _dio.post('/api/auth/email-otp/verify-email',
          data: {'email': email, 'otp': otp});
    } on DioException catch (e) {
      throw _err(e);
    }
    // Re-read the session so `emailVerified` is authoritative, not assumed.
    return currentUser();
  }

  /// Password reset (Better Auth). Emails a link to the web page that sets
  /// the new password — resets finish in the browser on purpose (the
  /// Universal Link / App Link manifests exclude /auth*). The server answers
  /// the same whether or not the address has an account.
  ///
  /// `redirectTo` is a path, not a URL: Better Auth resolves it against its
  /// own base URL, so it passes the trusted-origin check on every flavour
  /// (a dev build talking to 10.0.2.2 would fail it with an absolute URL).
  Future<void> requestPasswordReset(String email) async {
    try {
      await _dio.post('/api/auth/request-password-reset',
          data: {'email': email, 'redirectTo': '/auth/reset'});
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<void> signOut() async {
    try {
      await _dio.post('/api/auth/sign-out');
    } catch (_) {
      // Best effort — clear the local token regardless.
    }
    await _tokens.clear();
  }

  Future<void> _persistToken(Response<dynamic> res) async {
    final header = res.headers.value('set-auth-token');
    final body = res.data is Map ? (res.data as Map)['token'] : null;
    final token = header ?? (body is String ? body : null);
    if (token != null && token.isNotEmpty) await _tokens.write(token);
  }

  AuthUser? _extractUser(dynamic data) {
    if (data is Map && data['user'] is Map) {
      return AuthUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
    }
    if (data is Map && data['id'] != null && data['email'] != null) {
      return AuthUser.fromJson(Map<String, dynamic>.from(data));
    }
    return null;
  }

  ApiException _err(DioException e, {String? social}) {
    final data = e.response?.data;
    String? msg;
    String? code;
    if (data is Map) {
      if (data['message'] is String) msg = data['message'] as String;
      if (data['code'] is String) code = data['code'] as String;
      final err = data['error'];
      if (msg == null && err is Map && err['message'] is String) {
        msg = err['message'] as String;
      }
    }
    // Better Auth's social errors are terse codes; say what to do instead.
    if (social != null) {
      final name = social == 'apple' ? 'Apple' : 'Google';
      switch (code) {
        case 'INVALID_TOKEN':
        case 'ID_TOKEN_NOT_SUPPORTED':
          msg = "$name didn't give us a valid sign-in token. Please try again.";
        case 'EMAIL_NOT_VERIFIED':
        case 'ACCOUNT_NOT_LINKED':
        case 'USER_ALREADY_EXISTS':
          msg =
              "An account with that email already exists but its email isn't verified yet. "
              'Sign in with your password, verify your email, then link $name from Settings.';
        case 'EMAIL_DOESNT_MATCH':
          msg =
              "That $name account uses a different email from this SportPadi account.";
        case 'SOCIAL_ACCOUNT_ALREADY_LINKED':
          msg = 'That $name account is already linked to another SportPadi account.';
        default:
          break;
      }
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      msg =
          'Can\'t reach the server. Check the API URL and that it\'s running.';
    }
    return ApiException(
      msg ?? 'Something went wrong. Please try again.',
      statusCode: e.response?.statusCode,
    );
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) =>
      AuthRepository(ref.watch(dioProvider), ref.watch(tokenStorageProvider)),
);
