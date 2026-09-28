import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum Flavor { dev, staging, prod }

/// Resolved runtime configuration for a flavor. The API base URL can be
/// overridden at build time with `--dart-define=API_BASE_URL=...`.
class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.apiBaseUrl,
    required this.appName,
  });

  final Flavor flavor;
  final String apiBaseUrl;
  final String appName;

  bool get isProd => flavor == Flavor.prod;

  static const _defineBase = String.fromEnvironment('API_BASE_URL');

  factory AppConfig.of(Flavor flavor) {
    final fallback = switch (flavor) {
      // The dev default only reaches a Next.js server on the SAME machine as
      // an emulator/simulator: 10.0.2.2 is the Android emulator's alias for
      // the host, localhost works on the iOS Simulator. A REAL phone can reach
      // neither — it must be pointed at the machine's LAN address or at
      // staging:  --dart-define=API_BASE_URL=http://192.168.1.20:3000
      //           --dart-define=API_BASE_URL=https://test.sportpadi.com
      // (plain http to a LAN host is allowed by NSAllowsLocalNetworking on
      // iOS and usesCleartextTraffic in the debug manifest on Android).
      Flavor.dev => Platform.isIOS ? 'http://localhost:3000' : 'http://10.0.2.2:3000',
      Flavor.staging => 'https://test.sportpadi.com',
      Flavor.prod => 'https://sportpadi.com',
    };
    return AppConfig(
      flavor: flavor,
      apiBaseUrl: _defineBase.isNotEmpty ? _defineBase : fallback,
      appName: switch (flavor) {
        Flavor.dev => 'sportpadi · dev',
        Flavor.staging => 'sportpadi · staging',
        Flavor.prod => 'sportpadi',
      },
    );
  }
}

/// Overridden in `bootstrap()` with the flavor's [AppConfig].
final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);
