import 'package:dio/dio.dart';

/// A user-facing error surfaced from the API layer.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.detail});

  final String message;
  final int? statusCode;

  /// The technical cause, safe to show in small print under [message]:
  /// "connectionError · SocketException: Failed host lookup: 'sportpadi.com'",
  /// "HandshakeException: …", "HTTP 403 · text/html". Release builds have no
  /// console, so this is the only way a "can't reach the server" on a real
  /// phone can be told apart from DNS, TLS, a timeout or a firewall page.
  final String? detail;

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
    final status = e.response?.statusCode;
    String? msg;
    if (data is Map && data['message'] is String) {
      msg = data['message'] as String;
    }
    final parts = <String>[e.type.name];
    if (status != null) {
      final ct = e.response?.headers.value('content-type');
      parts.add('HTTP $status${ct != null ? ' · ${ct.split(';').first}' : ''}');
      // A firewall / CDN challenge page instead of our JSON: the request
      // reached the edge but was refused before the app server saw it.
      if (e.response?.headers.value('cf-mitigated') != null ||
          (data is String && data.contains('Cloudflare'))) {
        parts.add('blocked by the site firewall (Cloudflare)');
      }
    }
    if (e.error != null) parts.add('${e.error}');
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      msg = "Can't reach the server.";
    }
    if (status == 404) {
      msg ??= 'Not found.';
    } else if (status != null && status >= 500) {
      msg ??= 'The server had a problem ($status).';
    } else if (status == 403 && msg == null) {
      msg = 'The request was refused ($status).';
    }
    return ApiException(
      msg ?? fallback,
      statusCode: status,
      detail: parts.join(' · '),
    );
  }
  return ApiException(fallback, detail: e.runtimeType.toString());
}
