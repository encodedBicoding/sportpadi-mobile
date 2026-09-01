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

  ApiException _err(DioException e) {
    final data = e.response?.data;
    String? msg;
    if (data is Map) {
      if (data['message'] is String) msg = data['message'] as String;
      final err = data['error'];
      if (msg == null && err is Map && err['message'] is String) {
        msg = err['message'] as String;
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
