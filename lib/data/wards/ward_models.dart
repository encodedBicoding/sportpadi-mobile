import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Wards (docs/design/wards-and-messaging.md, Part A): player accounts a
/// guardian runs for someone who can't sign in — a child, or anyone who needs
/// a carer. These mirror the `/api/mobile/wards` payloads.

/// The relationships a guardian can have to a ward, in picker order.
const wardRelationships = <String>['parent', 'guardian', 'carer', 'other'];

String relationshipLabel(String? r) => switch (r) {
      'parent' => 'Parent',
      'guardian' => 'Guardian',
      'carer' => 'Carer',
      _ => 'Other',
    };

/// Genders a ward can have; null is "Prefer not to say".
const wardGenders = <String?>['female', 'male', 'non_binary', null];

String genderLabel(String? g) => switch (g) {
      'male' => 'Male',
      'female' => 'Female',
      'non_binary' => 'Non-binary',
      _ => 'Prefer not to say',
    };

/// Who can see a ward's profile, in picker order.
const wardVisibilities = <String>['private', 'groups', 'public'];

String visibilityLabel(String v) => switch (v) {
      'groups' => 'Group members',
      'public' => 'Everyone',
      _ => 'Only guardians & organisers',
    };

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e)
      ]
    : const [];

/// One of my wards (an active guardianship).
class Ward {
  const Ward({
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.qrCode,
    this.dateOfBirth,
    this.age,
    this.gender,
    this.visibility = 'private',
    this.searchable = false,
    this.relationship = 'parent',
    this.createdAt,
  });

  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;

  /// The ward's personal check-in QR (organisers scan it at the gate).
  final String? qrCode;

  /// "YYYY-MM-DD", or null.
  final String? dateOfBirth;
  final int? age;
  final String? gender;
  final String visibility; // private | groups | public
  final bool searchable;

  /// MY relationship to this ward.
  final String relationship;
  final DateTime? createdAt;

  String get firstName {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? displayName : parts.first;
  }

  /// The date of birth as a local calendar date (no time-zone shift).
  DateTime? get dob {
    final s = dateOfBirth;
    if (s == null || s.length < 10) return null;
    final y = int.tryParse(s.substring(0, 4));
    final m = int.tryParse(s.substring(5, 7));
    final d = int.tryParse(s.substring(8, 10));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  factory Ward.fromJson(Map<String, dynamic> j) => Ward(
        userId: parseStr(j['userId']) ?? '',
        displayName: parseStr(j['displayName']) ?? 'Player',
        username: parseStr(j['username']),
        avatarUrl: parseStr(j['avatarUrl']),
        qrCode: parseStr(j['qrCode']),
        dateOfBirth: parseStr(j['dateOfBirth']),
        age: parseInt(j['age']),
        gender: parseStr(j['gender']),
        visibility: parseStr(j['visibility']) ?? 'private',
        searchable: j['searchable'] == true,
        relationship: parseStr(j['relationship']) ?? 'parent',
        createdAt: parseDate(j['createdAt']),
      );
}

/// A co-guardian invitation waiting for MY answer.
class WardInvite {
  const WardInvite({
    required this.wardId,
    required this.wardName,
    this.wardAvatarUrl,
    this.invitedByName,
    this.relationship = 'parent',
    this.createdAt,
  });

  final String wardId;
  final String wardName;
  final String? wardAvatarUrl;
  final String? invitedByName;
  final String relationship;
  final DateTime? createdAt;

  factory WardInvite.fromJson(Map<String, dynamic> j) => WardInvite(
        wardId: parseStr(j['wardId']) ?? '',
        wardName: parseStr(j['wardName']) ?? 'Player',
        wardAvatarUrl: parseStr(j['wardAvatarUrl']),
        invitedByName: parseStr(j['invitedByName']),
        relationship: parseStr(j['relationship']) ?? 'parent',
        createdAt: parseDate(j['createdAt']),
      );
}

/// A guardian of a ward — active, or invited and not yet answered.
class WardGuardian {
  const WardGuardian({
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.relationship = 'parent',
    this.status = 'active',
  });

  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final String relationship;
  final String status; // active | pending

