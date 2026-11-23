import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;

/// The server's time-zone rules, laid over the tz database baked into this
/// build — the Dart half of `packages/api/src/zoneTable.ts`.
///
/// The `timezone` package ships the IANA database as it was when the package
/// was published, and that goes stale the day a government changes its
/// clock. In November 2026 British Columbia stopped falling back (tzdata
/// 2026b): the bundled table still had Vancouver going to PST on Nov 1, so an
/// 8:15 kick-off showed as "8:15 AM PST" and "9:15 AM your time" for a viewer
/// on UTC−7, while the web (the browser's own, current ICU) said "PDT". The
/// server's ICU is the tz database the owner can update without a store
/// release, so `GET /api/mobile/timezones` hands the app its rules for a
/// window around today; here they replace the bundled ones inside that window
/// (history before it is kept) and are saved to a file so the next cold start
/// has them before the network does. Everything here fails quietly: the
/// bundled table is the fallback, never an error.

String? _baseUrl;
int _fetchedAtMs = 0;
Future<bool>? _inflight;

/// The bundled location for each zone the server's rules replaced, so a later
/// refresh merges onto the original rather than onto its own last merge.
final Map<String, tz.Location> _bundled = {};

/// Zones the bundled table didn't have at all (added from the server's rules).
final Set<String> _added = {};

/// The tz database version the server's rules came from ("2026e"), once any
/// have been applied — for diagnostics.
String? zoneRulesVersion;

/// Goes up whenever DIFFERENT rules are laid over the table (a new tz version
/// or window — not the same answer fetched again), so open screens can repaint
/// (`TimeZoneRulesHost`, shared/widgets/time_zone_rules_host.dart).
final ValueNotifier<int> zoneRulesRevision = ValueNotifier<int>(0);
String? _appliedSignature;

/// Zone names the last applied answer had rules for.
final Set<String> _covered = {};

/// Did the server's last answer include [name]? (Settings asks again,
/// straight away, for a picked zone it didn't.)
bool zoneRulesCover(String? name) => name != null && _covered.contains(name);

const _refreshEvery = Duration(hours: 12);
const _fileName = 'zone_rules_v1.json';
const _buildName =
    String.fromEnvironment('FLUTTER_BUILD_NAME', defaultValue: 'dev');

/// Where to fetch from (the flavour's API base URL); set once at start-up.
void configureZoneRules(String apiBaseUrl) => _baseUrl = apiBaseUrl;

Future<File?> _file() async {
  try {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  } catch (_) {
    return null;
  }
}

/// Apply the rules this phone saved last time. True when there were some and
/// their window still covers today.
Future<bool> loadCachedZoneRules() async {
  try {
    final f = await _file();
    if (f == null || !await f.exists()) return false;
    final saved = jsonDecode(await f.readAsString());
    if (saved is! Map) return false;
    final data = saved['data'];
    if (data is! Map || !applyZoneRules(data)) return false;
    final at = saved['fetchedAt'];
    _fetchedAtMs = at is int ? at : 0;
    return true;
  } catch (_) {
    return false;
  }
}

/// Fetch and apply the server's rules, at most every 12 hours unless [force].
/// [extra]: zone names to ask for explicitly (the phone's own, the picked one)
/// in case the server's table spells them differently. True when new rules
/// were applied. Never throws.
Future<bool> refreshZoneRules({
  List<String?> extra = const [],
  bool force = false,
}) {
  // A forced ask while a routine one is on its way: wait for it, then ask
  // again (with the names as they are now — a zone just picked).
  final running = _inflight;
  if (force && running != null) {
    return running.then((_) => refreshZoneRules(extra: extra, force: true));
  }
  final age = DateTime.now().millisecondsSinceEpoch - _fetchedAtMs;
  if (!force && age >= 0 && age < _refreshEvery.inMilliseconds) {
    return Future.value(false);
  }
  return _inflight ??= _refresh(extra).whenComplete(() => _inflight = null);
}

