import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';

/// Reads groups over the REST bridge (`/api/mobile/groups`), which reuses the
/// backend tRPC procedures `groups.mineDetailed` and `groups.get` behind bearer
/// auth. See sportpadi-workspace: apps/web/src/app/api/mobile/.
class GroupsRepository {
  GroupsRepository(this._dio);

  final Dio _dio;

  Future<List<GroupSummary>> myGroups() async {
    try {
      final res = await _dio.get('/api/mobile/groups');
      final data = res.data;
      final list = data is List
          ? data
          : (data is Map && data['items'] is List
              ? data['items'] as List
              : const []);
      return [
        for (final e in list)
          GroupSummary.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<List<GroupSummary>> discoverGroups() async {
    try {
      final res = await _dio.get('/api/mobile/groups/discover');
      final data = res.data;
      final list = data is List
          ? data
          : (data is Map && data['items'] is List
              ? data['items'] as List
              : const []);
      return [
        for (final e in list)
          GroupSummary.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// Create a group (creator becomes admin). Returns the new group id.
  Future<String> createGroup(String name, String? description) async {
    try {
      final res = await _dio.post('/api/mobile/groups', data: {
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
      });
      final data = res.data;
      return (data is Map ? data['id'] : null) as String? ?? '';
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// Admin: edit name / description / images.
  Future<void> updateGroup(String groupId, Map<String, dynamic> patch) async {
    try {
      await _dio.post('/api/mobile/groups/$groupId',
          data: {'action': 'update', ...patch});
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<void> inviteUser(String groupId, String userId) async {
    try {
      await _dio.post('/api/mobile/groups/$groupId',
          data: {'action': 'invite', 'userId': userId});
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// Group invitations I've received (an admin invited me), newest first,
  /// a page at a time. [groupId] narrows to one group (its page's banner).
  Future<InvitationsPage> invitationsPage({int? cursor, String? groupId}) async {
    try {
      final res = await _dio.get('/api/mobile/groups/invitations', queryParameters: {
        'page': 1,
        if (cursor != null) 'cursor': cursor,
        if (groupId != null) 'groupId': groupId,
      });
      return InvitationsPage.fromJson(
          res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const {});
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// How many invitations are waiting for me (the Invites tab badge).
  Future<int> invitationCount() async {
    try {
      final res = await _dio.get('/api/mobile/groups/invitations',
          queryParameters: {'count': 1});
      final m = res.data is Map ? res.data as Map : const {};
      final n = m['count'];
      return n is num ? n.toInt() : 0;
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// Accept (join the group) or decline an invitation.
  Future<void> respondInvitation(String invitationId, bool accept) async {
    try {
      await _dio.post('/api/mobile/groups/invitations',
          data: {'invitationId': invitationId, 'accept': accept});
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// Search profiles by name / @handle (for invites).
  Future<List<GroupMemberItem>> searchUsers(String query) async {
    try {
      final res = await _dio
          .get('/api/mobile/users/search', queryParameters: {'q': query});
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          GroupMemberItem.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<List<Map<String, dynamic>>> leaderboardCategories(
      String groupId) async {
    try {
      final res =
          await _dio.get('/api/mobile/groups/$groupId/leaderboard-categories');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          if (e is Map) Map<String, dynamic>.from(e)
      ];
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// The group's player board for one sport; [ageBand] is one of
  /// `all | u12 | u16 | u18 | adults` (by date of birth).
  Future<List<LeaderboardRow>> leaderboard(String groupId,
      {String? categoryId, String ageBand = 'all'}) async {
    try {
      final res = await _dio
          .get('/api/mobile/groups/$groupId/leaderboard', queryParameters: {
        if (categoryId != null) 'categoryId': categoryId,
        if (ageBand != 'all') 'ageBand': ageBand,
      });
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          LeaderboardRow.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<GroupOverview> overview(String groupId) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$groupId/overview');
      return GroupOverview.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  /// Badges for the group page's Talk tiles — or, with [teamId], the team
  /// page's (only that team's announcements, coach threads and discussions).
  Future<GroupTalkCounts> talkCounts(String groupId, {String? teamId}) async {
    try {
      final res = await _dio.get(
        '/api/mobile/groups/$groupId/talk-counts',
        queryParameters: {if (teamId != null) 'teamId': teamId},
      );
      return res.data is Map
          ? GroupTalkCounts.fromJson(Map<String, dynamic>.from(res.data as Map))
          : GroupTalkCounts.none;
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  Future<GroupDetail> group(String id) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$id');
      return GroupDetail.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw _err(e);
    }
  }

  ApiException _err(DioException e) {
    if (e.response?.statusCode == 404) {
      return ApiException('Group not found.', statusCode: 404);
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return ApiException('Can\'t reach the server.', statusCode: null);
    }
    return ApiException('Could not load groups.',
        statusCode: e.response?.statusCode);
  }
}

final groupsRepositoryProvider = Provider<GroupsRepository>(
    (ref) => GroupsRepository(ref.watch(dioProvider)));

final groupLeaderboardProvider = FutureProvider.autoDispose.family<
        List<LeaderboardRow>,
        ({String groupId, String? categoryId, String ageBand})>(
    (ref, a) => ref
        .watch(groupsRepositoryProvider)
        .leaderboard(a.groupId, categoryId: a.categoryId, ageBand: a.ageBand));

/// Sport categories this group has completed games in (board switcher).
final groupLeaderboardCategoriesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, groupId) async {
  final res =
      await ref.watch(groupsRepositoryProvider).leaderboardCategories(groupId);
  return res;
});

final groupOverviewProvider = FutureProvider.autoDispose
    .family<GroupOverview, String>((ref, groupId) =>
        ref.watch(groupsRepositoryProvider).overview(groupId));

/// What's new for me in a group's Talk tiles (announcements, messages,
/// discussions). The group page invalidates it on app resume, when it's back
/// on top and when a Talk sheet closes.
final groupTalkCountsProvider = FutureProvider.autoDispose
    .family<GroupTalkCounts, String>((ref, groupId) =>
        ref.watch(groupsRepositoryProvider).talkCounts(groupId));

typedef TeamTalkKey = ({String groupId, String teamId});

/// The team page's Talk badges: the same counts, for one team. Re-read like
/// the group's — on resume, back on top, and when a Talk sheet closes.
final teamTalkCountsProvider = FutureProvider.autoDispose
    .family<GroupTalkCounts, TeamTalkKey>((ref, k) => ref
        .watch(groupsRepositoryProvider)
        .talkCounts(k.groupId, teamId: k.teamId));

/// How many group invitations are waiting for me — the Invites tab badge.
/// Invalidate it whenever invitations may have changed (it also bumps the
/// tab's list, which watches it).
final groupInvitationCountProvider = FutureProvider.autoDispose<int>(
    (ref) => ref.watch(groupsRepositoryProvider).invitationCount());

/// My pending invitation to one group, if any (the banner on its page).
final groupInviteForProvider = FutureProvider.autoDispose
    .family<GroupInvitation?, String>((ref, groupId) async {
  final page = await ref
      .watch(groupsRepositoryProvider)
      .invitationsPage(groupId: groupId);
  return page.items.isEmpty ? null : page.items.first;
});

/// Ask the Groups tab to open a section (2 = Invites) — set by the
/// "You've been invited" notification, read and cleared by the tab.
final groupsTabRequestProvider = StateProvider<int?>((_) => null);
