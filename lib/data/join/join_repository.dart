import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/join/join_models.dart';

class JoinRepository {
  JoinRepository(this._dio);
  final Dio _dio;

  Future<GroupJoinInfo> groupInfo(String id) async {
    try {
      final res = await _dio.get('/api/mobile/join/group/$id');
      if (res.data == null || res.data is! Map) {
        throw ApiException('Group not found.', statusCode: 404);
      }
      return GroupJoinInfo.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load this invite.');
    }
  }

  Future<void> joinGroup(String id) async {
    try {
      await _dio.post('/api/mobile/join/group/$id');
    } catch (e) {
      throw apiError(e, fallback: 'Could not join the group.');
    }
  }

  Future<TeamJoinInfo> teamInfo(String id) async {
    try {
      final res = await _dio.get('/api/mobile/join/team/$id');
      if (res.data == null || res.data is! Map) {
        throw ApiException('Team not found.', statusCode: 404);
      }
      return TeamJoinInfo.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load this invite.');
    }
  }

  Future<void> joinTeam(String id, {int? jerseyNumber}) async {
    try {
      await _dio.post('/api/mobile/join/team/$id',
          data: {'jerseyNumber': jerseyNumber});
    } catch (e) {
      throw apiError(e, fallback: 'Could not join the team.');
    }
  }
}

final joinRepositoryProvider =
    Provider<JoinRepository>((ref) => JoinRepository(ref.watch(dioProvider)));

final groupJoinInfoProvider = FutureProvider.autoDispose
    .family<GroupJoinInfo, String>(
        (ref, id) => ref.watch(joinRepositoryProvider).groupInfo(id));

final teamJoinInfoProvider = FutureProvider.autoDispose
    .family<TeamJoinInfo, String>(
        (ref, id) => ref.watch(joinRepositoryProvider).teamInfo(id));
