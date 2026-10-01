import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/manage/manage_models.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

class ManageRepository {
  ManageRepository(this._dio);
  final Dio _dio;

  Future<List<Category>> categories() async {
    try {
      final res = await _dio.get('/api/mobile/categories');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          Category.fromJson(Map<String, dynamic>.from(e as Map))
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load sports.');
    }
  }

  Future<Map<String, dynamic>> createEvent(Map<String, dynamic> body) async {
    try {
      final res = await _dio.post('/api/mobile/events', data: body);
      return res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
    } catch (e) {
      throw apiError(e, fallback: 'Could not create the event.');
    }
  }

  Future<Map<String, dynamic>> createTeam(
      String groupId, Map<String, dynamic> body) async {
    try {
      final res =
          await _dio.post('/api/mobile/groups/$groupId/teams', data: body);
      return res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
    } catch (e) {
      throw apiError(e, fallback: 'Could not create the team.');
    }
  }

  Future<Map<String, dynamic>> createTournament(
      Map<String, dynamic> body) async {
    try {
      final res = await _dio.post('/api/mobile/tournaments', data: body);
      return res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
    } catch (e) {
      throw apiError(e, fallback: 'Could not create the tournament.');
    }
  }

  Future<List<SimpleUser>> eligibleMembers(String teamId) async {
    try {
      final res = await _dio.get('/api/mobile/teams/$teamId/eligible-members');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          SimpleUser.fromJson(Map<String, dynamic>.from(e as Map))
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load members.');
    }
  }

  /// Add a group member to the team. A ward isn't added: their guardians
  /// are invited instead ([AddMemberResult.pendingWardInvite]).
  Future<AddMemberResult> addMember(
    String teamId, {
    required String playerId,
    List<String>? positions,
    int? jerseyNumber,
    bool? isStarter,
  }) async {
    try {
      final res = await _dio.post('/api/mobile/teams/$teamId/members', data: {
        'playerId': playerId,
        'positions': positions,
        'jerseyNumber': jerseyNumber,
        'isStarter': isStarter,
      });
      return res.data is Map
          ? AddMemberResult.fromJson(Map<String, dynamic>.from(res.data as Map))
          : const AddMemberResult();
    } catch (e) {
      throw apiError(e, fallback: 'Could not add the player.');
    }
  }

  /// Admin: wards invited onto the team, still waiting for a guardian.
  Future<List<TeamWardInvite>> wardInvites(String teamId) async {
    try {
      final res = await _dio.get('/api/mobile/teams/$teamId/ward-invites');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          if (e is Map) TeamWardInvite.fromJson(Map<String, dynamic>.from(e))
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load invitations.');
    }
  }

  /// Admin: withdraw a ward's team invitation nobody has answered yet.
  Future<void> cancelWardInvite(String teamId, String inviteId) async {
    try {
      await _dio.delete('/api/mobile/teams/$teamId/ward-invites',
          queryParameters: {'inviteId': inviteId});
    } catch (e) {
      throw apiError(e, fallback: 'Could not cancel the invitation.');
    }
  }

