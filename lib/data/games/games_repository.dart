import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/analytics/device_id.dart';
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

  // Clock actions carry a client action id: a retry on a flaky link is a
  // no-op server-side (docs/design/watch-officiant.md).
  Future<void> start(String gameId) => _post(
      gameId, {'action': 'start', 'actionId': newActionId()},
      fallback: 'Could not start the game.');

  Future<void> complete(String gameId) => _post(
      gameId, {'action': 'complete', 'actionId': newActionId()},
      fallback: 'Could not complete the game.');

  Future<void> abandon(String gameId) => _post(gameId, {'action': 'abandon'},
      fallback: 'Could not abandon the game.');

  Future<void> timer(String gameId, String timerAction, {int? minutes}) =>
      _post(
          gameId,
          {
            'action': 'timer',
            'timerAction': timerAction,
            if (minutes != null) 'minutes': minutes,
            'actionId': newActionId(),
          },
          fallback: 'Clock update failed.');

  Future<void> phase(String gameId, String phaseAction) => _post(
      gameId,
      {'action': 'phase', 'phaseAction': phaseAction, 'actionId': newActionId()},
      fallback: 'Could not change the period.');

  /// Team timeout: 'call' | 'undo' | 'end' (basketball / volleyball).
  Future<void> timeout(String gameId, String teamId, String timeoutAction) =>
      _post(
          gameId,
          {
            'action': 'timeout',
            'teamId': teamId,
            'timeoutAction': timeoutAction
          },
          fallback: 'Could not update the timeout.');

  /// Basketball shot clock: back to the full count, or the short one
  /// ([short]) after an offensive rebound.
  Future<void> shotClock(String gameId, {bool short = false}) => _post(gameId,
      {'action': 'shotClock', 'shotAction': short ? 'resetShort' : 'reset'},
      fallback: 'Could not reset the shot clock.');

  /// Volleyball: 'startNext' (next set) | 'sidesSwitched' (ends changed).
  Future<void> volleyballSet(String gameId, String setAction) =>
      _post(gameId, {'action': 'volleyballSet', 'setAction': setAction},
          fallback: 'Could not update the set.');

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
      _post(
          gameId,
          {
            'action': 'activity',
            'teamId': teamId,
            'type': type,
            'playerId': playerId,
            if (relatedPlayerId != null) 'relatedPlayerId': relatedPlayerId,
            if (minute != null) 'minute': minute,
          },
          fallback: 'Could not record that.');

  /// A completed tournament / league match's MVP vote + awards (raw JSON,
  /// the same shape event_mvp_card.dart reads for events; api games/mvp.ts).
  Future<Map<String, dynamic>> mvpAwards(String gameId) async {
    try {
      final res = await _dio.get('/api/mobile/games/$gameId', queryParameters: {'view': 'mvp'});
      return res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const {};
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the awards.');
    }
  }

  /// Kudos after full time (api games/kudos.ts): who tagged whom, my tag,
  /// whether I can give one, my teammates and the tag list.
  Future<GameKudos> kudos(String gameId) async {
    try {
      final res = await _dio.get('/api/mobile/games/$gameId', queryParameters: {'view': 'kudos'});
      return GameKudos.fromJson(res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const {});
    } catch (e) {
      throw apiError(e, fallback: 'Could not load kudos.');
    }
  }

  Future<void> giveKudos(String gameId, String playerId, String tag) =>
      _post(gameId, {'action': 'kudos', 'playerId': playerId, 'tag': tag},
          fallback: 'Could not send your kudos.');

  Future<void> removeKudos(String gameId) =>
      _post(gameId, {'action': 'removeKudos'}, fallback: 'Could not take that back.');

  /// Anonymous match MVP vote (players and coaches in the match, while open).
  Future<void> voteMvp(String gameId, String playerId) =>
      _post(gameId, {'action': 'voteMvp', 'playerId': playerId},
          fallback: 'Could not save your vote.');

  Future<void> voidActivity(String gameId, String activityId) =>
      _post(gameId, {'action': 'void', 'activityId': activityId},
          fallback: 'Could not delete that entry.');

  /// Correct a recorded stat in place — the type and the moment stay; the
  /// team, player, second player (null clears it) and minute can change.
  Future<void> editActivity(
    String gameId,
    String activityId, {
    required String teamId,
    required String playerId,
    required String? relatedPlayerId,
    int? minute,
    bool minuteEditable = false,
  }) =>
      _post(
          gameId,
          {
            'action': 'editActivity',
            'activityId': activityId,
            'teamId': teamId,
            'playerId': playerId,
            'relatedPlayerId': relatedPlayerId,
            if (minuteEditable) 'minute': minute,
          },
          fallback: 'Could not save that change.');

  Future<void> substitute(
    String gameId, {
    required String teamId,
    required String playerOffId,
    required String playerOnId,
    int? minute,
  }) =>
      _post(
          gameId,
          {
            'action': 'substitute',
            'teamId': teamId,
            'playerOffId': playerOffId,
            'playerOnId': playerOnId,
            if (minute != null) 'minute': minute,
          },
          fallback: 'Substitution failed.');

  /// Pre-kick-off team selection (group admins only). Before a game starts the
  /// line-up IS the team roster, so this moves a player between starters and
  /// bench rather than logging a match substitution. Pass [playerOffId] alone
  /// to bench a starter, [playerOnId] alone to promote a sub, or both to swap.
  Future<void> setLineup(
    String gameId, {
    required String teamId,
    String? playerOffId,
    String? playerOnId,
  }) =>
      _post(
          gameId,
          {
            'action': 'lineup',
            'teamId': teamId,
            if (playerOffId != null) 'playerOffId': playerOffId,
            if (playerOnId != null) 'playerOnId': playerOnId,
          },
          fallback: 'Could not change the line-up.');

  Future<void> takeover(String gameId) => _post(gameId, {'action': 'takeover'},
      fallback: 'Could not take over the scoresheet.');

  // -- Flexible officiants ---------------------------------------------------

  /// Call people in as officiants. Returns (added, requested) — tournament
  /// call-ins are requests the invitee accepts first.
  Future<({int added, int requested})> addOfficiants(
      String gameId, List<String> userIds, String role) async {
    try {
      final res = await _dio.post('/api/mobile/games/$gameId', data: {
        'action': 'addOfficiants',
        'userIds': userIds,
        'role': role,
      });
      final d = res.data is Map ? res.data as Map : const {};
      return (
        added: (d['added'] as num?)?.toInt() ?? 0,
        requested: (d['requested'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      throw apiError(e, fallback: 'Could not call them in.');
    }
  }

  Future<void> setOfficiantRole(String gameId, String userId, String role) =>
      _post(gameId, {'action': 'officiantRole', 'userId': userId, 'role': role},
          fallback: 'Could not change their job.');

  Future<void> removeOfficiant(String gameId, String userId) =>
      _post(gameId, {'action': 'removeOfficiant', 'userId': userId},
          fallback: 'Could not update the officiants.');

  Future<List<OfficiantCandidate>> officiantCandidates(String gameId,
      {String? q}) async {
    try {
      final res = await _dio.get('/api/mobile/games/$gameId/officiants',
          queryParameters: {if (q != null && q.isNotEmpty) 'q': q});
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          if (e is Map)
            OfficiantCandidate.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load people.');
    }
  }

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

/// Someone who could be called in to officiate.
class OfficiantCandidate {
  const OfficiantCandidate({
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.groupAdmin = false,
    this.status,
  });
  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final bool groupAdmin;
  final String? status; // officiating | pending | null

  factory OfficiantCandidate.fromJson(Map<String, dynamic> j) =>
      OfficiantCandidate(
        userId: '${j['userId'] ?? ''}',
        displayName: '${j['displayName'] ?? 'Player'}',
        username: j['username'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        groupAdmin: j['groupAdmin'] == true,
        status: j['status'] as String?,
      );
}


/// A completed tournament / league match's MVP vote + awards.
final gameMvpProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, gameId) =>
        ref.watch(gamesRepositoryProvider).mvpAwards(gameId));


/// Kudos on one game (api games/kudos.ts kudosView).
class GameKudos {
  const GameKudos({
    required this.received,
    required this.mine,
    required this.canGive,
    required this.teammates,
    required this.tags,
  });

  /// playerId → tag → count.
  final Map<String, Map<String, int>> received;
  final ({String toUser, String tag})? mine;
  final bool canGive;
  final List<String> teammates;
  final List<({String key, String label, String icon, String hint})> tags;

  factory GameKudos.fromJson(Map<String, dynamic> j) {
    final rec = <String, Map<String, int>>{};
    if (j['received'] is Map) {
      for (final e in (j['received'] as Map).entries) {
        if (e.value is Map) {
          rec['${e.key}'] = {
            for (final t in (e.value as Map).entries)
              if (t.value is num) '${t.key}': (t.value as num).toInt(),
          };
        }
      }
    }
    final m = j['mine'];
    return GameKudos(
      received: rec,
      mine: m is Map && m['toUser'] is String && m['tag'] is String
          ? (toUser: m['toUser'] as String, tag: m['tag'] as String)
          : null,
      canGive: j['canGive'] == true,
      teammates: [for (final t in (j['teammates'] as List? ?? const [])) '$t'],
      tags: [
        for (final t in (j['tags'] as List? ?? const []))
          if (t is Map)
            (
              key: '${t['key'] ?? ''}',
              label: '${t['label'] ?? ''}',
              icon: '${t['icon'] ?? ''}',
              hint: '${t['hint'] ?? ''}',
            ),
      ],
    );
  }
}

final gameKudosProvider = FutureProvider.autoDispose.family<GameKudos, String>(
    (ref, gameId) => ref.watch(gamesRepositoryProvider).kudos(gameId));
