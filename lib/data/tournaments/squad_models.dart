import 'package:sportpadi_mobile/shared/format/event_time.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// A small profile embedded in squad rows.
class SquadProfile {
  const SquadProfile({required this.displayName, this.username, this.avatarUrl});
  final String displayName;
  final String? username;
  final String? avatarUrl;
  static SquadProfile? from(dynamic j) => j is Map
      ? SquadProfile(
          displayName: parseStr(j['displayName']) ?? 'Player',
          username: parseStr(j['username']),
          avatarUrl: parseStr(j['avatarUrl']),
        )
      : null;
}

/// One player's row in a team's squad for ONE tournament.
class SquadPlayer {
  const SquadPlayer({
    required this.id,
    required this.playerId,
    required this.status,
    required this.source,
    this.calledAt,
    this.respondedAt,
    this.acceptedAt,
    this.joinedAfterKickoff = false,
    this.positions = const [],
    this.jerseyNumber,
    this.isStarter = false,
    this.posX,
    this.posY,
    this.isCaptain = false,
    this.profile,
  });
  final String id; // squad row id
  final String playerId;
  final String status; // called | accepted | declined | withdrawn | removed
  final String source; // call | coach
  final DateTime? calledAt;
  final DateTime? respondedAt;
  final DateTime? acceptedAt;
  final bool joinedAfterKickoff;
  final List<String> positions;
  final int? jerseyNumber;
  final bool isStarter;
  final double? posX;
  final double? posY;
  final bool isCaptain;
  final SquadProfile? profile;

  String get name => profile?.displayName ?? 'Player';
  bool get accepted => status == 'accepted';
  bool get pending => status == 'called';

  factory SquadPlayer.fromJson(Map<String, dynamic> j) => SquadPlayer(
        id: (j['id'] ?? '') as String,
        playerId: (j['playerId'] ?? '') as String,
        status: parseStr(j['status']) ?? 'called',
        source: parseStr(j['source']) ?? 'call',
        calledAt: parseDate(j['calledAt']),
        respondedAt: parseDate(j['respondedAt']),
        acceptedAt: parseDate(j['acceptedAt']),
        joinedAfterKickoff: j['joinedAfterKickoff'] == true,
        positions: parseStrList(j['positions']),
        jerseyNumber: parseInt(j['jerseyNumber']),
        isStarter: j['isStarter'] == true,
        posX: parseDouble(j['posX']),
        posY: parseDouble(j['posY']),
        isCaptain: j['isCaptain'] == true,
        profile: SquadProfile.from(j['profile']),
      );
}

/// A roster member who hasn't been called yet (for the call-up picker).
class UncalledPlayer {
  const UncalledPlayer({required this.playerId, this.positions = const [], this.jerseyNumber, this.profile});
  final String playerId;
  final List<String> positions;
  final int? jerseyNumber;
  final SquadProfile? profile;
  String get name => profile?.displayName ?? 'Player';
  factory UncalledPlayer.fromJson(Map<String, dynamic> j) => UncalledPlayer(
        playerId: (j['playerId'] ?? '') as String,
        positions: parseStrList(j['positions']),
        jerseyNumber: parseInt(j['jerseyNumber']),
        profile: SquadProfile.from(j['profile']),
      );
}

class SquadGame {
  const SquadGame({required this.id, required this.status, required this.teams});
  final String id;
  final String status;
  final List<({String name, int score, String? result})> teams;
  factory SquadGame.fromJson(Map<String, dynamic> j) => SquadGame(
        id: (j['id'] ?? '') as String,
        status: parseStr(j['status']) ?? 'scheduled',
        teams: j['teams'] is List
            ? [
                for (final t in j['teams'] as List)
                  if (t is Map)
                    (
                      name: parseStr(t['name']) ?? 'Team',
                      score: parseInt(t['score']) ?? 0,
                      result: parseStr(t['result']),
                    ),
              ]
            : const [],
      );
}

/// The tournament-scoped team profile (tournamentSquads.get).
/// Another approved team in the same tournament.
class SquadOpponent {
  const SquadOpponent({required this.id, required this.name, this.logoUrl, this.role});
  final String id;
  final String name;
  final String? logoUrl;
  final String? role;

  factory SquadOpponent.fromJson(Map<String, dynamic> j) => SquadOpponent(
        id: (j['id'] ?? '') as String,
        name: parseStr(j['name']) ?? 'Team',
        logoUrl: parseStr(j['logoUrl']),
        role: parseStr(j['role']),
      );
}

