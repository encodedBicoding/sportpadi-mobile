import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/ads/admob.dart';
import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/router/app_router.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/core/theme/app_theme.dart';
import 'package:sportpadi_mobile/core/theme/theme_mode.dart';
import 'package:sportpadi_mobile/shared/widgets/push_banner.dart';

class SportpadiApp extends ConsumerWidget {
  const SportpadiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final config = ref.watch(appConfigProvider);
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Follows the phone's light/dark setting unless the user picked one
      // in Settings → Appearance.
      themeMode: mode,
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
      builder: (context, child) {
        // Status bar + Android navigation bar follow the active theme, so
        // icons never vanish (dark icons on dark, light on light) and the
        // system bar blends into the page canvas.
        final p = context.palette;
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: p.bg,
            systemNavigationBarDividerColor: p.bg,
            systemNavigationBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
          ),
          child: ExcludeSemantics(
            child: AppOpenAdHost(
              child: PushBannerHost(child: child ?? const SizedBox.shrink()),
            ),
          ),
        );
      },
    );
  }
}