  Future<void> updateMember(
    String memberId, {
    List<String>? positions,
    int? jerseyNumber,
    bool? isStarter,
  }) async {
    try {
      await _dio.patch('/api/mobile/teams/members/$memberId', data: {
        if (positions != null) 'positions': positions,
        if (jerseyNumber != null) 'jerseyNumber': jerseyNumber,
        if (isStarter != null) 'isStarter': isStarter,
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not update the player.');
    }
  }

  Future<void> removeMember(String memberId) async {
    try {
      await _dio.delete('/api/mobile/teams/members/$memberId');
    } catch (e) {
      throw apiError(e, fallback: 'Could not remove the player.');
    }
  }

  Future<void> setCaptain(String teamId, String? playerId) async {
    try {
      await _dio.post('/api/mobile/teams/$teamId/captain',
          data: {'playerId': playerId});
    } catch (e) {
      throw apiError(e, fallback: 'Could not set the captain.');
    }
  }

  Future<List<TeamSummary>> searchTeams(
    String q, {
    String? categoryId,
    String? excludeGroupId,
  }) async {
    try {
      final res = await _dio.get('/api/mobile/team-search', queryParameters: {
        'q': q,
        if (categoryId != null) 'categoryId': categoryId,
        if (excludeGroupId != null) 'excludeGroupId': excludeGroupId,
      });
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          TeamSummary.fromJson(Map<String, dynamic>.from(e as Map))
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not search teams.');
    }
  }

  Future<List<TournamentInvite>> invites(String groupId) async {
    try {
      final res =
          await _dio.get('/api/mobile/groups/$groupId/tournament-invites');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          TournamentInvite.fromJson(Map<String, dynamic>.from(e as Map))
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load invites.');
    }
  }

  Future<WalletStatus> walletStatus(String groupId) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$groupId/wallet');
      return WalletStatus.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (_) {
      return const WalletStatus();
    }
  }

  Future<void> checkIn(String eventId, String playerId) async {
    try {
      await _dio.post('/api/mobile/checkin',
          data: {'eventId': eventId, 'playerId': playerId});
    } catch (e) {
      throw apiError(e, fallback: 'Could not check in.');
    }
  }

  Future<void> setFormation(
    String teamId, {
    String? formationName,
    required List<Map<String, dynamic>> placements,
  }) async {
    try {
      await _dio.post('/api/mobile/teams/$teamId/formation', data: {
        'formationName': formationName,
        'placements': placements,
      });
    } catch (e) {
      throw apiError(e, fallback: 'Could not save the formation.');
    }
  }

  /// Every unanswered tournament invite waiting on this user, across every
  /// group they administer.
  Future<List<TournamentInvite>> myInvites() async {
    try {
      final res = await _dio.get('/api/mobile/tournament-invites');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          TournamentInvite.fromJson(Map<String, dynamic>.from(e as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load invitations.');
    }
  }

  /// Returns the resulting status: `approved`, `rejected`, or
  /// `payment_required` when the tournament charges an entry fee that hasn't
  /// been paid — in which case call [payInvite] and send the user to checkout.
  Future<String> respondInvite(String ttId, String action) async {
    try {
      final res = await _dio.post(
        '/api/mobile/tournament-invites/$ttId/respond',
        data: {'action': action},
      );
      final d = res.data;
      return d is Map ? '${d['status'] ?? 'approved'}' : 'approved';
    } catch (e) {
      throw apiError(e, fallback: 'Could not respond to the invite.');
    }
  }

  /// Hosted-checkout URL for a paid tournament's entry fee.
  Future<String> payInvite(String ttId) async {
    try {
      final res = await _dio.post('/api/mobile/tournament-invites/$ttId/pay');
      final d = res.data;
      final url = d is Map ? parseStr(d['url']) : null;
      if (url == null || url.isEmpty) {
        throw ApiException('Could not start the payment.');
      }
      return url;
    } catch (e) {
      throw apiError(e, fallback: 'Could not start the payment.');
    }
  }
}

final manageRepositoryProvider = Provider<ManageRepository>(
    (ref) => ManageRepository(ref.watch(dioProvider)));

/// Tournament invitations waiting on the signed-in user.
final myTournamentInvitesProvider =
    FutureProvider<List<TournamentInvite>>((ref) async {
  return ref.watch(manageRepositoryProvider).myInvites();
});

final categoriesProvider = FutureProvider<List<Category>>(
    (ref) => ref.watch(manageRepositoryProvider).categories());

final eligibleMembersProvider = FutureProvider.autoDispose
    .family<List<SimpleUser>, String>((ref, teamId) =>
        ref.watch(manageRepositoryProvider).eligibleMembers(teamId));

/// Admin: wards invited onto a team, waiting for a guardian's answer.
final teamWardInvitesProvider = FutureProvider.autoDispose
    .family<List<TeamWardInvite>, String>((ref, teamId) =>
        ref.watch(manageRepositoryProvider).wardInvites(teamId));

final groupWalletProvider = FutureProvider.autoDispose
    .family<WalletStatus, String>((ref, groupId) =>
        ref.watch(manageRepositoryProvider).walletStatus(groupId));

final groupInvitesProvider = FutureProvider.autoDispose
    .family<List<TournamentInvite>, String>(
        (ref, groupId) => ref.watch(manageRepositoryProvider).invites(groupId));
