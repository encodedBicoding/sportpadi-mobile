import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// The per-sport record design (docs/design/sport-records.md §2–§5, §8).
///
/// Thirteen sports get a bespoke design — soccer, basketball, volleyball,
/// baseball, tennis, padel, ping pong, chess, ultimate, golf, hiking, running
/// and paintball; every other sport (cricket, rugby …) shares the neutral
/// one. The server names the design in `design` (older payloads: `family`);
/// this file turns that into a look (gradient, accent, artwork) and the
/// numbers each design leads with.

/// Which record DESIGN a sport gets. (Named for its first life, when the
/// sport's family picked it; `design` on the payload picks it now.)
enum SportFamily {
  soccer,
  basketball,
  volleyball,
  baseball,
  tennis,
  padel,
  tableTennis,
  chess,
  ultimate,
  golf,
  hiking,
  running,
  paintball,
  generic,
}

/// The same enum by the name the design doc uses.
typedef SportDesign = SportFamily;

/// The server's sport family for a category name — a mirror of
/// `sportFamilyFor` in packages/api/src/games/activityDefaults.ts, for
/// payloads that only carry the category's name (event / tournament records).
String sportFamilyKeyFor(String? name) {
  final n = (name ?? '').toLowerCase();
  bool has(List<String> ks) => ks.any(n.contains);
  if (has(['american football', 'gridiron', 'nfl'])) return 'american_football';
  if (has(['basket'])) return 'basketball';
  if (has(['volley'])) return 'volleyball';
  if (has(['cricket'])) return 'cricket';
  if (has(['baseball', 'softball'])) return 'baseball';
  if (has(['rugby'])) return 'rugby';
  if (has(['hockey'])) return 'hockey';
  if (has(['netball'])) return 'netball';
  if (has(['handball'])) return 'handball';
  if (has([
    'tennis', 'padel', 'paddle', 'squash', 'badminton', 'pickle', 'racket', //
    'racquet', 'ping',
  ])) {
    return 'racket';
  }
  if (has([
    'soccer', 'football', 'futsal', 'futbol', 'five-a-side', '5-a-side', //
    '5 a side',
  ])) {
    return 'soccer';
  }
  return 'generic';
}

/// The design for a server `family` value. Only the four original bespoke
/// families have a design of their own; anything else is generic.
SportFamily designFamily(String? family) => switch (family) {
      'soccer' => SportFamily.soccer,
      'basketball' => SportFamily.basketball,
      'volleyball' => SportFamily.volleyball,
      'baseball' => SportFamily.baseball,
      _ => SportFamily.generic,
    };

/// The design for a server `design` value ("table_tennis" …), or null when
/// it's missing or unknown (a server newer than this app).
SportFamily? designFromKey(String? design) => switch (design) {
      'soccer' => SportFamily.soccer,
      'basketball' => SportFamily.basketball,
      'volleyball' => SportFamily.volleyball,
      'baseball' => SportFamily.baseball,
      'tennis' => SportFamily.tennis,
      'padel' => SportFamily.padel,
      'table_tennis' => SportFamily.tableTennis,
      'chess' => SportFamily.chess,
      'ultimate' => SportFamily.ultimate,
      'golf' => SportFamily.golf,
      'hiking' => SportFamily.hiking,
      'running' => SportFamily.running,
      'paintball' => SportFamily.paintball,
      'generic' => SportFamily.generic,
      _ => null,
    };

