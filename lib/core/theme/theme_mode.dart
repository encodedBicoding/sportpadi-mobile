import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Appearance: follow the phone (default), or force Light / Dark. Stored on
/// the device so it survives restarts; read once at start-up.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.system) {
    _load();
  }

  static const _storage = FlutterSecureStorage();
  static const _key = 'sp_theme_mode';

  Future<void> _load() async {
    try {
      final v = await _storage.read(key: _key);
      final m = _parse(v);
      if (m != null && mounted) state = m;
    } catch (_) {
      // Keep following the system.
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      await _storage.write(key: _key, value: mode.name);
    } catch (_) {}
  }

  static ThemeMode? _parse(String? v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => null,
      };
}

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
    (_) => ThemeModeController());
