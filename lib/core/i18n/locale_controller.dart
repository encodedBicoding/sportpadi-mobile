import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:sportpadi_mobile/core/i18n/locales.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';

/// The player's language (docs/design/i18n.md): null = follow the phone.
/// Signed in, the PROFILE is the source of truth — the same language on every
/// device and on the web; the copy in secure storage is what the app uses
/// before sign-in and while the profile loads. Settings → Language sets it.
class LocaleController extends StateNotifier<Locale?> {
  LocaleController(this._ref) : super(null) {
    _load();
  }

  final Ref _ref;
  static const _storage = FlutterSecureStorage();
  static const _key = 'sp_locale';
  bool _loaded = false;

  /// A profile value that arrived before storage finished loading.
  bool _hasPending = false;
  String? _pending;

  Future<void> _load() async {
    try {
      final v = await _storage.read(key: _key);
      if (mounted && spLocaleFor(v) != null) state = Locale(v!);
    } catch (_) {
      // Follow the phone.
    } finally {
      _loaded = true;
      if (_hasPending) {
        _hasPending = false;
        syncFromProfile(_pending);
      }
    }
  }

  /// The signed-in profile's language (null = follow the phone): it wins over
  /// whatever this device had, so a choice made on the web or another phone
  /// applies here too.
  void syncFromProfile(String? code) {
    if (!_loaded) {
      _hasPending = true;
      _pending = code;
      return;
    }
    final l = spLocaleFor(code);
    if (l == null) {
      if (state == null) return;
      state = null;
      // ignore: discarded_futures
      _storage.delete(key: _key).catchError((_) {});
      return;
    }
    if (state?.languageCode == l.code) return;
    state = l.locale;
    // ignore: discarded_futures
    _storage.write(key: _key, value: l.code).catchError((_) {});
  }

  /// Pick a language, or null to follow the phone again. Signed in, it's saved
  /// on the profile first (that's what every device follows) — returns false
  /// when that fails, and nothing changes. Signed out, it's saved on the device.
  Future<bool> set(String? code) async {
    final l = spLocaleFor(code);
    final signedIn = _ref.read(authControllerProvider).valueOrNull?.user != null;
    if (signedIn) {
      try {
        await _ref
            .read(dioProvider)
            .post('/api/mobile/me', data: {'action': 'set-locale', 'locale': l?.code});
      } catch (_) {
        return false;
      }
    }
    state = l?.locale;
    try {
      if (l == null) {
        await _storage.delete(key: _key);
      } else {
        await _storage.write(key: _key, value: l.code);
      }
    } catch (_) {}
    if (signedIn) _ref.invalidate(meProvider);
    return true;
  }
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale?>((ref) => LocaleController(ref));

/// Mounted once in the app: the signed-in profile's language is applied as
/// soon as the profile is known — on start-up (already cached or freshly
/// loaded) and whenever it changes. Lives here rather than in the controller
/// so building the controller never fetches /me (the request interceptor
/// reads the controller).
class LocaleProfileSync extends ConsumerStatefulWidget {
  const LocaleProfileSync({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LocaleProfileSync> createState() => _LocaleProfileSyncState();
}

class _LocaleProfileSyncState extends ConsumerState<LocaleProfileSync> {
  /// The profile value last applied ('' = not yet; '-' = follow the phone).
  String _applied = '';

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authControllerProvider).valueOrNull?.user != null;
    if (!signedIn) {
      _applied = ''; // signed out: the device decides; re-apply after the next sign-in
      return widget.child;
    }
    // Watching (not listening) also covers a profile that was already loaded
    // before this widget built — the old listener missed that case.
    final me = ref.watch(meProvider).valueOrNull;
    if (me != null) {
      final key = me.locale ?? '-';
      if (key != _applied) {
        _applied = key;
        final code = me.locale;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(localeControllerProvider.notifier).syncFromProfile(code);
        });
      }
    }
    return widget.child;
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
