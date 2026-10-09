import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/dio_client.dart';

/// Ad PLACEMENTS — where ads may appear in the app, decided in the owner
/// console (packages/lib/src/adPlacements.ts). The app ships ANCHORS (named
/// points in a screen); this says what fills each: a first-party ad slot
/// (`first_party` + [slotKey]) or AdMob native (`admob_native`). An anchor
/// that isn't listed draws nothing.
///
/// Policy numbers ([firstAfter], [every], [maxPerList]) arrive already
/// clamped by the server; [adRows] applies them the same way the web does.
class AdPlacement {
  const AdPlacement({
    required this.anchor,
    required this.fill,
    required this.slotKey,
    required this.firstAfter,
    required this.every,
    required this.maxPerList,
  });

  final String anchor;

  /// 'first_party' | 'admob_native' (never 'none' — those aren't sent).
  final String fill;
  final String? slotKey;
  final int firstAfter;
  final int every;
  final int maxPerList;

  bool get isFirstParty => fill == 'first_party' && (slotKey ?? '').isNotEmpty;
  bool get isAdMobNative => fill == 'admob_native';

  factory AdPlacement.fromJson(Map<String, dynamic> j) {
    final m = (j['mobile'] as Map?) ?? const {};
    return AdPlacement(
      anchor: j['anchor'] as String? ?? '',
      fill: m['fill'] as String? ?? 'none',
      slotKey: m['slotKey'] as String?,
      firstAfter: (j['firstAfter'] as num?)?.toInt() ?? 4,
      every: (j['every'] as num?)?.toInt() ?? 0,
      maxPerList: (j['maxPerList'] as num?)?.toInt() ?? 1,
    );
  }

  /// Row indexes (0-based) AFTER which an ad goes, for a list of [count]
  /// rows: the first after [firstAfter] rows, then every [every], at most
  /// [maxPerList]. An ad may follow the LAST row (below the content) unless
  /// the list paginates ([hasMore]) — then the last row stays ad-free so
  /// nothing sits beside "load more". Mirrors `adRowsFor` on the web.
  List<int> adRows(int count, {bool hasMore = false}) {
    final out = <int>[];
    if (count <= 0) return out;
    final last = hasMore ? count - 2 : count - 1;
    var i = firstAfter - 1;
    while (i >= 0 && i <= last && out.length < maxPerList) {
      out.add(i);
      if (every <= 0) break;
      i += every;
    }
    return out;
  }
}

class AdPlacements {
  const AdPlacements({required this.version, required this.byAnchor});
  static const empty = AdPlacements(version: 0, byAnchor: {});

  final int version;
  final Map<String, AdPlacement> byAnchor;

  AdPlacement? operator [](String anchor) => byAnchor[anchor];
}

class PlacementsRepository {
  PlacementsRepository(this._dio);
  final Dio _dio;

  Future<AdPlacements> fetch() async {
    final res = await _dio.get('/api/mobile/placements');
    final data = res.data is Map ? res.data as Map : const {};
    final list = (data['placements'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => AdPlacement.fromJson(Map<String, dynamic>.from(m)))
        .where((p) => p.anchor.isNotEmpty && p.fill != 'none');
    return AdPlacements(
      version: (data['version'] as num?)?.toInt() ?? 0,
      byAnchor: {for (final p in list) p.anchor: p},
    );
  }
}

final placementsRepositoryProvider = Provider<PlacementsRepository>(
    (ref) => PlacementsRepository(ref.watch(dioProvider)));

/// The live config: fetched on first use, refreshed every 15 minutes and
/// whenever the app comes back to the foreground after that long. Starts as
/// [AdPlacements.empty] (no ads) until the first answer, and keeps the last
/// good answer across failures — a server blip never flickers ads on/off.
class PlacementsController extends StateNotifier<AdPlacements>
    with WidgetsBindingObserver {
  PlacementsController(this._repo) : super(AdPlacements.empty) {
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(_interval, (_) => _refresh());
  }

  static const _interval = Duration(minutes: 15);
  final PlacementsRepository _repo;
  Timer? _timer;
  DateTime? _fetchedAt;
  bool _busy = false;

  Future<void> _refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final next = await _repo.fetch();
      _fetchedAt = DateTime.now();
      if (next.version != state.version ||
          next.byAnchor.length != state.byAnchor.length) {
        state = next;
      }
    } catch (_) {
      /* keep what we have */
    } finally {
      _busy = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final at = _fetchedAt;
    if (at == null || DateTime.now().difference(at) > _interval) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final placementsProvider =
    StateNotifierProvider<PlacementsController, AdPlacements>(
        (ref) => PlacementsController(ref.watch(placementsRepositoryProvider)));

/// One anchor's placement, or null when the console hasn't set it.
final placementProvider = Provider.family<AdPlacement?, String>(
    (ref, anchor) => ref.watch(placementsProvider)[anchor]);
