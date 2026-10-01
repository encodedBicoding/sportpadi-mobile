import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';

class EventsRepository {
  EventsRepository(this._dio);
  final Dio _dio;

  /// Compulsory "balance by attribute" gate. Null on any failure — the event
  /// screen fails open rather than blocking on a network error.
  Future<Map<String, dynamic>?> balanceSetup(String eventId) async {
    try {
      final res = await _dio.get('/api/mobile/balance-setup',
          queryParameters: {'eventId': eventId});
      return res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveBalanceRoles(String categoryId, List<String> roles) async {
    try {
      await _dio.post('/api/mobile/balance-setup',
          data: {'categoryId': categoryId, 'roles': roles});
    } catch (e) {
      throw apiError(e, fallback: "Couldn't save. Try again.");
    }
  }

  Future<List<EventSummary>> discover() async {
    try {
      final res = await _dio.get('/api/mobile/discover');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          EventSummary.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load events.');
    }
  }

  Future<List<EventSummary>> forGroup(String groupId,
      {String scope = 'upcoming'}) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$groupId/events',
          queryParameters: {'scope': scope});
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          EventSummary.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load events.');
    }
  }

  /// Paged per-group events (upcoming or past), mirroring the web events page.
  Future<({List<EventSummary> items, int? nextCursor})> forGroupPaged(
      String groupId,
      {String scope = 'upcoming',
      int? cursor}) async {
    try {
      final res = await _dio
          .get('/api/mobile/groups/$groupId/events-page', queryParameters: {
        'scope': scope,
        if (cursor != null) 'cursor': cursor,
      });
      final d = res.data is Map ? res.data as Map : const {};
      final raw = d['items'];
      return (
        items: raw is List
            ? [
                for (final e in raw)
                  EventSummary.fromJson(Map<String, dynamic>.from(e as Map)),
              ]
            : <EventSummary>[],
        nextCursor: (d['nextCursor'] as num?)?.toInt(),
      );
    } catch (e) {
      throw apiError(e, fallback: 'Could not load events.');
    }
  }

  /// Upcoming events near a point, distance-sorted (web NearMe logic).
  Future<List<EventSummary>> near(
      {required double lat,
      required double lng,
      int radiusMiles = 25,
      String? categoryId}) async {
    try {
      final res = await _dio.get('/api/mobile/events-near', queryParameters: {
        'lat': lat,
        'lng': lng,
        'radius': radiusMiles,
        if (categoryId != null) 'categoryId': categoryId,
      });
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          EventSummary.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load nearby events.');
    }
  }

  Future<EventDetail> bySlug(String slug) async {
    try {
      final res = await _dio.get('/api/mobile/events/$slug');
      if (res.data == null || res.data is! Map) {
        throw ApiException('Event not found.', statusCode: 404);
      }
      return EventDetail.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the event.');
    }
  }

  /// Toggle my interest in an event — or, with [forPlayerId], one of my
  /// wards' (a guardian RSVPing for them). Returns the new state.
  Future<bool> toggleInterest(String eventId, {String? forPlayerId}) async {
    try {
      final res = await _dio.post('/api/mobile/event-actions/$eventId', data: {
        'action': 'interest',
        if (forPlayerId != null) 'forPlayerId': forPlayerId,
      });
      return res.data is Map && (res.data as Map)['interested'] == true;
    } catch (e) {
      throw apiError(e, fallback: 'Could not update interest.');
    }
  }

  /// Teams generated for this event, with player lists.
  Future<List<EventTeam>> teamsForEvent(String eventId) async {
    try {
      final res = await _dio.get('/api/mobile/event-teams',
          queryParameters: {'eventId': eventId});
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final t in list)
          EventTeam.fromJson(Map<String, dynamic>.from(t as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load teams.');
    }
  }

  Future<void> generateTeams(String eventId, {int? teamCount}) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId', data: {
        'action': 'generate-teams',
        if (teamCount != null) 'teamCount': teamCount,
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not generate teams.');
    }
  }

  Future<void> clearTeams(String eventId) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'clear-teams'});
    } catch (e) {
      throw apiError(e, fallback: 'Could not clear teams.');
    }
  }

  Future<void> checkOut(String eventId, {String? playerId}) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId', data: {
        'action': 'check-out',
        if (playerId != null) 'playerId': playerId,
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not check out.');
    }
  }

  /// Dissolve teams and reopen the event (web "Reset teams").
  Future<void> resetTeams(String eventId) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'reset-teams'});
    } catch (e) {
      throw apiError(e, fallback: 'Could not reset teams.');
    }
  }

  Future<void> setEventStatus(String eventId, String status) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'set-status', 'status': status});
    } catch (e) {
      throw apiError(e, fallback: 'Could not update the event.');
    }
  }

  /// Refund sweep status for a cancelled event (organizer only).
  Future<Map<String, dynamic>> refundStatus(String eventId) async {
    try {
      final res = await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'refund-status'});
      return res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const {};
    } catch (e) {
      throw apiError(e, fallback: 'Could not load refund status.');
    }
  }

  /// Retry outstanding refunds on a cancelled event. Idempotent server-side:
  /// per-charge claims + provider idempotency keys mean nobody is refunded
  /// twice, however often this is tapped.
  Future<Map<String, dynamic>> retryRefunds(String eventId) async {
    try {
      final res = await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'retry-refunds'});
      return res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const {};
    } catch (e) {
      throw apiError(e, fallback: 'Could not retry the refunds.');
    }
  }

  /// Close the event; recreate spawns the next occurrence for recurring events.
  /// Cancel (or delete, when no money moved) an event that hasn't completed.
  /// Returns the server summary: {deleted, refunded, failed}.
  Future<Map<String, dynamic>> cancelEvent(String eventId) async {
    try {
      final res = await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'cancel'});
      return res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const {};
    } catch (e) {
      throw apiError(e, fallback: 'Could not cancel the event.');
    }
  }

  Future<void> completeEvent(String eventId, {bool recreate = false}) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'complete', if (recreate) 'recreate': true});
    } catch (e) {
      throw apiError(e, fallback: 'Could not close the event.');
    }
  }

  /// Hosted-by card: whether I follow the group + its follower count.
  Future<({bool following, int followers})> followState(String groupId) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$groupId/follow');
      final d = res.data is Map ? res.data as Map : const {};
      return (
        following: d['following'] == true,
        followers: (d['followers'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      throw apiError(e, fallback: 'Could not load follow state.');
    }
  }

  Future<void> setFollow(String groupId, bool follow) async {
    try {
      await _dio
          .post('/api/mobile/groups/$groupId/follow', data: {'follow': follow});
    } catch (e) {
      throw apiError(e, fallback: 'Could not update follow.');
    }
  }

  /// Player scans an event QR. Returns the outcome status + event title.
  /// [forPlayerId]: a guardian checking in one of their wards.
  Future<Map<String, dynamic>> checkInByQr(String qrCode,
      {String? forPlayerId}) async {
    try {
      final res = await _dio.post('/api/mobile/checkin-qr', data: {
        'qrCode': qrCode,
        if (forPlayerId != null) 'forPlayerId': forPlayerId,
      });
      return res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
    } catch (e) {
      throw apiError(e, fallback: 'Check-in failed.');
    }
  }

  /// Edit core event details (only provided fields change).
  Future<void> updateEvent(String eventId, Map<String, dynamic> patch) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'update', ...patch});
    } catch (e) {
      throw apiError(e, fallback: 'Could not update the event.');
    }
  }

  /// The event's reminder schedule + whether I muted it.
  Future<EventReminders> reminders(String eventId) async {
    try {
      final res = await _dio.get('/api/mobile/event-actions/$eventId',
          queryParameters: {'view': 'reminders'});
      return EventReminders.fromJson(res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const <String, dynamic>{});
    } catch (e) {
      throw apiError(e, fallback: 'Could not load reminders.');
    }
  }

  /// Mute (or unmute) this event's reminders for me.
  Future<void> setRemindersMuted(String eventId, bool muted) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'mute-reminders', 'muted': muted});
    } catch (e) {
      throw apiError(e, fallback: 'Could not update reminders.');
    }
  }

  /// Replace the event's image list (cover must be one of them).
  Future<void> setImages(String eventId, List<String> images,
      {String? thumbnailUrl}) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId', data: {
        'action': 'set-images',
        'images': images,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not save photos.');
    }
  }

  /// Presign + upload an image; returns the public URL to persist.
  Future<String> uploadImage(List<int> bytes, String contentType,
      {String assetType = 'eventImage', String? scopeId}) async {
    try {
      final pre = await _dio.post('/api/mobile/upload-url', data: {
        'assetType': assetType,
        'contentType': contentType,
        if (scopeId != null) 'scopeId': scopeId,
      });
      final d = Map<String, dynamic>.from(pre.data as Map);
      final headers = d['headers'] is Map
          ? Map<String, dynamic>.from(d['headers'] as Map)
          : <String, dynamic>{};
      // Bare client: the presigned URL points at object storage, not our API.
      final put = Dio();
      final res = await put.put<void>(
        d['uploadUrl'] as String,
        data: Stream.fromIterable([bytes]),
        options: Options(
          headers: {...headers, 'Content-Length': bytes.length},
          contentType: contentType,
        ),
      );
      if ((res.statusCode ?? 500) >= 300) {
        throw ApiException('Upload failed.', statusCode: res.statusCode);
      }
      return d['publicUrl'] as String;
    } catch (e) {
      throw apiError(e, fallback: 'Upload failed.');
    }
  }

  /// Late-arrival pool: checked-in players not yet on a team.
  Future<List<PoolPlayer>> availablePool(String eventId) async {
    try {
      final res = await _dio.get('/api/mobile/events-pool',
          queryParameters: {'eventId': eventId});
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          PoolPlayer.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the pool.');
    }
  }

  Future<void> poolAdd(String eventId, String playerId,
      {String? teamId, bool? asSub}) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId', data: {
        'action': 'pool-add',
        'playerId': playerId,
        if (teamId != null) 'teamId': teamId,
        if (asSub != null) 'asSub': asSub,
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not add the player.');
    }
  }

  Future<void> poolAutoAssign(String eventId) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'pool-auto'});
    } catch (e) {
      throw apiError(e, fallback: 'Could not assign the pool.');
    }
  }

  // ---- Captain draft -------------------------------------------------------

  Future<Map<String, dynamic>?> draftGet(String eventId) async {
    try {
      final res = await _dio
          .get('/api/mobile/draft', queryParameters: {'eventId': eventId});
      return res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : null;
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the draft.');
    }
  }

  Future<void> draftStart(String eventId,
      {required int teamCount, int timerSeconds = 0}) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId', data: {
        'action': 'draft-start',
        'teamCount': teamCount,
        'timerSeconds': timerSeconds,
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not start the draft.');
    }
  }

  Future<void> draftPick(String eventId, String playerId) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'draft-pick', 'playerId': playerId});
    } catch (e) {
      throw apiError(e, fallback: 'Could not make that pick.');
    }
  }

  Future<void> draftUndo(String eventId) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'draft-undo'});
    } catch (e) {
      throw apiError(e, fallback: 'Could not undo.');
    }
  }

  Future<void> draftCancel(String eventId) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'draft-cancel'});
    } catch (e) {
      throw apiError(e, fallback: 'Could not cancel the draft.');
    }
  }

  /// SSE ping stream for an event's captain draft — each emission means
  /// "refetch the draft state now".
  Stream<void> draftPings(String eventId) async* {
    final res = await _dio.get<ResponseBody>(
      '/api/mobile/draft-stream/$eventId',
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
        receiveTimeout: Duration.zero,
      ),
    );
    final body = res.data;
    if (body == null) return;
    var buffer = '';
    await for (final chunk in body.stream) {
      buffer += utf8.decode(chunk, allowMalformed: true);
      while (true) {
        final sep = buffer.indexOf('\n\n');
        if (sep < 0) break;
        final frame = buffer.substring(0, sep);
        buffer = buffer.substring(sep + 2);
        if (frame.split('\n').any((l) => l.startsWith('data:'))) {
          yield null;
        }
      }
    }
  }

  /// Create a match from 2+ event teams. Returns the new game id when given.
  /// Paginated Browse grid (optional text + location filter).
  Future<({List<EventSummary> items, int? nextCursor})> browse({
    int cursor = 0,
    int limit = 24,
    String? q,
    String? categoryId,
    bool liveOnly = false,
    bool tournamentsOnly = false,
    double? lat,
    double? lng,
    int? radiusMiles,
  }) async {
    try {
      final res = await _dio.get('/api/mobile/browse', queryParameters: {
        'cursor': cursor,
        'limit': limit,
        if (q != null && q.isNotEmpty) 'q': q,
        if (categoryId != null) 'categoryId': categoryId,
        if (liveOnly) 'live': '1',
        if (tournamentsOnly) 'tournaments': '1',
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (radiusMiles != null) 'radius': radiusMiles,
      });
      final m = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const <String, dynamic>{};
      final list = m['items'] is List ? m['items'] as List : const [];
      return (
        items: [
          for (final e in list)
            EventSummary.fromJson(Map<String, dynamic>.from(e as Map))
        ],
        nextCursor:
            m['nextCursor'] is num ? (m['nextCursor'] as num).toInt() : null,
      );
    } catch (e) {
      throw apiError(e, fallback: 'Could not load events.');
    }
  }

  /// Personal Home feed: upcoming events across the user's groups (live
  /// first) plus their past events.
  Future<({List<EventSummary> upcoming, List<EventSummary> past})>
      myFeed() async {
    try {
      final res = await _dio.get('/api/mobile/home');
      final m = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const <String, dynamic>{};
      List<EventSummary> parse(String key) => m[key] is List
          ? [
              for (final e in m[key] as List)
                EventSummary.fromJson(Map<String, dynamic>.from(e as Map))
            ]
          : const [];
      return (upcoming: parse('upcoming'), past: parse('past'));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load your events.');
    }
  }

  /// "Events for you": upcoming public events in groups the user ISN'T in and
  /// hasn't followed, ranked server-side, each carrying the reason it was
  /// picked. Coordinates are optional — without them the ranking falls back to
  /// sport and recency, so a declined location permission costs a signal, not
  /// the section.
  Future<List<EventSummary>> suggested({
    double? lat,
    double? lng,
    String? categoryId,
    int limit = 8,
  }) async {
    try {
      final res =
          await _dio.get('/api/mobile/events/suggested', queryParameters: {
        'limit': limit,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (categoryId != null) 'categoryId': categoryId,
      });
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          if (e is Map) EventSummary.fromJson(Map<String, dynamic>.from(e))
      ];
    } catch (_) {
      // A suggestion shelf is a bonus, never a reason for Home to fail.
      return const [];
    }
  }

  /// Sports that currently have events (Browse filter chips).
  Future<List<Map<String, dynamic>>> browseCategories() async {
    try {
      final res = await _dio.get('/api/mobile/browse-categories');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          if (e is Map) Map<String, dynamic>.from(e)
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load sports.');
    }
  }

  /// Universal network search: events, groups, players, teams.
  Future<Map<String, dynamic>> searchAll(String q) async {
    try {
      final res =
          await _dio.get('/api/mobile/search-all', queryParameters: {'q': q});
      return res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const <String, dynamic>{};
    } catch (e) {
      throw apiError(e, fallback: 'Search failed.');
    }
  }

  Future<String?> createGame(
    String eventId,
    List<String> teamIds, {
    int? durationMinutes,
    String? homeTeamId,
    Map<String, String> teamColors = const {},
    List<String> officiantIds = const [],
    Map<String, dynamic>? basketball,
    Map<String, dynamic>? volleyball,
  }) async {
    try {
      final attributes = <String, dynamic>{
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        if (homeTeamId != null) 'homeTeamId': homeTeamId,
      };
      final res = await _dio.post('/api/mobile/event-actions/$eventId', data: {
        'action': 'create-game',
        'teamIds': teamIds,
        if (attributes.isNotEmpty) 'attributes': attributes,
        if (teamColors.isNotEmpty)
          'teamColors': [
            for (final e in teamColors.entries)
              {'teamId': e.key, 'color': e.value},
          ],
        if (officiantIds.isNotEmpty) 'officiantIds': officiantIds,
        if (basketball != null) 'basketball': basketball,
        if (volleyball != null) 'volleyball': volleyball,
      });
      return res.data is Map ? (res.data as Map)['id'] as String? : null;
    } catch (e) {
      throw apiError(e, fallback: 'Could not create the match.');
    }
  }

  Future<void> deleteGame(String eventId, String gameId) async {
    try {
      await _dio.post('/api/mobile/event-actions/$eventId',
          data: {'action': 'delete-game', 'gameId': gameId});
    } catch (e) {
      throw apiError(e, fallback: 'Could not delete the game.');
    }
  }
}