/// The design for a category name alone — a mirror of `recordDesignFor` in
/// packages/api/src/players/recordDesign.ts, for payloads that carry only a
/// name.
SportFamily designForName(String? name) {
  final n = (name ?? '').toLowerCase();
  bool has(List<String> ks) => ks.any(n.contains);
  if (has(['chess'])) return SportFamily.chess;
  if (has(['frisbee', 'ultimate'])) return SportFamily.ultimate;
  if (has(['golf'])) return SportFamily.golf;
  if (has(['paintball', 'airsoft'])) return SportFamily.paintball;
  // Before "tennis": table tennis and padel both contain other sports' words.
  if (has([
    'ping pong', 'ping-pong', 'pingpong', 'table tennis', 'table-tennis', //
  ])) {
    return SportFamily.tableTennis;
  }
  if (has(['padel', 'paddle'])) return SportFamily.padel;
  if (has(['tennis'])) return SportFamily.tennis;
  if (has(['hik', 'trek', 'hill walk'])) return SportFamily.hiking;
  if (has([
    'running', 'run club', 'jog', 'marathon', '5k', '10k', 'track', //
  ])) {
    return SportFamily.running;
  }
  return designFamily(sportFamilyKeyFor(name));
}

/// The design for a category name alone.
SportFamily familyForName(String? name) => designForName(name);

/// The design for a category record (or an event's / tournament's
/// `category`): its `design`, else its `family`, else its name.
SportFamily familyOf(Map<String, dynamic> category) {
  final byDesign = designFromKey(parseStr(category['design']));
  if (byDesign != null) return byDesign;
  final byFamily = designFamily(parseStr(category['family']));
  if (byFamily != SportFamily.generic) return byFamily;
  return designForName(parseStr(category['name']));
}

/// Sports about showing up rather than winning (§8): hikes and runs. Their
/// record leads with check-ins; W/D/L only appears when they have games.
bool isAttendanceDesign(SportFamily f) =>
    f == SportFamily.hiking || f == SportFamily.running;

/// Colours of one sport's hero: a two-stop vertical gradient and an accent
/// for the numbers that matter.
class SportTheme {
  const SportTheme({
    required this.top,
    required this.bottom,
    required this.accent,
    required this.artName,
    required this.emoji,
  });
  final Color top;
  final Color bottom;
  final Color accent;

  /// What the artwork is ("Pitch", "Hardwood" …) — for semantics only.
  final String artName;

  /// The emoji used when a category has none of its own.
  final String emoji;

  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, bottom],
      );
}

SportTheme sportTheme(SportFamily f) => switch (f) {
      SportFamily.soccer => const SportTheme(
          top: Color(0xFF0B6B3A),
          bottom: Color(0xFF064E2B),
          accent: Color(0xFF6EDC9E),
          artName: 'Pitch',
          emoji: '⚽'),
      SportFamily.basketball => const SportTheme(
          top: Color(0xFFB4531F),
          bottom: Color(0xFF7A3412),
          accent: Color(0xFFFDBA74),
          artName: 'Hardwood',
          emoji: '🏀'),
      SportFamily.volleyball => const SportTheme(
          top: Color(0xFF0E7490),
          bottom: Color(0xFF164E63),
          accent: Color(0xFFFDE68A),
          artName: 'Beach',
          emoji: '🏐'),
      SportFamily.baseball => const SportTheme(
          top: Color(0xFF1E3A8A),
          bottom: Color(0xFF172554),
          accent: Color(0xFFF87171),
          artName: 'Diamond',
          emoji: '⚾'),
      SportFamily.tennis => const SportTheme(
          top: Color(0xFF1D4ED8),
          bottom: Color(0xFF1E3A8A),
          accent: Color(0xFFD9F99D),
          artName: 'Hard court',
          emoji: '🎾'),
      SportFamily.padel => const SportTheme(
          top: Color(0xFF0F766E),
          bottom: Color(0xFF134E4A),
          accent: Color(0xFFFDE047),
          artName: 'Glass court',
          emoji: '🎾'),
      SportFamily.tableTennis => const SportTheme(
          top: Color(0xFF1E3A8A),
          bottom: Color(0xFF172554),
          accent: Color(0xFFF97316),
          artName: 'Table',
          emoji: '🏓'),
      SportFamily.chess => const SportTheme(
          top: Color(0xFF3F2A1D),
          bottom: Color(0xFF1C130D),
          accent: Color(0xFFF5D08A),
          artName: 'Board',
          emoji: '♟️'),
      SportFamily.ultimate => const SportTheme(
          top: Color(0xFF4D7C0F),
          bottom: Color(0xFF365314),
          accent: Color(0xFFFEF08A),
          artName: 'Field',
          emoji: '🥏'),
      SportFamily.golf => const SportTheme(
          top: Color(0xFF166534),
          bottom: Color(0xFF052E16),
          accent: Color(0xFFFACC15),
          artName: 'Fairway',
          emoji: '⛳'),
      SportFamily.hiking => const SportTheme(
          top: Color(0xFF065F46),
          bottom: Color(0xFF022C22),
          accent: Color(0xFFFDE68A),
          artName: 'Trail',
          emoji: '🥾'),
      SportFamily.running => const SportTheme(
          top: Color(0xFFB91C1C),
          bottom: Color(0xFF7F1D1D),
          accent: Color(0xFFFFFFFF),
          artName: 'Track',
          emoji: '🏃'),
      SportFamily.paintball => const SportTheme(
          top: Color(0xFF3F4A1F),
          bottom: Color(0xFF1A1F0D),
          accent: Color(0xFFF472B6),
          artName: 'Arena',
          emoji: '🎯'),
      SportFamily.generic => const SportTheme(
          top: Color(0xFF1F2937),
          bottom: Color(0xFF0B0F14),
          accent: Color(0xFF6EDC9E),
          artName: 'Court',
          emoji: '🏅'),
    };

