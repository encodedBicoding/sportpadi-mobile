import 'package:sportpadi_mobile/data/manage/manage_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournament_models.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// "My tournaments", team first — one card per team the user plays for (or,
/// as a group admin, runs). Mirrors `tournaments.myTeams`.
class MyTeamCard {
  const MyTeamCard({
    required this.teamId,
    required this.name,
    this.logoUrl,
    this.kitPrimary,
    this.kitSecondary,
    this.groupId,
    this.groupName,
    this.categoryName,
    this.categoryEmoji,
    this.isMember = false,
    this.isAdmin = false,
    this.live = 0,
    this.upcoming = 0,
    this.invited = 0,
    this.past = 0,
    this.callUps = 0,
    this.played = 0,
    this.won = 0,
    this.drawn = 0,
    this.lost = 0,
    this.nextUp,
  });

  final String teamId;
  final String name;
  final String? logoUrl;
  final String? kitPrimary;
  final String? kitSecondary;
  final String? groupId;
  final String? groupName;
  final String? categoryName;
  final String? categoryEmoji;
  final bool isMember;
  final bool isAdmin;
  final int live;
  final int upcoming;
  final int invited;
  final int past;
  final int callUps;
  final int played;
  final int won;
  final int drawn;
  final int lost;
  final MyTeamNextUp? nextUp;

  int get total => live + upcoming + invited + past + callUps;

  String get subtitle => [
        if (categoryName != null) '${categoryEmoji ?? ''} $categoryName'.trim(),
        if (groupName != null) groupName!,
      ].join(' · ');

  factory MyTeamCard.fromJson(Map<String, dynamic> j) {
    final cat = j['category'];
    final counts = j['counts'] is Map ? j['counts'] as Map : const {};
    final rec = j['record'] is Map ? j['record'] as Map : const {};
    final next = j['nextUp'];
    return MyTeamCard(
      teamId: '${j['teamId'] ?? ''}',
      name: '${j['name'] ?? 'Team'}',
      logoUrl: parseStr(j['logoUrl']),
      kitPrimary: parseStr(j['kitPrimary']),
      kitSecondary: parseStr(j['kitSecondary']),
      groupId: parseStr(j['groupId']),
      groupName: parseStr(j['groupName']),
      categoryName: cat is Map ? parseStr(cat['name']) : null,
      categoryEmoji: cat is Map ? parseStr(cat['emoji']) : null,
      isMember: j['isMember'] == true,
      isAdmin: j['isAdmin'] == true,
      live: parseInt(counts['live']) ?? 0,
      upcoming: parseInt(counts['upcoming']) ?? 0,
      invited: parseInt(counts['invited']) ?? 0,
      past: parseInt(counts['past']) ?? 0,
      callUps: parseInt(counts['callUps']) ?? 0,
      played: parseInt(rec['played']) ?? 0,
      won: parseInt(rec['won']) ?? 0,
      drawn: parseInt(rec['drawn']) ?? 0,
      lost: parseInt(rec['lost']) ?? 0,
      nextUp: next is Map
          ? MyTeamNextUp.fromJson(Map<String, dynamic>.from(next))
          : null,
    );
  }
}

/// A live game, else the soonest scheduled one.
class MyTeamNextUp {
  const MyTeamNextUp({
    required this.status,
    required this.opponentName,
    this.scheduledDate,
    this.scheduledTime,
    this.myScore = 0,
    this.oppScore = 0,
  });
  final String status;
  final String opponentName;
  final String? scheduledDate;
  final String? scheduledTime;
  final int myScore;
  final int oppScore;

  bool get isLive => status == 'live';

  factory MyTeamNextUp.fromJson(Map<String, dynamic> j) => MyTeamNextUp(
        status: '${j['status'] ?? 'scheduled'}',
        opponentName: '${j['opponentName'] ?? 'TBD'}',
        scheduledDate: parseStr(j['scheduledDate']),
        scheduledTime: parseStr(j['scheduledTime']),
        myScore: parseInt(j['myScore']) ?? 0,
        oppScore: parseInt(j['oppScore']) ?? 0,
      );
}

/// One tournament on a team's page. [bucket] is live | upcoming | invited | past.
class MyTeamTournament {
  const MyTeamTournament({
    required this.id,
    required this.eventId,
    required this.title,
    required this.bucket,
    required this.teamId,
    this.eventDate,
    this.locationName,
    this.tournamentStatus = '',
    this.hostGroupId,
    this.hostGroupName,
    this.categoryLabel,
    this.role = 'guest',
    this.opponents = const [],
    this.games = const [],
    this.invite,
  });
  final String id;
  final String eventId;
  final String title;
  final String bucket;
  final String teamId;
  final DateTime? eventDate;
  final String? locationName;
  final String tournamentStatus;
  final String? hostGroupId;
  final String? hostGroupName;
  final String? categoryLabel;
  final String role;
  final List<String> opponents;
  final List<MyTournamentGame> games;
  final TournamentInvite? invite;

  factory MyTeamTournament.fromJson(Map<String, dynamic> j) {
    final cat = j['category'];
    return MyTeamTournament(
      id: '${j['tournamentTeamId'] ?? j['eventId'] ?? ''}',
      eventId: '${j['eventId'] ?? ''}',
      title: '${j['title'] ?? 'Tournament'}',
      bucket: '${j['bucket'] ?? 'upcoming'}',
      teamId: '${j['teamId'] ?? ''}',
      eventDate: parseDate(j['eventDate']),
      locationName: parseStr(j['locationName']),
      tournamentStatus: '${j['tournamentStatus'] ?? ''}',
      hostGroupId: parseStr(j['hostGroupId']),
      hostGroupName: parseStr(j['hostGroupName']),
      categoryLabel: cat is Map
          ? '${cat['emoji'] ?? ''} ${cat['name'] ?? ''}'.trim()
          : null,
      role: '${j['role'] ?? 'guest'}',
      opponents: j['opponents'] is List
          ? [
              for (final o in j['opponents'] as List)
                if (o is Map) '${o['name'] ?? 'Team'}'
            ]
          : const [],
      games: j['games'] is List
          ? [
              for (final g in j['games'] as List)
                if (g is Map)
                  MyTournamentGame.fromJson(Map<String, dynamic>.from(g))
            ]
          : const [],
      invite: j['invite'] is Map
          ? TournamentInvite.fromJson(
              Map<String, dynamic>.from(j['invite'] as Map))
          : null,
    );
  }
}

class MyTeamTournamentsView {
  const MyTeamTournamentsView({required this.team, required this.entries});
  final MyTeamCard team;
  final List<MyTeamTournament> entries;

  factory MyTeamTournamentsView.fromJson(Map<String, dynamic> j) =>
      MyTeamTournamentsView(
        team: MyTeamCard.fromJson(j['team'] is Map
            ? Map<String, dynamic>.from(j['team'] as Map)
            : const {}),
        entries: j['entries'] is List
            ? [
                for (final e in j['entries'] as List)
                  if (e is Map)
                    MyTeamTournament.fromJson(Map<String, dynamic>.from(e))
              ]
            : const [],
      );
}
