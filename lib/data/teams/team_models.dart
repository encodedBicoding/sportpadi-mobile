import '../../shared/format/parse.dart';

class TeamSummary {
  const TeamSummary({
    required this.id,
    required this.name,
    this.categoryId,
    this.username,
    this.logoUrl,
    this.kitPrimary,
    this.kitSecondary,
    this.memberCount,
    this.categoryEmoji,
    this.categoryName,
    this.grade,
  });

  final String id;
  final String name;
  final String? categoryId;
  final String? username;
  final String? logoUrl;
  final String? kitPrimary;
  final String? kitSecondary;
  final int? memberCount;
  final String? categoryEmoji;
  final String? grade;
  final String? categoryName;

  factory TeamSummary.fromJson(Map<String, dynamic> j) {
    final cat = j['category'];
    return TeamSummary(
      id: (j['id'] ?? '') as String,
      name: (j['name'] ?? 'Team') as String,
      categoryId: parseStr(j['categoryId']),
      username: parseStr(j['username']),
      logoUrl: parseStr(j['logoUrl']),
      kitPrimary: parseStr(j['kitPrimary']),
      kitSecondary: parseStr(j['kitSecondary']),
      memberCount: parseInt(j['memberCount']),
      categoryEmoji: cat is Map ? parseStr(cat['emoji']) : null,
      categoryName: cat is Map ? parseStr(cat['name']) : null,
      grade: parseStr(j['grade']),
    );
  }
}

/// "Who's it for?" options when creating/editing an event in a group
/// (`GET /api/mobile/groups/:id/event-audiences`). Admins get every team and
/// may make whole-group events ([canGeneral]); coaches get the teams they
/// coach, and can only make events for those.
class EventAudienceOptions {
  const EventAudienceOptions({
    this.isAdmin = false,
    this.canGeneral = false,
    this.teams = const [],
  });
  final bool isAdmin;
  final bool canGeneral;
  final List<AudienceTeamOption> teams;

  /// May this viewer create an event at all (general or for a team)?
  bool get canCreate => canGeneral || teams.isNotEmpty;

  bool hasTeam(String teamId) => teams.any((t) => t.id == teamId);

  factory EventAudienceOptions.fromJson(Map<String, dynamic> j) =>
      EventAudienceOptions(
        isAdmin: j['isAdmin'] == true,
        canGeneral: j['canGeneral'] == true,
        teams: [
          for (final t in (j['teams'] is List ? j['teams'] as List : const []))
            if (t is Map)
              AudienceTeamOption.fromJson(Map<String, dynamic>.from(t))
        ].where((t) => t.id.isNotEmpty).toList(),
      );
}

/// A team an event can be aimed at.
class AudienceTeamOption {
  const AudienceTeamOption({
    required this.id,
    required this.name,
    this.logoUrl,
    this.grade,
    this.categoryId,
    this.players,
  });
  final String id;
  final String name;
  final String? logoUrl;
  final String? grade; // kids | adults
  final String? categoryId;
  final int? players;

  bool get isKids => grade == 'kids';

  factory AudienceTeamOption.fromJson(Map<String, dynamic> j) =>
      AudienceTeamOption(
        id: parseStr(j['id']) ?? '',
        name: parseStr(j['name']) ?? 'Team',
        logoUrl: parseStr(j['logoUrl']),
        grade: parseStr(j['grade']),
        categoryId: parseStr(j['categoryId']),
        players: parseInt(j['players']),
      );
}

class FormationSlot {
  const FormationSlot(this.role, this.x, this.y);
  final String role;
  final double x;
  final double y;
}

class FormationDef {
  const FormationDef(this.name, this.slots);
  final String name;
  final List<FormationSlot> slots;
}

class FormationConfig {
  const FormationConfig({
    this.needsFormation = false,
    this.maxStarters = 11,
    this.surface,
    this.defaultFormationName,
    this.formations = const [],
    this.positions = const [],
  });

  final bool needsFormation;
  final int maxStarters;
  final String? surface;
  final String? defaultFormationName;
  final List<FormationDef> formations;
  final List<String> positions;

