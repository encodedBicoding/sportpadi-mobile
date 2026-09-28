import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/links/link_resolver.dart';

/// Universal Links (iOS) and App Links (Android).
///
/// Two ways a link arrives and both must work, because they fail differently:
/// a COLD start hands the URL over before any router exists, and a warm link
/// arrives on a stream while the app is already on some screen. Miss the first
/// and shared links appear to do nothing when the app wasn't running — the most
/// common deep-link bug there is.
///
/// Anything the resolver marks `web` is handed straight back to the browser.
/// Android App Links can't exclude paths, so the OS will hand us hosted
/// checkout and Stripe onboarding URLs regardless; bouncing them out is what
/// keeps a payment from dying in an app that can't complete it.
class DeepLinkService {
  DeepLinkService();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _started = false;

  /// Whoever is currently able to act on a link. The guest shell registers
  /// first; when the user signs in, the signed-in shell takes over. Held as a
  /// field rather than captured by the stream listener so that hand-over
  /// works without restarting the stream (and the cold-start link is still
  /// delivered exactly once).
  void Function(Uri uri)? _handler;

  /// The link that launched the app, if any. Read once — a cold-start link is
  /// delivered exactly once and must not be replayed on a later resume.
  Uri? _pendingColdStart;
  bool _coldStartRead = false;

  /// Begin listening. `onLink` is called for every link from now on, including
  /// the cold-start one.
  Future<void> start(void Function(Uri uri) onLink) async {
    _handler = onLink;
    if (_started) return;
    _started = true;

    _sub = _appLinks.uriLinkStream.listen(
      (uri) => _handler?.call(uri),
      onError: (Object e) {
        if (kDebugMode) debugPrint('[deeplink] stream error: $e');
      },
    );

    // The cold-start link. Fetched separately because the stream doesn't
    // replay it, and it may already have been consumed by `takeColdStart`.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null && !_coldStartRead) {
        _coldStartRead = true;
        onLink(initial);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[deeplink] initial link failed: $e');
    }
  }

  /// The launch link, for a caller that wants it BEFORE the router is ready
  /// (so it can decide the first screen rather than pushing on top of Home).
  Future<Uri?> takeColdStart() async {
    if (_coldStartRead) return null;
    _coldStartRead = true;
    try {
      _pendingColdStart = await _appLinks.getInitialLink();
    } catch (_) {
      _pendingColdStart = null;
    }
    return _pendingColdStart;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _handler = null;
    _started = false;
  }
}

final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final s = DeepLinkService();
  ref.onDispose(s.dispose);
  return s;
});

/// Act on one incoming link.
///
/// Returns true when the app handled it. `push` and `switchTab` are supplied by
/// the shell, which owns the router and the tab state.
Future<bool> handleDeepLink(
  Uri uri, {
  required void Function(String route) push,
  required void Function(int tab) switchTab,
}) async {
  final target = resolveLink(uri.toString());

  if (target.web) {
    // Ours by hostname, but not ours to render — send it back out. Without
    // this, an Android user tapping a payment or upgrade link would land in the
    // app and simply be stuck.
    //
    // inAppBrowserView, NOT externalApplication: we are a verified handler for
    // this host, so a plain VIEW intent on Android can be routed straight back
    // to us — app → "browser" → app, forever. Custom Tabs (Android) and
    // SFSafariViewController (iOS) are real browsers that cannot resolve to us,
    // and they still share the system cookie jar, so a Stripe or checkout
    // session signed in elsewhere carries over.
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!ok) await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (e) {
      if (kDebugMode) debugPrint('[deeplink] could not re-open $uri: $e');
    }
    return true;
  }

  final route = target.route;
  if (route != null) {
    push(route);
    return true;
  }
  final tab = target.tab;
  if (tab != null) {
    switchTab(tab);
    return true;
  }

  // A marketing page or something we don't know: nothing sensible to open, so
  // leave the user where they are rather than bouncing them to Home.
  if (kDebugMode) debugPrint('[deeplink] no destination for $uri');
  return false;
}