class TournamentSquad {
  const TournamentSquad({
    required this.tournamentTeamId,
    required this.role,
    required this.status,
    required this.teamId,
    required this.teamName,
    this.teamUsername,
    this.teamLogoUrl,
    this.kitPrimary,
    this.kitSecondary,
    required this.teamGroupId,
    this.captainPlayerId,
    required this.eventId,
    required this.eventTitle,
    this.eventDescription,
    this.eventDate,
    this.startTime,
    this.endTime,
    this.locationName,
    this.timezone,
    required this.eventStatus,
    this.hostGroupId,
    this.hostGroupName,
    this.categoryName,
    this.categoryEmoji,
    this.opponents = const [],
    required this.mode,
    required this.kickedOff,
    this.formationName,
    required this.formationConfig,
    required this.canManage,
    required this.coaches,
    required this.squad,
    required this.uncalled,
    this.mySquadId,
    this.myStatus,
    this.myCallNote,
    this.myCalledByName,
    this.myOtherTeamName,
    required this.games,
  });
  final String tournamentTeamId;
  final String role;
  final String status;
  final String teamId;
  final String teamName;
  final String? teamUsername;
  final String? teamLogoUrl;
  final String? kitPrimary;
  final String? kitSecondary;
  final String teamGroupId;
  final String? captainPlayerId;
  final String eventId;
  final String eventTitle;
  final String? eventDescription;
  final DateTime? eventDate;

  /// Bare SQL times: they arrive carrying a dummy date, so read the clock in
  /// UTC (see [whenLabel]) or it shifts by the device's offset.
  final DateTime? startTime;
  final DateTime? endTime;
  final String? locationName;

  /// Venue IANA zone — start/end are a naive wall clock without it.
  final String? timezone;
  final String eventStatus;
  final String? hostGroupId;
  final String? hostGroupName;
  final String? categoryName;
  final String? categoryEmoji;

  /// The other approved teams — for a friendly, simply the opponent.
  final List<SquadOpponent> opponents;
  final String mode; // friendly | multi_team | league
  final bool kickedOff;
  final String? formationName;
  final Map<String, dynamic> formationConfig; // raw server FormationConfig
  final bool canManage;
  final List<SquadProfile> coaches;
  final List<SquadPlayer> squad;
  final List<UncalledPlayer> uncalled;
  final String? mySquadId;
  final String? myStatus;

  /// What the coach wrote when calling this viewer up, and who wrote it.
  final String? myCallNote;
  final String? myCalledByName;
  final String? myOtherTeamName;
  final List<SquadGame> games;

  String get kind => mode == 'league' ? 'League' : mode == 'multi_team' ? 'Tournament' : 'Friendly';
  List<SquadPlayer> get accepted => squad.where((p) => p.accepted).toList();
  List<SquadPlayer> get pending => squad.where((p) => p.pending).toList();
  List<SquadPlayer> get notPlaying => squad.where((p) => !p.accepted && !p.pending).toList();
  bool get needsFormation => formationConfig['needsFormation'] == true;
  int get maxStarters => parseInt(formationConfig['maxStarters']) ?? 11;
  bool get isOver => eventStatus == 'completed' || eventStatus == 'cancelled';

  /// Venue clock, zone label, and the viewer's own time when it differs.
  EventTimeParts get when => formatEventTime(
        eventDate: eventDate,
        startTime: startTime,
        endTime: endTime,
        timezone: timezone,
      );

  /// "Sat, Oct 12 · 2:30 PM GMT+1" — the venue line.
  String get whenLabel => when.line;

