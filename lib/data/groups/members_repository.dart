import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';

class MembersRepository {
  MembersRepository(this._dio);
  final Dio _dio;

  Future<MembersPage> forGroup(String groupId, {int? cursor}) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$groupId/members',
          queryParameters: cursor != null ? {'cursor': cursor} : null);
      return MembersPage.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load members.');
    }
  }

  /// The group's followers (admin only — the server enforces it).
  Future<List<GroupMemberItem>> followers(String groupId) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$groupId/followers');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          GroupMemberItem.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load followers.');
    }
  }

  /// Promote followers into members (admin only).
  Future<void> promoteFollowers(String groupId, List<String> userIds) async {
    try {
      await _dio.post('/api/mobile/groups/$groupId/followers',
          data: {'userIds': userIds});
    } catch (e) {
      throw apiError(e, fallback: 'Could not promote.');
    }
  }
}

final membersRepositoryProvider = Provider<MembersRepository>(
    (ref) => MembersRepository(ref.watch(dioProvider)));

final groupMembersProvider = FutureProvider.autoDispose
    .family<MembersPage, String>((ref, groupId) =>
        ref.watch(membersRepositoryProvider).forGroup(groupId));

final groupFollowersProvider = FutureProvider.autoDispose
    .family<List<GroupMemberItem>, String>((ref, groupId) =>
        ref.watch(membersRepositoryProvider).followers(groupId));
