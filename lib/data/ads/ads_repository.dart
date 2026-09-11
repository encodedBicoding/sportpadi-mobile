import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

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
  });
  final String id;
  final String slotId;
  final String imageUrl;
  final String clickUrl;
  final String? altText;
  final String? advertiserName;
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
          ));
        }
      }
      return out;
    } catch (_) {
      return const []; // ads must never break a screen
    }
  }

  Future<void> log(String action, String adId, String? slotId) async {
    try {
      await _dio.post('/api/mobile/ads',
          data: {'action': action, 'adId': adId, 'slotId': slotId});
    } catch (_) {/* best-effort */}
  }

  /// Refresh the user's ad locale — ONLY when location permission is already
  /// granted at the OS level. Never prompts.
  Future<void> personalizeIfPermitted() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return;
      }
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
              locationSettings:
                  const LocationSettings(accuracy: LocationAccuracy.low));
      await _dio.post('/api/mobile/ads', data: {
        'action': 'personalize',
        'lat': pos.latitude,
        'lng': pos.longitude,
      });
    } catch (_) {/* best-effort */}
  }
}

final adsRepositoryProvider =
    Provider<AdsRepository>((ref) => AdsRepository(ref.watch(dioProvider)));

final servedAdsProvider = FutureProvider.autoDispose
    .family<List<ServedAd>, String>((ref, joinedKeys) =>
        ref.watch(adsRepositoryProvider).serve(joinedKeys.split(',')));
