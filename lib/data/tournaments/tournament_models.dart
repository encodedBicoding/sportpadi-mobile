import '../../shared/format/parse.dart';

class TournamentSummary {
  const TournamentSummary({
    required this.eventId,
    required this.title,
    this.slug,
    this.eventDate,
    this.status,
    this.categoryEmoji,
    this.categoryName,
    this.isHost = false,
    this.hostTeamName,
    this.guestTeamName,
    this.guestStatus,
    this.hostTeamLogo,
    this.hostKitPrimary,
    this.guestTeamLogo,
    this.guestKitPrimary,
    this.mode = 'friendly',
    this.maxTeams = 2,
    this.teamsIn = 0,
    this.teamsInvited = 0,
    this.organiserOnly = false,
  });

  final String eventId;
  final String title;
  final String? slug;
  final DateTime? eventDate;
  final String? status;
  final String? categoryEmoji;
  final String? categoryName;
  final bool isHost;
  final String? hostTeamName;
  final String? guestTeamName;
  final String? guestStatus;
  final String? hostTeamLogo;
  final String? hostKitPrimary;
  final String? guestTeamLogo;
  final String? guestKitPrimary;

  /// friendly | multi_team | league. A multi-team tournament isn't a pair —
  /// the card shows the draw's fill — and its organiser may field no team
  /// of their own ([organiserOnly]).
  final String mode;
  final int maxTeams;
  final int teamsIn;
  final int teamsInvited;
  final bool organiserOnly;
  bool get isMulti => mode != 'friendly';

  factory TournamentSummary.fromJson(Map<String, dynamic> j) {
    final cat = j['category'];
    final host = j['hostTeam'];
    final guest = j['guestTeam'];
    return TournamentSummary(
      eventId: (j['eventId'] ?? '') as String,
      title: (j['title'] ?? 'Tournament') as String,
      slug: parseStr(j['slug']),
      eventDate: parseDate(j['eventDate']),
      status: parseStr(j['status']),
      categoryEmoji: cat is Map ? parseStr(cat['emoji']) : null,
      categoryName: cat is Map ? parseStr(cat['name']) : null,
      isHost: j['isHost'] == true,
      hostTeamName: host is Map ? parseStr(host['name']) : null,
      guestTeamName: guest is Map ? parseStr(guest['name']) : null,
      guestStatus: parseStr(j['guestStatus']),
      hostTeamLogo: host is Map ? parseStr(host['logoUrl']) : null,
      hostKitPrimary: host is Map ? parseStr(host['kitPrimary']) : null,
      guestTeamLogo: guest is Map ? parseStr(guest['logoUrl']) : null,
      guestKitPrimary: guest is Map ? parseStr(guest['kitPrimary']) : null,
      mode: parseStr(j['mode']) ?? 'friendly',
      maxTeams: (j['maxTeams'] as num?)?.toInt() ?? 2,
      teamsIn: (j['teamsIn'] as num?)?.toInt() ?? 0,
      teamsInvited: (j['teamsInvited'] as num?)?.toInt() ?? 0,
      organiserOnly: j['organiserOnly'] == true,
    );
  }
}

/// One line on the "My tournaments" tab: a tournament one of my teams is in.
class MyTournamentGame {
  const MyTournamentGame({
    required this.gameId,
    required this.status,
    this.scheduledDate,
    this.scheduledTime,
    this.myScore = 0,
    this.oppScore = 0,
    this.result,
    this.opponentName = 'TBD',
  });
  final String gameId;
  final String status;
  final String? scheduledDate;
  final String? scheduledTime;
  final int myScore;
  final int oppScore;
  final String? result; // win | draw | loss
  final String opponentName;

  factory MyTournamentGame.fromJson(Map<String, dynamic> j) => MyTournamentGame(
        gameId: (j['gameId'] ?? '') as String,
        status: (j['status'] ?? '') as String,
        scheduledDate: parseStr(j['scheduledDate']),
        scheduledTime: parseStr(j['scheduledTime']),
        myScore: (j['myScore'] as num?)?.toInt() ?? 0,
        oppScore: (j['oppScore'] as num?)?.toInt() ?? 0,
        result: parseStr(j['result']),
        opponentName: (j['opponentName'] ?? 'TBD') as String,
      );
}

class MyTournamentEntry {
  const MyTournamentEntry({
    required this.eventId,
    required this.title,
    this.eventDate,
    required this.tournamentStatus,
    this.hostGroupId,
    this.hostGroupName,
    required this.teamId,
    required this.teamName,
    this.teamLogoUrl,
    this.teamGroupName,
    this.category,
    required this.role,
    required this.entryStatus,
    this.games = const [],
  });
  final String eventId;
  final String title;
  final DateTime? eventDate;
  final String tournamentStatus;

  /// With [eventId] and [teamId], the address of this team's tournament-scoped
  /// squad page: /groups/:hostGroupId/tournaments/:eventId/teams/:teamId
  final String? hostGroupId;
  final String? hostGroupName;
  final String teamId;
  final String teamName;
  final String? teamLogoUrl;
  final String? teamGroupName;
  final String? category;
  final String role; // host | guest
  final String entryStatus; // pending | approved
  final List<MyTournamentGame> games;

  factory MyTournamentEntry.fromJson(Map<String, dynamic> j) =>
      MyTournamentEntry(
        eventId: (j['eventId'] ?? '') as String,
        title: (j['title'] ?? 'Tournament') as String,
        eventDate: parseDate(j['eventDate']),
        tournamentStatus: (j['tournamentStatus'] ?? '') as String,
        hostGroupId: parseStr(j['hostGroupId']),
        hostGroupName: parseStr(j['hostGroupName']),
        teamId: (j['teamId'] ?? '') as String,
        teamName: (j['teamName'] ?? 'Team') as String,
        teamLogoUrl: parseStr(j['teamLogoUrl']),
        teamGroupName: parseStr(j['teamGroupName']),
        category: parseStr(j['category']),
        role: (j['role'] ?? 'guest') as String,
        entryStatus: (j['entryStatus'] ?? '') as String,
        games: j['games'] is List
            ? [
                for (final g in j['games'] as List)
                  MyTournamentGame.fromJson(
                      Map<String, dynamic>.from(g as Map)),
              ]
            : const [],
      );
}