  bool get isPending => status == 'pending';

  factory WardGuardian.fromJson(Map<String, dynamic> j) => WardGuardian(
        userId: parseStr(j['userId']) ?? '',
        displayName: parseStr(j['displayName']) ?? 'Player',
        username: parseStr(j['username']),
        avatarUrl: parseStr(j['avatarUrl']),
        relationship: parseStr(j['relationship']) ?? 'parent',
        status: parseStr(j['status']) ?? 'active',
      );
}

/// A player who used to be my ward and now runs their own account (Wards 3,
/// A11): claimed at 15–17, so I stay on as their supervising guardian until
/// [supervisedUntil]. I can't act for them; I still hear from staff.
class SupervisedPlayer {
  const SupervisedPlayer({
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.age,
    this.supervisedUntil,
    this.claimedAt,
    this.relationship = 'parent',
  });

  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final int? age;

  /// Their 18th birthday, "YYYY-MM-DD" (a calendar date, not an instant).
  final String? supervisedUntil;
  final DateTime? claimedAt;
  final String relationship;

  factory SupervisedPlayer.fromJson(Map<String, dynamic> j) => SupervisedPlayer(
        userId: parseStr(j['userId']) ?? '',
        displayName: parseStr(j['displayName']) ?? 'Player',
        username: parseStr(j['username']),
        avatarUrl: parseStr(j['avatarUrl']),
        age: parseInt(j['age']),
        supervisedUntil: parseStr(j['supervisedUntil']),
        claimedAt: parseDate(j['claimedAt']),
        relationship: parseStr(j['relationship']) ?? 'parent',
      );
}

/// `GET /api/mobile/wards` — my wards, the invitations I haven't answered,
/// and the players I supervise.
class WardsOverview {
  const WardsOverview({
    this.wards = const [],
    this.invites = const [],
    this.supervised = const [],
  });

  final List<Ward> wards;
  final List<WardInvite> invites;
  final List<SupervisedPlayer> supervised;

  factory WardsOverview.fromJson(Map<String, dynamic> j) => WardsOverview(
        wards: [for (final m in _maps(j['wards'])) Ward.fromJson(m)],
        invites: [for (final m in _maps(j['invites'])) WardInvite.fromJson(m)],
        supervised: [
          for (final m in _maps(j['supervised'])) SupervisedPlayer.fromJson(m)
        ].where((s) => s.userId.isNotEmpty).toList(),
      );
}

/// A hand-over link waiting for the ward to use it (Wards 3, A11).
class WardClaim {
  const WardClaim({
    required this.email,
    this.createdAt,
    this.expiresAt,
    this.expired = false,
  });

  final String email;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final bool expired;

  static WardClaim? fromJson(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    final email = parseStr(j['email']);
    if (email == null) return null;
    return WardClaim(
      email: email,
      createdAt: parseDate(j['createdAt']),
      expiresAt: parseDate(j['expiresAt']),
      expired: j['expired'] == true,
    );
  }
}

/// What the public `/claim/<token>` page shows (`GET /api/mobile/claim`).
class ClaimInfo {
  const ClaimInfo({
    required this.state,
    this.firstName,
    this.email,
    this.guardianName,
    this.supervised = false,
    this.supervisedUntil,
    this.minPasswordLength = 8,
  });

  /// ready | expired | used | invalid
  final String state;
  final String? firstName;
  final String? email;
  final String? guardianName;

  /// Under 18: a supervising guardian stays on until [supervisedUntil].
  final bool supervised;

  /// "YYYY-MM-DD" (a calendar date).
  final String? supervisedUntil;
  final int minPasswordLength;

  bool get isReady => state == 'ready';

  static const invalid = ClaimInfo(state: 'invalid');

