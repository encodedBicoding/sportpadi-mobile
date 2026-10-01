import '../../shared/format/parse.dart';
import 'basketball_models.dart';

/// Volleyball — sets, set points, timeouts and the stat sheet. Mirrors
/// `games.get → volleyball` (packages/api/src/games/volleyball.ts).
class VolleyballRules {
  const VolleyballRules({
    this.bestOf = 5,
    this.setPoints = 25,
    this.decidingSetPoints = 15,
    this.winBy = 2,
    this.timeoutsPerSet = 2,
    this.switchAt = 8,
  });

  /// 1 (single set), 3 or 5.
  final int bestOf;
  final int setPoints;
  final int decidingSetPoints;
  final int winBy;
  final int timeoutsPerSet;

  /// Teams change ends in the deciding set when a team reaches this.
  final int switchAt;

  int get setsToWin => bestOf ~/ 2 + 1;

  VolleyballRules copyWith({
    int? bestOf,
    int? setPoints,
    int? decidingSetPoints,
    int? winBy,
    int? timeoutsPerSet,
    int? switchAt,
  }) =>
      VolleyballRules(
        bestOf: bestOf ?? this.bestOf,
        setPoints: setPoints ?? this.setPoints,
        decidingSetPoints: decidingSetPoints ?? this.decidingSetPoints,
        winBy: winBy ?? this.winBy,
        timeoutsPerSet: timeoutsPerSet ?? this.timeoutsPerSet,
        switchAt: switchAt ?? this.switchAt,
      );

  Map<String, dynamic> toJson() => {
        'bestOf': bestOf,
        'setPoints': setPoints,
        'decidingSetPoints': decidingSetPoints,
        'winBy': winBy,
        'timeoutsPerSet': timeoutsPerSet,
        'switchAt': switchAt,
      };

  factory VolleyballRules.fromJson(dynamic j) {
    if (j is! Map) return const VolleyballRules();
    final b = parseInt(j['bestOf']);
    return VolleyballRules(
      bestOf: b == 1 || b == 3 || b == 5 ? b! : 5,
      setPoints: parseInt(j['setPoints']) ?? 25,
      decidingSetPoints: parseInt(j['decidingSetPoints']) ?? 15,
      winBy: parseInt(j['winBy']) ?? 2,
      timeoutsPerSet: parseInt(j['timeoutsPerSet']) ?? 2,
      switchAt: parseInt(j['switchAt']) ?? 8,
    );
  }
}

/// One set: its target, the points each team has, and who won it.
class VbSetLine {
  const VbSetLine({required this.n, required this.target, this.points = const {}, this.winnerTeamId});
  final int n;
  final int target;
  final Map<String, int> points;
  final String? winnerTeamId;

  factory VbSetLine.fromJson(Map<String, dynamic> j) => VbSetLine(
        n: parseInt(j['n']) ?? 1,
        target: parseInt(j['target']) ?? 25,
        points: parseIntMap(j['points']),
        winnerTeamId: parseStr(j['winnerTeamId']),
      );
}

/// One stat-sheet line (a player's, or a team's totals).
class VbLine {
  const VbLine({
    this.pts = 0,
    this.kills = 0,
    this.attackErrors = 0,
    this.aces = 0,
    this.serviceErrors = 0,
    this.blocks = 0,
    this.digs = 0,
    this.assists = 0,
    this.receptionErrors = 0,
    this.faults = 0,
    this.playerId = '',
    this.teamId = '',
  });
  final int pts, kills, attackErrors, aces, serviceErrors, blocks, digs, assists, receptionErrors, faults;
  final String playerId;
  final String teamId;

  int get errors => attackErrors + serviceErrors + receptionErrors + faults;

  factory VbLine.fromJson(Map<String, dynamic> j) {
    int n(String k) => parseInt(j[k]) ?? 0;
    return VbLine(
      pts: n('pts'),
      kills: n('kills'),
      attackErrors: n('attackErrors'),
      aces: n('aces'),
      serviceErrors: n('serviceErrors'),
      blocks: n('blocks'),
      digs: n('digs'),
      assists: n('assists'),
      receptionErrors: n('receptionErrors'),
      faults: n('faults'),
      playerId: parseStr(j['playerId']) ?? '',
      teamId: parseStr(j['teamId']) ?? '',
    );
  }
}

class VolleyballInfo {
  const VolleyballInfo({
    required this.rules,
    this.currentSet = 1,
    this.sets = const [],
    this.setsWon = const {},
    this.matchWinnerTeamId,
    this.currentSetDecided = false,
    this.switchSidesDue = false,
    this.timeoutsLeft = const {},
    this.activeTimeout,
    this.boxPlayers = const [],
    this.boxTeams = const {},
  });
  final VolleyballRules rules;
  final int currentSet;
  final List<VbSetLine> sets;
  final Map<String, int> setsWon;
  final String? matchWinnerTeamId;

  /// The current set is over — the officiant starts the next one.
  final bool currentSetDecided;

  /// Deciding set, a team just reached the switch point: change ends.
  final bool switchSidesDue;
  final Map<String, int> timeoutsLeft;
  final ActiveTimeout? activeTimeout;
  final List<VbLine> boxPlayers;
  final Map<String, VbLine> boxTeams;

  VbSetLine? get current {
    for (final s in sets) {
      if (s.n == currentSet) return s;
    }
    return null;
  }

  static VolleyballInfo? fromJson(dynamic j) {
    if (j is! Map) return null;
    final box = j['box'];
    return VolleyballInfo(
      rules: VolleyballRules.fromJson(j['rules']),
      currentSet: parseInt(j['currentSet']) ?? 1,
      sets: j['sets'] is List
          ? [
              for (final s in j['sets'] as List)
                if (s is Map) VbSetLine.fromJson(Map<String, dynamic>.from(s))
            ]
          : const [],
      setsWon: parseIntMap(j['setsWon']),
      matchWinnerTeamId: parseStr(j['matchWinnerTeamId']),
      currentSetDecided: j['currentSetDecided'] == true,
      switchSidesDue: j['switchSidesDue'] == true,
      timeoutsLeft: parseIntMap(j['timeoutsLeft']),
      activeTimeout: ActiveTimeout.fromJson(j['activeTimeout']),
      boxPlayers: box is Map && box['players'] is List
          ? [
              for (final l in box['players'] as List)
                if (l is Map) VbLine.fromJson(Map<String, dynamic>.from(l))
            ]
          : const [],
      boxTeams: box is Map && box['teams'] is Map
          ? {
              for (final e in (box['teams'] as Map).entries)
                if (e.value is Map) '${e.key}': VbLine.fromJson(Map<String, dynamic>.from(e.value as Map))
            }
          : const {},
    );
  }
}
