import '../../shared/format/parse.dart';

/// Basketball — the rules a game is played under plus the numbers beyond the
/// score (team fouls / bonus, personal fouls, first-to-N winner, box score).
/// Mirrors `games.get → basketball` (packages/api/src/games/basketball.ts).
class BasketballRules {
  const BasketballRules({
    this.format = 'timed',
    this.quarterMinutes = 10,
    this.overtimeMinutes = 5,
    this.targetScore = 21,
    this.winBy = 2,
    this.foulLimit = 5,
    this.bonusAt = 5,
    this.timeoutsFirstHalf = 2,
    this.timeoutsSecondHalf = 3,
    this.timeoutsPerOvertime = 1,
    this.timeoutsPerGame = 2,
    this.shotClock = 24,
    this.shotClockShort = 14,
  });

  /// timed | target
  final String format;
  final int quarterMinutes;
  final int overtimeMinutes;
  final int targetScore;
  final int winBy;
  final int foulLimit;
  final int bonusAt;

  /// FIBA: 2 in the first half, 3 in the second (max 2 in the last two
  /// minutes of Q4), 1 per overtime; first-to-N counts the whole game.
  final int timeoutsFirstHalf;
  final int timeoutsSecondHalf;
  final int timeoutsPerOvertime;
  final int timeoutsPerGame;

  /// Shot clock seconds (0 = none) and the reset after an offensive rebound.
  final int shotClock;
  final int shotClockShort;

  bool get isTarget => format == 'target';

  BasketballRules copyWith({
    String? format,
    int? quarterMinutes,
    int? overtimeMinutes,
    int? targetScore,
    int? winBy,
    int? foulLimit,
    int? bonusAt,
    int? timeoutsFirstHalf,
    int? timeoutsSecondHalf,
    int? timeoutsPerOvertime,
    int? timeoutsPerGame,
    int? shotClock,
    int? shotClockShort,
  }) =>
      BasketballRules(
        format: format ?? this.format,
        quarterMinutes: quarterMinutes ?? this.quarterMinutes,
        overtimeMinutes: overtimeMinutes ?? this.overtimeMinutes,
        targetScore: targetScore ?? this.targetScore,
        winBy: winBy ?? this.winBy,
        foulLimit: foulLimit ?? this.foulLimit,
        bonusAt: bonusAt ?? this.bonusAt,
        timeoutsFirstHalf: timeoutsFirstHalf ?? this.timeoutsFirstHalf,
        timeoutsSecondHalf: timeoutsSecondHalf ?? this.timeoutsSecondHalf,
        timeoutsPerOvertime: timeoutsPerOvertime ?? this.timeoutsPerOvertime,
        timeoutsPerGame: timeoutsPerGame ?? this.timeoutsPerGame,
        shotClock: shotClock ?? this.shotClock,
        shotClockShort: shotClockShort ?? this.shotClockShort,
      );

  Map<String, dynamic> toJson() => {
        'format': format,
        'quarterMinutes': quarterMinutes,
        'overtimeMinutes': overtimeMinutes,
        'targetScore': targetScore,
        'winBy': winBy,
        'foulLimit': foulLimit,
        'bonusAt': bonusAt,
        'timeoutsFirstHalf': timeoutsFirstHalf,
        'timeoutsSecondHalf': timeoutsSecondHalf,
        'timeoutsPerOvertime': timeoutsPerOvertime,
        'timeoutsPerGame': timeoutsPerGame,
        'shotClock': shotClock,
        'shotClockShort': shotClockShort,
      };

  factory BasketballRules.fromJson(dynamic j) {
    if (j is! Map) return const BasketballRules();
    return BasketballRules(
      format: parseStr(j['format']) == 'target' ? 'target' : 'timed',
      quarterMinutes: parseInt(j['quarterMinutes']) ?? 10,
      overtimeMinutes: parseInt(j['overtimeMinutes']) ?? 5,
      targetScore: parseInt(j['targetScore']) ?? 21,
      winBy: parseInt(j['winBy']) ?? 2,
      foulLimit: parseInt(j['foulLimit']) ?? 5,
      bonusAt: parseInt(j['bonusAt']) ?? 5,
      timeoutsFirstHalf: parseInt(j['timeoutsFirstHalf']) ?? 2,
      timeoutsSecondHalf: parseInt(j['timeoutsSecondHalf']) ?? 3,
      timeoutsPerOvertime: parseInt(j['timeoutsPerOvertime']) ?? 1,
      timeoutsPerGame: parseInt(j['timeoutsPerGame']) ?? 2,
      shotClock: parseInt(j['shotClock']) ?? 24,
      shotClockShort: parseInt(j['shotClockShort']) ?? 14,
    );
  }
}

/// A team timeout in progress — the on-screen countdown (basketball 60 s,
/// volleyball 30 s).
class ActiveTimeout {
  const ActiveTimeout(
      {required this.teamId, required this.at, this.seconds = 60});
  final String teamId;
  final DateTime at;
  final int seconds;

  static ActiveTimeout? fromJson(dynamic j) {
    if (j is! Map) return null;
    final teamId = parseStr(j['teamId']);
    final at = parseDate(j['at']);
    if (teamId == null || at == null) return null;
    return ActiveTimeout(
        teamId: teamId, at: at, seconds: parseInt(j['seconds']) ?? 60);
  }
}

