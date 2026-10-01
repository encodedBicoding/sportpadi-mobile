import 'package:sportpadi_mobile/shared/format/parse.dart';

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
    this.isOwner = false,
    this.isFollower = false,
    this.membershipRequest,
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

  /// The creator flag — what unlocks "transfer ownership" and the
  /// membership-requests queue.
  final bool isOwner;

  /// I follow the group (members usually do too — check [isMember] for
  /// membership, never this).
  final bool isFollower;

  /// My latest request to join, or null when I never asked.
  final GroupMembershipRequestRef? membershipRequest;

  /// A request of mine is waiting on the owner.
  bool get hasPendingRequest => membershipRequest?.isPending ?? false;

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
        isOwner: j['isOwner'] == true,
        isFollower: j['isFollower'] == true,
        membershipRequest:
            GroupMembershipRequestRef.fromJson(j['membershipRequest']),
      );
}

/// My latest request to join a group (group detail's `membershipRequest`).
class GroupMembershipRequestRef {
  const GroupMembershipRequestRef(
      {required this.id, required this.status, this.createdAt});
  final String id;

  /// `pending` · `approved` · `declined` · `cancelled`.
  final String status;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  static GroupMembershipRequestRef? fromJson(dynamic v) {
    if (v is! Map) return null;
    final id = parseStr(v['id']);
    final status = parseStr(v['status']);
    if (id == null || status == null) return null;
    return GroupMembershipRequestRef(
        id: id, status: status, createdAt: parseDate(v['createdAt']));
  }
}

/// A membership request in the owner's queue
/// (`GET /api/mobile/groups/:id/membership-requests`).
class MembershipRequestItem {
  const MembershipRequestItem({
    required this.id,
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.message,
    this.status = 'pending',
    this.createdAt,
    this.decidedAt,
    this.followingSince,
  });
  final String id;
  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final String? message;

  /// `pending` · `approved` · `declined` · `cancelled`.
  final String status;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final DateTime? followingSince;

  bool get isPending => status == 'pending';

  factory MembershipRequestItem.fromJson(Map<String, dynamic> j) =>
      MembershipRequestItem(
        id: parseStr(j['id']) ?? '',
        userId: parseStr(j['userId']) ?? '',
        displayName: parseStr(j['displayName']) ?? 'Unknown',
        username: parseStr(j['username']),
        avatarUrl: parseStr(j['avatarUrl']),
        message: parseStr(j['message']),
        status: parseStr(j['status']) ?? 'pending',
        createdAt: parseDate(j['createdAt']),
        decidedAt: parseDate(j['decidedAt']),
        followingSince: parseDate(j['followingSince']),
      );
}

/// Badges for the group page's Talk tiles
/// (`GET /api/mobile/groups/:id/talk-counts`): unseen announcements (and how
/// many of them are urgent), conversations with unread messages, discussions
/// with new activity.
class GroupTalkCounts {
  const GroupTalkCounts({
    this.announcements = 0,
    this.urgent = 0,
    this.messages = 0,
    this.discussions = 0,
  });
  final int announcements;
  final int urgent;
  final int messages;
  final int discussions;

  static const none = GroupTalkCounts();