final eventsRepositoryProvider = Provider<EventsRepository>(
    (ref) => EventsRepository(ref.watch(dioProvider)));

final discoverProvider = FutureProvider.autoDispose<List<EventSummary>>(
    (ref) => ref.watch(eventsRepositoryProvider).discover());

final myFeedProvider = FutureProvider.autoDispose<
    ({
      List<EventSummary> upcoming,
      List<EventSummary> past
    })>((ref) => ref.watch(eventsRepositoryProvider).myFeed());

/// Suggestions for the Home shelf. Keyed by the optional coordinates + sport
/// so a location fix (or a sport chip) re-ranks rather than re-using a
/// location-blind list.
typedef SuggestedKey = ({double? lat, double? lng, String? categoryId});

final suggestedEventsProvider = FutureProvider.autoDispose
    .family<List<EventSummary>, SuggestedKey>(
        (ref, key) => ref.watch(eventsRepositoryProvider).suggested(
              lat: key.lat,
              lng: key.lng,
              categoryId: key.categoryId,
              limit: 8,
            ));

final browseCategoriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
        (ref) => ref.watch(eventsRepositoryProvider).browseCategories());

final groupEventsProvider = FutureProvider.autoDispose
    .family<List<EventSummary>, String>((ref, groupId) =>
        ref.watch(eventsRepositoryProvider).forGroup(groupId));

final eventDetailProvider = FutureProvider.autoDispose
    .family<EventDetail, String>(
        (ref, slug) => ref.watch(eventsRepositoryProvider).bySlug(slug));

final eventRemindersProvider = FutureProvider.autoDispose
    .family<EventReminders, String>((ref, eventId) =>
        ref.watch(eventsRepositoryProvider).reminders(eventId));

final eventTeamsProvider = FutureProvider.autoDispose
    .family<List<EventTeam>, String>((ref, eventId) =>
        ref.watch(eventsRepositoryProvider).teamsForEvent(eventId));

final availablePoolProvider = FutureProvider.autoDispose
    .family<List<PoolPlayer>, String>((ref, eventId) =>
        ref.watch(eventsRepositoryProvider).availablePool(eventId));

final draftProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, eventId) =>
        ref.watch(eventsRepositoryProvider).draftGet(eventId));
