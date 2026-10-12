import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';

/// A lenient view over one JSON object from the leagues API (the shapes
/// mirror the web's `leagues` router 1:1, so the app reads them directly
/// instead of keeping a parallel set of model classes in step).
class J {
  const J(this.raw);
  final Map<String, dynamic> raw;

  static J of(dynamic v) =>
      J(v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{});

  bool has(String k) => raw[k] != null;
  String? s(String k) {
    final v = raw[k];
    if (v == null) return null;
    final t = v.toString();
    return t.isEmpty ? null : t;
  }

  String str(String k, [String fallback = '']) => s(k) ?? fallback;
  int i(String k, [int fallback = 0]) {
    final v = raw[k];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  int? iOrNull(String k) {
    final v = raw[k];
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  double? d(String k) {
    final v = raw[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  bool b(String k) => raw[k] == true;
  DateTime? date(String k) {
    final v = raw[k];
    return v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
  }

  J? o(String k) => raw[k] is Map ? J.of(raw[k]) : null;
  List<J> list(String k) => raw[k] is List
      ? [for (final x in raw[k] as List) if (x is Map) J.of(x)]
      : const [];
  List<String> strs(String k) => raw[k] is List
      ? [for (final x in raw[k] as List) if (x != null) x.toString()]
      : const [];
}

class LeaguesRepository {
  LeaguesRepository(this._dio);
  final Dio _dio;

  /// GET /api/mobile/leagues/<op>?input=<json>
  Future<dynamic> query(String op, [Map<String, dynamic>? input]) async {
    try {
      final res = await _dio.get('/api/mobile/leagues/$op',
          queryParameters: input == null ? null : {'input': jsonEncode(input)});
      return res.data;
    } catch (e) {
      throw apiError(e, fallback: 'Could not load the league.');
    }
  }

  /// POST /api/mobile/leagues/<op>
  Future<dynamic> mutate(String op, Map<String, dynamic> input) async {
    try {
      final res = await _dio.post('/api/mobile/leagues/$op', data: input);
      return res.data;
    } catch (e) {
      throw apiError(e, fallback: "That didn't work — try again.");
    }
  }

  Future<J> obj(String op, [Map<String, dynamic>? input]) async =>
      J.of(await query(op, input));

  Future<List<J>> arr(String op, [Map<String, dynamic>? input]) async {
    final v = await query(op, input);
    return v is List ? [for (final x in v) if (x is Map) J.of(x)] : const [];
  }
}

final leaguesRepositoryProvider = Provider<LeaguesRepository>(
    (ref) => LeaguesRepository(ref.watch(dioProvider)));

LeaguesRepository _r(Ref ref) => ref.watch(leaguesRepositoryProvider);

/// Organiser console payload (league, stages, teams, fixtures, tables, MVPs…).
final leagueManageProvider = FutureProvider.autoDispose.family<J, String>(
    (ref, leagueId) => _r(ref).obj('manage', {'leagueId': leagueId}));

/// Public league page by slug.
final leaguePublicProvider = FutureProvider.autoDispose
    .family<J, String>((ref, slug) => _r(ref).obj('get', {'slug': slug}));

/// A competition across its seasons (web `/competitions/[slug]`).
final competitionProvider = FutureProvider.autoDispose
    .family<J, String>((ref, slug) => _r(ref).obj('competition', {'slug': slug}));

/// One full ranking list. Key = "slug|key".
final leagueRankingProvider =
    FutureProvider.autoDispose.family<J, String>((ref, k) {
  final i = k.indexOf('|');
  return _r(ref)
      .obj('ranking', {'slug': k.substring(0, i), 'key': k.substring(i + 1)});
});

final groupLeaguesProvider = FutureProvider.autoDispose
    .family<List<J>, String>(
        (ref, groupId) => _r(ref).arr('listForGroup', {'groupId': groupId}));

final leagueSetupProvider = FutureProvider.autoDispose
    .family<J, String>((ref, groupId) => _r(ref).obj('setup', {'groupId': groupId}));

/// Coach: league invitations / entries of teams in groups I run.
final myLeagueEntriesProvider = FutureProvider.autoDispose<List<J>>(
    (ref) => _r(ref).arr('myEntries'));

/// Player: my registrations + pass state + next matches.
final myLeaguesProvider =
    FutureProvider.autoDispose<List<J>>((ref) => _r(ref).arr('myLeagues'));

/// Player: my open league call-ups (accepting registers me).
final myLeagueCallsProvider =
    FutureProvider.autoDispose<List<J>>((ref) => _r(ref).arr('myCalls'));

/// Organiser: the season's venues, earlier ones to copy, home venues, unplaced fixtures.
final leagueVenuesProvider = FutureProvider.autoDispose
    .family<J, String>((ref, leagueId) => _r(ref).obj('venues', {'leagueId': leagueId}));

final leaguePassProvider = FutureProvider.autoDispose
    .family<J, String>((ref, entryId) => _r(ref).obj('pass', {'entryId': entryId}));

/// Key = "leagueId|teamId".
final leagueRosterProvider =
    FutureProvider.autoDispose.family<J, String>((ref, k) {
  final i = k.indexOf('|');
  return _r(ref).obj(
      'roster', {'leagueId': k.substring(0, i), 'teamId': k.substring(i + 1)});
});

final leagueAdvancementProvider = FutureProvider.autoDispose
    .family<J?, String>((ref, leagueId) async {
  final v = await _r(ref).query('advancement', {'leagueId': leagueId});
  return v is Map ? J.of(v) : null;
});

final leagueChecksProvider = FutureProvider.autoDispose.family<List<J>, String>(
    (ref, leagueId) => _r(ref).arr('checks', {'leagueId': leagueId}));

/// Key = "leagueId|query".
final leagueTeamSearchProvider =
    FutureProvider.autoDispose.family<List<J>, String>((ref, k) {
  final i = k.indexOf('|');
  return _r(ref).arr(
      'searchTeams', {'leagueId': k.substring(0, i), 'q': k.substring(i + 1)});
});

final leagueNextSeasonProvider = FutureProvider.autoDispose.family<J, String>(
    (ref, leagueId) => _r(ref).obj('nextSeasonPlan', {'leagueId': leagueId}));

/// A group's teams in leagues (the group's Leagues tab): invitations (admins),
/// current and past seasons per team.
final groupTeamLeaguesProvider = FutureProvider.autoDispose.family<J, String>(
    (ref, groupId) => _r(ref).obj('forGroupTeams', {'groupId': groupId}));

/// One team's league seasons (team page).
final teamLeaguesProvider = FutureProvider.autoDispose
    .family<J, String>((ref, teamId) => _r(ref).obj('forTeam', {'teamId': teamId}));

/// Current-league badges for teams. Key = comma-joined sorted team ids.
final teamLeagueBadgesProvider =
    FutureProvider.autoDispose.family<Map<String, List<J>>, String>((ref, key) async {
  final ids = key.split(',').where((x) => x.isNotEmpty).toList();
  if (ids.isEmpty) return const {};
  final v = await _r(ref).query('teamBadges', {'teamIds': ids});
  if (v is! Map) return const {};
  return {
    for (final e in v.entries)
      e.key.toString(): [if (e.value is List) for (final x in e.value as List) if (x is Map) J.of(x)],
  };
});
