import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/router/app_router.dart';
import 'package:sportpadi_mobile/core/theme/app_theme.dart';

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
      builder: (context, child) =>
          ExcludeSemantics(child: child ?? const SizedBox.shrink()),
    );
  }
}