  factory GroupTalkCounts.fromJson(Map<String, dynamic> j) => GroupTalkCounts(
        announcements: parseInt(j['announcements']) ?? 0,
        urgent: parseInt(j['urgent']) ?? 0,
        messages: parseInt(j['messages']) ?? 0,
        discussions: parseInt(j['discussions']) ?? 0,
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
    this.username,
    this.rank = 0,
    this.prevRank,
    this.move,
    this.isNew = false,
    this.isWard = false,
  });
  final String playerId;
  final String displayName;

  /// A ward (a player a guardian runs).
  final bool isWard;
  final String? avatarUrl;
  final String? username;

  /// Place on the board now (1-based, by points).
  final int rank;

  /// Place before the most recent session, or null if not on it then.
  final int? prevRank;

  /// prevRank − rank: >0 moved up, <0 down, 0 held; null = nothing to compare.
  final int? move;

  /// On the board for the first time after the most recent session.
  final bool isNew;
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
      username: j['username'] as String?,
      rank: (j['rank'] as num?)?.toInt() ?? 0,
      prevRank: (j['prevRank'] as num?)?.toInt(),
      move: (j['move'] as num?)?.toInt(),
      isNew: j['isNew'] == true,
      isWard: j['isWard'] == true,
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
    this.canCreateTournaments = false,
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
  final bool canCreateTournaments;
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
  bool get walletPendingSetup =>
      walletExists && walletStatus != 'active' && walletStatus != 'frozen';
  bool get walletUnderReview =>
      walletPendingSetup && walletOnboardingStep == 'under_review';

  factory GroupOverview.fromJson(Map<String, dynamic> j) {
    final usage = j['checkInUsage'];
    final wallet = j['wallet'];
    final out = j['outstanding'];
    return GroupOverview(
      checkinUsed: usage is Map ? (usage['used'] as num?)?.toInt() : null,
      checkinLimit: usage is Map ? (usage['limit'] as num?)?.toInt() : null,
      checkinUnlimited: usage is Map ? usage['unlimited'] != false : true,
      canUseWallet: j['canUseWallet'] == true,
      canCreateTournaments: j['canCreateTournaments'] == true,
      walletExists: wallet is Map && wallet['exists'] == true,
      walletFrozen: wallet is Map && wallet['status'] == 'frozen',
      walletStatus: wallet is Map ? wallet['status'] as String? : null,
      walletOnboardingStep:
          wallet is Map ? wallet['onboardingStep'] as String? : null,
      walletActionNeeded:
          wallet is Map && wallet['onboardingActionNeeded'] == true,
      outstandingCount: out is Map ? (out['count'] as num?)?.toInt() ?? 0 : 0,
      outstandingTotalMinor:
          out is Map ? (out['totalMinor'] as num?)?.toInt() ?? 0 : 0,
      outstandingCurrency: out is Map ? (out['currency'] as String? ?? '') : '',
      outstandingExponent:
          out is Map ? (out['currencyExponent'] as num?)?.toInt() ?? 2 : 2,
    );
  }
}

/// An invitation to join a group, sent to me by one of its admins
/// (groups.myInvitations).
class GroupInvitation {
  const GroupInvitation({
    required this.id,
    required this.groupId,
    required this.groupName,
    this.groupImageUrl,
    this.groupDescription,
    this.verified = false,
    this.memberCount,
    this.invitedAt,
    this.inviterName,
  });
  final String id;
  final String groupId;
  final String groupName;
  final String? groupImageUrl;
  final String? groupDescription;
  final bool verified;
  final int? memberCount;
  /// When they (last) invited me.
  final DateTime? invitedAt;
  /// The admin who invited me.
  final String? inviterName;

  factory GroupInvitation.fromJson(Map<String, dynamic> j) {
    final g = j['group'] is Map ? Map<String, dynamic>.from(j['group'] as Map) : const <String, dynamic>{};
    final by = j['invitedBy'] is Map ? Map<String, dynamic>.from(j['invitedBy'] as Map) : null;
    final badge = parseStr(g['verificationBadge']);
    return GroupInvitation(
      id: (j['id'] ?? '') as String,
      groupId: (g['id'] ?? '') as String,
      groupName: (g['name'] as String?) ?? 'A group',
      groupImageUrl: g['imageUrl'] as String?,
      groupDescription: g['description'] as String?,
      verified: badge != null && badge != 'none',
      memberCount: parseInt(g['memberCount']),
      invitedAt: parseDate(j['invitedAt']),
      inviterName: by == null ? null : parseStr(by['displayName']),
    );
  }
}

/// One page of my invitations (scroll-paged), and how many are waiting.
class InvitationsPage {
  const InvitationsPage({required this.items, this.nextCursor, this.total = 0});
  final List<GroupInvitation> items;
  final int? nextCursor;
  final int total;

  factory InvitationsPage.fromJson(Map<String, dynamic> j) => InvitationsPage(
        items: j['items'] is List
            ? [
                for (final e in j['items'] as List)
                  if (e is Map) GroupInvitation.fromJson(Map<String, dynamic>.from(e)),
              ]
            : const [],
        nextCursor: parseInt(j['nextCursor']),
        total: parseInt(j['total']) ?? 0,
      );
}
