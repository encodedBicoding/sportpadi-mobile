import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Gamification (docs/gamification): level, streaks, quests, achievements,
/// boards and the post-match summary. Same endpoints the web uses through
/// tRPC, via the /api/mobile/progression mirrors.

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _list(dynamic v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];
int _int(dynamic v) => parseInt(v) ?? 0;
double _dbl(dynamic v) => parseDouble(v) ?? 0;

class Streak {
  const Streak({required this.current, required this.best, required this.paused});
  final int current;
  final int best;
  final bool paused;
  factory Streak.fromJson(Map<String, dynamic> j) =>
      Streak(current: _int(j['current']), best: _int(j['best']), paused: j['paused'] == true);
}

class Quest {
  const Quest({required this.key, required this.title, required this.description, required this.target, required this.progress, required this.done});
  final String key, title, description;
  final int target, progress;
  final bool done;
  factory Quest.fromJson(Map<String, dynamic> j) => Quest(
        key: parseStr(j['key']) ?? '',
        title: parseStr(j['title']) ?? '',
        description: parseStr(j['description']) ?? '',
        target: _int(j['target']),
        progress: _int(j['progress']),
        done: j['done'] == true,
      );
}

class Mission {
  const Mission({required this.key, required this.title, required this.description, required this.target, required this.progress, required this.done, required this.xp, this.endsAt});
  final String key, title, description;
  final int target, progress, xp;
  final bool done;
  final DateTime? endsAt;
  factory Mission.fromJson(Map<String, dynamic> j) => Mission(
        key: parseStr(j['key']) ?? '',
        title: parseStr(j['title']) ?? '',
        description: parseStr(j['description']) ?? '',
        target: _int(j['target']),
        progress: _int(j['progress']),
        done: j['done'] == true,
        xp: _int(j['xp']),
        endsAt: parseDate(j['endsAt']),
      );
}

class WeekQuests {
  const WeekQuests({required this.quests, required this.completed, required this.needed, required this.rewardXp, required this.rewarded, this.endsAt, this.missions = const []});
  final List<Mission> missions;
  final List<Quest> quests;
  final int completed, needed, rewardXp;
  final bool rewarded;
  final DateTime? endsAt;
  factory WeekQuests.fromJson(Map<String, dynamic> j) => WeekQuests(
        quests: [for (final q in _list(j['quests'])) Quest.fromJson(q)],
        completed: _int(j['completed']),
        needed: _int(j['needed']),
        rewardXp: _int(j['rewardXp']),
        rewarded: j['rewarded'] == true,
        endsAt: parseDate(j['endsAt']),
        missions: [for (final m in _list(j['missions'])) Mission.fromJson(m)],
      );
}

class NextUnlock {
  const NextUnlock({required this.title, required this.description, required this.current, required this.target});
  final String title, description;
  final int current, target;
}

class YourWeek {
  const YourWeek({required this.level, required this.title, required this.xp, required this.nextLevelXp, required this.progress, required this.streak, this.quests, this.next});
  final int level, xp;
  final int? nextLevelXp;
  final String title;
  final double progress;
  final Streak streak;
  final WeekQuests? quests;
  final NextUnlock? next;

  static YourWeek? fromJson(Map<String, dynamic> j) {
    if (j['available'] != true) return null;
    final n = j['next'] is Map ? _map(j['next']) : null;
    return YourWeek(
      level: _int(j['level']),
      title: parseStr(j['title']) ?? 'Rookie',
      xp: _int(j['xp']),
      nextLevelXp: parseInt(j['nextLevelXp']),
      progress: _dbl(j['progress']),
      streak: Streak.fromJson(_map(j['streak'])),
      quests: j['quests'] is Map ? WeekQuests.fromJson(_map(j['quests'])) : null,
      next: n == null
          ? null
          : NextUnlock(
              title: parseStr(n['title']) ?? '',
              description: parseStr(n['description']) ?? '',
              current: _int(n['current']),
              target: _int(n['target'])),
    );
  }
}

