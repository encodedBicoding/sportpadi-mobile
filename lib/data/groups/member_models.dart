import '../../shared/format/parse.dart';

class GroupMemberItem {
  const GroupMemberItem({
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.role,
    this.isMember = false,
    this.createdAt,
    this.isWard = false,
    this.wardOf,
    this.wardOfUserId,
  });

  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final String? role;

  /// Followers list only: already a member of the group (can't be promoted).
  final bool isMember;

  /// Followers list only: when they followed.
  final DateTime? createdAt;

  /// A ward (a player a guardian runs). Limited wards come back with a short
  /// name, no photo and an empty username.
  final bool isWard;

  /// The guardian's name ("Ward of Ada Obi"), when the viewer may see it.
  final String? wardOf;
  final String? wardOfUserId;

  factory GroupMemberItem.fromJson(Map<String, dynamic> j) => GroupMemberItem(
        userId: (j['userId'] ?? j['playerId'] ?? j['id'] ?? '') as String,
        displayName: (j['displayName'] ?? j['name'] ?? 'Member') as String,
        username: parseStr(j['username']),
        avatarUrl: parseStr(j['avatarUrl']),
        role: parseStr(j['role']),
        isMember: j['isMember'] == true,
        createdAt: parseDate(j['createdAt']),
        isWard: j['isWard'] == true,
        wardOf: parseStr(j['wardOf']),
        wardOfUserId: parseStr(j['wardOfUserId']),
      );
}

class MembersPage {
  const MembersPage({required this.items, this.nextCursor});
  final List<GroupMemberItem> items;
  final int? nextCursor;

  factory MembersPage.fromJson(Map<String, dynamic> j) {
    final raw = j['items'];
    return MembersPage(
      items: raw is List
          ? [
              for (final e in raw)
                GroupMemberItem.fromJson(Map<String, dynamic>.from(e as Map))
            ]
          : const [],
      nextCursor: parseInt(j['nextCursor']),
    );
  }
}
