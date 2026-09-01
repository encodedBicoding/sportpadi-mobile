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
      Flavor.dev => 'http://10.0.2.2:3000',
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
