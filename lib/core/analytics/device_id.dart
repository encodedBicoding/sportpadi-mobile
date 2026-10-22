// This install's analytics id (core/analytics/usage_tracker.dart): random,
// kept in secure storage, sent on every API request as `x-sp-device`.
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

String _uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) =>
      b.sublist(from, to).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// This install's analytics id, loaded once at start-up ([DeviceId.load]).
class DeviceId {
  DeviceId._();
  static const _key = 'sp_device_id';
  static String? _value;
  static Future<String>? _loading;

  /// Null until loaded (the first request or two may go without it).
  static String? get value => _value;

  static Future<String> load() => _loading ??= _read();

  static Future<String> _read() async {
    const storage = FlutterSecureStorage();
    try {
      final v = await storage.read(key: _key);
      if (v != null && RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(v)) {
        return _value = v;
      }
    } catch (_) {}
    final fresh = _uuidV4().replaceAll('-', '');
    try {
      await storage.write(key: _key, value: fresh);
    } catch (_) {}
    return _value = fresh;
  }
}