  factory TournamentSquad.fromJson(Map<String, dynamic> j) {
    final team = j['team'] is Map ? Map<String, dynamic>.from(j['team'] as Map) : const <String, dynamic>{};
    final event = j['event'] is Map ? Map<String, dynamic>.from(j['event'] as Map) : const <String, dynamic>{};
    final cat = event['category'];
    final formation = j['formation'] is Map ? Map<String, dynamic>.from(j['formation'] as Map) : const <String, dynamic>{};
    final me = j['me'];
    final other = j['myOtherTeam'];
    return TournamentSquad(
      tournamentTeamId: (j['tournamentTeamId'] ?? '') as String,
      role: parseStr(j['role']) ?? 'guest',
      status: parseStr(j['status']) ?? 'pending',
      teamId: (team['id'] ?? '') as String,
      teamName: parseStr(team['name']) ?? 'Team',
      teamUsername: parseStr(team['username']),
      teamLogoUrl: parseStr(team['logoUrl']),
      kitPrimary: parseStr(team['kitPrimary']),
      kitSecondary: parseStr(team['kitSecondary']),
      teamGroupId: (team['groupId'] ?? '') as String,
      captainPlayerId: parseStr(team['captainPlayerId']),
      eventId: (event['id'] ?? '') as String,
      eventTitle: parseStr(event['title']) ?? 'Tournament',
      eventDescription: parseStr(event['description']),
      eventDate: parseDate(event['eventDate']),
      startTime: parseDate(event['startTime']),
      endTime: parseDate(event['endTime']),
      locationName: parseStr(event['locationName']),
      timezone: parseStr(event['timezone']),
      eventStatus: parseStr(event['status']) ?? 'open',
      hostGroupId: parseStr(event['hostGroupId']),
      hostGroupName: parseStr(event['hostGroupName']),
      categoryName: cat is Map ? parseStr(cat['name']) : null,
      categoryEmoji: cat is Map ? parseStr(cat['emoji']) : null,
      opponents: j['opponents'] is List
          ? [
              for (final o in j['opponents'] as List)
                if (o is Map)
                  SquadOpponent.fromJson(Map<String, dynamic>.from(o)),
            ]
          : const [],
      mode: parseStr(j['mode']) ?? 'friendly',
      kickedOff: j['kickedOff'] == true,
      formationName: parseStr(formation['name']),
      formationConfig: formation['config'] is Map ? Map<String, dynamic>.from(formation['config'] as Map) : const {},
      canManage: j['canManage'] == true,
      coaches: j['coaches'] is List
          ? [for (final c in j['coaches'] as List) if (SquadProfile.from(c) != null) SquadProfile.from(c)!]
          : const [],
      squad: j['squad'] is List
          ? [for (final s in j['squad'] as List) SquadPlayer.fromJson(Map<String, dynamic>.from(s as Map))]
          : const [],
      uncalled: j['uncalled'] is List
          ? [for (final u in j['uncalled'] as List) UncalledPlayer.fromJson(Map<String, dynamic>.from(u as Map))]
          : const [],
      mySquadId: me is Map ? parseStr(me['squadId']) : null,
      myStatus: me is Map ? parseStr(me['status']) : null,
      myCallNote: me is Map ? parseStr(me['callNote']) : null,
      myCalledByName: me is Map ? parseStr(me['calledByName']) : null,
      myOtherTeamName: other is Map ? parseStr(other['name']) : null,
      games: j['games'] is List
          ? [for (final g in j['games'] as List) SquadGame.fromJson(Map<String, dynamic>.from(g as Map))]
          : const [],
    );
  }
}

/// A call-up in the player's inbox (tournamentSquads.myCalls).
class SquadCall {
  const SquadCall({
    required this.squadId,
    required this.status,
    this.calledAt,
    this.acceptedAt,
    this.joinedAfterKickoff = false,
    this.isStarter = false,
    this.teamId,
    this.teamName,
    this.teamLogoUrl,
    this.teamGroupId,
    this.eventId,
    this.eventTitle,
    this.eventDate,
    this.startTime,
    this.endTime,
    this.locationName,
    this.timezone,
    this.eventStatus,
    this.hostGroupId,
    this.hostGroupName,
    this.categoryName,
    this.categoryEmoji,
    this.opponentName,
    this.callNote,
  });
  final String squadId;
  final String status;
  final DateTime? calledAt;
  final DateTime? acceptedAt;
  final bool joinedAfterKickoff;
  final bool isStarter;
  final String? teamId;
  final String? teamName;
  final String? teamLogoUrl;
  final String? teamGroupId;
  final String? eventId;
  final String? eventTitle;
  final DateTime? eventDate;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? locationName;
  final String? timezone;
  final String? eventStatus;
  final String? hostGroupId;
  final String? hostGroupName;
  final String? categoryName;
  final String? categoryEmoji;
  final String? opponentName;

  /// The coach's remark sent with the call-up.
  final String? callNote;

  /// Venue clock, zone label, and the viewer's own time when it differs.
  EventTimeParts get when => formatEventTime(
        eventDate: eventDate,
        startTime: startTime,
        endTime: endTime,
        timezone: timezone,
      );

  /// "Sat, Oct 12 · 2:30 PM GMT+1" — the venue line.
  String get whenLabel => when.line;

  /// Route to the tournament-scoped team page (host group id first, like web).
  String? get route => (eventId != null && teamId != null)
      ? '/groups/${hostGroupId ?? teamGroupId}/tournaments/$eventId/teams/$teamId'
      : null;