  static FormationDef _def(Map<String, dynamic> j) {
    final raw = j['slots'];
    final slots = raw is List
        ? [
            for (final e in raw)
              if (e is Map)
                FormationSlot(
                  (e['role'] ?? '') as String,
                  parseDouble(e['x']) ?? 50,
                  parseDouble(e['y']) ?? 50,
                ),
          ]
        : <FormationSlot>[];
    return FormationDef((j['name'] ?? '') as String, slots);
  }

  factory FormationConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const FormationConfig();
    final rawForms = j['formations'];
    final forms = rawForms is List
        ? [for (final e in rawForms) if (e is Map) _def(Map<String, dynamic>.from(e))]
        : <FormationDef>[];
    final def = j['defaultFormation'];
    return FormationConfig(
      needsFormation: j['needsFormation'] == true,
      maxStarters: parseInt(j['maxStarters']) ?? 11,
      surface: parseStr(j['surface']),
      defaultFormationName: def is Map ? parseStr(def['name']) : null,
      formations: forms,
      positions: parseStrList(j['positions']),
    );
  }
}

class TeamMember {
  const TeamMember({
    required this.memberId,
    required this.playerId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.jerseyNumber,
    this.positions = const [],
    this.isStarter = false,
    this.isCaptain = false,
    this.posX,
    this.posY,
    this.isWard = false,
  });

  final String memberId;
  final String playerId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final int? jerseyNumber;
  final List<String> positions;
  final bool isStarter;
  final bool isCaptain;
  final double? posX;
  final double? posY;

  /// A ward (a player run by a guardian).
  final bool isWard;

  factory TeamMember.fromJson(Map<String, dynamic> j, {String? captainPlayerId}) {
    final pid = (j['playerId'] ?? '') as String;
    final positions = parseStrList(j['positions']);
    final pos = parseStr(j['position']);
    return TeamMember(
      memberId: (j['id'] ?? '') as String,
      playerId: pid,
      displayName: (j['displayName'] ?? 'Player') as String,
      username: parseStr(j['username']),
      avatarUrl: parseStr(j['avatarUrl']),
      jerseyNumber: parseInt(j['jerseyNumber']),
      positions: positions.isNotEmpty ? positions : (pos != null ? [pos] : const []),
      isStarter: j['isStarter'] == true,
      isCaptain: captainPlayerId != null && pid == captainPlayerId,
      posX: parseDouble(j['posX']),
      posY: parseDouble(j['posY']),
      isWard: j['isWard'] == true,
    );
  }
}

class TeamDetail {
  const TeamDetail({
    required this.id,
    required this.name,
    this.username,
    this.logoUrl,
    this.kitPrimary,
    this.kitSecondary,
    this.description,
    this.homeVenue,
    this.categoryName,
    this.groupId,
    this.formationName,
    this.members = const [],
    this.formation = const FormationConfig(),
    this.canManage = false,
  });

  final String id;
  final String name;
  final String? username;
  final String? logoUrl;
  final String? kitPrimary;
  final String? kitSecondary;
  final String? description;
  final String? homeVenue;
  final String? categoryName;
  final String? groupId;
  final String? formationName;
  final List<TeamMember> members;
  final FormationConfig formation;
  final bool canManage;

  List<String> get positionOptions => formation.positions;

  factory TeamDetail.fromJson(Map<String, dynamic> j) {
    final cat = j['category'];
    final captain = parseStr(j['captainPlayerId']);
    final formation = j['formation'];
    final rawMembers = j['members'];
    final members = rawMembers is List
        ? [
            for (final e in rawMembers)
              TeamMember.fromJson(Map<String, dynamic>.from(e as Map), captainPlayerId: captain),
          ]
        : <TeamMember>[];
    members.sort((a, b) {
      if (a.isStarter != b.isStarter) return a.isStarter ? -1 : 1;
      return (a.jerseyNumber ?? 999).compareTo(b.jerseyNumber ?? 999);
    });
    return TeamDetail(
      id: (j['id'] ?? '') as String,
      name: (j['name'] ?? 'Team') as String,
      username: parseStr(j['username']),
      logoUrl: parseStr(j['logoUrl']),
      kitPrimary: parseStr(j['kitPrimary']),
      kitSecondary: parseStr(j['kitSecondary']),
      description: parseStr(j['description']),
      homeVenue: parseStr(j['homeVenue']),
      categoryName: cat is Map ? parseStr(cat['name']) : null,
      groupId: parseStr(j['groupId']),
      formationName: parseStr(j['formationName']),
      members: members,
      formation: FormationConfig.fromJson(
          formation is Map ? Map<String, dynamic>.from(formation) : null),
      canManage: j['canManage'] == true,
    );
  }
}

