import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/app.dart';
import 'package:sportpadi_mobile/core/env/app_config.dart';

/// Shared entrypoint for every flavor.
Future<void> bootstrap(Flavor flavor) async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.of(flavor);
  runApp(
    ProviderScope(
      overrides: [appConfigProvider.overrideWithValue(config)],
      child: const SportpadiApp(),
    ),
  );
}