  factory ClaimInfo.fromJson(Map<String, dynamic> j) {
    final state = parseStr(j['state']) ?? 'invalid';
    return ClaimInfo(
      state: const ['ready', 'expired', 'used', 'invalid'].contains(state)
          ? state
          : 'invalid',
      firstName: parseStr(j['firstName']),
      email: parseStr(j['email']),
      guardianName: parseStr(j['guardianName']),
      supervised: j['supervised'] == true,
      supervisedUntil: parseStr(j['supervisedUntil']),
      minPasswordLength: parseInt(j['minPasswordLength']) ?? 8,
    );
  }
}

/// `GET /api/mobile/wards?id=` — one ward with its guardians.
class WardDetail {
  const WardDetail({
    required this.ward,
    this.guardians = const [],
    this.me = '',
    this.claim,
    this.claimable = false,
    this.claimOpensOn,
    this.claimBlockedReason,
  });

  final Ward ward;
  final List<WardGuardian> guardians;

  /// The signed-in user's id (to mark "you" in the guardians list).
  final String me;

  /// The hand-over link waiting to be used, if any (Wards 3).
  final WardClaim? claim;

  /// Old enough (15+) to hand the account over now.
  final bool claimable;

  /// "YYYY-MM-DD" — when handing over opens (their 15th birthday).
  final String? claimOpensOn;

  /// Why it can't be handed over yet ("Handing over opens when…").
  final String? claimBlockedReason;

  List<WardGuardian> get active => [
        for (final g in guardians)
          if (!g.isPending) g
      ];
  List<WardGuardian> get pending => [
        for (final g in guardians)
          if (g.isPending) g
      ];

  factory WardDetail.fromJson(Map<String, dynamic> j) => WardDetail(
        ward: Ward.fromJson(j['ward'] is Map
            ? Map<String, dynamic>.from(j['ward'] as Map)
            : const <String, dynamic>{}),
        guardians: [
          for (final m in _maps(j['guardians'])) WardGuardian.fromJson(m)
        ],
        me: parseStr(j['me']) ?? '',
        claim: WardClaim.fromJson(j['claim']),
        claimable: j['claimable'] == true,
        claimOpensOn: parseStr(j['claimOpensOn']),
        claimBlockedReason: parseStr(j['claimBlockedReason']),
      );
}

/// A group's `verificationBadge` means "verified" unless it's "none"
/// (booleans accepted for older payloads).
bool _verifiedBadge(Object? v) =>
    v is bool ? v : (v is String && v.isNotEmpty && v != 'none');

/// A team a ward plays on inside one of their groups.
class WardGroupTeam {
  const WardGroupTeam({required this.id, required this.name, this.logoUrl});

  final String id;
  final String name;
  final String? logoUrl;

  factory WardGroupTeam.fromJson(Map<String, dynamic> j) => WardGroupTeam(
        id: parseStr(j['id']) ?? '',
        name: parseStr(j['name']) ?? 'Team',
        logoUrl: parseStr(j['logoUrl']),
      );
}

/// A group a ward is in (`GET /api/mobile/wards?id=&view=groups` → member).
class WardGroup {
  const WardGroup({
    required this.groupId,
    required this.name,
    this.slug,
    this.imageUrl,
    this.verified = false,
    this.joinedAt,
    this.addedByName,
    this.teams = const [],
  });

  final String groupId;
  final String name;
  final String? slug;
  final String? imageUrl;

  /// The group carries the verification badge.
  final bool verified;
  final DateTime? joinedAt;

  /// The guardian who brought them in, when the server knows.
  final String? addedByName;
  final List<WardGroupTeam> teams;

  factory WardGroup.fromJson(Map<String, dynamic> j) => WardGroup(
        groupId: parseStr(j['groupId']) ?? '',
        name: parseStr(j['name']) ?? 'Group',
        slug: parseStr(j['slug']),
        imageUrl: parseStr(j['imageUrl']),
        verified: _verifiedBadge(j['verificationBadge']),
        joinedAt: parseDate(j['joinedAt']),
        addedByName: parseStr(j['addedByName']),
        teams: [for (final m in _maps(j['teams'])) WardGroupTeam.fromJson(m)],
      );
}

/// One of MY groups the ward isn't in yet (→ canAdd).
class WardGroupOption {
  const WardGroupOption({
    required this.groupId,
    required this.name,
    this.slug,
    this.imageUrl,
    this.verified = false,
  });