  factory SquadCall.fromJson(Map<String, dynamic> j) {
    final t = j['team'];
    final e = j['event'];
    final cat = e is Map ? e['category'] : null;
    return SquadCall(
      squadId: (j['squadId'] ?? '') as String,
      status: parseStr(j['status']) ?? 'called',
      calledAt: parseDate(j['calledAt']),
      acceptedAt: parseDate(j['acceptedAt']),
      joinedAfterKickoff: j['joinedAfterKickoff'] == true,
      isStarter: j['isStarter'] == true,
      teamId: t is Map ? parseStr(t['id']) : null,
      teamName: t is Map ? parseStr(t['name']) : null,
      teamLogoUrl: t is Map ? parseStr(t['logoUrl']) : null,
      teamGroupId: t is Map ? parseStr(t['groupId']) : null,
      eventId: e is Map ? parseStr(e['id']) : null,
      eventTitle: e is Map ? parseStr(e['title']) : null,
      eventDate: e is Map ? parseDate(e['eventDate']) : null,
      startTime: e is Map ? parseDate(e['startTime']) : null,
      endTime: e is Map ? parseDate(e['endTime']) : null,
      locationName: e is Map ? parseStr(e['locationName']) : null,
      timezone: e is Map ? parseStr(e['timezone']) : null,
      hostGroupName: e is Map ? parseStr(e['hostGroupName']) : null,
      opponentName: parseStr(j['opponentName']),
      callNote: parseStr(j['callNote']),
      eventStatus: e is Map ? parseStr(e['status']) : null,
      hostGroupId: e is Map ? parseStr(e['hostGroupId']) : null,
      categoryName: cat is Map ? parseStr(cat['name']) : null,
      categoryEmoji: cat is Map ? parseStr(cat['emoji']) : null,
    );
  }
}

class MyCalls {
  const MyCalls({required this.pending, required this.accepted});
  final List<SquadCall> pending;
  final List<SquadCall> accepted;
  factory MyCalls.fromJson(Map<String, dynamic> j) => MyCalls(
        pending: j['pending'] is List
            ? [for (final c in j['pending'] as List) SquadCall.fromJson(Map<String, dynamic>.from(c as Map))]
            : const [],
        accepted: j['accepted'] is List
            ? [for (final c in j['accepted'] as List) SquadCall.fromJson(Map<String, dynamic>.from(c as Map))]
            : const [],
      );
}

/// A tournament a team is in (tournamentSquads.forTeam) — Tournaments tab.
class TeamTournamentEntry {
  const TeamTournamentEntry({
    required this.tournamentTeamId,
    required this.role,
    required this.status,
    this.formationName,
    required this.mode,
    required this.accepted,
    required this.pending,
    required this.starters,
    required this.eventId,
    required this.eventTitle,
    this.eventDate,
    required this.eventStatus,
    this.hostGroupId,
    this.categoryName,
    this.categoryEmoji,
  });
  final String tournamentTeamId;
  final String role;
  final String status;
  final String? formationName;
  final String mode;
  final int accepted;
  final int pending;
  final int starters;
  final String eventId;
  final String eventTitle;
  final DateTime? eventDate;
  final String eventStatus;
  final String? hostGroupId;
  final String? categoryName;
  final String? categoryEmoji;
  String get kind => mode == 'league' ? 'League' : mode == 'multi_team' ? 'Tournament' : 'Friendly';

  factory TeamTournamentEntry.fromJson(Map<String, dynamic> j) {
    final e = j['event'] is Map ? Map<String, dynamic>.from(j['event'] as Map) : const <String, dynamic>{};
    final cat = e['category'];
    return TeamTournamentEntry(
      tournamentTeamId: (j['tournamentTeamId'] ?? '') as String,
      role: parseStr(j['role']) ?? 'guest',
      status: parseStr(j['status']) ?? 'pending',
      formationName: parseStr(j['formationName']),
      mode: parseStr(j['mode']) ?? 'friendly',
      accepted: parseInt(j['accepted']) ?? 0,
      pending: parseInt(j['pending']) ?? 0,
      starters: parseInt(j['starters']) ?? 0,
      eventId: (e['id'] ?? '') as String,
      eventTitle: parseStr(e['title']) ?? 'Tournament',
      eventDate: parseDate(e['eventDate']),
      eventStatus: parseStr(e['status']) ?? 'open',
      hostGroupId: parseStr(e['hostGroupId']),
      categoryName: cat is Map ? parseStr(cat['name']) : null,
      categoryEmoji: cat is Map ? parseStr(cat['emoji']) : null,
    );
  }
}
