import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:sportpadi_mobile/core/i18n/locales.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';

/// The player's language (docs/design/i18n.md): null = follow the phone.
/// Stored on the device (so it's right before sign-in) and on the profile
/// (so the web and notifications agree). Settings → Language sets it.
class LocaleController extends StateNotifier<Locale?> {
  LocaleController(this._ref) : super(null) {
    _load();
  }

  final Ref _ref;
  static const _storage = FlutterSecureStorage();
  static const _key = 'sp_locale';
  bool _loaded = false;

  Future<void> _load() async {
    try {
      final v = await _storage.read(key: _key);
      if (mounted && spLocaleFor(v) != null) state = Locale(v!);
    } catch (_) {
      // Follow the phone.
    } finally {
      _loaded = true;
    }
  }

  /// The profile says what they chose on another device: adopt it.
  void syncFromProfile(String? code) {
    if (!_loaded) return;
    final l = spLocaleFor(code);
    if (l == null || state?.languageCode == l.code) return;
    state = l.locale;
    // ignore: discarded_futures
    _storage.write(key: _key, value: l.code).catchError((_) {});
  }

  /// Pick a language, or null to follow the phone again. Saves locally first
  /// (instant), then on the profile when signed in (best effort).
  Future<void> set(String? code) async {
    final l = spLocaleFor(code);
    state = l?.locale;
    try {
      if (l == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: l.code);
      }
    } catch (_) {}
    final me = _ref.read(meProvider).valueOrNull;
    if (me != null) {
      try {
        await _ref
            .read(dioProvider)
            .post('/api/mobile/me', data: {'action': 'set-locale', 'locale': l?.code});
        _ref.invalidate(meProvider);
      } catch (_) {
        // The device choice still applies; the profile catches up next time.
      }
    }
  }
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale?>((ref) => LocaleController(ref));

/// Mounted once in the app: when the signed-in profile carries a language
/// chosen elsewhere (the web, another phone), the app adopts it. Lives here
/// rather than in the controller so building the controller never fetches
/// /me (the request interceptor reads the controller).
class LocaleProfileSync extends ConsumerWidget {
  const LocaleProfileSync({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authControllerProvider).valueOrNull?.user != null;
    if (signedIn) {
      ref.listen(meProvider, (_, next) {
        final code = next.valueOrNull?.locale;
        if (code != null) {
          ref.read(localeControllerProvider.notifier).syncFromProfile(code);
        }
      });
    }
    return child;
  }
}

/// What the API should phrase things in: the explicit choice, else the
/// phone's best match. Sent as x-sp-locale on every request.
String currentLocaleCode(Ref ref) {
  final chosen = ref.read(localeControllerProvider);
  if (chosen != null) return chosen.languageCode;
  return negotiateLocale(WidgetsBinding.instance.platformDispatcher.locales)
      .languageCode;
}