/// A member of the coaching staff.
class TeamCoach {
  const TeamCoach({
    required this.id,
    required this.userId,
    required this.displayName,
    this.role = 'Coach',
    this.avatarUrl,
  });
  final String id;
  final String userId;
  final String displayName;
  final String role;
  final String? avatarUrl;

  factory TeamCoach.fromJson(Map<String, dynamic> j) => TeamCoach(
        id: (j['id'] ?? '') as String,
        userId: (j['userId'] ?? '') as String,
        displayName: (j['displayName'] ?? 'Coach') as String,
        role: parseStr(j['role']) ?? 'Coach',
        avatarUrl: parseStr(j['avatarUrl']),
      );
}

class TeamCoaches {
  const TeamCoaches({this.roleOptions = const [], this.coaches = const []});
  final List<String> roleOptions;
  final List<TeamCoach> coaches;

  factory TeamCoaches.fromJson(Map<String, dynamic> j) => TeamCoaches(
        roleOptions: parseStrList(j['roleOptions']),
        coaches: j['coaches'] is List
            ? [
                for (final c in j['coaches'] as List)
                  TeamCoach.fromJson(Map<String, dynamic>.from(c as Map))
              ]
            : const [],
      );
}

/// One of the team's recent games.
class TeamGame {
  const TeamGame({
    required this.id,
    required this.status,
    required this.myScore,
    required this.oppScore,
    required this.oppName,
    this.result,
    this.playedAt,
    this.eventTitle,
  });
  final String id;
  final String status;
  final int myScore;
  final int oppScore;
  final String oppName;
  final String? result; // win | loss | draw (completed only)
  final DateTime? playedAt;
  final String? eventTitle;

