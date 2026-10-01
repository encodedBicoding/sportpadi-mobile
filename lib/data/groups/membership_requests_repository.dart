import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';

/// Membership requests (`/api/mobile/groups/:id/membership-requests`): a
/// follower asks to join; only the group OWNER sees the queue and decides.
/// Errors carry the server's readable message — callers show `'$e'`.
class MembershipRequestsRepository {
  MembershipRequestsRepository(this._dio);
  final Dio _dio;

  String _path(String groupId) =>
      '/api/mobile/groups/$groupId/membership-requests';

  /// The owner's queue. [status]: `pending` · `approved` · `declined` ·
  /// `all`. Anyone else gets a 403 ([ApiException.statusCode]).
  Future<List<MembershipRequestItem>> list(String groupId,
      {String status = 'pending'}) async {
    try {
      final res = await _dio
          .get(_path(groupId), queryParameters: {'status': status});
      final data = res.data;
      final list = data is List ? data : const [];
      return [
        for (final e in list)
          if (e is Map)
            MembershipRequestItem.fromJson(Map<String, dynamic>.from(e)),
      ].where((r) => r.id.isNotEmpty).toList();
    } catch (e) {
      throw apiError(e, fallback: "Couldn't load membership requests.");
    }
  }

  /// Pending requests, for the owner's badge (0 for everyone else).
  Future<int> pendingCount(String groupId) async {
    try {
      final res = await _dio
          .get(_path(groupId), queryParameters: {'view': 'count'});
      final data = res.data;
      final n = data is Map ? data['pending'] : null;
      return n is num ? n.toInt() : 0;
    } catch (e) {
      throw apiError(e, fallback: "Couldn't load membership requests.");
    }
  }

  /// Ask to join (also follows the group). [message] is optional, ≤300.
  Future<void> request(String groupId, {String? message}) async {
    final m = message?.trim() ?? '';
    try {
      await _dio.post(_path(groupId), data: {
        'action': 'request',
        if (m.isNotEmpty) 'message': m,
      });
    } catch (e) {
      throw apiError(e, fallback: "Couldn't send your request.");
    }
  }

  /// Withdraw my pending request.
  Future<void> cancel(String groupId) async {
    try {
      await _dio.post(_path(groupId), data: {'action': 'cancel'});
    } catch (e) {
      throw apiError(e, fallback: "Couldn't cancel your request.");
    }
  }

  /// Owner: approve (→ member) or decline a request.
  Future<void> decide(String groupId,
      {required String requestId, required bool approve}) async {
    try {
      await _dio.post(_path(groupId), data: {
        'action': 'decide',
        'requestId': requestId,
        'approve': approve,
      });
    } catch (e) {
      throw apiError(e, fallback: "Couldn't save the decision.");
    }
  }
}

final membershipRequestsRepositoryProvider =
    Provider<MembershipRequestsRepository>(
        (ref) => MembershipRequestsRepository(ref.watch(dioProvider)));

/// A tab of the owner's queue.
typedef MembershipRequestsKey = ({String groupId, String status});

/// The owner's membership requests for one status. Invalidate the family
/// (`ref.invalidate(membershipRequestsProvider)`) after a decision.
final membershipRequestsProvider = FutureProvider.autoDispose
    .family<List<MembershipRequestItem>, MembershipRequestsKey>((ref, k) =>
        ref
            .watch(membershipRequestsRepositoryProvider)
            .list(k.groupId, status: k.status));

/// Pending requests waiting on the owner (0 for everyone else).
final membershipRequestCountProvider =
    FutureProvider.autoDispose.family<int, String>((ref, groupId) =>
        ref.watch(membershipRequestsRepositoryProvider).pendingCount(groupId));
