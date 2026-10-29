import '../../shared/format/parse.dart';
import 'basketball_models.dart';
import 'volleyball_models.dart';

export 'basketball_models.dart';
export 'volleyball_models.dart';

/// One side in a game, with its live score.
class GameTeam {
  const GameTeam({
    required this.teamId,
    required this.name,
    this.color,
    this.score = 0,
    this.result,
    this.groupTeamId,
    this.logoUrl,
  });
  final String teamId;
  final String name;

  /// The kit colour this side wears in THIS game (officiating uses it).
  final String? color;

  /// Tournament team crest — the scoreboard shows it before the colour.
  final String? logoUrl;
  final int score;
  final String? result; // win | loss | draw (set at completion)
  final String? groupTeamId;

  factory GameTeam.fromJson(Map<String, dynamic> j) => GameTeam(
        teamId: (j['teamId'] ?? '') as String,
        name: (j['name'] ?? 'Team') as String,
        color: parseStr(j['color']),
        score: parseInt(j['score']) ?? 0,
        result: parseStr(j['result']),
        groupTeamId: parseStr(j['groupTeamId']),
        logoUrl: parseStr(j['logoUrl']),
      );
}

/// A participant snapshot (seeded at kickoff).
class GamePlayer {
  const GamePlayer({
    required this.playerId,
    required this.teamId,
    required this.displayName,
    this.onField = false,
    this.sentOff = false,
    this.avatarUrl,
    this.jersey,
  });
  final String playerId;
  final String teamId;
  final String displayName;
  final bool onField;
  final bool sentOff;
  final String? avatarUrl;
  final int? jersey;

  factory GamePlayer.fromJson(Map<String, dynamic> j) => GamePlayer(
        playerId: (j['playerId'] ?? '') as String,
        teamId: (j['teamId'] ?? '') as String,
        displayName: (j['displayName'] ?? 'Player') as String,
        onField: j['onField'] == true,
        sentOff: j['sentOff'] == true,
        avatarUrl: parseStr(j['avatarUrl']),
        jersey: parseInt(j['jersey']),
      );
}

/// Pre-kickoff roster entry / bench candidate.
class GameRosterEntry {
  const GameRosterEntry({
    required this.playerId,
    required this.teamId,
    required this.displayName,
    this.isSub = false,
    this.avatarUrl,
    this.jersey,
  });
  final String playerId;
  final String teamId;
  final String displayName;
  final bool isSub;
  final String? avatarUrl;
  final int? jersey;

  factory GameRosterEntry.fromJson(Map<String, dynamic> j) => GameRosterEntry(
        playerId: (j['playerId'] ?? '') as String,
        teamId: (j['teamId'] ?? '') as String,
        displayName: (j['displayName'] ?? 'Player') as String,
        isSub: j['isSub'] == true,
        avatarUrl: parseStr(j['avatarUrl']),
        jersey: parseInt(j['jersey']),
      );
}

/// One recorded activity (goal, card, sub, …).
class GameActivity {
  const GameActivity({
    required this.id,
    required this.type,
    required this.teamId,
    required this.playerId,
    required this.playerName,
    this.minute,
    this.phase,
    this.clockLeft,
    this.relatedPlayerId,
    this.relatedPlayerName,
    this.jersey,
  });
  final String id;
  final String type;
  final String teamId;
  final String playerId;
  final String playerName;
  final int? minute;
  final String? phase;

  /// Seconds left on a count-down clock when it happened (basketball).
  final int? clockLeft;
  final String? relatedPlayerId;
  final String? relatedPlayerName;
  final int? jersey;

  factory GameActivity.fromJson(Map<String, dynamic> j) => GameActivity(
        id: (j['id'] ?? '') as String,
        type: (j['type'] ?? '') as String,
        teamId: (j['teamId'] ?? '') as String,
        playerId: (j['playerId'] ?? '') as String,
        playerName: (j['playerName'] ?? 'Player') as String,
        minute: parseInt(j['minute']),
        phase: parseStr(j['phase']),
        clockLeft: parseInt(j['clockLeft']),
        relatedPlayerId: parseStr(j['relatedPlayerId']),
        relatedPlayerName: parseStr(j['relatedPlayerName']),
        jersey: parseInt(j['jersey']),
      );
}

