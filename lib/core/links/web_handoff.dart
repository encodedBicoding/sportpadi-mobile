import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';

/// A link to a website page that opens ALREADY SIGNED IN as the app's user —
/// the one-tap hand-off (web: packages/auth/src/handoff.ts).
///
/// The app asks the server for a single-use code (good for 2 minutes) tied to
/// [path], and opens `/api/auth/handoff/redeem?code=…`: the website swaps it
/// for its own browser session and lands on [path]. If the code can't be had
/// (offline, signed out, an older server), the plain page is returned and the
/// site simply asks them to sign in. `/api/*` is excluded from Universal /
/// App Links, so the redeem URL always opens in the browser, not back here.
///
/// [path] is a site-relative path ("/groups/<id>/upgrade?tier=…").
Future<Uri> signedInWebUri(Ref ref, String path) =>
    _signedIn(ref.read(appConfigProvider).apiBaseUrl, ref.read(dioProvider),
        path);

/// [signedInWebUri] from a widget.
/// A group's web-only payment page (upgrade, billing) at the address the app
/// doesn't claim. `/groups/<id>/upgrade` is inside the `/groups/` App Link the
/// app owns on Android, so opening it — or the hand-off redirecting to it —
/// lands straight back in the app ("it just reloads"). The web serves the same
/// pages at `/pay/<id>/<page>`, with a "Back to the app" bar.
String webPayPath(String groupId, String page) => '/pay/$groupId/$page';

/// `/groups/<id>/upgrade|billing…` → the same page at `/pay/<id>/…` (keeps the query).
Uri webPayUri(Uri uri) {
  final m = RegExp(r'^/groups/([^/]+)/(upgrade|billing)(/.*)?$').firstMatch(uri.path);
  if (m == null) return uri;
  return uri.replace(path: '/pay/${m[1]}/${m[2]}${m[3] ?? ''}');
}

Future<Uri> signedInWebUriFor(WidgetRef ref, String path) =>
    _signedIn(ref.read(appConfigProvider).apiBaseUrl, ref.read(dioProvider),
        path);

Future<Uri> _signedIn(String base, Dio dio, String path) async {
  final plain = Uri.parse('$base$path');
  try {
    final res =
        await dio.post('/api/auth/handoff/create', data: {'path': path});
    final data = res.data;
    final code = data is Map ? data['code'] : null;
    if (code is String && code.isNotEmpty) {
      return Uri.parse('$base/api/auth/handoff/redeem')
          .replace(queryParameters: {'code': code});
    }
  } catch (_) {
    // Fall through to the plain page.
  }
  return plain;
}
