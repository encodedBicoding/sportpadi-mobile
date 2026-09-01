import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/games/game_models.dart';

/// Live games over the REST bridge (`/api/mobile/games…`), which reuses the
/// backend tRPC games router. Realtime updates arrive over the SSE stream at
/// /api/mobile/games/:id/stream — each event is a ping meaning "refetch now".
class GamesRepository {
  GamesRepository(this._dio);
  final Dio _dio;

  Future<List<GameSummary>> forEvent(String eventId) async {
    try {
      final res = await _dio
          .get('/api/mobile/games', queryParameters: {'eventId': eventId});
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          GameSummary.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load games.');
    }
  }

  Future<GameDetail> game(String gameId) async {
    try {
      final res = await _dio.get('/api/mobile/games/$gameId');
      if (res.data is! Map) {
        throw ApiException('Game not found.', statusCode: 404);
      }
      return GameDetail.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the game.');
    }
  }

  Future<void> _post(String gameId, Map<String, dynamic> body,
      {required String fallback}) async {
    try {
      await _dio.post('/api/mobile/games/$gameId', data: body);
    } catch (e) {
      throw apiError(e, fallback: fallback);
    }
  }

  Future<void> start(String gameId) =>
      _post(gameId, {'action': 'start'}, fallback: 'Could not start the game.');

  Future<void> complete(String gameId) => _post(gameId, {'action': 'complete'},
      fallback: 'Could not complete the game.');

  Future<void> abandon(String gameId) => _post(gameId, {'action': 'abandon'},
      fallback: 'Could not abandon the game.');

  Future<void> timer(String gameId, String timerAction, {int? minutes}) =>
      _post(gameId, {
        'action': 'timer',
        'timerAction': timerAction,
        if (minutes != null) 'minutes': minutes,
      }, fallback: 'Clock update failed.');

  Future<void> phase(String gameId, String phaseAction) => _post(
      gameId, {'action': 'phase', 'phaseAction': phaseAction},
      fallback: 'Could not change the period.');

  Future<void> shootout(String gameId, String teamId, String outcome) => _post(
      gameId, {'action': 'shootout', 'teamId': teamId, 'outcome': outcome},
      fallback: 'Could not record the penalty.');

  Future<void> addActivity(
    String gameId, {
    required String teamId,
    required String type,
    required String playerId,
    String? relatedPlayerId,
    int? minute,
  }) =>
      _post(gameId, {
        'action': 'activity',
        'teamId': teamId,
        'type': type,
        'playerId': playerId,
        if (relatedPlayerId != null) 'relatedPlayerId': relatedPlayerId,
        if (minute != null) 'minute': minute,
      }, fallback: 'Could not record that.');

  Future<void> voidActivity(String gameId, String activityId) => _post(
      gameId, {'action': 'void', 'activityId': activityId},
      fallback: 'Could not void that entry.');

  Future<void> substitute(
    String gameId, {
    required String teamId,
    required String playerOffId,
    required String playerOnId,
    int? minute,
  }) =>
      _post(gameId, {
        'action': 'substitute',
        'teamId': teamId,
        'playerOffId': playerOffId,
        'playerOnId': playerOnId,
        if (minute != null) 'minute': minute,
      }, fallback: 'Substitution failed.');

  Future<void> takeover(String gameId) => _post(gameId, {'action': 'takeover'},
      fallback: 'Could not take over the scoresheet.');

  /// Open the SSE ping stream for a game. Emits once per published update;
  /// the caller refetches [game] on each emission. Closes on error — the
  /// controller reconnects with backoff while the screen is open.
  Stream<void> pings(String gameId) async* {
    final res = await _dio.get<ResponseBody>(
      '/api/mobile/games/$gameId/stream',
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
        // The default receiveTimeout would kill a long-lived stream.
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
        // Only data frames count; comments (": ping") are keepalives.
        if (frame.split('\n').any((l) => l.startsWith('data:'))) {
          yield null;
        }
      }
    }
  }
}

final gamesRepositoryProvider =
    Provider<GamesRepository>((ref) => GamesRepository(ref.watch(dioProvider)));

final eventGamesProvider = FutureProvider.autoDispose
    .family<List<GameSummary>, String>(
        (ref, eventId) => ref.watch(gamesRepositoryProvider).forEvent(eventId));
