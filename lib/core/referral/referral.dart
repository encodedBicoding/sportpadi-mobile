import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Share-link attribution (gamification phase 3), mirroring the web: a
/// signed-in player's share links carry who shared them; the person who opens
/// one and plays is recorded as brought by them (the server decides whether it
/// counts — only brand-new players do).

final _uuid = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', caseSensitive: false);

/// Add ?ref=<me>&k=<kind>&src=<id> to a share URL (unchanged when signed out).
String withRef(String url, String? me, String kind, [String? sourceId]) {
  if (me == null || me.isEmpty) return url;
  final u = Uri.tryParse(url);
  if (u == null) return url;
  return u.replace(queryParameters: {
    ...u.queryParameters,
    'ref': me,
    'k': kind,
    if (sourceId != null && sourceId.isNotEmpty) 'src': sourceId,
  }).toString();
}

class ReferralStore {
  ReferralStore(this._storage);
  final FlutterSecureStorage _storage;
  static const _key = 'sp_pending_ref';

  /// Remember the ref on an incoming link (first one wins, 30-day life).
  Future<void> capture(Uri uri) async {
    final ref = uri.queryParameters['ref'];
    if (ref == null || !_uuid.hasMatch(ref)) return;
    try {
      if (await _read() != null) return;
      final k = uri.queryParameters['k'];
      final src = uri.queryParameters['src'];
      await _storage.write(
        key: _key,
        value: jsonEncode({
          'ref': ref,
          'k': k == 'event' || k == 'group' ? k : 'app',
          'src': src != null && _uuid.hasMatch(src) ? src : null,
          'at': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (_) {/* best-effort */}
  }

  Future<Map<String, dynamic>?> _read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final at = (m['at'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - at > 30 * 86400000) {
        await _storage.delete(key: _key);
        return null;
      }
      return m;
    } catch (_) {
      await _storage.delete(key: _key);
      return null;
    }
  }

  /// Signed in: send the pending ref once, then forget it either way.
  Future<void> claim(Dio dio, String myUserId) async {
    final m = await _read();
    if (m == null) return;
    await _storage.delete(key: _key);
    if (m['ref'] == myUserId) return;
    try {
      await dio.post('/api/mobile/progression/referral', data: {
        'referrerId': m['ref'],
        'kind': m['k'],
        if (m['src'] != null) 'sourceId': m['src'],
      });
    } catch (_) {/* attribution is best-effort */}
  }
}

final referralStoreProvider = Provider<ReferralStore>((_) => ReferralStore(const FlutterSecureStorage()));

