import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';

class MembersRepository {
  MembersRepository(this._dio);
  final Dio _dio;

  /// One page of members (infinite scroll), or — with [all] — the WHOLE
  /// roster. Pickers that must offer every member (game officiants) pass
  /// all: true; a page would silently hide members past the first 18.
  Future<MembersPage> forGroup(String groupId,
      {int? cursor, bool all = false}) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$groupId/members',
          queryParameters: all
              ? {'all': 1}
              : (cursor != null ? {'cursor': cursor} : null));
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
  /// Admin: make a member an admin, or an admin a member again.
  Future<void> setRole(String groupId, String userId, String role) async {
    try {
      await _dio.post('/api/mobile/groups/$groupId',
          data: {'action': 'setRole', 'userId': userId, 'role': role});
    } catch (e) {
      throw apiError(e, fallback: 'Could not change the role.');
    }
  }

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

/// The group's full roster — every member, unpaged. Officiant pickers use
/// this so they match the web (groups.membersWithProfiles) and the server's
/// own rule: ANY admin or member of the group may officiate.
final groupAllMembersProvider = FutureProvider.autoDispose
    .family<List<GroupMemberItem>, String>((ref, groupId) async =>
        (await ref.watch(membersRepositoryProvider).forGroup(groupId, all: true))
            .items);

final groupFollowersProvider = FutureProvider.autoDispose
    .family<List<GroupMemberItem>, String>((ref, groupId) =>
        ref.watch(membersRepositoryProvider).followers(groupId));