/// The basketball shot clock: time left when it last stopped, and since when
/// it has been running (null = stopped).
class ShotClockState {
  const ShotClockState({required this.remainingMs, this.runningSince});
  final int remainingMs;
  final DateTime? runningSince;
  bool get running => runningSince != null;

  /// Milliseconds left at [now] (server time).
  int leftMs(DateTime now) {
    if (runningSince == null) return remainingMs < 0 ? 0 : remainingMs;
    var ran = now.difference(runningSince!).inMilliseconds;
    if (ran < 0) ran = 0;
    final left = remainingMs - ran;
    return left < 0 ? 0 : left;
  }

  static ShotClockState? fromJson(dynamic j) {
    if (j is! Map) return null;
    final ms = parseInt(j['remainingMs']);
    if (ms == null) return null;
    return ShotClockState(
        remainingMs: ms, runningSince: parseDate(j['runningSince']));
  }
}

Map<String, int> parseIntMap(dynamic v) => v is Map
    ? {for (final e in v.entries) '${e.key}': parseInt(e.value) ?? 0}
    : const {};

/// One box-score line (a player's, or a team's totals).
class BoxLine {
  const BoxLine({
    this.pts = 0,
    this.fgm = 0,
    this.fga = 0,
    this.tpm = 0,
    this.tpa = 0,
    this.ftm = 0,
    this.fta = 0,
    this.oreb = 0,
    this.dreb = 0,
    this.reb = 0,
    this.ast = 0,
    this.stl = 0,
    this.blk = 0,
    this.tov = 0,
    this.pf = 0,
    this.playerId = '',
    this.teamId = '',
  });
  final int pts,
      fgm,
      fga,
      tpm,
      tpa,
      ftm,
      fta,
      oreb,
      dreb,
      reb,
      ast,
      stl,
      blk,
      tov,
      pf;
  final String playerId;
  final String teamId;

  factory BoxLine.fromJson(Map<String, dynamic> j) {
    int n(String k) => parseInt(j[k]) ?? 0;
    return BoxLine(
      pts: n('pts'),
      fgm: n('fgm'),
      fga: n('fga'),
      tpm: n('tpm'),
      tpa: n('tpa'),
      ftm: n('ftm'),
      fta: n('fta'),
      oreb: n('oreb'),
      dreb: n('dreb'),
      reb: n('reb'),
      ast: n('ast'),
      stl: n('stl'),
      blk: n('blk'),
      tov: n('tov'),
      pf: n('pf'),
      playerId: parseStr(j['playerId']) ?? '',
      teamId: parseStr(j['teamId']) ?? '',
    );
  }
}

class BasketballInfo {
  const BasketballInfo({
    required this.rules,
    this.foulPeriod,
    this.teamFouls = const {},
    this.inPenalty = const {},
    this.playerFouls = const {},
    this.targetWinnerTeamId,
    this.boxPlayers = const [],
    this.boxTeams = const {},
    this.timeoutsLeft = const {},
    this.timeoutPeriodLabel,
    this.activeTimeout,
    this.shotClock,
  });
  final BasketballRules rules;

  /// Timeouts each team still has in the current allowance.
  final Map<String, int> timeoutsLeft;

  /// "1st half" / "2nd half" / "Overtime" / "Game".
  final String? timeoutPeriodLabel;
  final ActiveTimeout? activeTimeout;

  /// Null when the game has no shot clock.
  final ShotClockState? shotClock;

  /// Quarter the team fouls are for ("Q3"); null when the whole game counts.
  final String? foulPeriod;
  final Map<String, int> teamFouls;
  final Map<String, bool> inPenalty;
  final Map<String, int> playerFouls;
  final String? targetWinnerTeamId;
  final List<BoxLine> boxPlayers;
  final Map<String, BoxLine> boxTeams;

  static BasketballInfo? fromJson(dynamic j) {
    if (j is! Map) return null;
    Map<String, int> ints(dynamic v) => parseIntMap(v);
    final box = j['box'];
    return BasketballInfo(
      rules: BasketballRules.fromJson(j['rules']),
      foulPeriod: parseStr(j['foulPeriod']),
      teamFouls: ints(j['teamFouls']),
      inPenalty: j['inPenalty'] is Map
          ? {
              for (final e in (j['inPenalty'] as Map).entries)
                '${e.key}': e.value == true
            }
          : const {},
      playerFouls: ints(j['playerFouls']),
      targetWinnerTeamId: parseStr(j['targetWinnerTeamId']),
      boxPlayers: box is Map && box['players'] is List
          ? [
              for (final l in box['players'] as List)
                if (l is Map) BoxLine.fromJson(Map<String, dynamic>.from(l))
            ]
          : const [],
      boxTeams: box is Map && box['teams'] is Map
          ? {
              for (final e in (box['teams'] as Map).entries)
                if (e.value is Map)
                  '${e.key}': BoxLine.fromJson(
                      Map<String, dynamic>.from(e.value as Map))
            }
          : const {},
      timeoutsLeft: ints(j['timeoutsLeft']),
      timeoutPeriodLabel: parseStr(j['timeoutPeriodLabel']),
      activeTimeout: ActiveTimeout.fromJson(j['activeTimeout']),
      shotClock: ShotClockState.fromJson(j['shotClock']),
    );
  }
}
