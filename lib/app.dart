import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/ads/admob.dart';
import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/router/app_router.dart';
import 'package:sportpadi_mobile/core/theme/app_theme.dart';
import 'package:sportpadi_mobile/shared/widgets/push_banner.dart';

class SportpadiApp extends ConsumerWidget {
  const SportpadiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final config = ref.watch(appConfigProvider);
    return MaterialApp.router(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.light,
      routerConfig: router,
      // This Flutter build's semantics compiler crashes with
      // '!semantics.parentDataDirty' (rendering/object.dart:5724) on many
      // widget shapes (Badge, *Button.icon, Text.rich, ...) — a framework
      // bug, not app code. Excluding the whole tree from semantics stops it
      // app-wide (incl. sheets/dialogs/snackbars). Trade-off: screen readers
      // are disabled. Remove this builder after upgrading Flutter.
      // PushBannerHost renders pushes that arrive while the app is OPEN —
      // neither platform shows a system notification for those.
      // AppOpenAdHost watches the lifecycle for the AdMob app-open ad
      // (Android only; a no-op elsewhere).
      builder: (context, child) => ExcludeSemantics(
        child: AppOpenAdHost(
          child: PushBannerHost(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