/// One recordable activity type from the sport's schema.
class ActivityDef {
  const ActivityDef({
    required this.type,
    required this.label,
    this.icon,
    this.requiresRelated = false,
    this.assistAllowed = false,
    this.scorePoints,
    this.scoreTeam,
    this.tally = const {},
    this.assistTally = const {},
    this.side,
    this.weight,
  });
  final String type;
  final String label;
  final String? icon;
  final bool requiresRelated;
  final bool assistAllowed;
  final int? scorePoints;

  /// Who a scoring activity scores for: "own" (a goal) or "opponent" (an own goal).
  final String? scoreTeam;

  /// What one of these adds to the player's stat line (e.g. {goals: 1}).
  final Map<String, int> tally;

  /// What the assisting player gets (e.g. {assists: 1}).
  final Map<String, int> assistTally;

  /// attack | defence | support | discipline — groups the scoring pad.
  final String? side;

  /// Match-rating points; negative for a mistake (own goal, missed penalty).
  final double? weight;

  bool get isMistake => (weight ?? 0) < 0 || side == 'discipline';

  factory ActivityDef.fromJson(Map<String, dynamic> j) {
    final assist = j['assist'];
    final score = j['score'];
    return ActivityDef(
      type: (j['type'] ?? '') as String,
      label: (j['label'] ?? j['type'] ?? '') as String,
      icon: parseStr(j['icon']),
      requiresRelated: j['requiresRelated'] == true,
      assistAllowed: assist is Map && assist['allowed'] == true,
      scorePoints: score is Map ? parseInt(score['points']) : null,
      scoreTeam: score is Map ? parseStr(score['team']) : null,
      tally: _intMap(j['tally']),
      assistTally: assist is Map ? _intMap(assist['tally']) : const {},
      side: parseStr(j['side']),
      weight: j['weight'] is num ? (j['weight'] as num).toDouble() : null,
    );
  }
}