/// Text and fills on a sport hero — dark in light AND dark mode.
const Color sportHeroInk = Color(0xFFFFFFFF);
const Color sportHeroMuted = Color(0xB3FFFFFF); // white 70%
const Color sportHeroPill = Color(0x24FFFFFF); // white 14%

const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

/// The sport's colour on an ordinary card (white in light mode, the raised
/// surface in dark): its hero accent where that reads, a deeper shade of it
/// where the pale accent would vanish on white.
Color sportInk(SportFamily f, {required bool dark}) => switch (f) {
      SportFamily.tennis =>
        dark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
      SportFamily.padel =>
        dark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E),
      SportFamily.tableTennis =>
        dark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
      SportFamily.chess =>
        dark ? const Color(0xFFF5D08A) : const Color(0xFF8A5A2B),
      SportFamily.ultimate =>
        dark ? const Color(0xFFBEF264) : const Color(0xFF4D7C0F),
      SportFamily.golf =>
        dark ? const Color(0xFF4ADE80) : const Color(0xFF166534),
      SportFamily.hiking =>
        dark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
      SportFamily.running =>
        dark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
      SportFamily.paintball =>
        dark ? const Color(0xFFF472B6) : const Color(0xFFDB2777),
      _ => dark ? const Color(0xFF1EB86B) : const Color(0xFF0F7A45),
    };

// ── Stat keys ───────────────────────────────────────────────────────────────

/// One of a sport's stat keys with how to show it.
class SportStat {
  const SportStat(this.key, this.label, this.icon);
  final String key;
  final String label;
  final String? icon;
}

const Map<String, String> _defaultLabels = {
  'goals': 'Goals',
  'assists': 'Assists',
  'ownGoals': 'Own goals',
  'yellows': 'Yellow cards',
  'reds': 'Red cards',
  'points': 'Points',
  'fouls': 'Fouls',
  'reb': 'Rebounds',
  'steals': 'Steals',
  'blocks': 'Blocks',
  'turnovers': 'Turnovers',
  'fg3Made': '3-pointers',
  'aces': 'Aces',
  'kills': 'Kills',
  'digs': 'Digs',
  'runs': 'Runs',
  'homeRuns': 'Home runs',
  'hits': 'Hits',
  'strikeouts': 'Strikeouts',
  'faults': 'Faults',
  'scores': 'Scores',
};

