import 'package:dio/dio.dart';

/// A user-facing error surfaced from the API layer.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Normalises any thrown error (usually a [DioException]) into an [ApiException]
/// with a message safe to show a user.
ApiException apiError(Object e, {String fallback = 'Something went wrong.'}) {
  if (e is ApiException) {
    return e;
  }
  if (e is DioException) {
    final data = e.response?.data;
    String? msg;
    if (data is Map && data['message'] is String) {
      msg = data['message'] as String;
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      msg = "Can't reach the server.";
    }
    if (e.response?.statusCode == 404) {
      msg ??= 'Not found.';
    }
    return ApiException(msg ?? fallback, statusCode: e.response?.statusCode);
  }
  return ApiException(fallback);
}
