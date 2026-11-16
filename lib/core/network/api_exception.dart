import 'package:dio/dio.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

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
///
/// Which message the user ends up seeing — most specific first, and each step
/// speaks only when every step above it had nothing to say:
///  1. **what the server said** (`data['message']`, trimmed and not blank).
///     Only the server knows why THIS request was refused, and it has already
///     phrased it in the user's language (every request carries `x-sp-locale`,
///     docs/design/i18n.md), so it beats every generic line below.
///  2. **the transport**, when no complete answer arrived. `connectionError`
///     and `connectionTimeout` really are an unreachable server;
///     `receiveTimeout` means it WAS reached and simply did not finish inside
///     `dio_client.dart`'s 20 s. The two must not say the same thing — reading
///     a slow route as a dead server cost a whole debugging session.
///  3. **the status**, for the three a person can make sense of: 404, 5xx, 403.
///  4. the caller's [fallback]: the repository knows what the call was FOR
///     ("Could not load tickets."), which is more use than anything this
///     function can say without a status.
///  5. "Something went wrong." when the caller passed no fallback.
///
/// [ApiException.detail] is a separate, always-technical line — see there.
ApiException apiError(Object e, {String? fallback}) {
  if (e is ApiException) {
    return e;
  }
  // A default parameter value has to be a constant and a translated string is
  // not, so the last resort is resolved here instead of in the signature.
  final last = fallback ?? l10n.common_somethingWentWrong;
  if (e is DioException) {
    final data = e.response?.data;
    final status = e.response?.statusCode;
    String? msg;
    if (data is Map && data['message'] is String) {
      final sent = (data['message'] as String).trim();
      // A blank "message" is not a message: let the branches below speak
      // rather than show the user an empty error.
      if (sent.isNotEmpty) msg = sent;
    }
    final parts = <String>[e.type.name];
    if (status != null) {
      final ct = e.response?.headers.value('content-type');
      parts.add(l10n.common_http(status, (ct != null ? ' · ${ct.split(';').first}' : '')));
      // A firewall / CDN challenge page instead of our JSON: the request
      // reached the edge but was refused before the app server saw it.
      if (e.response?.headers.value('cf-mitigated') != null ||
          (data is String && data.contains(l10n.common_cloudflare))) {
        parts.add('blocked by the site firewall (Cloudflare)');
      }
    }
    if (e.error != null) parts.add('${e.error}');
    // Every branch from here down assigns with `??=`: it DEFERS to whatever
    // the server already said (rule 1 above), and never overwrites it.
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      msg ??= l10n.common_cantReachTheServer;
    } else if (e.type == DioExceptionType.receiveTimeout) {
      // Reached, answering, just not finished in time — not unreachable.
      msg ??= l10n.common_theServerIsTakingTooLong;
    }
    if (status == 404) {
      msg ??= l10n.common_notFound;
    } else if (status != null) {
      // Nested so `status` is promoted to a plain int: the generated
      // l10n methods take a non-nullable Object.
      if (status >= 500) {
        msg ??= l10n.common_theServerHadAProblem(status);
      } else if (status == 403) {
        msg ??= l10n.common_theRequestWasRefused(status);
      }
    }
    return ApiException(
      msg ?? last,
      statusCode: status,
      detail: parts.join(' · '),
    );
  }
  return ApiException(last, detail: e.runtimeType.toString());
}
