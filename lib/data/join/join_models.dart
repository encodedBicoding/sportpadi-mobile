import '../../shared/format/parse.dart';

class GroupJoinInfo {
  const GroupJoinInfo({
    required this.id,
    required this.name,
    this.imageUrl,
    this.memberCount,
    this.alreadyMember = false,
    this.requestToJoin = false,
  });

  final String id;
  final String name;
  final String? imageUrl;
  final int? memberCount;
  final bool alreadyMember;

  /// Opened by an id, not a code: this link can't add anyone — the group's
  /// page is where to ask to join (review H2).
  final bool requestToJoin;

  factory GroupJoinInfo.fromJson(Map<String, dynamic> j) => GroupJoinInfo(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? 'Group') as String,
        imageUrl: parseStr(j['imageUrl']),
        memberCount: parseInt(j['memberCount']),
        alreadyMember: j['alreadyMember'] == true,
        requestToJoin: j['requestToJoin'] == true,
      );
}

class TeamJoinInfo {
  const TeamJoinInfo({
    required this.id,
    required this.name,
    this.username,
    this.logoUrl,
    this.kitPrimary,
    this.kitSecondary,
    this.groupName,
    this.categoryEmoji,
    this.categoryName,
    this.alreadyOnTeam = false,
    this.requestToJoin = false,
  });

  final String id;
  final String name;
  final String? username;
  final String? logoUrl;
  final String? kitPrimary;
  final String? kitSecondary;
  final String? groupName;
  final String? categoryEmoji;
  final String? categoryName;
  final bool alreadyOnTeam;

  /// Opened by an id, not a code: this link can't add anyone.
  final bool requestToJoin;

  factory TeamJoinInfo.fromJson(Map<String, dynamic> j) {
    final cat = j['category'];
    return TeamJoinInfo(
      id: (j['id'] ?? '') as String,
      name: (j['name'] ?? 'Team') as String,
      username: parseStr(j['username']),
      logoUrl: parseStr(j['logoUrl']),
      kitPrimary: parseStr(j['kitPrimary']),
      kitSecondary: parseStr(j['kitSecondary']),
      groupName: parseStr(j['groupName']),
      categoryEmoji: cat is Map ? parseStr(cat['emoji']) : null,
      categoryName: cat is Map ? parseStr(cat['name']) : null,
      alreadyOnTeam: j['alreadyOnTeam'] == true,
      requestToJoin: j['requestToJoin'] == true,
    );
  }
}

/// A secret invite link (docs/wiki/sharing.md "Invite links"): a group's
/// membership link or a team's join link, as its admins see it.
class InviteLink {
  const InviteLink({required this.code, required this.path});

  final String code;

  /// `/join/<code>` or `/join-team/<code>` — the app puts its own site base in
  /// front (`shareSiteUrl`).
  final String path;

  factory InviteLink.fromJson(Map<String, dynamic> j) => InviteLink(
        code: (j['code'] ?? '') as String,
        path: (j['path'] ?? '') as String,
      );
}

/// Whose link: a group's membership link, or one team's join link.
class InviteScope {
  const InviteScope.group(String this.groupId) : teamId = null;
  const InviteScope.team(String this.teamId) : groupId = null;

  final String? groupId;
  final String? teamId;

  String get apiPath => teamId != null
      ? '/api/mobile/teams/$teamId/invite-link'
      : '/api/mobile/groups/$groupId/invite-link';
}
