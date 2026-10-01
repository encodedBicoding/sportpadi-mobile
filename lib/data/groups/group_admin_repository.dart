import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Group ADMIN tools that live in the group menu on the web: fines,
/// promo codes and ownership transfer. (A member's own fines are in
/// PaymentsRepository; this is the issuing side.)
class GroupAdminRepository {
  GroupAdminRepository(this._dio);
  final Dio _dio;

  // ── Fines ──────────────────────────────────────────────────────────────

  Future<GroupFines> fines(String groupId) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$groupId/fines');
      return GroupFines.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load fines.');
    }
  }

  /// `amount` is in MAJOR units of the wallet currency (e.g. 25.00).
  Future<int> issueFine(
    String groupId, {
    required List<String> userIds,
    required String title,
    required double amount,
  }) async {
    try {
      final res = await _dio.post('/api/mobile/groups/$groupId/fines', data: {
        'action': 'issue',
        'userIds': userIds,
        'title': title,
        'amount': amount,
      });
      final m =
          res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
      return parseInt(m['count']) ?? userIds.length;
    } catch (e) {
      throw apiError(e, fallback: 'Could not issue the fine.');
    }
  }

  Future<void> pardonFine(String groupId, String fineId) async {
    try {
      await _dio.post('/api/mobile/groups/$groupId/fines',
          data: {'action': 'pardon', 'fineId': fineId});
    } catch (e) {
      throw apiError(e, fallback: 'Could not pardon the fine.');
    }
  }

  // ── Promo codes ────────────────────────────────────────────────────────

  Future<List<GroupPromo>> promos(String groupId) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$groupId/promo');
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final e in list)
          if (e is Map) GroupPromo.fromJson(Map<String, dynamic>.from(e))
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load promo codes.');
    }
  }

  Future<GroupPromo> redeemPromo(String groupId, String code) async {
    try {
      final res = await _dio.post('/api/mobile/groups/$groupId/promo',
          data: {'action': 'redeem', 'code': code});
      return GroupPromo.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'That code could not be applied.');
    }
  }

  // ── Ownership ──────────────────────────────────────────────────────────

  Future<void> transferOwnership(String groupId, String userId) async {
    try {
      await _dio.post('/api/mobile/groups/$groupId',
          data: {'action': 'transferOwnership', 'userId': userId});
    } catch (e) {
      throw apiError(e, fallback: 'Could not transfer ownership.');
    }
  }
}

class GroupFines {
  const GroupFines({required this.canUse, required this.fines});

  /// The wallet entitlement the feature needs.
  final bool canUse;
  final List<GroupFine> fines;

  factory GroupFines.fromJson(Map<String, dynamic> j) => GroupFines(
        canUse: j['canUse'] == true,
        fines: [
          for (final e in (j['fines'] is List ? j['fines'] as List : const []))
            if (e is Map) GroupFine.fromJson(Map<String, dynamic>.from(e))
        ],
      );
}

class GroupFine {
  const GroupFine({
    required this.id,
    required this.userId,
    required this.title,
    required this.amountMinor,
    required this.currency,
    required this.currencyExponent,
    required this.status,
    this.userName,
    this.userUsername,
    this.userAvatarUrl,
    this.paidAt,
    this.pardonedAt,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String title;
  final int amountMinor;
  final String currency;
  final int currencyExponent;
  final String status; // active | paid | pardoned
  final String? userName;
  final String? userUsername;
  final String? userAvatarUrl;
  final DateTime? paidAt;
  final DateTime? pardonedAt;
  final DateTime? createdAt;

  factory GroupFine.fromJson(Map<String, dynamic> j) {
    final u =
        j['user'] is Map ? Map<String, dynamic>.from(j['user'] as Map) : null;
    return GroupFine(
      id: parseStr(j['id']) ?? '',
      userId: parseStr(j['userId']) ?? '',
      title: parseStr(j['title']) ?? 'Fine',
      amountMinor: parseInt(j['amountMinor']) ?? 0,
      currency: parseStr(j['currency']) ?? '',
      currencyExponent: parseInt(j['currencyExponent']) ?? 2,
      status: parseStr(j['status']) ?? 'active',
      userName: parseStr(u?['displayName']),
      userUsername: parseStr(u?['username']),
      userAvatarUrl: parseStr(u?['avatarUrl']),
      paidAt: parseDate(j['paidAt']),
      pardonedAt: parseDate(j['pardonedAt']),
      createdAt: parseDate(j['createdAt']),
    );
  }
}

class GroupPromo {
  const GroupPromo({
    required this.code,
    required this.active,
    this.description,
    this.startsAt,
    this.endsAt,
    this.redeemedAt,
  });
  final String code;
  final bool active;
  final String? description;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? redeemedAt;

  factory GroupPromo.fromJson(Map<String, dynamic> j) => GroupPromo(
        code: parseStr(j['code']) ?? '',
        active: j['active'] == true,
        description: parseStr(j['description']),
        startsAt: parseDate(j['startsAt'] ?? j['starts_at']),
        endsAt: parseDate(j['endsAt'] ?? j['ends_at']),
        redeemedAt: parseDate(j['redeemedAt'] ?? j['redeemed_at']),
      );
}

final groupAdminRepositoryProvider = Provider<GroupAdminRepository>(
    (ref) => GroupAdminRepository(ref.watch(dioProvider)));

final groupFinesProvider = FutureProvider.autoDispose
    .family<GroupFines, String>((ref, groupId) =>
        ref.watch(groupAdminRepositoryProvider).fines(groupId));

final groupPromosProvider = FutureProvider.autoDispose
    .family<List<GroupPromo>, String>((ref, groupId) =>
        ref.watch(groupAdminRepositoryProvider).promos(groupId));