class Achievement {
  const Achievement({required this.key, required this.title, required this.description, required this.xp, this.unlocked = false});
  final String key, title, description;
  final int xp;
  final bool unlocked;
}

class MyProgression {
  const MyProgression({
    required this.level,
    required this.title,
    required this.isPublic,
    required this.xp,
    required this.nextLevelXp,
    required this.progress,
    required this.categories,
    required this.weekly,
    required this.unlocked,
    required this.catalogue,
  });
  final int level;
  final String title;
  final bool isPublic;
  final int? xp;
  final int? nextLevelXp;
  final double progress;
  final List<({String categoryId, String title, int level})> categories;
  final Streak? weekly;
  final List<Achievement> unlocked;
  final List<Achievement> catalogue;

  static MyProgression? fromJson(Map<String, dynamic> j) {
    if (j['available'] != true) return null;
    final got = {for (final a in _list(j['achievements'])) parseStr(a['key']) ?? ''};
    final streaks = _list(j['streaks']);
    final w = streaks.where((s) => s['key'] == 'weekly').toList();
    return MyProgression(
      level: _int(j['level']),
      title: parseStr(j['title']) ?? 'Rookie',
      isPublic: j['public'] == true,
      xp: parseInt(j['xp']),
      nextLevelXp: parseInt(j['nextLevelXp']),
      progress: _dbl(j['progress']),
      categories: [
        for (final c in _list(j['categories']))
          (categoryId: parseStr(c['categoryId']) ?? '', title: parseStr(c['title']) ?? '', level: _int(c['level']))
      ],
      weekly: w.isEmpty ? null : Streak.fromJson(w.first),
      unlocked: [
        for (final a in _list(j['achievements']))
          Achievement(
              key: parseStr(a['key']) ?? '',
              title: parseStr(a['title']) ?? '',
              description: parseStr(a['description']) ?? '',
              xp: _int(a['xp']),
              unlocked: true)
      ],
      catalogue: [
        for (final a in _list(j['catalogue']))
          Achievement(
              key: parseStr(a['key']) ?? '',
              title: parseStr(a['title']) ?? '',
              description: parseStr(a['description']) ?? '',
              xp: _int(a['xp']),
              unlocked: got.contains(parseStr(a['key'])))
      ],
    );
  }
}

class Identity {
  const Identity({required this.level, required this.title, this.weeklyStreak, this.frame = 'none'});
  final int level;
  final String title;
  final int? weeklyStreak;
  /// Avatar frame earned by level: none | bronze | silver | gold | legend.
  final String frame;
}

class Season {
  const Season({required this.id, required this.name, this.startsAt, this.endsAt});
  final String id, name;
  final DateTime? startsAt, endsAt;
}

class GroupProgression {
  const GroupProgression({
    required this.level,
    required this.progress,
    required this.weeklyStreak,
    required this.games,
    required this.players,
    required this.venues,
    required this.xp,
    required this.achievements,
    required this.titles,
    required this.seasons,
  });
  final int level, weeklyStreak, games, players, venues, xp;
  final double progress;
  final List<String> achievements;
  final Map<String, List<String>> titles;
  final List<Season> seasons;

  Season? get currentSeason {
    for (final s in seasons) {
      if (s.endsAt == null) return s;
    }
    return null;
  }

  factory GroupProgression.fromJson(Map<String, dynamic> j) {
    final r = _map(j['reputation']);
    final t = _map(j['titles']);
    return GroupProgression(
      level: _int(r['level']),
      progress: _dbl(r['progress']),
      weeklyStreak: _int(r['weeklyStreak']),
      games: _int(r['games']),
      players: _int(r['players']),
      venues: _int(r['venues']),
      xp: _int(r['xp']),
      achievements: [
        for (final a in _list(r['achievements']))
          if (a['got'] == true) parseStr(a['title']) ?? ''
      ],
      titles: {
        for (final e in t.entries)
          e.key: [for (final v in (e.value is List ? e.value as List : const [])) '$v']
      },
      seasons: [
        for (final s in _list(j['seasons']))
          Season(
            id: parseStr(s['id']) ?? '',
            name: parseStr(s['name']) ?? 'Season',
            startsAt: parseDate(s['startsAt']),
            endsAt: parseDate(s['endsAt']),
          )
      ],
    );
  }
}