String _defaultIcon(String key, SportFamily family) => switch (key) {
      'goals' => family == SportFamily.ultimate ? '🥏' : '⚽',
      'scores' => '🥏',
      'assists' => '🅰️',
      'ownGoals' => '🥅',
      'yellows' => '🟨',
      'reds' => '🟥',
      'points' => _pointsIcon(family),
      'faults' => '⚠️',
      'fouls' => '✋',
      'aces' => '🎯',
      'blocks' => family == SportFamily.volleyball ? '🧱' : '🖐️',
      'runs' => '⚾',
      'homeRuns' => '💥',
      'hits' => '🏏',
      'strikeouts' => '❌',
      _ => '',
    };

String _pointsIcon(SportFamily f) => switch (f) {
      SportFamily.basketball => '🏀',
      SportFamily.volleyball => '🏐',
      SportFamily.tennis || SportFamily.padel => '🎾',
      SportFamily.tableTennis => '🏓',
      SportFamily.chess => '♟️',
      SportFamily.ultimate => '🥏',
      SportFamily.golf => '⛳',
      SportFamily.paintball => '🎯',
      _ => '⭐',
    };

/// A readable label for a bare stat key ("homeRuns" → "Home runs").
String defaultStatLabel(String key) {
  final known = _defaultLabels[key];
  if (known != null) return known;
  final spaced = key.replaceAllMapped(
      RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}');
  return spaced.isEmpty ? key : spaced[0].toUpperCase() + spaced.substring(1);
}

/// The sport's own stat fields (owner-editable) from the payload.
List<SportStat> statFields(dynamic raw, SportFamily family) => [
      for (final f in listOf(raw))
        if (parseStr(f['key']) != null)
          SportStat(
            parseStr(f['key'])!,
            parseStr(f['label']) ?? defaultStatLabel(parseStr(f['key'])!),
            parseStr(f['icon']) ??
                _nonEmpty(_defaultIcon(parseStr(f['key'])!, family)),
          ),
    ];

String? _nonEmpty(String s) => s.isEmpty ? null : s;

/// How to show [key]: the sport's own field when it has one, else defaults.
SportStat fieldFor(String key, List<SportStat> fields, SportFamily family) {
  for (final f in fields) {
    if (f.key == key) return f;
  }
  return SportStat(
      key, defaultStatLabel(key), _nonEmpty(_defaultIcon(key, family)));
}

/// Whether the sport tracks [key] at all (in its fields, or in the counts).
bool hasStat(String key, List<SportStat> fields, Map<String, dynamic> counts) =>
    fields.any((f) => f.key == key) || counts.containsKey(key);

int countOf(Map<String, dynamic> counts, String key) => statInt(counts[key]);

/// The first of [keys] the sport tracks ("points", "goals", "scores" …), or
/// null when it tracks none of them.
String? firstStatKey(
    List<String> keys, List<SportStat> fields, Map<String, dynamic> counts) {
  for (final k in keys) {
    if (hasStat(k, fields, counts)) return k;
  }
  return null;
}

/// Total ÷ games, or "—" instead of dividing by zero.
String perGame(num total, int games, {int decimals = 1}) =>
    games <= 0 ? '—' : (total / games).toStringAsFixed(decimals);

/// Win percentage baseball-style: three decimals, no leading zero (".636").
String baseballPct(int wins, int games) {
  if (games <= 0) return '—';
  final s = (wins / games).toStringAsFixed(3);
  return s.startsWith('0') ? s.substring(1) : s;
}

String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

// ── Scopes ──────────────────────────────────────────────────────────────────

/// All · Local · Tournaments.
enum RecordScope { all, local, tournament }

extension RecordScopeX on RecordScope {
  /// The tally on a category record.
  String get tallyKey => switch (this) {
        RecordScope.all => 'overall',
        RecordScope.local => 'local',
        RecordScope.tournament => 'tournament',
      };

  /// The bests bucket on a category record.
  String get bestsKey => switch (this) {
        RecordScope.all => 'all',
        RecordScope.local => 'local',
        RecordScope.tournament => 'tournament',
      };

