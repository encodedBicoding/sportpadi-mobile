import '../../shared/format/parse.dart';

class GroupMemberItem {
  const GroupMemberItem({
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.role,
  });

  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final String? role;

  factory GroupMemberItem.fromJson(Map<String, dynamic> j) => GroupMemberItem(
        userId: (j['userId'] ?? j['playerId'] ?? j['id'] ?? '') as String,
        displayName: (j['displayName'] ?? j['name'] ?? 'Member') as String,
        username: parseStr(j['username']),
        avatarUrl: parseStr(j['avatarUrl']),
        role: parseStr(j['role']),
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
