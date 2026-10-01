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

  /// Profile privacy while I'm supervised (claimed under 18). `applies` is
  /// false for everyone else.
  Future<MyPrivacy> myPrivacy() async {
    try {
      final res = await _dio.get('/api/mobile/me/privacy');
      return MyPrivacy.fromJson(res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const <String, dynamic>{});
    } catch (e) {
      throw apiError(e, fallback: 'Could not load your privacy settings.');
    }
  }

  /// Change who sees my profile and/or whether search finds me.
  /// [profilePrivate]: everyone but supervised players — make the public
  /// profile private (or public again).
  Future<void> setMyPrivacy(
      {String? visibility, bool? searchable, bool? profilePrivate}) async {
    try {
      await _dio.post('/api/mobile/me/privacy', data: {
        if (visibility != null) 'visibility': visibility,
        if (searchable != null) 'searchable': searchable,
        if (profilePrivate != null) 'profilePrivate': profilePrivate,
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not save your privacy settings.');
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
  /// Soft-delete the account: PII is wiped, sign-in is disabled everywhere,
  /// historic records render as "Deleted user". Irreversible.
  Future<void> deleteAccount() async {
    try {
      await _dio.post('/api/mobile/me', data: {'action': 'deleteAccount'});
    } catch (e) {
      throw apiError(e, fallback: 'Could not delete the account.');
    }
  }

  // ── Payment methods (cards on file) ──────────────────────────────────

  Future<List<PaymentCard>> cards() async {
    try {
      final res = await _dio.get('/api/mobile/billing');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final c in list)
          PaymentCard.fromJson(Map<String, dynamic>.from(c as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load your cards.');
    }
  }

  /// URL of Stripe's hosted card-setup page (open in browser, then [syncCards]).
  Future<String> startAddCard() async {
    try {
      final res =
          await _dio.post('/api/mobile/billing', data: {'action': 'start'});
      return Map<String, dynamic>.from(res.data as Map)['url'] as String;
    } catch (e) {
      throw apiError(e, fallback: 'Could not start card setup.');
    }
  }

  Future<void> syncCards() async {
    try {
      await _dio.post('/api/mobile/billing', data: {'action': 'sync'});
    } catch (e) {
      throw apiError(e, fallback: 'Could not refresh cards.');
    }
  }

  Future<void> setPrimaryCard(String id) async {
    try {
      await _dio
          .post('/api/mobile/billing', data: {'action': 'primary', 'id': id});
    } catch (e) {
      throw apiError(e, fallback: 'Could not update the card.');
    }
  }

  Future<void> removeCard(String id) async {
    try {
      await _dio
          .post('/api/mobile/billing', data: {'action': 'remove', 'id': id});
    } catch (e) {
      throw apiError(e, fallback: 'Could not remove the card.');
    }
  }

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

final myCardsProvider = FutureProvider.autoDispose<List<PaymentCard>>(
    (ref) => ref.watch(profileRepositoryProvider).cards());

final meProvider = FutureProvider.autoDispose<Profile?>(
    (ref) => ref.watch(profileRepositoryProvider).me());

final sportsSetupProvider = FutureProvider.autoDispose<SportsSetup>(
    (ref) => ref.watch(profileRepositoryProvider).sports());

final attendedEventsProvider = FutureProvider.autoDispose<List<EventSummary>>(
    (ref) => ref.watch(profileRepositoryProvider).attendedEvents());

final myPrivacyProvider = FutureProvider.autoDispose<MyPrivacy>(
    (ref) => ref.watch(profileRepositoryProvider).myPrivacy());
