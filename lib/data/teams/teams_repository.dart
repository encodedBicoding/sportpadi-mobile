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

  /// What the group may build right now (plan OR promo code) — the same rule
  /// the server enforces on create. See [TeamAllowance].
  Future<TeamAllowance> allowance(String groupId) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$groupId/teams/allowance');
      return TeamAllowance.fromJson(
          res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const {});
    } catch (e) {
      throw apiError(e, fallback: 'Could not check your team allowance.');
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

final teamAllowanceProvider = FutureProvider.autoDispose
    .family<TeamAllowance, String>(
        (ref, groupId) => ref.watch(teamsRepositoryProvider).allowance(groupId));

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

/// Team building for a group: a plan (tier) OR an active promo code grants
///  - BUILD_ONE_TEAM: one team per sport ([canBuild] true, [canBuildMultiple] false)
///  - BUILD_MULTIPLE_TEAMS: any number per sport ([canBuildMultiple] true).
/// [takenCategoryIds] are the sports that already have a team — off the menu
/// on one-per-sport plans. Web reads the same thing (groupTeams.createAllowance).
class TeamAllowance {
  const TeamAllowance({
    this.canBuild = false,
    this.canBuildMultiple = false,
    this.takenCategoryIds = const {},
  });
  final bool canBuild;
  final bool canBuildMultiple;
  final Set<String> takenCategoryIds;

  /// Can this sport take another team?
  bool canAddTo(String categoryId) =>
      canBuild && (canBuildMultiple || !takenCategoryIds.contains(categoryId));

  factory TeamAllowance.fromJson(Map<String, dynamic> j) => TeamAllowance(
        canBuild: j['canBuild'] == true,
        canBuildMultiple: j['canBuildMultiple'] == true,
        takenCategoryIds: {
          for (final x in (j['takenCategoryIds'] is List
              ? j['takenCategoryIds'] as List
              : const []))
            if (x is String) x,
        },
      );
}
