import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:sportpadi_mobile/core/location/location_provider.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/push/push_service.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// One served ad, ready to render: an advertiser's SPONSORED creative (badged
/// "Ad") or a PROMO — SportPadi's own message with a title, body and button.
class ServedAd {
  const ServedAd({
    required this.id,
    required this.slotId,
    required this.imageUrl,
    required this.clickUrl,
    this.altText,
    this.advertiserName,
    this.size,
    this.kind = 'sponsored',
    this.title,
    this.body,
    this.ctaLabel,
    this.accent,
    this.hideOnDismiss = true,
    this.logViews = true,
  });
  final String id;
  final String slotId;
  /// Empty when a message has no picture.
  final String imageUrl;
  /// https://… or one of our own paths ("/groups/…").
  final String clickUrl;
  final String? altText;
  final String? advertiserName;
  /// Owner-entered size, e.g. "728x90", "300x250" or "responsive".
  final String? size;
  /// sponsored | promo
  final String kind;
  final String? title;
  final String? body;
  final String? ctaLabel;
  /// green | orange | blue | ink — the panel colour when there's no image.
  final String? accent;
  /// Closing it hides it for good (otherwise it can come back).
  final bool hideOnDismiss;
  /// Report views? False when the ad doesn't record impressions and no cap
  /// counts views — then nothing is sent.
  final bool logViews;

  bool get isPromo => kind == 'promo';
  bool get hasImage => imageUrl.isNotEmpty;

  /// Width/height ratio from [size] when it's "WxH"; null otherwise.
  double? get aspectRatio {
    final m = RegExp(r'^\s*(\d+)\s*[x×]\s*(\d+)\s*$').firstMatch(size ?? '');
    if (m == null) return null;
    final w = double.parse(m.group(1)!);
    final h = double.parse(m.group(2)!);
    return h > 0 ? w / h : null;
  }

  factory ServedAd.fromJson(Map<String, dynamic> ad, String slotId) => ServedAd(
        id: (ad['id'] ?? '') as String,
        slotId: slotId,
        imageUrl: (ad['imageUrl'] ?? '') as String,
        clickUrl: (ad['clickUrl'] ?? '') as String,
        altText: parseStr(ad['altText']),
        advertiserName: parseStr(ad['advertiserName']),
        size: parseStr(ad['size']),
        kind: parseStr(ad['kind']) ?? 'sponsored',
        title: parseStr(ad['title']),
        body: parseStr(ad['body']),
        ctaLabel: parseStr(ad['ctaLabel']),
        accent: parseStr(ad['accent']),
        hideOnDismiss: ad['hideOnDismiss'] != false,
        logViews: ad['logViews'] != false,
      );
}

/// What one slot picked for this viewer, and how it wants to be shown:
/// banner | carousel | card | top_bar (inline, where the slot is placed) or
/// bottom_sheet | modal | whats_new (pop up when the app opens).
class ServedSlot {
  const ServedSlot({
    required this.key,
    required this.slotId,
    required this.display,
    required this.ads,
  });
  final String key;
  final String slotId;
  final String display;
  final List<ServedAd> ads;

  bool get isPopup =>
      display == 'bottom_sheet' || display == 'modal' || display == 'whats_new';
}

class AdsRepository {
  AdsRepository(this._dio, {required this.anonId});
  final Dio _dio;
  /// This install's random id (used only while signed out, for caps like
  /// "show twice"). Null when signed in — the server uses the account.
  final Future<String?> Function() anonId;

  static String? _version;
  /// The app's version ("1.4.0"), so messages about newer features only
  /// reach apps that have them.
  static Future<String?> appVersion() async {
    if (_version != null) return _version;
    try {
      _version = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}
    return _version;
  }

  static String get _os => defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// What each slot picked for this viewer. [popup]: of the pop-up slots,
  /// only the best one with something to show ([keys] may be empty = all).
  Future<List<ServedSlot>> serveSlots(List<String> keys, {bool popup = false}) async {
    try {
      final anon = await anonId();
      final v = await appVersion();
      final res = await _dio.get('/api/mobile/ads', queryParameters: {
        'keys': keys.join(','),
        'rich': '1',
        'os': _os,
        if (v != null) 'v': v,
        if (anon != null) 'anon': anon,
        if (popup) 'mode': 'popup',
      });
      final slots = res.data is Map ? (res.data['slots'] as List? ?? []) : [];
      final out = <ServedSlot>[];
      for (final s in slots) {
        final m = Map<String, dynamic>.from(s as Map);
        final slotId = (m['slotId'] ?? '') as String;
        out.add(ServedSlot(
          key: (m['key'] ?? '') as String,
          slotId: slotId,
          display: parseStr(m['display']) ?? 'banner',
          ads: [
            for (final a in (m['ads'] as List? ?? []))
              ServedAd.fromJson(Map<String, dynamic>.from(a as Map), slotId),
          ],
        ));
      }
      if (kDebugMode && !popup && out.every((s) => s.ads.isEmpty)) {
        debugPrint('[ads] no ads for slots ${keys.join(',')} — check the slot '
            'keys exist, are active, platform is mobile/both, an active ad is '
            'attached, its audience fits, and (for location-targeted ads) '
            'this device has a locale.');
      }
      return out;
    } catch (e) {
      if (kDebugMode) debugPrint('[ads] serve failed: $e');
      return const []; // ads must never break a screen
    }
  }

  /// Every ad across the given slots, flattened (inline slots only).
  Future<List<ServedAd>> serve(List<String> keys) async => [
        for (final s in await serveSlots(keys))
          if (!s.isPopup) ...s.ads,
      ];

  /// impression | click — also counted against the viewer's caps.
  Future<void> log(String action, String adId, String? slotId) async {
    try {
      final anon = await anonId();
      await _dio.post('/api/mobile/ads', data: {
        'action': action,
        'adId': adId,
        'slotId': slotId,
        if (anon != null) 'anonId': anon,
      });
    } catch (_) {/* best-effort */}
  }

  /// Closed / "Not now". Hides it for good when the message says so.
  Future<void> dismiss(String adId) async {
    try {
      final anon = await anonId();
      await _dio.post('/api/mobile/ads', data: {
        'action': 'dismiss',
        'adId': adId,
        if (anon != null) 'anonId': anon,
      });
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

final adsRepositoryProvider = Provider<AdsRepository>((ref) => AdsRepository(
      ref.watch(dioProvider),
      anonId: () async {
        // Signed in: the server knows who it is.
        if (ref.read(authControllerProvider).valueOrNull?.user != null) return null;
        try {
          return await ref.read(pushServiceProvider).deviceId();
        } catch (_) {
          return null;
        }
      },
    ));

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

/// The same, per slot with each slot's display (AdDisplay draws each slot in
/// its own format).
final servedSlotsProvider = FutureProvider.autoDispose
    .family<List<ServedSlot>, String>((ref, joinedKeys) async {
  final repo = ref.watch(adsRepositoryProvider);
  final loc = ref.watch(locationProvider.select((s) => s.location));
  await repo
      .personalizeIfPermitted(known: loc)
      .timeout(const Duration(seconds: 5), onTimeout: () => false);
  return repo.serveSlots(joinedKeys.split(','));
});