  String get label => switch (this) {
        RecordScope.all => 'All',
        RecordScope.local => 'Local',
        RecordScope.tournament => 'Tournaments',
      };
}

Map<String, dynamic> tallyOf(Map<String, dynamic> cat, RecordScope s) =>
    mapOf(cat[s.tallyKey]);

/// The category's recent games in [s], newest first.
List<Map<String, dynamic>> recentOf(Map<String, dynamic> cat, RecordScope s) {
  final all = listOf(cat['recent']);
  if (s == RecordScope.all) return all;
  return [
    for (final g in all)
      if (parseStr(g['scope']) == s.name) g
  ];
}

Map<String, dynamic> bestsOf(Map<String, dynamic> cat, RecordScope s) =>
    mapOf(mapOf(cat['bests'])[s.bestsKey]);

int gamesOf(Map<String, dynamic> tally) => statInt(tally['games']);

/// The category's check-ins (§8): `{ checkIns, thisYear, last30, firstAt,
/// lastAt, weekStreak, monthly, recent }` — empty on older payloads.
Map<String, dynamic> attendanceOf(Map<String, dynamic> cat) =>
    mapOf(cat['attendance']);

int checkInsOf(Map<String, dynamic> cat) =>
    statInt(attendanceOf(cat)['checkIns']);

/// A sport "has a record" when they've played it OR checked in to its
/// events (§8 — hikes and runs have check-ins, rarely games).
bool hasPlayed(Map<String, dynamic> cat) =>
    gamesOf(mapOf(cat['overall'])) > 0 || checkInsOf(cat) > 0;

/// Alias with the design doc's wording.
bool hasRecord(Map<String, dynamic> cat) => hasPlayed(cat);

// ── Nouns ───────────────────────────────────────────────────────────────────

/// What one game is called in the sport: a match, a round, a race …
String gameNoun(SportFamily f) => switch (f) {
      SportFamily.tennis || SportFamily.padel => 'match',
      SportFamily.golf => 'round',
      SportFamily.running => 'race',
      _ => 'game',
    };

/// [gameNoun] in the plural ("matches", "rounds").
String gameNounPlural(SportFamily f) =>
    gameNoun(f) == 'match' ? 'matches' : '${gameNoun(f)}s';

/// "12 matches", "1 round".
String gamesPhrase(SportFamily f, int n) =>
    '$n ${n == 1 ? gameNoun(f) : gameNounPlural(f)}';

/// What one check-in is called: a hike, a run, else a check-in.
String outingNoun(SportFamily f) => switch (f) {
      SportFamily.hiking => 'hike',
      SportFamily.running => 'run',
      _ => 'check-in',
    };

// ── Attendance (§8) ─────────────────────────────────────────────────────────

final DateFormat _monthYear = DateFormat('MMM yyyy', 'en_US');
final DateFormat _monthDay = DateFormat('MMM d', 'en_US');
final DateFormat _monthDayYear = DateFormat('MMM d, yyyy', 'en_US');
final DateFormat _monthShort = DateFormat('MMM', 'en_US');

/// "Oct 12" this year, "Oct 12, 2025" before.
String shortDay(dynamic v) {
  final d = v is DateTime ? v : parseDate(v);
  if (d == null) return '';
  return d.year == DateTime.now().year
      ? _monthDay.format(d)
      : _monthDayYear.format(d);
}

/// "2026-10" → "Oct" (the bar chart's month labels).
String monthLabel(String? key) {
  final parts = (key ?? '').split('-');
  if (parts.length != 2) return '';
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (y == null || m == null || m < 1 || m > 12) return '';
  return _monthShort.format(DateTime(y, m));
}

/// The 12 months of check-ins, oldest first: (month key, count).
List<(String, int)> monthlyOf(Map<String, dynamic> att) => [
      for (final m in listOf(att['monthly']))
        (parseStr(m['month']) ?? '', statInt(m['n'])),
    ];

