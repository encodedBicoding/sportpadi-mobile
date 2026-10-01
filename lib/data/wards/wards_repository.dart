import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/wards/ward_models.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Wards REST bridge (`/api/mobile/wards`). A guardian creates, edits and
/// shares the running of player accounts that have no login of their own.
class WardsRepository {
  WardsRepository(this._dio);
  final Dio _dio;

  /// My wards, plus co-guardian invitations waiting for my answer.
  Future<WardsOverview> mine() async {
    try {
      final res = await _dio.get('/api/mobile/wards');
      return WardsOverview.fromJson(res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const <String, dynamic>{});
    } catch (e) {
      throw apiError(e, fallback: "Couldn't load your wards.");
    }
  }

  /// One ward with its guardians (active and invited).
  Future<WardDetail> get(String wardId) async {
    try {
      final res =
          await _dio.get('/api/mobile/wards', queryParameters: {'id': wardId});
      if (res.data is! Map) {
        throw ApiException('Ward not found.', statusCode: 404);
      }
      return WardDetail.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: "Couldn't load this ward.");
    }
  }

  Future<Map<String, dynamic>> _post(
      Map<String, dynamic> body, String fallback) async {
    try {
      final res = await _dio.post('/api/mobile/wards', data: body);
      return res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
    } catch (e) {
      throw apiError(e, fallback: fallback);
    }
  }

  /// Create a ward. The caller has already ticked the ward-terms consent.
  /// Returns the new ward's user id.
  Future<String> create({
    required String firstName,
    required String lastName,
    required String dateOfBirth,
    String? gender,
    required String relationship,
    String? avatarUrl,
  }) async {
    final r = await _post({
      'action': 'create',
      'firstName': firstName,
      'lastName': lastName,
      'dateOfBirth': dateOfBirth,
      'gender': gender,
      'relationship': relationship,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      'consent': true,
    }, "Couldn't add the ward.");
    return parseStr(r['wardId']) ?? '';
  }

  /// Edit a ward's profile, privacy, or my relationship to them. Only the
  /// keys in [patch] change (`gender`/`avatarUrl` may be null to clear).
  Future<void> update(String wardId, Map<String, dynamic> patch) async {
    await _post({'action': 'update', 'wardId': wardId, ...patch},
        "Couldn't save the changes.");
  }

  /// Invite another SportPadi user to co-guardian. Returns true when they'd
  /// already been invited (nothing new was sent).
  Future<bool> invite(String wardId, String userId, String relationship) async {
    final r = await _post({
      'action': 'invite',
      'wardId': wardId,
      'userId': userId,
      'relationship': relationship,
    }, "Couldn't send the invitation.");
    return r['alreadyInvited'] == true;
  }

  /// Accept (which is my consent) or decline a co-guardian invitation.
  Future<void> respond(String wardId, {required bool accept}) async {
    await _post({'action': 'respond', 'wardId': wardId, 'accept': accept},
        "Couldn't answer the invitation.");
  }

  Future<void> cancelInvite(String wardId, String userId) async {
    await _post({'action': 'cancel-invite', 'wardId': wardId, 'userId': userId},
        "Couldn't cancel the invitation.");
  }

  /// Stop being a guardian. The server refuses when I'm the only one.
  Future<void> leave(String wardId) async {
    await _post({'action': 'leave', 'wardId': wardId},
        "Couldn't remove you as a guardian.");
  }

  /// The ward's groups (with their teams there) and mine they could join.
  Future<WardGroups> groups(String wardId) async {
    try {
      final res = await _dio.get('/api/mobile/wards',
          queryParameters: {'id': wardId, 'view': 'groups'});
      return WardGroups.fromJson(res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const <String, dynamic>{});
    } catch (e) {
      throw apiError(e, fallback: "Couldn't load their groups.");
    }
  }

  /// Add the ward to one of my groups. Returns true when they were already
  /// a member.
  Future<bool> joinGroup(String wardId, String groupId) async {
    final r = await _post(
        {'action': 'join-group', 'wardId': wardId, 'groupId': groupId},
        "Couldn't add them to the group.");
    return r['alreadyMember'] == true;
  }

  /// Take the ward out of a group (and its teams there).
  Future<void> leaveGroup(String wardId, String groupId) async {
    await _post({'action': 'leave-group', 'wardId': wardId, 'groupId': groupId},
        "Couldn't remove them from the group.");
  }

  /// Team invitations waiting on me — for every ward, or just [wardId].
  Future<List<WardTeamInvite>> teamInvites({String? wardId}) async {
    try {
      final res = await _dio.get('/api/mobile/wards', queryParameters: {
        'view': 'team-invites',
        if (wardId != null) 'id': wardId,
      });
      final data = res.data;
      if (data is! List) return const [];
      return [
        for (final e in data)
          if (e is Map) WardTeamInvite.fromJson(Map<String, dynamic>.from(e))
      ];
    } catch (e) {
      throw apiError(e, fallback: "Couldn't load team invitations.");
    }
  }

  /// Accept (put the ward on the team) or decline a team invitation.
  Future<WardTeamInviteResult> respondTeamInvite(String inviteId,
      {required bool accept}) async {
    final r = await _post({
      'action': 'respond-team-invite',
      'inviteId': inviteId,
      'accept': accept
    }, "Couldn't answer the invitation.");
    return WardTeamInviteResult.fromJson(r);
  }

  // ── Handing the account over (Wards 3, A11) ──────────────────────────

  /// Send (or re-send) the hand-over link to the ward's own [email]. Starting
  /// again replaces any earlier link. The server explains every refusal
  /// (address already has an account, too many links today, under 15).
  Future<WardClaim?> startClaim(String wardId, String email) async {
    final r = await _post(
        {'action': 'start-claim', 'wardId': wardId, 'email': email.trim()},
        "Couldn't send the link.");
    return WardClaim.fromJson(r);
  }

  /// Withdraw the pending hand-over link.
  Future<void> cancelClaim(String wardId) async {
    await _post({'action': 'cancel-claim', 'wardId': wardId},
        "Couldn't cancel the link.");
  }

  /// PUBLIC: what the emailed `/claim/<token>` link is for (no sign-in — the
  /// token is the credential). A malformed or unknown token reads as
  /// "invalid" rather than an error.
  Future<ClaimInfo> claimInfo(String token) async {
    try {
      final res = await _dio
          .get('/api/mobile/claim', queryParameters: {'token': token});
      if (res.data is! Map) return ClaimInfo.invalid;
      return ClaimInfo.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400 || status == 404) return ClaimInfo.invalid;
      throw apiError(e, fallback: "Couldn't open this link.");
    } catch (e) {
      throw apiError(e, fallback: "Couldn't open this link.");
    }
  }

  /// PUBLIC: choose a password — the account becomes the ward's. Returns the
  /// email to sign in with, and whether a guardian stays on supervising.
  Future<({String email, bool supervised})> completeClaim(
      String token, String password) async {
    try {
      final res = await _dio.post('/api/mobile/claim',
          data: {'token': token, 'password': password});
      final d = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const <String, dynamic>{};
      return (
        email: parseStr(d['email']) ?? '',
        supervised: d['supervised'] == true,
      );
    } catch (e) {
      throw apiError(e, fallback: "Couldn't set up the account.");
    }
  }

  /// Delete the ward's account. [confirmName] must match their name.
  Future<void> delete(String wardId, String confirmName) async {
    await _post(
        {'action': 'delete', 'wardId': wardId, 'confirmName': confirmName},
        "Couldn't delete the ward.");
  }
}

final wardsRepositoryProvider =
    Provider<WardsRepository>((ref) => WardsRepository(ref.watch(dioProvider)));

final myWardsProvider = FutureProvider.autoDispose<WardsOverview>(
    (ref) => ref.watch(wardsRepositoryProvider).mine());

final wardDetailProvider = FutureProvider.autoDispose
    .family<WardDetail, String>(
        (ref, wardId) => ref.watch(wardsRepositoryProvider).get(wardId));

final wardGroupsProvider = FutureProvider.autoDispose
    .family<WardGroups, String>(
        (ref, wardId) => ref.watch(wardsRepositoryProvider).groups(wardId));

/// Team invitations for my wards: pass a ward id for one ward, or '' for all.
final wardTeamInvitesProvider = FutureProvider.autoDispose
    .family<List<WardTeamInvite>, String>((ref, wardId) => ref
        .watch(wardsRepositoryProvider)
        .teamInvites(wardId: wardId.isEmpty ? null : wardId));

/// The public claim link's state, by token.
final claimInfoProvider = FutureProvider.autoDispose.family<ClaimInfo, String>(
    (ref, token) => ref.watch(wardsRepositoryProvider).claimInfo(token));