class RewardLine {
  const RewardLine({required this.kind, required this.label, required this.xp, required this.count});
  final String kind, label;
  final int xp, count;
  factory RewardLine.fromJson(Map<String, dynamic> j) => RewardLine(
      kind: parseStr(j['kind']) ?? '', label: parseStr(j['label']) ?? '', xp: _int(j['xp']), count: _int(j['count']));
}

class MatchSummary {
  const MatchSummary({
    required this.status,
    required this.played,
    required this.teams,
    required this.myStats,
    required this.xp,
    required this.earned,
    required this.unlocked,
    this.identity,
    this.eventTitle,
  });
  final String status;
  final bool played;
  final List<({String name, int score, String? result, bool mine, String? color})> teams;
  final List<({String label, String? icon, int value})> myStats;
  final int xp;
  final List<RewardLine> earned;
  final List<String> unlocked;
  final ({int level, String title, int weeklyStreak})? identity;
  final String? eventTitle;

  factory MatchSummary.fromJson(Map<String, dynamic> j) {
    final id = j['identity'] is Map ? _map(j['identity']) : null;
    return MatchSummary(
      status: parseStr(j['status']) ?? '',
      played: j['played'] == true,
      teams: [
        for (final t in _list(j['teams']))
          (
            name: parseStr(t['name']) ?? 'Team',
            score: _int(t['score']),
            result: parseStr(t['result']),
            mine: t['mine'] == true,
            color: parseStr(t['color'])
          )
      ],
      myStats: [
        for (final s in _list(j['myStats']))
          (label: parseStr(s['label']) ?? '', icon: parseStr(s['icon']), value: _int(s['value']))
      ],
      xp: _int(j['xp']),
      earned: [for (final l in _list(j['earned'])) RewardLine.fromJson(l)],
      unlocked: [for (final u in _list(j['unlocked'])) parseStr(u['title']) ?? ''],
      identity: id == null
          ? null
          : (level: _int(id['level']), title: parseStr(id['title']) ?? '', weeklyStreak: _int(id['weeklyStreak'])),
      eventTitle: parseStr(_map(j['event'])['title']),
    );
  }
}

class BoardEntry {
  const BoardEntry({required this.rank, required this.userId, required this.displayName, required this.username, this.avatarUrl, this.value});
  final int rank;
  final String userId, displayName, username;
  final String? avatarUrl;
  final int? value;
}

class Board {
  const Board({required this.title, required this.unit, required this.blurb, required this.entries, this.needsCategory = false});
  final String title, unit, blurb;
  final List<BoardEntry> entries;
  final bool needsCategory;
  factory Board.fromJson(Map<String, dynamic> j) => Board(
        title: parseStr(j['title']) ?? '',
        unit: parseStr(j['unit']) ?? '',
        blurb: parseStr(j['blurb']) ?? '',
        needsCategory: j['needsCategory'] == true,
        entries: [
          for (final e in _list(j['entries']))
            BoardEntry(
              rank: _int(e['rank']),
              userId: parseStr(e['userId']) ?? '',
              displayName: parseStr(e['displayName']) ?? 'Player',
              username: parseStr(e['username']) ?? '',
              avatarUrl: parseStr(e['avatarUrl']),
              value: parseInt(e['value']),
            )
        ],
      );
}

class Strength {
  const Strength({required this.label, this.icon, required this.value, required this.percentile});
  final String label;
  final String? icon;
  final int value, percentile;
}