  final String groupId;
  final String name;
  final String? slug;
  final String? imageUrl;

  /// The group carries the verification badge.
  final bool verified;

  factory WardGroupOption.fromJson(Map<String, dynamic> j) => WardGroupOption(
        groupId: parseStr(j['groupId']) ?? '',
        name: parseStr(j['name']) ?? 'Group',
        slug: parseStr(j['slug']),
        imageUrl: parseStr(j['imageUrl']),
        verified: _verifiedBadge(j['verificationBadge']),
      );
}

/// `GET /api/mobile/wards?id=&view=groups` — the ward's groups, and mine
/// they could be added to.
class WardGroups {
  const WardGroups({this.member = const [], this.canAdd = const []});

  final List<WardGroup> member;
  final List<WardGroupOption> canAdd;

  factory WardGroups.fromJson(Map<String, dynamic> j) => WardGroups(
        member: [for (final m in _maps(j['member'])) WardGroup.fromJson(m)],
        canAdd: [
          for (final m in _maps(j['canAdd'])) WardGroupOption.fromJson(m)
        ],
      );
}

/// A coach wants one of my wards on a team — waiting for a guardian's answer
/// (`GET /api/mobile/wards?view=team-invites`).
class WardTeamInvite {
  const WardTeamInvite({
    required this.id,
    required this.teamId,
    required this.teamName,
    this.teamLogoUrl,
    required this.groupId,
    required this.groupName,
    this.categoryName,
    this.categoryEmoji,
    required this.wardId,
    required this.wardName,
    this.wardAvatarUrl,
    this.positions = const [],
    this.jerseyNumber,
    this.isStarter = false,
    this.invitedByName,
    this.createdAt,
  });

  final String id;
  final String teamId;
  final String teamName;
  final String? teamLogoUrl;
  final String groupId;
  final String groupName;
  final String? categoryName;
  final String? categoryEmoji;
  final String wardId;
  final String wardName;
  final String? wardAvatarUrl;
  final List<String> positions;
  final int? jerseyNumber;
  final bool isStarter;
  final String? invitedByName;
  final DateTime? createdAt;

  String get wardFirstName {
    final parts = wardName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? wardName : parts.first;
  }

  /// "Striker, Winger · #9 · Starter" — what the coach picked.
  String get roleLine => [
        if (positions.isNotEmpty) positions.join(', '),
        if (jerseyNumber != null) '#$jerseyNumber',
        isStarter ? 'Starter' : 'Sub',
      ].join(' · ');

  factory WardTeamInvite.fromJson(Map<String, dynamic> j) => WardTeamInvite(
        id: parseStr(j['id']) ?? '',
        teamId: parseStr(j['teamId']) ?? '',
        teamName: parseStr(j['teamName']) ?? 'Team',
        teamLogoUrl: parseStr(j['teamLogoUrl']),
        groupId: parseStr(j['groupId']) ?? '',
        groupName: parseStr(j['groupName']) ?? 'Group',
        categoryName: parseStr(j['categoryName']),
        categoryEmoji: parseStr(j['categoryEmoji']),
        wardId: parseStr(j['wardId']) ?? '',
        wardName: parseStr(j['wardName']) ?? 'Player',
        wardAvatarUrl: parseStr(j['wardAvatarUrl']),
        positions: parseStrList(j['positions']),
        jerseyNumber: parseInt(j['jerseyNumber']),
        isStarter: j['isStarter'] == true,
        invitedByName: parseStr(j['invitedByName']),
        createdAt: parseDate(j['createdAt']),
      );
}

/// What answering a team invitation did (`respond-team-invite`).
class WardTeamInviteResult {
  const WardTeamInviteResult(
      {this.jerseyDropped = false, this.madeSub = false});

  /// Their jersey number was taken meanwhile, so they joined without one.
  final bool jerseyDropped;

  /// The starting line-up was full, so they joined as a sub.
  final bool madeSub;

  factory WardTeamInviteResult.fromJson(Map<String, dynamic> j) =>
      WardTeamInviteResult(
        jerseyDropped: j['jerseyDropped'] == true,
        madeSub: j['madeSub'] == true,
      );
}
