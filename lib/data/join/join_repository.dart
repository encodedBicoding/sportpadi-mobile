import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/join/join_models.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Join links carry a secret code (`/join/<code>`, `/join-team/<code>`), and
/// that code is what these calls send. An id there never joins anyone: the
/// server answers 412 (review H2), and the router opens the group / team
/// page for an id before any of this is asked.
class JoinRepository {
  JoinRepository(this._dio);
  final Dio _dio;

  /// null = not a live link (unknown, reset, or the group's gone): the
  /// screen says so honestly, with no Retry that could never help.
  Future<GroupJoinInfo?> groupInfo(String code) async {
    try {
      final res = await _dio.get('/api/mobile/join/group/${Uri.encodeComponent(code)}');
      if (res.data == null || res.data is! Map) return null;
      return GroupJoinInfo.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load this invite.');
    }
  }

  /// Joins by the code; the group's id, for the page to open next.
  Future<String?> joinGroup(String code) async {
    try {
      final res = await _dio.post('/api/mobile/join/group/${Uri.encodeComponent(code)}');
      final d = res.data;
      return d is Map && d['groupId'] is String ? d['groupId'] as String : null;
    } catch (e) {
      throw apiError(e, fallback: 'Could not join the group.');
    }
  }

  /// null = not a live link (as [groupInfo]).
  Future<TeamJoinInfo?> teamInfo(String code) async {
    try {
      final res = await _dio.get('/api/mobile/join/team/${Uri.encodeComponent(code)}');
      if (res.data == null || res.data is! Map) return null;
      return TeamJoinInfo.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load this invite.');
    }
  }

  /// Joins by the code; the team's id, for the page to open next.
  Future<String?> joinTeam(String code, {int? jerseyNumber}) async {
    try {
      final res = await _dio.post('/api/mobile/join/team/${Uri.encodeComponent(code)}',
          data: {'jerseyNumber': jerseyNumber});
      final d = res.data;
      return d is Map && d['teamId'] is String ? d['teamId'] as String : null;
    } catch (e) {
      throw apiError(e, fallback: 'Could not join the team.');
    }
  }

  /// The group's admins: the secret link (made on first use).
  Future<InviteLink> inviteLink(InviteScope scope) async {
    try {
      final res = await _dio.get(scope.apiPath);
      return InviteLink.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: l10n.share_couldntLoadInviteLink);
    }
  }

  /// The group's admins: a new code — the old link stops working at once.
  Future<InviteLink> resetInviteLink(InviteScope scope) async {
    try {
      final res = await _dio.post(scope.apiPath, data: {'action': 'reset'});
      return InviteLink.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: l10n.share_couldntResetLink);
    }
  }
}

final joinRepositoryProvider =
    Provider<JoinRepository>((ref) => JoinRepository(ref.watch(dioProvider)));

final groupJoinInfoProvider = FutureProvider.autoDispose
    .family<GroupJoinInfo?, String>(
        (ref, id) => ref.watch(joinRepositoryProvider).groupInfo(id));

final teamJoinInfoProvider = FutureProvider.autoDispose
    .family<TeamJoinInfo?, String>(
        (ref, id) => ref.watch(joinRepositoryProvider).teamInfo(id));
