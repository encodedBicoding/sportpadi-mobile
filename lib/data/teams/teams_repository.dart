import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';

class TeamsRepository {
  TeamsRepository(this._dio);
  final Dio _dio;

  Future<List<TeamSummary>> forGroup(String groupId) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$groupId/teams');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          TeamSummary.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load teams.');
    }
  }

  Future<TeamDetail> get(String teamId) async {
    try {
      final res = await _dio.get('/api/mobile/teams/$teamId');
      if (res.data == null || res.data is! Map) {
        throw ApiException('Team not found.', statusCode: 404);
      }
      return TeamDetail.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the team.');
    }
  }

  Future<TeamCoaches> coaches(String teamId) async {
    try {
      final res = await _dio.get('/api/mobile/teams/$teamId/coaches');
      return TeamCoaches.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load coaches.');
    }
  }

  Future<void> addCoach(String teamId, String userId, String role) async {
    try {
      await _dio.post('/api/mobile/teams/$teamId/coaches',
          data: {'userId': userId, 'role': role});
    } catch (e) {
      throw apiError(e, fallback: 'Could not add the coach.');
    }
  }

  Future<void> removeCoach(String teamId, String coachId) async {
    try {
      await _dio.delete('/api/mobile/teams/$teamId/coaches',
          data: {'coachId': coachId});
    } catch (e) {
      throw apiError(e, fallback: 'Could not remove the coach.');
    }
  }

  Future<List<TeamGame>> recentGames(String teamId, {int months = 6}) async {
    try {
      final res = await _dio.get('/api/mobile/teams/$teamId/games',
          queryParameters: {'months': months});
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final g in list)
          TeamGame.fromJson(Map<String, dynamic>.from(g as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load games.');
    }
  }

  Future<PlayerCard> playerCard(String teamId, String playerId) async {
    try {
      final res = await _dio.get('/api/mobile/teams/$teamId/player',
          queryParameters: {'playerId': playerId});
      return PlayerCard.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the player.');
    }
  }

  Future<TeamStats> stats(String teamId) async {
    try {
      final res = await _dio.get('/api/mobile/teams/$teamId/stats');
      return TeamStats.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load stats.');
    }
  }
}


final teamsRepositoryProvider =
    Provider<TeamsRepository>((ref) => TeamsRepository(ref.watch(dioProvider)));

final groupTeamsProvider = FutureProvider.autoDispose
    .family<List<TeamSummary>, String>(
        (ref, groupId) => ref.watch(teamsRepositoryProvider).forGroup(groupId));

final teamDetailProvider = FutureProvider.autoDispose
    .family<TeamDetail, String>(
        (ref, teamId) => ref.watch(teamsRepositoryProvider).get(teamId));

final teamCoachesProvider = FutureProvider.autoDispose
    .family<TeamCoaches, String>(
        (ref, teamId) => ref.watch(teamsRepositoryProvider).coaches(teamId));

final teamGamesProvider = FutureProvider.autoDispose
    .family<List<TeamGame>, String>(
        (ref, teamId) => ref.watch(teamsRepositoryProvider).recentGames(teamId));

final teamStatsProvider = FutureProvider.autoDispose.family<TeamStats, String>(
    (ref, teamId) => ref.watch(teamsRepositoryProvider).stats(teamId));

final playerCardProvider = FutureProvider.autoDispose
    .family<PlayerCard, ({String teamId, String playerId})>((ref, key) => ref
        .watch(teamsRepositoryProvider)
        .playerCard(key.teamId, key.playerId));
