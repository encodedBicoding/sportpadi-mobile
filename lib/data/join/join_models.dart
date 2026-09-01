import '../../shared/format/parse.dart';

class GroupJoinInfo {
  const GroupJoinInfo({
    required this.id,
    required this.name,
    this.imageUrl,
    this.memberCount,
    this.alreadyMember = false,
  });

  final String id;
  final String name;
  final String? imageUrl;
  final int? memberCount;
  final bool alreadyMember;

  factory GroupJoinInfo.fromJson(Map<String, dynamic> j) => GroupJoinInfo(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? 'Group') as String,
        imageUrl: parseStr(j['imageUrl']),
        memberCount: parseInt(j['memberCount']),
        alreadyMember: j['alreadyMember'] == true,
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
    );
  }
}
