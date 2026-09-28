import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:sportpadi_mobile/core/location/location_provider.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';

/// One served ad, ready to render.
class ServedAd {
  const ServedAd({
    required this.id,
    required this.slotId,
    required this.imageUrl,
    required this.clickUrl,
    this.altText,
    this.advertiserName,
    this.size,
  });
  final String id;
  final String slotId;
  final String imageUrl;
  final String clickUrl;
  final String? altText;
  final String? advertiserName;
  /// Owner-entered size, e.g. "728x90", "300x250" or "responsive".
  final String? size;

  /// Width/height ratio from [size] when it's "WxH"; null otherwise.
  double? get aspectRatio {
    final m = RegExp(r'^\s*(\d+)\s*[x×]\s*(\d+)\s*$').firstMatch(size ?? '');
    if (m == null) return null;
    final w = double.parse(m.group(1)!);
    final h = double.parse(m.group(2)!);
    return h > 0 ? w / h : null;
  }
}

class AdsRepository {
  AdsRepository(this._dio);
  final Dio _dio;

  /// Location-targeted ads for the given slot keys (mobile platform).
  Future<List<ServedAd>> serve(List<String> keys) async {
    try {
      final res = await _dio
          .get('/api/mobile/ads', queryParameters: {'keys': keys.join(',')});
      final slots = res.data is Map ? (res.data['slots'] as List? ?? []) : [];
      final out = <ServedAd>[];
      for (final s in slots) {
        final m = Map<String, dynamic>.from(s as Map);
        final slotId = (m['slotId'] ?? '') as String;
        for (final a in (m['ads'] as List? ?? [])) {
          final ad = Map<String, dynamic>.from(a as Map);
          out.add(ServedAd(
            id: (ad['id'] ?? '') as String,
            slotId: slotId,
            imageUrl: (ad['imageUrl'] ?? '') as String,
            clickUrl: (ad['clickUrl'] ?? '') as String,
            altText: ad['altText'] as String?,
            advertiserName: ad['advertiserName'] as String?,
            size: ad['size'] as String?,
          ));
        }
      }
      if (kDebugMode && out.isEmpty) {
        debugPrint('[ads] no ads for slots ${keys.join(',')} — check the slot '
            'keys exist, are active, platform is mobile/both, an active ad is '
            'attached, and (for location-targeted ads) this device has a locale.');
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('[ads] serve failed: $e');
      return const []; // ads must never break a screen
    }
  }

  Future<void> log(String action, String adId, String? slotId) async {
    try {
      await _dio.post('/api/mobile/ads',
          data: {'action': action, 'adId': adId, 'slotId': slotId});
    } catch (_) {/* best-effort */}
  }

  Future<bool>? _personalizing;
  String? _personalizedFor; // "lat,lng" last sent, to skip repeats

  /// Refresh the user's ad locale — ONLY when location permission is already
  /// granted at the OS level. Never prompts. Memoised per run so the serve
  /// call can await it (location-targeted ads only match once the server
  /// knows where the viewer is). Pass [known] to reuse a position the app
  /// already has (Browse/Discover) instead of taking another fix.
  Future<bool> personalizeIfPermitted({UserLocation? known}) {
    if (known != null) return _personalize(known.lat, known.lng);
    return _personalizing ??= _locateAndPersonalize();
  }

  Future<bool> _locateAndPersonalize() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return false;
      }
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
              locationSettings:
                  const LocationSettings(accuracy: LocationAccuracy.low));
      return await _personalize(pos.latitude, pos.longitude);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _personalize(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
    if (_personalizedFor == key) return true;
    try {
      await _dio.post('/api/mobile/ads', data: {
        'action': 'personalize',
        'lat': lat,
        'lng': lng,
      });
      _personalizedFor = key;
      return true;
    } catch (_) {
      return false;
    }
  }
}

final adsRepositoryProvider =
    Provider<AdsRepository>((ref) => AdsRepository(ref.watch(dioProvider)));

/// Ads for a comma-joined list of slot keys. Sends the viewer's location to
/// the server FIRST (when the OS already allows it, or when Browse/Discover
/// has a fix) so location-targeted ads can match on the very first serve —
/// and re-serves whenever a location arrives later.
final servedAdsProvider = FutureProvider.autoDispose
    .family<List<ServedAd>, String>((ref, joinedKeys) async {
  final repo = ref.watch(adsRepositoryProvider);
  // Re-run when the app's own location fix changes (e.g. after Browse asks).
  final loc = ref.watch(locationProvider.select((s) => s.location));
  await repo
      .personalizeIfPermitted(known: loc)
      .timeout(const Duration(seconds: 5), onTimeout: () => false);
  return repo.serve(joinedKeys.split(','));
});