/// "24 hikes · 6-week streak" — an attendance sport's line on its card.
String attendanceSummary(SportFamily f, Map<String, dynamic> att) {
  final n = statInt(att['checkIns']);
  final streak = statInt(att['weekStreak']);
  final last = shortDay(att['lastAt']);
  final noun = outingNoun(f);
  return [
    plural(n, noun),
    if (streak > 0)
      '$streak-week streak'
    else if (last.isNotEmpty)
      'last $last',
  ].join(' · ');
}

/// "Hiking since Mar 2025 · last Oct 12".
String attendanceSinceLine(SportFamily f, Map<String, dynamic> att) {
  final first = parseDate(att['firstAt']);
  final last = shortDay(att['lastAt']);
  final verb = switch (f) {
    SportFamily.hiking => 'Hiking',
    SportFamily.running => 'Running',
    _ => 'Showing up',
  };
  final parts = [
    if (first != null) '$verb since ${_monthYear.format(first)}',
    if (last.isNotEmpty) 'last $last',
  ];
  return parts.isEmpty ? attendanceSummary(f, att) : parts.join(' · ');
}

// ── Chess (§8) ──────────────────────────────────────────────────────────────

/// W + ½D the way chess writes it: "7½", "½", "7".
String chessScore(int wins, int draws) {
  final whole = wins + draws ~/ 2;
  if (draws.isEven) return '$whole';
  return whole == 0 ? '½' : '$whole½';
}

/// The score as a share of the games played, 0–100 — null with no games.
int? chessScorePct(int wins, int draws, int games) =>
    games <= 0 ? null : ((wins + draws / 2) * 100 / games).round();

/// A game's result in chess notation, from the player's side.
String chessResult(String? result) => switch (result) {
      'win' => '1–0',
      'draw' => '½–½',
      'loss' => '0–1',
      _ => '–',
    };

/// One point, half a point or none: the form-circle mark for W / D / L.
String chessMark(String r) => switch (r) {
      'W' => '1',
      'D' => '½',
      'L' => '0',
      _ => r,
    };

// ── Form ────────────────────────────────────────────────────────────────────

/// "W" / "D" / "L" per game with a result, newest first.
List<String> formOf(List<Map<String, dynamic>> recent) => [
      for (final g in recent)
        switch (parseStr(g['result'])) {
          'win' => 'W',
          'draw' => 'D',
          'loss' => 'L',
          _ => '',
        }
    ].where((r) => r.isNotEmpty).toList();

/// The current run ("W3", "L1"), or null without results.
String? streakOf(List<Map<String, dynamic>> recent) {
  final f = formOf(recent);
  if (f.isEmpty) return null;
  var n = 0;
  for (final r in f) {
    if (r != f.first) break;
    n++;
  }
  return '${f.first}$n';
}

/// W green, D grey, L red.
Color resultColor(String r, {required Color win, required Color loss}) =>
    switch (r) {
      'W' => win,
      'L' => loss,
      _ => const Color(0xFF9CA3AF),
    };

// ── Headline numbers & record line (§5) ─────────────────────────────────────

/// "61%", or "—" with no games.
String winPctOf(Map<String, dynamic> tally) =>
    gamesOf(tally) > 0 ? '${statInt(tally['winRate'])}%' : '—';

