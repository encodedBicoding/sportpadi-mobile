import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/attention/attention_models.dart';

/// `GET /api/mobile/attention` — everything waiting on me, in one call.
class AttentionRepository {
  AttentionRepository(this._dio);
  final Dio _dio;

  Future<AttentionSummary> summary() async {
    try {
      final res = await _dio.get('/api/mobile/attention');
      return res.data is Map
          ? AttentionSummary.fromJson(
              Map<String, dynamic>.from(res.data as Map))
          : AttentionSummary.none;
    } catch (e) {
      throw apiError(e, fallback: "Couldn't load what's waiting for you.");
    }
  }
}

final attentionRepositoryProvider = Provider<AttentionRepository>(
    (ref) => AttentionRepository(ref.watch(dioProvider)));

/// The side-menu button's dot and the menu's row badges. Polled while
/// something watches it (a menu button is on screen), like the bell; also
/// invalidated on app resume, pushes, tab switches, when the menu opens and
/// when a page opened from it closes. Watch `.valueOrNull`: a failed refetch
/// keeps the last counts.
final attentionProvider = FutureProvider.autoDispose<AttentionSummary>((ref) {
  final timer = Timer(const Duration(seconds: 45), () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);
  return ref.watch(attentionRepositoryProvider).summary();
});