  factory TeamGame.fromJson(Map<String, dynamic> j) => TeamGame(
        id: (j['id'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        myScore: parseInt(j['myScore']) ?? 0,
        oppScore: parseInt(j['oppScore']) ?? 0,
        oppName: (j['oppName'] ?? 'Opponent') as String,
        result: parseStr(j['result']),
        playedAt: parseDate(j['playedAt']),
        eventTitle: parseStr(j['eventTitle']),
      );
}

/// Tournament record + per-player activity tallies.
class TeamStats {
  const TeamStats({
    this.played = 0,
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
    this.goalsFor = 0,
    this.goalsAgainst = 0,
    this.players = const {},
  });
  final int played;
  final int won;
  final int drawn;
  final int lost;
  final int goalsFor;
  final int goalsAgainst;

  /// playerId -> { activityType -> count }.
  final Map<String, Map<String, int>> players;

  factory TeamStats.fromJson(Map<String, dynamic> j) {
    final rec = j['record'] is Map ? j['record'] as Map : const {};
    final raw = j['players'];
    final stats = raw is Map && raw['stats'] is Map
        ? raw['stats'] as Map
        : const {};
    final players = <String, Map<String, int>>{};
    stats.forEach((k, v) {
      if (v is Map) {
        players['$k'] = {
          for (final e in v.entries) '${e.key}': parseInt(e.value) ?? 0
        };
      }
    });
    return TeamStats(
      played: parseInt(rec['played']) ?? 0,
      won: parseInt(rec['won']) ?? 0,
      drawn: parseInt(rec['drawn']) ?? 0,
      lost: parseInt(rec['lost']) ?? 0,
      goalsFor: parseInt(rec['goalsFor']) ?? 0,
      goalsAgainst: parseInt(rec['goalsAgainst']) ?? 0,
      players: players,
    );
  }
}

/// The tap-a-player card: identity, team role, sport setup, and tallies.
class PlayerCard {
  const PlayerCard({
    required this.playerId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.jerseyNumber,
    this.positions = const [],
    this.isStarter = false,
    this.onTeam = false,
    this.categoryName,
    this.categoryEmoji,
    this.setup = const [],
    this.appearances = 0,
    this.tallies = const [],
    this.restricted = false,
  });
  final String playerId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final int? jerseyNumber;
  final List<String> positions;
  final bool isStarter;
  final bool onTeam;
  final String? categoryName;
  final String? categoryEmoji;
  final List<({String label, String value})> setup;
  final int appearances;
  final List<({String type, String label, String? icon, int count})> tallies;

  /// A ward whose guardians keep their card private from this viewer: the
  /// name is short, and there's no username, photo, setup or tallies.
  final bool restricted;

  factory PlayerCard.fromJson(Map<String, dynamic> j) => PlayerCard(
        playerId: (j['playerId'] ?? '') as String,
        displayName: (j['displayName'] ?? 'Player') as String,
        username: parseStr(j['username']),
        avatarUrl: parseStr(j['avatarUrl']),
        jerseyNumber: parseInt(j['jerseyNumber']),
        positions: parseStrList(j['positions']),
        isStarter: j['isStarter'] == true,
        onTeam: j['onTeam'] == true,
        categoryName: parseStr(j['categoryName']),
        categoryEmoji: parseStr(j['categoryEmoji']),
        setup: j['setup'] is List
            ? [
                for (final e in j['setup'] as List)
                  if (e is Map)
                    (
                      label: '${e['label'] ?? ''}',
                      value: '${e['value'] ?? ''}',
                    )
              ]
            : const [],
        appearances: parseInt(j['appearances']) ?? 0,
        tallies: j['tallies'] is List
            ? [
                for (final e in j['tallies'] as List)
                  if (e is Map)
                    (
                      type: '${e['type'] ?? ''}',
                      label: '${e['label'] ?? ''}',
                      icon: parseStr(e['icon']),
                      count: parseInt(e['count']) ?? 0,
                    )
              ]
            : const [],
        restricted: j['restricted'] == true,
      );
}

/// What `POST /api/mobile/teams/:id/members` did: a ward isn't added
/// directly — their guardians get an invitation instead.
class AddMemberResult {
  const AddMemberResult({
    this.pendingWardInvite = false,
    this.inviteId,
    this.alreadyInvited = false,
    this.guardians = 0,
    this.wardName,
  });

  final bool pendingWardInvite;
  final String? inviteId;
  final bool alreadyInvited;

  /// How many guardians were asked.
  final int guardians;
  final String? wardName;

  /// The snackbar line for a ward invitation (null for a direct add).
  String? get wardMessage {
    if (!pendingWardInvite) return null;
    if (alreadyInvited) return 'Already invited — waiting for a guardian.';
    final who = wardName ?? 'their';
    final owner = wardName == null ? who : "$who's";
    return 'Invitation sent to $owner guardian${guardians == 1 ? '' : 's'}.';
  }

  factory AddMemberResult.fromJson(Map<String, dynamic> j) => AddMemberResult(
        pendingWardInvite: j['pendingWardInvite'] == true,
        inviteId: parseStr(j['inviteId']),
        alreadyInvited: j['alreadyInvited'] == true,
        guardians: parseInt(j['guardians']) ?? 0,
        wardName: parseStr(j['wardName']),
      );
}

/// A ward invited onto a team, waiting for a guardian's answer (admin view,
/// `GET /api/mobile/teams/:id/ward-invites`).
class TeamWardInvite {
  const TeamWardInvite({
    required this.inviteId,
    required this.wardId,
    required this.displayName,
    this.avatarUrl,
    this.positions = const [],
    this.jerseyNumber,
    this.isStarter = false,
    this.createdAt,
  });

  final String inviteId;
  final String wardId;
  final String displayName;
  final String? avatarUrl;
  final List<String> positions;
  final int? jerseyNumber;
  final bool isStarter;
  final DateTime? createdAt;

  factory TeamWardInvite.fromJson(Map<String, dynamic> j) => TeamWardInvite(
        inviteId: parseStr(j['inviteId']) ?? '',
        wardId: parseStr(j['wardId']) ?? '',
        displayName: parseStr(j['displayName']) ?? 'Player',
        avatarUrl: parseStr(j['avatarUrl']),
        positions: parseStrList(j['positions']),
        jerseyNumber: parseInt(j['jerseyNumber']),
        isStarter: j['isStarter'] == true,
        createdAt: parseDate(j['createdAt']),
      );
}