/// The three big numbers on a hero / sport card: (value, label).
///
/// [attendance] is the category's check-ins — what the hiking and running
/// designs lead with.
List<(String, String)> headlineFor(
  SportFamily family,
  Map<String, dynamic> tally,
  List<SportStat> fields, {
  Map<String, dynamic> attendance = const {},
}) {
  final c = mapOf(tally['counts']);
  final g = gamesOf(tally);
  final w = statInt(tally['wins']);
  final pct = winPctOf(tally);
  int n(String k) => countOf(c, k);
  bool tracks(String k) => hasStat(k, fields, c);
  switch (family) {
    case SportFamily.soccer:
      return [
        ('${n('goals')}', 'Goals'),
        ('${n('assists')}', 'Assists'),
        (perGame(n('goals') + n('assists'), g, decimals: 2), 'G+A / game'),
      ];
    case SportFamily.basketball:
      return [
        ('${n('points')}', 'PTS'),
        (perGame(n('points'), g), 'PPG'),
        if (hasStat('assists', fields, c))
          (perGame(n('assists'), g), 'APG')
        else
          ('$g', 'GP'),
      ];
    case SportFamily.volleyball:
      return [
        ('${n('points')}', 'Points'),
        ('${n('aces')}', 'Aces'),
        ('${n('blocks')}', 'Blocks'),
      ];
    case SportFamily.baseball:
      return [
        ('${n('runs')}', 'Runs'),
        ('${n('hits')}', 'Hits'),
        ('${n('homeRuns')}', 'HR'),
      ];
    case SportFamily.tennis:
      return [
        ('$w', 'Wins'),
        (pct, 'Win %'),
        if (tracks('aces')) ('${n('aces')}', 'Aces') else ('$g', 'Matches'),
      ];
    case SportFamily.padel:
      return [
        ('$w', 'Wins'),
        (pct, 'Win %'),
        if (tracks('points'))
          ('${n('points')}', 'Points')
        else
          ('$g', 'Matches'),
      ];
    case SportFamily.tableTennis:
      return [
        ('$w', 'Wins'),
        (pct, 'Win %'),
        if (tracks('points'))
          (perGame(n('points'), g), 'Pts / game')
        else
          ('$g', 'Games'),
      ];
    case SportFamily.chess:
      return [
        (
          g > 0 ? '${chessScore(w, statInt(tally['draws']))} / $g' : '—',
          'Score'
        ),
        ('$w', 'Wins'),
        ('${statInt(tally['draws'])}', 'Draws'),
      ];
    case SportFamily.ultimate:
      return _ultimateHeadline(tally, fields);
    case SportFamily.golf:
      return [('$g', 'Rounds'), ('$w', 'Wins'), (pct, 'Win %')];
    case SportFamily.hiking:
    case SportFamily.running:
      return _attendanceHeadline(family, tally, fields, attendance);
    case SportFamily.paintball:
      return [
        ('$g', 'Games'),
        (pct, 'Win %'),
        if (tracks('points'))
          (perGame(n('points'), g), 'Pts / game')
        else
          ('$w', 'Wins'),
      ];
    case SportFamily.generic:
      return _genericHeadline(tally, fields);
  }
}

List<(String, String)> _genericHeadline(
    Map<String, dynamic> tally, List<SportStat> fields) {
  final first = fields.isEmpty ? null : fields.first;
  return [
    ('${gamesOf(tally)}', 'Games'),
    (winPctOf(tally), 'Win %'),
    if (first != null)
      ('${countOf(mapOf(tally['counts']), first.key)}', first.label)
    else
      ('${statInt(tally['points'])}', 'Points'),
  ];
}

/// Ultimate: scores (whatever the sport calls them) · assists · win %.
List<(String, String)> _ultimateHeadline(
    Map<String, dynamic> tally, List<SportStat> fields) {
  final c = mapOf(tally['counts']);
  final scoreKey = firstStatKey(const ['points', 'goals', 'scores'], fields, c);
  return [
    if (scoreKey != null)
      ('${countOf(c, scoreKey)}', 'Scores')
    else
      ('${gamesOf(tally)}', 'Games'),
    if (hasStat('assists', fields, c))
      ('${countOf(c, 'assists')}', 'Assists')
    else
      ('${statInt(tally['wins'])}', 'Wins'),
    (winPctOf(tally), 'Win %'),
  ];
}

