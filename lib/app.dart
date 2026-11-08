import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:sportpadi_mobile/core/ads/admob.dart';
import 'package:sportpadi_mobile/core/i18n/date_locale.dart' show applyDateLocale;
import 'package:sportpadi_mobile/core/i18n/fallback_delegates.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart' show setCurrentL10n;
import 'package:sportpadi_mobile/core/i18n/locale_controller.dart';
import 'package:sportpadi_mobile/core/i18n/locales.dart';
import 'package:sportpadi_mobile/l10n/generated/app_localizations.dart';
import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/router/app_router.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/core/theme/app_theme.dart';
import 'package:sportpadi_mobile/core/theme/theme_mode.dart';
import 'package:sportpadi_mobile/core/update/app_update.dart';
import 'package:sportpadi_mobile/shared/widgets/push_banner.dart';

class SportpadiApp extends ConsumerWidget {
  const SportpadiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final config = ref.watch(appConfigProvider);
    final mode = ref.watch(themeModeProvider);
    // The player's language, or null to follow the phone (docs/design/i18n.md).
    final locale = ref.watch(localeControllerProvider);
    return MaterialApp.router(
      title: config.appName,
      locale: locale,
      supportedLocales: kSupportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        // Pidgin, Yorùbá, Igbo, Hausa: framework strings in English.
        ...fallbackLocalizationsDelegates,
      ],
      // Phone language → the closest we speak ("yo-NG" → yo), else English.
      localeListResolutionCallback: (device, _) => negotiateLocale(device),
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
        // Code without a BuildContext reads the same strings (core/i18n/l10n.dart).
        setCurrentL10n(AppLocalizations.of(context));
        applyDateLocale(Localizations.localeOf(context).languageCode);
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
            // AppUpdateGate: once per session, "new version" card / required
            // update screen over everything (core/update/app_update.dart).
            child: AppUpdateGate(
              child: AppOpenAdHost(
                child: LocaleProfileSync(
                  child: PushBannerHost(child: child ?? const SizedBox.shrink()),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