Future<bool> _refresh(List<String?> extra) async {
  final base = _baseUrl;
  if (base == null) return false;
  try {
    final names = <String>{
      for (final n in extra)
        if (n != null && n.isNotEmpty) n,
    }.take(8).join(',');
    // A plain client: no session needed (the route works signed out), and no
    // auth interceptor that could end a session on a stray 401.
    final dio = Dio(BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Accept': 'application/json',
        // Same as dio_client.dart: Dart's default agent gets bot-challenged.
        'User-Agent': 'SportPadi/$_buildName '
            '(${Platform.operatingSystem} ${Platform.operatingSystemVersion})',
      },
    ));
    final res = await dio.get<dynamic>(
      '/api/mobile/timezones',
      queryParameters: names.isEmpty ? null : {'zones': names},
    );
    final data = res.data;
    if (data is! Map || !applyZoneRules(data)) return false;
    _fetchedAtMs = DateTime.now().millisecondsSinceEpoch;
    final f = await _file();
    if (f != null) {
      try {
        await f.writeAsString(
            jsonEncode({'fetchedAt': _fetchedAtMs, 'data': data}));
      } catch (_) {
        // Not saved: the next cold start fetches again.
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Lay a `/api/mobile/timezones` answer over the tz database. False (and
/// nothing changed) when it is unreadable, or its window is already over.
bool applyZoneRules(Map<dynamic, dynamic> data) {
  final to = data['to'];
  final zones = data['zones'];
  if (to is! num || zones is! Map) return false;
  if (to.toInt() * 1000 < DateTime.now().millisecondsSinceEpoch) return false;
  final db = tz.timeZoneDatabase;
  if (!db.isInitialized) return false;
  final applied = <String>[];
  for (final e in zones.entries) {
    final name = e.key;
    final rules = e.value;
    if (name is! String || rules is! Map) continue;
    final loc = _parse(name, rules);
    if (loc == null) continue;
    db.add(loc);
    applied.add(name);
  }
  if (applied.isEmpty) return false;
  final v = data['tz'];
  zoneRulesVersion = v is String ? v : null;
  _covered
    ..clear()
    ..addAll(applied);
  // Same tz version, window and zones = the same rules: nothing to repaint.
  final signature = '$v|${data['from']}|$to|${applied.length}';
  if (signature != _appliedSignature) {
    _appliedSignature = signature;
    zoneRulesRevision.value++;
  }
  return true;
}

/// One zone's `{ t, z, o }` (packages/lib/src/zoneRules.ts) as a Location:
/// the bundled transitions before the window, then the server's.
tz.Location? _parse(String name, Map<dynamic, dynamic> r) {
  final t = r['t'];
  final z = r['z'];
  final o = r['o'];
  if (t is! List || z is! List || o is! List) return null;
  if (t.isEmpty || t.length != z.length || o.isEmpty) return null;

  final zones = <tz.TimeZone>[];
  for (final s in o) {
    if (s is! List || s.length < 3) return null;
    final off = s[0];
    final dst = s[1];
    final abbr = s[2];
    if (off is! num || off.abs() > 18 * 3600 || abbr is! String) return null;
    zones.add(tz.TimeZone(off.toInt() * 1000,
        isDst: dst == 1 || dst == true, abbreviation: abbr));
  }

  final at = <int>[];
  final zi = <int>[];
  for (var i = 0; i < t.length; i++) {
    final ti = t[i];
    final zz = z[i];
    if (ti is! num || zz is! int || zz < 0 || zz >= zones.length) return null;
    final ms = ti.toInt() * 1000;
    if (at.isNotEmpty && ms <= at.last) return null;
    at.add(ms);
    zi.add(zz);
  }

  final old = _pristine(name);
  if (old == null) return tz.Location(name, at, zi, zones);
  final mergedAt = <int>[];
  final mergedZi = <int>[];
  for (var i = 0; i < old.transitionAt.length; i++) {
    if (old.transitionAt[i] >= at.first) break;
    mergedAt.add(old.transitionAt[i]);
    mergedZi.add(old.transitionZone[i]);
  }
  final shift = old.zones.length;
  for (var i = 0; i < at.length; i++) {
    mergedAt.add(at[i]);
    mergedZi.add(shift + zi[i]);
  }
  return tz.Location(name, mergedAt, mergedZi, [...old.zones, ...zones]);
}

tz.Location? _pristine(String name) {
  final kept = _bundled[name];
  if (kept != null) return kept;
  if (_added.contains(name)) return null;
  final loc = tz.timeZoneDatabase.locations[name];
  if (loc == null) {
    _added.add(name);
    return null;
  }
  _bundled[name] = loc;
  return loc;
}
