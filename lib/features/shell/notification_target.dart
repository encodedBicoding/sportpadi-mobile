import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/links/deep_links.dart';
import 'package:sportpadi_mobile/core/router/app_router.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart';

/// Where a tapped notification goes — the ONE place that decides it, for a
/// push tapped in the system tray (background or cold start), a locally
/// posted foreground notification, and the in-app banner.
///
///   • it carries a destination the app has a screen for → that screen
///     (same resolver as Universal/App Links, so a shared URL and a push land
///     in the same place, tabs included);
///   • the destination is ours but web-only (a hosted payment, an upgrade)
///     → an in-app browser, exactly as a tapped link would;
///   • a link to someone else's site → the browser;
///   • no destination, or one the app can't place → the Notifications inbox,
///     where the message itself is readable.
///
/// Uses the router directly (not a BuildContext), so it works from a plugin
/// callback that fires before or outside any particular screen.
Future<void> openNotificationTarget(WidgetRef ref, String? url) async {
  final router = ref.read(routerProvider);
  void inbox() => router.push('/notifications');

  final raw = url?.trim() ?? '';
  if (raw.isEmpty) return inbox();

  final base = Uri.parse(ref.read(appConfigProvider).apiBaseUrl);
  final Uri? uri = raw.startsWith('http')
      ? Uri.tryParse(raw)
      : Uri.tryParse(
          '${base.scheme}://${base.authority}${raw.startsWith('/') ? '' : '/'}$raw');
  if (uri == null) return inbox();

  // Absolute link to another site: not ours to resolve. (The resolver only
  // looks at the path, so without this check https://other.site/events/x
  // would open one of OUR events.)
  final host = uri.host.toLowerCase();
  final ours = host == base.host.toLowerCase() ||
      host == 'sportpadi.com' ||
      host.endsWith('.sportpadi.com');
  if (!ours) {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (e) {
      if (kDebugMode) debugPrint('[push] could not open $uri: $e');
    }
    return inbox();
  }

  final handled = await handleDeepLink(
    uri,
    push: (route) => router.push(route),
    switchTab: (tab) {
      // A tab lives on /home; make sure that's what's showing, then pick it.
      router.go('/home');
      ref.read(homeTabIndexProvider.notifier).state = tab;
    },
  );
  if (!handled) inbox();
}
