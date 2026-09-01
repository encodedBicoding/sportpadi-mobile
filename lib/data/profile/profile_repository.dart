import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/profile/profile_models.dart';

class ProfileRepository {
  ProfileRepository(this._dio);
  final Dio _dio;

  Future<Profile?> me() async {
    try {
      final res = await _dio.get('/api/mobile/me');
      final data = res.data;
      if (data == null || data is! Map) return null;
      return Profile.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load your profile.');
    }
  }

  /// Edit display name / username / avatar.
  Future<void> updateMe(Map<String, dynamic> patch) async {
    try {
      await _dio.post('/api/mobile/me', data: patch);
    } catch (e) {
      throw apiError(e, fallback: 'Could not update your profile.');
    }
  }

  /// Categories + my saved sport setups, for the My Sports editor.
  Future<SportsSetup> sports() async {
    try {
      final res = await _dio.get('/api/mobile/me/sports');
      return SportsSetup.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load your sports.');
    }
  }

  Future<void> upsertSport(String categoryId, Map<String, dynamic> answers,
      {List<String> preferredPositions = const []}) async {
    try {
      await _dio.post('/api/mobile/me/sports', data: {
        'action': 'upsert',
        'categoryId': categoryId,
        'extra': answers,
        'preferredPositions': preferredPositions,
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not save that sport.');
    }
  }

  Future<void> removeSport(String categoryId) async {
    try {
      await _dio.post('/api/mobile/me/sports',
          data: {'action': 'remove', 'categoryId': categoryId});
    } catch (e) {
      throw apiError(e, fallback: 'Could not remove that sport.');
    }
  }

  /// Events I checked in to (for the profile Events grid).
  Future<List<EventSummary>> attendedEvents() async {
    try {
      final res = await _dio.get('/api/mobile/me/events');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          EventSummary.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load your events.');
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>(
    (ref) => ProfileRepository(ref.watch(dioProvider)));

final meProvider = FutureProvider.autoDispose<Profile?>(
    (ref) => ref.watch(profileRepositoryProvider).me());

final sportsSetupProvider = FutureProvider.autoDispose<SportsSetup>(
    (ref) => ref.watch(profileRepositoryProvider).sports());

final attendedEventsProvider = FutureProvider.autoDispose<List<EventSummary>>(
    (ref) => ref.watch(profileRepositoryProvider).attendedEvents());
