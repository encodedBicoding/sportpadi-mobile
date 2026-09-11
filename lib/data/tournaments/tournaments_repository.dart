import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/tournaments/tournament_models.dart';

class TournamentsRepository {
  TournamentsRepository(this._dio);
  final Dio _dio;

  /// Nav-badge probe: any live or upcoming tournament for my teams?
  /// Fails closed (no badge) on any error — never blocks the shell.
  Future<bool> mineHasActive() async {
    try {
      final res = await _dio.get('/api/mobile/my-tournaments',
          queryParameters: {'view': 'flag'});
      return res.data is Map && res.data['active'] == true;
    } catch (_) {
      return false;
    }
  }

  /// "My tournaments" tab — tournaments the signed-in user is in via a
  /// group-team roster spot, with that team's games.
  Future<List<MyTournamentEntry>> mine() async {
    try {
      final res = await _dio.get('/api/mobile/my-tournaments');
      final list = res.data is Map ? (res.data['entries'] as List? ?? []) : const [];
      return [
        for (final e in list)
          MyTournamentEntry.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load your tournaments.');
    }
  }

  Future<List<TournamentSummary>> forGroup(String groupId) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$groupId/tournaments');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          TournamentSummary.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load tournaments.');
    }
  }

  /// The tournament's match game (null until created).
  Future<Map<String, dynamic>?> matchGame(String eventId) async {
    try {
      final res = await _dio.get('/api/mobile/tournaments/$eventId/match');
      return res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : null;
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the match.');
    }
  }

  Future<void> respondOfficiant(
      String eventId, String gameId, bool approve) async {
    try {
      await _dio.post('/api/mobile/tournaments/$eventId/match', data: {
        'action': 'respond',
        'gameId': gameId,
        'decision': approve ? 'approve' : 'reject',
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not respond.');
    }
  }

  Future<void> resetMatch(String eventId) async {
    try {
      await _dio.post('/api/mobile/tournaments/$eventId/match',
          data: {'action': 'reset'});
    } catch (e) {
      throw apiError(e, fallback: 'Could not reset the match.');
    }
  }

  /// All match games of a multi-team / league tournament.
  Future<List<Map<String, dynamic>>> listGames(String eventId) async {
    try {
      final res = await _dio.get('/api/mobile/tournaments/$eventId/games');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          if (e is Map) Map<String, dynamic>.from(e)
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the matches.');
    }
  }

  /// Provisional / final tournament awards.
  Future<Map<String, dynamic>?> awards(String eventId) async {
    try {
      final res = await _dio.get('/api/mobile/tournaments/$eventId/awards');
      return res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : null;
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the awards.');
    }
  }

  Future<void> _act(String eventId, Map<String, dynamic> body,
      {required String fallback}) async {
    try {
      await _dio.post('/api/mobile/tournaments/$eventId', data: body);
    } catch (e) {
      throw apiError(e, fallback: fallback);
    }
  }

  Future<void> cancelTournament(String eventId) => _act(
      eventId, {'action': 'cancel'},
      fallback: 'Could not cancel the tournament.');

  Future<void> refundFee(String eventId, String tournamentTeamId) => _act(
      eventId, {'action': 'refundFee', 'tournamentTeamId': tournamentTeamId},
      fallback: 'Could not refund the fee.');

  Future<void> inviteTeam(String eventId, String teamId) => _act(
      eventId, {'action': 'inviteTeam', 'teamId': teamId},
      fallback: 'Could not invite the team.');

  Future<void> createMatch(String eventId, Map<String, dynamic> body) => _act(
      eventId, {'action': 'createMatch', ...body},
      fallback: 'Could not create the match game.');

  Future<void> schedule(String eventId, String gameId,
          {String? date, String? time}) =>
      _act(eventId, {
        'action': 'schedule',
        'gameId': gameId,
        'scheduledDate': date,
        'scheduledTime': time,
      }, fallback: 'Could not update the kickoff.');

  Future<void> subOffStarter(String eventId,
          {required String gameId,
          required String teamId,
          required String playerId,
          String? swapInPlayerId}) =>
      _act(eventId, {
        'action': 'subOff',
        'gameId': gameId,
        'teamId': teamId,
        'playerId': playerId,
        if (swapInPlayerId != null) 'swapInPlayerId': swapInPlayerId,
      }, fallback: 'Could not update the line-up.');

  Future<Map<String, dynamic>> get(String eventId) async {
    try {
      final res = await _dio.get('/api/mobile/tournaments/$eventId');
      if (res.data == null || res.data is! Map) {
        throw ApiException('Tournament not found.', statusCode: 404);
      }
      return Map<String, dynamic>.from(res.data as Map);
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the tournament.');
    }
  }
}

final tournamentsRepositoryProvider = Provider<TournamentsRepository>(
    (ref) => TournamentsRepository(ref.watch(dioProvider)));

final groupTournamentsProvider = FutureProvider.autoDispose
    .family<List<TournamentSummary>, String>((ref, groupId) =>
        ref.watch(tournamentsRepositoryProvider).forGroup(groupId));

final tournamentDetailProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, eventId) =>
        ref.watch(tournamentsRepositoryProvider).get(eventId));

final tournamentMatchProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, eventId) =>
        ref.watch(tournamentsRepositoryProvider).matchGame(eventId));

final tournamentGamesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, eventId) =>
        ref.watch(tournamentsRepositoryProvider).listGames(eventId));

final tournamentAwardsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, eventId) =>
        ref.watch(tournamentsRepositoryProvider).awards(eventId));

final myTournamentsProvider =
    FutureProvider.autoDispose<List<MyTournamentEntry>>(
        (ref) => ref.watch(tournamentsRepositoryProvider).mine());

/// Drives the dot on the Tournaments bottom-nav item (a dot, never a count).
final myTournamentsActiveProvider = FutureProvider.autoDispose<bool>(
    (ref) => ref.watch(tournamentsRepositoryProvider).mineHasActive());