Map<String, int> _intMap(dynamic v) => v is Map
    ? {
        for (final e in v.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
      }
    : const {};

/// Per-phase clock accounting.
class PhaseTimer {
  const PhaseTimer({this.pausedAt, this.pausedMs = 0, this.stoppageMin = 0});
  final DateTime? pausedAt;
  final int pausedMs;
  final int stoppageMin;

  factory PhaseTimer.fromJson(Map<String, dynamic>? j) => j == null
      ? const PhaseTimer()
      : PhaseTimer(
          pausedAt: parseDate(j['pausedAt']),
          pausedMs: parseInt(j['pausedMs']) ?? 0,
          stoppageMin: parseInt(j['stoppageMin']) ?? 0,
        );
}

/// An instantiated phase (H1 / HT / H2 / ET1 / shootout …).
class GamePhase {
  const GamePhase({
    required this.key,
    required this.kind, // timed | interval | shootout | extra
    required this.label,
    required this.status, // pending | live | ended
    this.nominalMinutes,
    this.nominalOffset = 0,
    this.startedAt,
    this.endedAt,
    this.timer = const PhaseTimer(),
  });
  final String key;
  final String kind;
  final String label;
  final String status;
  final int? nominalMinutes;
  final int nominalOffset;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final PhaseTimer timer;

  bool get isTimed => nominalMinutes != null && kind != 'interval';

  factory GamePhase.fromJson(Map<String, dynamic> j) => GamePhase(
        key: (j['key'] ?? '') as String,
        kind: (j['kind'] ?? 'timed') as String,
        label: (j['label'] ?? '') as String,
        status: (j['status'] ?? 'pending') as String,
        nominalMinutes: parseInt(j['nominalMinutes']),
        nominalOffset: parseInt(j['nominalOffset']) ?? 0,
        startedAt: parseDate(j['startedAt']),
        endedAt: parseDate(j['endedAt']),
        timer: PhaseTimer.fromJson(j['timer'] is Map
            ? Map<String, dynamic>.from(j['timer'] as Map)
            : null),
      );
}

class ShootoutTally {
  const ShootoutTally({this.scored = 0, this.taken = 0});
  final int scored;
  final int taken;
}

/// Phased-game lifecycle stored under attributes.lifecycle.
class GameLifecycle {
  const GameLifecycle({
    required this.phases,
    required this.currentPhaseIndex,
    this.shootoutTally = const {},
    this.shootoutOrder = const [],
    this.shootoutHistory = const [],
    this.drawResolutions = const [],
    this.hasExtraPhases = false,
    this.hasShootout = false,
  });
  final List<GamePhase> phases;
  final int currentPhaseIndex;
  final Map<String, ShootoutTally> shootoutTally; // teamId -> tally
  final List<String> shootoutOrder; // [firstTeamId, secondTeamId]
  final List<({String teamId, bool scored})> shootoutHistory;
  final List<String> drawResolutions; // extra_time | penalties
  final bool hasExtraPhases;
  final bool hasShootout;

  GamePhase? get current =>
      currentPhaseIndex >= 0 && currentPhaseIndex < phases.length
          ? phases[currentPhaseIndex]
          : null;

  /// The next PENDING timed phase from the current one on (web semantics:
  /// scan includes the current phase; shootouts are not timed phases).
  GamePhase? get nextTimed {
    for (var i = currentPhaseIndex; i < phases.length; i++) {
      if (i < 0) continue;
      if (phases[i].isTimed && phases[i].status == 'pending') return phases[i];
    }
    return null;
  }

  factory GameLifecycle.fromJson(Map<String, dynamic> j) {
    final rawPhases = j['phases'];
    final phases = rawPhases is List
        ? [
            for (final p in rawPhases)
              GamePhase.fromJson(Map<String, dynamic>.from(p as Map))
          ]
        : <GamePhase>[];
    final shootout = j['shootout'];
    final tally = <String, ShootoutTally>{};
    if (shootout is Map && shootout['tally'] is Map) {
      (shootout['tally'] as Map).forEach((k, v) {
        if (v is Map) {
          tally['$k'] = ShootoutTally(
            scored: parseInt(v['scored']) ?? 0,
            taken: parseInt(v['taken']) ?? 0,
          );
        }
      });
    }
    final rules = j['rules'];
    final order = <String>[];
    final history = <({String teamId, bool scored})>[];
    if (shootout is Map) {
      order.addAll(parseStrList(shootout['order']));
      if (shootout['history'] is List) {
        for (final h in shootout['history'] as List) {
          if (h is Map) {
            history.add((
              teamId: '${h['teamId'] ?? ''}',
              scored: h['scored'] == true,
            ));
          }
        }
      }
    }
    return GameLifecycle(
      phases: phases,
      currentPhaseIndex: parseInt(j['currentPhaseIndex']) ?? 0,
      shootoutTally: tally,
      shootoutOrder: order,
      shootoutHistory: history,
      drawResolutions:
          rules is Map ? parseStrList(rules['drawResolutions']) : const [],
      hasExtraPhases: phases.any((p) => p.kind == 'extra'),
      hasShootout: phases.any((p) => p.kind == 'shootout'),
    );
  }
}

/// Row in an event's games list.
class GameSummary {
  const GameSummary({
    required this.id,
    required this.status,
    required this.teams,
    this.startedAt,
    this.endedAt,
  });
  final String id;
  final String status; // scheduled | live | completed | abandoned
  final List<GameTeam> teams;
  final DateTime? startedAt;
  final DateTime? endedAt;

  factory GameSummary.fromJson(Map<String, dynamic> j) => GameSummary(
        id: (j['id'] ?? '') as String,
        status: (j['status'] ?? 'scheduled') as String,
        startedAt: parseDate(j['startedAt']),
        endedAt: parseDate(j['endedAt']),
        teams: j['teams'] is List
            ? [
                for (final t in j['teams'] as List)
                  GameTeam.fromJson(Map<String, dynamic>.from(t as Map))
              ]
            : const [],
      );
}

/// One officiant on a game. [role] is timekeeper | scorer | both; [pending]
/// is a tournament call-in that hasn't been accepted yet.
class GameOfficiant {
  const GameOfficiant({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.role = 'both',
    this.pending = false,
  });
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final String role;
  final bool pending;

  factory GameOfficiant.fromJson(Map<String, dynamic> j) => GameOfficiant(
        userId: '${j['userId'] ?? ''}',
        displayName: '${j['displayName'] ?? 'Officiant'}',
        avatarUrl: parseStr(j['avatarUrl']),
        role: parseStr(j['role']) ?? 'both',
        pending: j['pending'] == true,
      );
}

/// The viewer's officiating rights: the timekeeper runs the clock, the scorer
/// records stats, group admins ("admin") and "both" officiants do everything.
class OfficiatingRights {
  const OfficiatingRights({
    this.role,
    this.canTime = false,
    this.canScore = false,
    this.canCallIn = false,
    this.canAssign = false,
  });
  final String? role; // admin | timekeeper | scorer | both | null
  final bool canTime;
  final bool canScore;
  final bool canCallIn;
  final bool canAssign;

  factory OfficiatingRights.fromJson(dynamic j, {required bool fallback}) {
    if (j is! Map) {
      // Older server: canManage meant "may do everything".
      return OfficiatingRights(
          canTime: fallback,
          canScore: fallback,
          role: fallback ? 'both' : null);
    }
    return OfficiatingRights(
      role: parseStr(j['role']),
      canTime: j['canTime'] == true,
      canScore: j['canScore'] == true,
      canCallIn: j['canCallIn'] == true,
      canAssign: j['canAssign'] == true,
    );
  }
}

/// Category-aware officiating tools (from the server): what pausing is
/// called, whether time is added on, the period word, what the scorer records.
class OfficiatingProfile {
  const OfficiatingProfile({
    this.family = 'generic',
    this.clock = 'match',
    this.lengthMinutes,
    this.pauseLabel = 'Pause',
    this.resumeLabel = 'Resume',
    this.stoppagePresets = const [1, 2, 3, 5],
    this.periodWord = 'period',
    this.tools = const ['pause', 'stoppage', 'complete'],
    this.scorerRecords = const [],
    this.clockDirection = 'up',
    this.completeLabel = 'Full time',
  });
  final String family;

  /// 'down': the board shows time LEFT in the period (basketball quarters).
  final String clockDirection;

  /// What ending the game is called ("Full time", "End game").
  final String completeLabel;
  bool get countsDown => clockDirection == 'down';
  final String clock; // match | elapsed
  final int? lengthMinutes;
  final String pauseLabel;
  final String resumeLabel;
  final List<int> stoppagePresets;
  final String periodWord;
  final List<String> tools; // pause | stoppage | periods | complete
  final List<String> scorerRecords;

  bool has(String tool) => tools.contains(tool);
  bool get addsTime => stoppagePresets.isNotEmpty;

  factory OfficiatingProfile.fromJson(dynamic j) {
    if (j is! Map) return const OfficiatingProfile();
    return OfficiatingProfile(
      family: parseStr(j['family']) ?? 'generic',
      clock: parseStr(j['clock']) ?? 'match',
      lengthMinutes: parseInt(j['lengthMinutes']),
      pauseLabel: parseStr(j['pauseLabel']) ?? 'Pause',
      resumeLabel: parseStr(j['resumeLabel']) ?? 'Resume',
      stoppagePresets: j['stoppagePresets'] is List
          ? [
              for (final v in j['stoppagePresets'] as List)
                if (parseInt(v) != null) parseInt(v)!
            ]
          : const [],
      periodWord: parseStr(j['periodWord']) ?? 'period',
      tools: j['tools'] is List
          ? [
              for (final t in j['tools'] as List)
                if (t is Map && t['id'] != null) '${t['id']}'
            ]
          : const ['pause', 'complete'],
      scorerRecords: parseStrList(j['scorerRecords']),
      clockDirection: parseStr(j['clockDirection']) ?? 'up',
      completeLabel: () {
        final tools = j['tools'];
        if (tools is List) {
          for (final t in tools) {
            if (t is Map && t['id'] == 'complete' && t['label'] is String) {
              return t['label'] as String;
            }
          }
        }
        return 'Full time';
      }(),
    );
  }
}

/// Full live game state — the mobile mirror of the web `games.get` payload.
class GameDetail {
  const GameDetail({
    required this.id,
    required this.status,
    required this.teams,
    required this.participants,
    required this.roster,
    required this.bench,
    required this.activities,
    required this.schema,
    this.canManage = false,
    this.canManageLineup = false,
    this.startedAt,
    this.endedAt,
    this.lifecycle,
    this.timer = const PhaseTimer(),
    this.serverNow,
    this.fetchedAt,
    this.maxTeamsPerGame = 2,
    this.maxPlayersPerTeam = 11,
    this.categoryName,
    this.categoryEmoji,
    this.eventSlug,
    this.isTournament = false,
    this.leagueSlug,
    this.firstLeg = const {},
    this.awayGoals = false,
    this.legHomeTeamId,
    this.scoresheetHolder,
    this.officiantNames = const [],
    this.officiants = const [],
    this.officiating = const OfficiatingRights(),
    this.profile = const OfficiatingProfile(),
    this.durationMinutes,
    this.basketball,
    this.volleyball,
    this.clockBy,
    this.ratings = const {},
  });

  final String id;
  final String status;
  final List<GameTeam> teams;

  /// Match ratings once completed (1–10, 6.0 = par): playerId → rating.
  final Map<String, double> ratings;

  /// Who last touched the match clock, from any device (phone, web, watch):
  /// attributes.clock.lastBy — for "Paused · by Ade".
  final ClockBy? clockBy;
  final List<GamePlayer> participants;
  final List<GameRosterEntry> roster;
  final List<GameRosterEntry> bench;
  final List<GameActivity> activities;
  final List<ActivityDef> schema;
  final bool canManage;

  /// Group admin: may name the side before kick-off. Narrower than [canManage],
  /// which also covers assigned officiants — picking the team is a manager's
  /// call, running the scoresheet isn't.
  final bool canManageLineup;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final GameLifecycle? lifecycle;
  final PhaseTimer timer; // non-phased games
  final DateTime? serverNow;

  /// Device wall-clock at the moment this payload was parsed — the anchor for
  /// the serverNow offset so the match clock ticks between refetches.
  final DateTime? fetchedAt;
  final int maxTeamsPerGame;

  /// How many players a side may field — caps the starting line-up.
  final int maxPlayersPerTeam;
  final String? categoryName;
  final String? categoryEmoji;
  final String? eventSlug;
  final bool isTournament;

  /// League fixture: the league's public slug (games.get `league.slug`).
  final String? leagueSlug;

  /// Second leg of a two-leg league tie: first-leg goals per game team id
  /// (games.get `aggregate.firstLeg`); empty otherwise.
  final Map<String, int> firstLeg;

  /// The season plays the away-goals rule (second legs only).
  final bool awayGoals;

  /// This second leg's home side (game team id) — it scored its away goals in leg 1.
  final String? legHomeTeamId;

  /// This game plus the first leg, per game team.
  int aggregateFor(String teamId) =>
      (teams.where((t) => t.teamId == teamId).firstOrNull?.score ?? 0) + (firstLeg[teamId] ?? 0);
  final String? scoresheetHolder;
  final List<String> officiantNames;
  final List<GameOfficiant> officiants;
  final OfficiatingRights officiating;
  final OfficiatingProfile profile;

  /// Scheduled length (non-phased games), null when not set.
  final int? durationMinutes;

  /// Basketball games: rules, team fouls / bonus, box score.
  final BasketballInfo? basketball;
  bool get isBasketball => basketball != null;

  /// Volleyball matches: sets, set points, timeouts, stat sheet.
  final VolleyballInfo? volleyball;
  bool get isVolleyball => volleyball != null;

  /// Server time now, from the fetch's serverNow / fetchedAt anchor.
  DateTime get serverClock {
    final off = (serverNow != null && fetchedAt != null)
        ? serverNow!.difference(fetchedAt!)
        : Duration.zero;
    return DateTime.now().add(off);
  }

  bool get canTime => officiating.canTime;
  bool get canScore => officiating.canScore;

  bool get isLive => status == 'live';
  bool get isScheduled => status == 'scheduled';
  /// Level — on aggregate when this is a second leg.
  bool get isDrawn {
    if (teams.length < 2) return false;
    int agg(GameTeam t) => t.score + (firstLeg[t.teamId] ?? 0);
    final max = teams.map(agg).reduce((a, b) => a > b ? a : b);
    if (teams.where((t) => agg(t) == max).length < 2) return false;
    // Away-goals seasons: level on aggregate isn't level if away goals differ.
    final home = legHomeTeamId;
    if (awayGoals && home != null && teams.length == 2) {
      final away = teams.where((t) => t.teamId != home).firstOrNull;
      return (firstLeg[home] ?? 0) == (away?.score ?? 0);
    }
    return true;
  }

  List<GamePlayer> onFieldFor(String teamId) => participants
      .where((p) => p.teamId == teamId && p.onField && !p.sentOff)
      .toList();

  List<GameRosterEntry> benchFor(String teamId) =>
      bench.where((b) => b.teamId == teamId).toList();

  ActivityDef? defFor(String type) {
    for (final d in schema) {
      if (d.type == type) return d;
    }
    return null;
  }

  factory GameDetail.fromJson(Map<String, dynamic> j) {
    final attrs = j['attributes'];
    GameLifecycle? lifecycle;
    PhaseTimer timer = const PhaseTimer();
    int? duration;
    if (attrs is Map) {
      final d = parseInt(attrs['durationMinutes']);
      if (d != null && d > 0) duration = d;
      final lc = attrs['lifecycle'];
      if (lc is Map) {
        lifecycle = GameLifecycle.fromJson(Map<String, dynamic>.from(lc));
      }
      final t = attrs['timer'];
      if (t is Map) {
        timer = PhaseTimer.fromJson(Map<String, dynamic>.from(t));
      }
    }
    List<T> listOf<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
        v is List
            ? [for (final e in v) f(Map<String, dynamic>.from(e as Map))]
            : <T>[];
    return GameDetail(
      id: (j['id'] ?? '') as String,
      status: (j['status'] ?? 'scheduled') as String,
      teams: listOf(j['teams'], GameTeam.fromJson),
      participants: listOf(j['participants'], GamePlayer.fromJson),
      roster: listOf(j['roster'], GameRosterEntry.fromJson),
      bench: listOf(j['bench'], GameRosterEntry.fromJson),
      activities: listOf(j['activities'], GameActivity.fromJson),
      schema: j['schema'] is Map && (j['schema'] as Map)['activities'] is List
          ? [
              for (final d in (j['schema'] as Map)['activities'] as List)
                ActivityDef.fromJson(Map<String, dynamic>.from(d as Map))
            ]
          : listOf(j['schema'], ActivityDef.fromJson),
      canManage: j['canManage'] == true,
      canManageLineup: j['canManageLineup'] == true,
      startedAt: parseDate(j['startedAt']),
      endedAt: parseDate(j['endedAt']),
      lifecycle: lifecycle,
      timer: timer,
      serverNow: parseDate(j['serverNow']),
      fetchedAt: DateTime.now(),
      maxTeamsPerGame: parseInt(j['maxTeamsPerGame']) ?? 2,
      maxPlayersPerTeam: parseInt(j['maxPlayersPerTeam']) ?? 11,
      categoryName: parseStr(j['categoryName']),
      categoryEmoji: parseStr(j['categoryEmoji']),
      eventSlug: parseStr(j['eventSlug']),
      isTournament: j['isTournament'] == true,
      leagueSlug: j['league'] is Map ? parseStr((j['league'] as Map)['slug']) : null,
      firstLeg: j['aggregate'] is Map && (j['aggregate'] as Map)['firstLeg'] is Map
          ? {
              for (final e in ((j['aggregate'] as Map)['firstLeg'] as Map).entries)
                '${e.key}': (e.value is num) ? (e.value as num).toInt() : 0,
            }
          : const {},
      awayGoals: j['aggregate'] is Map && (j['aggregate'] as Map)['awayGoals'] == true,
      legHomeTeamId: j['aggregate'] is Map ? parseStr((j['aggregate'] as Map)['homeTeamId']) : null,
      scoresheetHolder: null,
      officiantNames: j['officiants'] is Map &&
              (j['officiants'] as Map)['people'] is List
          ? [
              for (final o in (j['officiants'] as Map)['people'] as List)
                if (o is Map && o['displayName'] != null) '${o['displayName']}'
            ]
          : const [],
      officiants:
          j['officiants'] is Map && (j['officiants'] as Map)['people'] is List
              ? [
                  for (final o in (j['officiants'] as Map)['people'] as List)
                    if (o is Map)
                      GameOfficiant.fromJson(Map<String, dynamic>.from(o))
                ]
              : const [],
      officiating: OfficiatingRights.fromJson(j['officiating'],
          fallback: j['canManage'] == true),
      profile: OfficiatingProfile.fromJson(j['officiatingProfile']),
      durationMinutes: duration,
      basketball: BasketballInfo.fromJson(j['basketball']),
      volleyball: VolleyballInfo.fromJson(j['volleyball']),
      clockBy: attrs is Map && attrs['clock'] is Map
          ? ClockBy.fromJson((attrs['clock'] as Map)['lastBy'])
          : null,
      ratings: j['ratings'] is Map
          ? {
              for (final e in (j['ratings'] as Map).entries)
                if (e.value is Map && (e.value as Map)['rating'] is num)
                  '${e.key}': ((e.value as Map)['rating'] as num).toDouble(),
            }
          : const {},
    );
  }
}

/// The last clock action on a match and who took it
/// (attributes.clock.lastBy, stamped server-side on every clock action).
class ClockBy {
  const ClockBy({required this.name, this.userId, this.action, this.via});
  final String name;
  final String? userId;

  /// kickoff · pause · resume · stoppage · endPhase · startNext · fullTime …
  final String? action;

  /// web · app · watchos · wearos
  final String? via;

  static ClockBy? fromJson(dynamic j) {
    if (j is! Map) return null;
    final name = j['name'];
    if (name is! String || name.isEmpty) return null;
    return ClockBy(
      name: name,
      userId: j['userId'] is String ? j['userId'] as String : null,
      action: j['action'] is String ? j['action'] as String : null,
      via: j['via'] is String ? j['via'] as String : null,
    );
  }
}

/// "Paused · by Ade" (or "· by you") while the clock is stopped by a pause;
/// just [base] when we don't know who, or it stopped for another reason.
String pausedLabel(GameDetail g, String? myUserId, {String base = 'Paused'}) {
  final by = g.clockBy;
  if (by == null || by.action != 'pause') return base;
  final who = myUserId != null && by.userId == myUserId ? 'you' : by.name;
  return '$base · by $who';
}