/// Hiking / running: check-ins · this year · week streak. With no check-ins
/// but some games (races), the neutral numbers.
List<(String, String)> _attendanceHeadline(
    SportFamily family,
    Map<String, dynamic> tally,
    List<SportStat> fields,
    Map<String, dynamic> att) {
  final checkIns = statInt(att['checkIns']);
  if (checkIns == 0 && gamesOf(tally) > 0) {
    return _genericHeadline(tally, fields);
  }
  return [
    ('$checkIns', family == SportFamily.hiking ? 'Hikes' : 'Runs'),
    ('${statInt(att['thisYear'])}', 'This year'),
    ('${statInt(att['weekStreak'])}', 'Week streak'),
  ];
}

/// The sport's one-line record ("P 23 · W 14 · D 4 · L 5 · 46 pts").
///
/// Hiking and running read from [attendance] ("Hiking since Mar 2025 · last
/// Oct 12") whenever they have check-ins.
String recordLineFor(SportFamily family, Map<String, dynamic> tally,
    {String? streak, Map<String, dynamic> attendance = const {}}) {
  final g = gamesOf(tally);
  final w = statInt(tally['wins']);
  final d = statInt(tally['draws']);
  final l = statInt(tally['losses']);
  final rate = statInt(tally['winRate']);
  switch (family) {
    case SportFamily.soccer:
      return 'P $g · W $w · D $d · L $l · ${statInt(tally['points'])} pts';
    case SportFamily.basketball:
      return [
        d > 0 ? '$w–$d–$l' : '$w–$l',
        '$rate%',
        if (streak != null) streak,
      ].join(' · ');
    case SportFamily.volleyball:
      return [
        'W $w',
        if (d > 0) 'D $d',
        'L $l',
        '$rate%',
      ].join(' · ');
    case SportFamily.baseball:
      return '${d > 0 ? '$w–$l–$d' : '$w–$l'} · ${baseballPct(w, g)}';
    case SportFamily.tennis:
    case SportFamily.padel:
    case SportFamily.tableTennis:
    case SportFamily.paintball:
      return [
        'W $w',
        if (d > 0) 'D $d',
        'L $l',
        winPctOf(tally),
      ].join(' · ');
    case SportFamily.chess:
      final scorePct = chessScorePct(w, d, g);
      return '+$w =$d −$l · ${scorePct == null ? '—' : '$scorePct%'}';
    case SportFamily.ultimate:
      return ['W $w', if (d > 0) 'D $d', 'L $l'].join(' · ');
    case SportFamily.golf:
      return [
        gamesPhrase(family, g),
        'W $w',
        if (d > 0) 'T $d',
        'L $l',
      ].join(' · ');
    case SportFamily.hiking:
    case SportFamily.running:
      if (statInt(attendance['checkIns']) > 0) {
        return attendanceSinceLine(family, attendance);
      }
      return ['W $w', if (d > 0) 'D $d', 'L $l'].join(' · ');
    case SportFamily.generic:
      return 'W $w · D $d · L $l';
  }
}

/// The line under a sport card's name: the record line, or for attendance
/// sports "24 hikes · 6-week streak"; "No games yet" with nothing on record.
String cardLineFor(SportFamily family, Map<String, dynamic> cat) {
  final tally = mapOf(cat['overall']);
  final att = attendanceOf(cat);
  final games = gamesOf(tally);
  final checkIns = statInt(att['checkIns']);
  if (isAttendanceDesign(family) && checkIns > 0) {
    return attendanceSummary(family, att);
  }
  if (games > 0) {
    return recordLineFor(family, tally,
        streak: streakOf(listOf(cat['recent'])), attendance: att);
  }
  if (checkIns > 0) return attendanceSummary(family, att);
  return 'No games yet';
}

// ── Dates ───────────────────────────────────────────────────────────────────

/// A game's day on the viewer's calendar: "Oct 12, 2026" — the same
/// `date` style the web uses for these dates.
String plainDay(dynamic v) {
  final d = v is DateTime ? v : parseDate(v);
  if (d == null) return '';
  return fmtInstant(d, style: InstantStyle.date);
}