class ProgressionRepository {
  ProgressionRepository(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> _get(String path, {Map<String, dynamic>? query, String fallback = 'Could not load.'}) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      return _map(res.data);
    } catch (e) {
      throw apiError(e, fallback: fallback);
    }
  }

  Future<YourWeek?> week() async => YourWeek.fromJson(await _get('/api/mobile/progression/week'));

  Future<MyProgression?> me() async => MyProgression.fromJson(await _get('/api/mobile/progression/me'));

  Future<void> setPublic(bool value) async {
    try {
      await _dio.post('/api/mobile/progression/me', data: {'public': value});
    } catch (e) {
      throw apiError(e, fallback: 'Could not save.');
    }
  }

  Future<Identity?> identity(String userId) async {
    try {
      final res = await _dio.get('/api/mobile/progression/identity/$userId');
      if (res.data is! Map) return null;
      final j = _map(res.data);
      return Identity(
          level: _int(j['level']),
          title: parseStr(j['title']) ?? '',
          weeklyStreak: parseInt(j['weeklyStreak']),
          frame: parseStr(j['frame']) ?? 'none');
    } catch (_) {
      return null; // identity is decoration: never fail a screen over it
    }
  }

  Future<MatchSummary> game(String gameId) async =>
      MatchSummary.fromJson(await _get('/api/mobile/progression/game/$gameId', fallback: 'Could not load the match.'));

  Future<GroupProgression?> group(String groupId) async {
    try {
      return GroupProgression.fromJson(await _get('/api/mobile/progression/group/$groupId'));
    } catch (_) {
      return null; // decoration: never fail the group page over it
    }
  }

  Future<void> startSeason(String groupId, String name) async {
    try {
      await _dio.post('/api/mobile/progression/group/$groupId', data: {'action': 'startSeason', 'name': name});
    } catch (e) {
      throw apiError(e, fallback: 'Could not start the season.');
    }
  }

  Future<Board> board(String board, {String? groupId, String? categoryId, String? seasonId}) async => Board.fromJson(await _get(
        '/api/mobile/progression/board',
        query: {
          'board': board,
          if (groupId != null) 'groupId': groupId,
          if (categoryId != null) 'categoryId': categoryId,
          if (seasonId != null) 'seasonId': seasonId,
          'limit': 25,
        },
        fallback: 'Could not load the board.',
      ));

  Future<List<Strength>> strengths(String userId, String categoryId) async {
    try {
      final res = await _dio.get('/api/mobile/progression/strengths/$userId', queryParameters: {'categoryId': categoryId});
      if (res.data is! Map) return const [];
      return [
        for (final m in _list(_map(res.data)['metrics']))
          if (_int(m['value']) > 0)
            Strength(label: parseStr(m['label']) ?? '', icon: parseStr(m['icon']), value: _int(m['value']), percentile: _int(m['percentile']))
      ];
    } catch (_) {
      return const [];
    }
  }
}

final progressionRepositoryProvider =
    Provider<ProgressionRepository>((ref) => ProgressionRepository(ref.watch(dioProvider)));

final yourWeekProvider = FutureProvider.autoDispose<YourWeek?>((ref) => ref.watch(progressionRepositoryProvider).week());

final myProgressionProvider =
    FutureProvider.autoDispose<MyProgression?>((ref) => ref.watch(progressionRepositoryProvider).me());

final identityProvider = FutureProvider.autoDispose
    .family<Identity?, String>((ref, userId) => ref.watch(progressionRepositoryProvider).identity(userId));

final matchSummaryProvider = FutureProvider.autoDispose
    .family<MatchSummary, String>((ref, gameId) => ref.watch(progressionRepositoryProvider).game(gameId));

typedef BoardKey = ({String board, String? groupId, String? categoryId, String? seasonId});

final boardProvider = FutureProvider.autoDispose.family<Board, BoardKey>((ref, k) => ref
    .watch(progressionRepositoryProvider)
    .board(k.board, groupId: k.groupId, categoryId: k.categoryId, seasonId: k.seasonId));

final groupProgressionProvider = FutureProvider.autoDispose
    .family<GroupProgression?, String>((ref, groupId) => ref.watch(progressionRepositoryProvider).group(groupId));

final strengthsProvider = FutureProvider.autoDispose
    .family<List<Strength>, ({String userId, String categoryId})>(
        (ref, k) => ref.watch(progressionRepositoryProvider).strengths(k.userId, k.categoryId));
