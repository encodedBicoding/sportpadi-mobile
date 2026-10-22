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

  // ── The Free plan's "Try Pro features for free" offer ─────────────────

  /// The offer for this group, or null (none running / not for this group).
  Future<ProOffer?> freeOffer(String groupId) async {
    try {
      final res = await _dio.get('/api/mobile/groups/$groupId/promo',
          queryParameters: {'view': 'offer'});
      return res.data is Map
          ? ProOffer.fromJson(Map<String, dynamic>.from(res.data as Map))
          : null;
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the offer.');
    }
  }

  /// The group OWNER accepts the offer terms ([version]) and switches it on.
  Future<void> acceptFreeOffer(String groupId, String version) async {
    try {
      await _dio.post('/api/mobile/groups/$groupId/promo',
          data: {'action': 'acceptOffer', 'version': version});
    } catch (e) {
      throw apiError(e, fallback: 'Could not switch the offer on.');
    }
  }

  /// The group OWNER opts the group out of a promo (the offer included).
  Future<void> optOutPromo(String groupId, String promoId) async {
    try {
      await _dio.post('/api/mobile/groups/$groupId/promo',
          data: {'action': 'optOut', 'promoId': promoId});
    } catch (e) {
      throw apiError(e, fallback: 'Could not opt out.');
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

  /// Leave a group yourself (not the owner — they transfer it first).
  /// Returns how many wards who joined through you left too.
  Future<int> leave(String groupId) async {
    try {
      final res = await _dio.post('/api/mobile/groups/$groupId',
          data: {'action': 'leave'});
      final d = res.data;
      return d is Map ? ((d['wardsRemoved'] as num?)?.toInt() ?? 0) : 0;
    } catch (e) {
      throw apiError(e, fallback: 'Could not leave the group.');
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
    this.walletUnlocked = false,
    this.feeTierName,
    this.feeNetBps,
    this.feeSource,
    this.renewsOn,
    this.autoRenew = false,
    this.optedOut = false,
    this.deactivated = false,
  });
  final String code;

  /// Auto-renewing: when it next renews (while on).
  final DateTime? renewsOn;
  final bool autoRenew;
  final bool optedOut;

  /// SportPadi switched the code off.
  final bool deactivated;
  final bool active;
  final String? description;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? redeemedAt;

  /// Redeem only: the code just gave the group payment collection, and the
  /// fee that applies (it follows the plan, not the code).
  final bool walletUnlocked;
  final String? feeTierName;
  final int? feeNetBps;
  final String? feeSource;

  factory GroupPromo.fromJson(Map<String, dynamic> j) => GroupPromo(
        code: parseStr(j['code']) ?? '',
        active: j['active'] == true,
        description: parseStr(j['description']),
        startsAt: parseDate(j['startsAt'] ?? j['starts_at']),
        endsAt: parseDate(j['endsAt'] ?? j['ends_at']),
        redeemedAt: parseDate(j['redeemedAt'] ?? j['redeemed_at']),
        walletUnlocked: j['walletUnlocked'] == true,
        feeTierName: j['feeTerms'] is Map ? parseStr((j['feeTerms'] as Map)['tierName']) : null,
        feeNetBps: j['feeTerms'] is Map ? parseInt((j['feeTerms'] as Map)['netBps']) : null,
        feeSource: j['feeTerms'] is Map ? parseStr((j['feeTerms'] as Map)['source']) : null,
        renewsOn: parseDate(j['renewsOn']),
        autoRenew: j['autoRenew'] == true,
        optedOut: j['optedOutAt'] != null,
        deactivated: j['deactivated'] == true,
      );
}

/// The Free plan's "Try Pro features for free" offer (promo.freeOffer).
class ProOffer {
  const ProOffer({
    required this.promoId,
    required this.code,
    required this.status,
    required this.isOwner,
    required this.planName,
    required this.feePhrase,
    required this.features,
    required this.terms,
    this.description,
    this.feeTierName,
    this.renewsOn,
    this.endsAt,
    this.since,
  });
  final String promoId;
  final String code;

  /// 'available' | 'on' | 'opted_out'
  final String status;
  final bool isOwner;
  final String planName;
  final String? description;
  final String feePhrase;
  final String? feeTierName;
  final List<({String code, String name, String? description})> features;
  final DateTime? renewsOn;
  final DateTime? endsAt;
  final DateTime? since;
  final ProOfferTerms terms;

  bool get isOn => status == 'on';

  factory ProOffer.fromJson(Map<String, dynamic> j) {
    final fee = j['fee'] is Map ? Map<String, dynamic>.from(j['fee'] as Map) : const <String, dynamic>{};
    return ProOffer(
      promoId: parseStr(j['promoId']) ?? '',
      code: parseStr(j['code']) ?? '',
      status: parseStr(j['status']) ?? 'available',
      isOwner: j['isOwner'] == true,
      planName: parseStr(j['planName']) ?? 'Free',
      description: parseStr(j['description']),
      feePhrase: parseStr(fee['phrase']) ?? '',
      feeTierName: parseStr(fee['tierName']),
      features: [
        for (final f in (j['features'] as List? ?? const []))
          if (f is Map)
            (
              code: '${f['code'] ?? ''}',
              name: '${f['name'] ?? ''}',
              description: parseStr(f['description']),
            ),
      ],
      renewsOn: parseDate(j['renewsOn']),
      endsAt: parseDate(j['endsAt']),
      since: parseDate(j['since']),
      terms: ProOfferTerms.fromJson(
          j['terms'] is Map ? Map<String, dynamic>.from(j['terms'] as Map) : const {}),
    );
  }
}

class ProOfferTerms {
  const ProOfferTerms({
    required this.version,
    required this.title,
    required this.updated,
    required this.intro,
    required this.keyPoints,
    required this.sections,
    required this.url,
  });
  final String version;
  final String title;
  final String updated;
  final String intro;
  final List<String> keyPoints;
  final List<({String heading, List<String> paragraphs, List<String> bullets})> sections;
  final String url;

  factory ProOfferTerms.fromJson(Map<String, dynamic> j) {
    List<String> strs(dynamic v) => [for (final x in (v as List? ?? const [])) '$x'];
    return ProOfferTerms(
      version: parseStr(j['version']) ?? '',
      title: parseStr(j['title']) ?? 'Pro Features Offer Terms',
      updated: parseStr(j['updated']) ?? '',
      intro: parseStr(j['intro']) ?? '',
      keyPoints: strs(j['keyPoints']),
      sections: [
        for (final s in (j['sections'] as List? ?? const []))
          if (s is Map)
            (
              heading: '${s['heading'] ?? ''}',
              paragraphs: strs(s['paragraphs']),
              bullets: strs(s['bullets']),
            ),
      ],
      url: parseStr(j['url']) ?? '/pro-offer-terms',
    );
  }
}

final groupAdminRepositoryProvider = Provider<GroupAdminRepository>(
    (ref) => GroupAdminRepository(ref.watch(dioProvider)));

final groupFinesProvider = FutureProvider.autoDispose
    .family<GroupFines, String>((ref, groupId) =>
        ref.watch(groupAdminRepositoryProvider).fines(groupId));

final freeOfferProvider = FutureProvider.autoDispose
    .family<ProOffer?, String>((ref, groupId) =>
        ref.watch(groupAdminRepositoryProvider).freeOffer(groupId));

final groupPromosProvider = FutureProvider.autoDispose
    .family<List<GroupPromo>, String>((ref, groupId) =>
        ref.watch(groupAdminRepositoryProvider).promos(groupId));
