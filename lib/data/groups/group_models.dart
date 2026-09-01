class GroupSummary {
  const GroupSummary({
    required this.id,
    required this.name,
    this.slug,
    this.description,
    this.logoUrl,
    this.coverImageUrl,
    this.memberCount,
    this.followerCount,
    this.verificationBadge,
    this.isMember = false,
    this.role,
  });

  final String id;
  final String name;
  final String? slug;
  final String? description;
  final String? logoUrl;
  final String? coverImageUrl;
  final int? memberCount;
  final int? followerCount;
  final String? verificationBadge;
  final bool isMember;
  final String? role; // admin | member (from mineDetailed)

  bool get isVerified =>
      verificationBadge != null &&
      verificationBadge!.isNotEmpty &&
      verificationBadge != 'none';

  factory GroupSummary.fromJson(Map<String, dynamic> j) => GroupSummary(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? 'Group') as String,
        slug: j['slug'] as String?,
        description: j['description'] as String?,
        logoUrl: (j['logoUrl'] ?? j['imageUrl']) as String?,
        coverImageUrl: j['coverImageUrl'] as String?,
        memberCount: (j['memberCount'] as num?)?.toInt(),
        followerCount: (j['followerCount'] as num?)?.toInt(),
        verificationBadge: j['verificationBadge'] as String?,
        isMember: j['isMember'] == true,
        role: j['role'] as String?,
      );

  GroupSummary copyWith({bool? isMember}) => GroupSummary(
        id: id,
        name: name,
        slug: slug,
        description: description,
        logoUrl: logoUrl,
        coverImageUrl: coverImageUrl,
        memberCount: memberCount,
        followerCount: followerCount,
        verificationBadge: verificationBadge,
        isMember: isMember ?? this.isMember,
      );
}

class GroupDetail {
  const GroupDetail({
    required this.id,
    required this.name,
    this.slug,
    this.description,
    this.logoUrl,
    this.coverImageUrl,
    this.verificationBadge,
    this.memberCount,
    this.followerCount,
    this.eventsCount,
    this.canManage = false,
    this.isMember = false,
  });

  final String id;
  final String name;
  final String? slug;
  final String? description;
  final String? logoUrl;
  final String? coverImageUrl;
  final String? verificationBadge;
  final int? memberCount;
  final int? followerCount;
  final int? eventsCount;
  final bool canManage;
  final bool isMember;

  bool get isVerified =>
      verificationBadge != null &&
      verificationBadge!.isNotEmpty &&
      verificationBadge != 'none';

  factory GroupDetail.fromJson(Map<String, dynamic> j) => GroupDetail(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? 'Group') as String,
        slug: j['slug'] as String?,
        description: j['description'] as String?,
        logoUrl: (j['logoUrl'] ?? j['imageUrl']) as String?,
        coverImageUrl: j['coverImageUrl'] as String?,
        verificationBadge: j['verificationBadge'] as String?,
        memberCount: (j['memberCount'] as num?)?.toInt(),
        followerCount: (j['followerCount'] as num?)?.toInt(),
        eventsCount: (j['eventsCount'] as num?)?.toInt(),
        canManage: j['canManage'] == true,
        isMember: j['isMember'] == true,
      );
}

/// One row on the group leaderboard.
class LeaderboardRow {
  const LeaderboardRow({
    required this.playerId,
    required this.displayName,
    this.avatarUrl,
    this.games = 0,
    this.wins = 0,
    this.draws = 0,
    this.losses = 0,
    this.points = 0,
    this.tallies = const {},
  });
  final String playerId;
  final String displayName;
  final String? avatarUrl;
  final int games;
  final int wins;
  final int draws;
  final int losses;
  final int points;
  final Map<String, int> tallies;

  factory LeaderboardRow.fromJson(Map<String, dynamic> j) {
    final t = <String, int>{};
    if (j['tallies'] is Map) {
      (j['tallies'] as Map).forEach((k, v) {
        if (v is num) t['$k'] = v.toInt();
      });
    }
    return LeaderboardRow(
      playerId: (j['playerId'] ?? '') as String,
      displayName: (j['displayName'] ?? 'Player') as String,
      avatarUrl: j['avatarUrl'] as String?,
      games: (j['games'] as num?)?.toInt() ?? 0,
      wins: (j['wins'] as num?)?.toInt() ?? 0,
      draws: (j['draws'] as num?)?.toInt() ?? 0,
      losses: (j['losses'] as num?)?.toInt() ?? 0,
      points: (j['points'] as num?)?.toInt() ?? 0,
      tallies: t,
    );
  }
}

/// The group-page extras: check-in usage, wallet availability, outstanding.
class GroupOverview {
  const GroupOverview({
    this.checkinUsed,
    this.checkinLimit,
    this.checkinUnlimited = true,
    this.canUseWallet = false,
    this.walletExists = false,
    this.walletFrozen = false,
    this.walletStatus,
    this.walletOnboardingStep,
    this.walletActionNeeded = false,
    this.outstandingCount = 0,
    this.outstandingTotalMinor = 0,
    this.outstandingCurrency = '',
    this.outstandingExponent = 2,
  });
  final int? checkinUsed;
  final int? checkinLimit;
  final bool checkinUnlimited;
  final bool canUseWallet;
  final bool walletExists;
  final bool walletFrozen;
  final String? walletStatus;
  /// provide_details | verify_identity | under_review | ready | rejected
  final String? walletOnboardingStep;
  /// The payment provider (Stripe) is waiting on the admin to finish a step.
  final bool walletActionNeeded;
  final int outstandingCount;
  final int outstandingTotalMinor;
  final String outstandingCurrency;
  final int outstandingExponent;

  bool get showWalletCard => canUseWallet || walletExists;
  bool get showUnlockBanner => !canUseWallet && !walletExists;
  bool get walletPendingSetup => walletExists && walletStatus != 'active' && walletStatus != 'frozen';
  bool get walletUnderReview => walletPendingSetup && walletOnboardingStep == 'under_review';

  factory GroupOverview.fromJson(Map<String, dynamic> j) {
    final usage = j['checkInUsage'];
    final wallet = j['wallet'];
    final out = j['outstanding'];
    return GroupOverview(
      checkinUsed:
          usage is Map ? (usage['used'] as num?)?.toInt() : null,
      checkinLimit:
          usage is Map ? (usage['limit'] as num?)?.toInt() : null,
      checkinUnlimited:
          usage is Map ? usage['unlimited'] != false : true,
      canUseWallet: j['canUseWallet'] == true,
      walletExists: wallet is Map && wallet['exists'] == true,
      walletFrozen: wallet is Map && wallet['status'] == 'frozen',
      walletStatus: wallet is Map ? wallet['status'] as String? : null,
      walletOnboardingStep:
          wallet is Map ? wallet['onboardingStep'] as String? : null,
      walletActionNeeded:
          wallet is Map && wallet['onboardingActionNeeded'] == true,
      outstandingCount:
          out is Map ? (out['count'] as num?)?.toInt() ?? 0 : 0,
      outstandingTotalMinor:
          out is Map ? (out['totalMinor'] as num?)?.toInt() ?? 0 : 0,
      outstandingCurrency:
          out is Map ? (out['currency'] as String? ?? '') : '',
      outstandingExponent:
          out is Map ? (out['currencyExponent'] as num?)?.toInt() ?? 2 : 2,
    );
  }
}
