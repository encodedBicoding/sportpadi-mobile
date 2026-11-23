import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:sportpadi_mobile/core/i18n/date_locale.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/shared/format/zone_rules.dart';

/// Instants in the VIEWER's zone — the Dart half of the "Instants in the
/// viewer's zone" block in `packages/lib/src/time.ts`.
///
/// Everything that HAPPENED at a moment — a message sent, a comment posted, an
/// announcement, a notification — is a UTC instant and is shown on the
/// viewer's own clock. The viewer's zone is the zone they picked in Settings
/// (profile, automatic off), otherwise the device's zone, otherwise whatever
/// `DateTime.toLocal()` gives. One place, so no screen drifts back to its own
/// idea of "today".
///
/// Event kick-offs are different: they're venue wall clocks — see
/// `event_time.dart` (which uses [viewerTimezone] for the "your time" half).
///
/// Which tz database answers (review the BC fix, 2026-11-22, before changing):
/// - the PHONE'S OWN zone is read from the phone (`DateTime.toLocal()`, the
///   OS's tz data, which iOS / Android keep current) — so "your time" always
///   agrees with the clock in the status bar;
/// - every other zone comes from the `timezone` package's table with the
///   server's current rules laid over it (`zone_rules.dart`); the bundled
///   table alone is only the offline fallback — it was what said "PST" for
///   Vancouver after BC stopped changing its clocks.

String? _deviceTz;
String? _pickedTz;
bool _ready = false;
bool _dbLoaded = false;

/// Load the IANA database, read the device's zone, and lay the server's
/// current rules over the bundled table (the saved copy at once; a fresh one
/// from [apiBaseUrl] — waited for, briefly, only when nothing was saved yet).
/// Safe to call more than once; a failure leaves instants on `toLocal()`,
/// which is never wrong for a phone on automatic, just unaware of a picked
/// zone.
Future<void> initTimeZones({String? apiBaseUrl}) async {
  if (_ready) return;
  try {
    // latest_10y: a fraction of the full ~1MB database, and it covers every
    // timestamp anyone will look at.
    tzdata.initializeTimeZones();
    _dbLoaded = true;
    _deviceTz = await FlutterTimezone.getLocalTimezone();
  } catch (_) {
    // Survivable — see above. Don't retry on every call.
  }
  deviceZoneChanges.value = _deviceTz;
  _ready = true;
  if (!_dbLoaded) return;
  if (apiBaseUrl != null) configureZoneRules(apiBaseUrl);
  final cached = await loadCachedZoneRules();
  final fresh = refreshTimeZoneRules();
  if (!cached) {
    // First start on this build: up to 2 s for the server's rules, so the
    // first screens don't show the stale table. Offline: the bundled one.
    try {
      await fresh.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Lands later (or never); the bundled table until then.
    }
  }
}

/// Fetch the server's current zone rules (at most twice a day unless [force];
/// on start, on resume and after a zone pick). Never throws.
Future<bool> refreshTimeZoneRules({bool force = false}) =>
    refreshZoneRules(extra: [_deviceTz, _pickedTz], force: force);

/// The phone's zone name as last read — changes (only) when the phone moved
/// zone, whoever re-read it (the signed-in timezone sync, or
/// `TimeZoneRulesHost` on resume for everyone). The host repaints open screens
/// on a change: every "is this the phone's own zone" answer depends on it.
final ValueNotifier<String?> deviceZoneChanges = ValueNotifier<String?>(null);

/// Re-read the device's zone (the phone may have crossed a border while the
/// app was in the background). Returns the zone, or null when unknown.
Future<String?> refreshDeviceTimezone() async {
  if (!_ready) await initTimeZones();
  try {
    _deviceTz = await FlutterTimezone.getLocalTimezone();
  } catch (_) {
    // Keep the last known zone.
  }
  deviceZoneChanges.value = _deviceTz;
  return deviceTimezone;
}

/// The device's own IANA zone ("Africa/Lagos"), when the database knows it.
String? get deviceTimezone => _loc(_deviceTz) != null ? _deviceTz : null;

/// The zone instants are shown in: the picked zone, else the device's. Null
/// only when neither is known (then [inViewerZone] falls back to `toLocal`).
String? get viewerTimezone =>
    _loc(_pickedTz) != null ? _pickedTz : deviceTimezone;

/// Set the zone the viewer PICKED (profile, automatic off), or null to follow
/// the device. Widgets that should repaint on a change watch
/// `viewerTimezoneProvider` (features/settings/timezone_provider.dart).
void setViewerTimezone(String? name) {
  _pickedTz = (name == null || name.isEmpty) ? null : name;
}

/// Every zone the database knows, sorted — for the Settings picker.
List<String> allTimezones() {
  if (!_dbLoaded) return const [];
  return tz.timeZoneDatabase.locations.keys.toList()..sort();
}

/// Is [name] a zone the database knows?
bool isKnownTimezone(String? name) => _loc(name) != null;

tz.Location? _loc(String? name) {
  if (!_dbLoaded || name == null || name.isEmpty) return null;
  try {
    return tz.getLocation(name);
  } catch (_) {
    return null;
  }
}

/// Is [name] the phone's own zone? Then the OS answers, not the table.
bool _isDevice(String? name) =>
    name != null && name.isNotEmpty && name == _deviceTz;

/// [instant] on the PHONE's clock, from the OS. Not `instant.toLocal()`: on a
/// `tz.TZDateTime` (what [zonedWallClock] returns for a venue) that converts
/// to the package's own `tz.local`, which is UTC unless someone sets it — a
/// silent "your time" in UTC.
DateTime osLocal(DateTime instant) =>
    DateTime.fromMillisecondsSinceEpoch(instant.millisecondsSinceEpoch);

/// [name]'s UTC offset at [instant]; null for an unknown zone.
Duration? zoneOffsetAt(String? name, DateTime instant) {
  if (_isDevice(name)) return osLocal(instant).timeZoneOffset;
  final loc = _loc(name);
  if (loc == null) return null;
  return Duration(
      milliseconds: loc.timeZone(instant.millisecondsSinceEpoch).offset);
}

/// [instant] on [name]'s clock — the result's year/month/day/hour/minute are
/// that wall clock, ready for a `DateFormat`. Null for an unknown zone.
DateTime? inZone(String? name, DateTime instant) {
  if (_isDevice(name)) return osLocal(instant);
  final loc = _loc(name);
  if (loc == null) return null;
  return tz.TZDateTime.from(instant, loc);
}

const _hourMs = 60 * 60 * 1000;

/// The instant a wall clock stands for, given the zone's offset (ms) at any
/// instant — a line-for-line copy of `resolveWallClock` in
/// `packages/lib/src/time.ts`, so the app, the web and the server resolve
/// every wall clock the same way (scripts/tz-check/scen.cjs sweeps every
/// quarter-hour of every transition day). RFC 5545's rule: a time that
/// happens twice (clocks went back) is its FIRST occurrence; one that never
/// happens (clocks went forward) is read with the offset before the gap, so
/// it lands after it (2:30 → 3:30). [local] is the wall clock's fields as if
/// they were UTC. Neither the package's `TZDateTime(...)` constructor nor a
/// local `DateTime(...)` is used for this: they pick differently on those
/// nights (the package takes the later 2:30 in Europe, the earlier in the
/// Americas).
int resolveWallClock(int local, int Function(int ms) offsetAt) {
  // Every reading of this wall clock lies within [local − 14 h, local + 12 h]
  // (offsets run from −12 h to +14 h): the offsets on either side of it.
  final before = offsetAt(local - 14 * _hourMs);
  final after = offsetAt(local + 12 * _hourMs);
  final a = local - before;
  final b = local - after;
  final aOk = offsetAt(a) == before;
  final bOk = offsetAt(b) == after;
  if (aOk && bOk) return a < b ? a : b;
  if (aOk) return a;
  if (bOk) return b;
  return a;
}

/// The phone's own UTC offset (ms) at an instant, from the OS.
int _osOffsetMs(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms).timeZoneOffset.inMilliseconds;

/// The instant a wall clock in [name] stands for ("08:15 on 22 Nov at the
/// venue"); null for an unknown zone.
DateTime? zonedWallClock(String? name, int year, int month, int day,
    [int hour = 0, int minute = 0]) {
  final local =
      DateTime.utc(year, month, day, hour, minute).millisecondsSinceEpoch;
  if (_isDevice(name)) {
    return DateTime.fromMillisecondsSinceEpoch(
        resolveWallClock(local, _osOffsetMs));
  }
  final loc = _loc(name);
  if (loc == null) return null;
  final ms = resolveWallClock(local, (t) => loc.timeZone(t).offset);
  return tz.TZDateTime.fromMillisecondsSinceEpoch(loc, ms);
}

/// "PDT", "GMT+1", "GMT+5:45" — [name]'s label at [instant], the same as
/// the web's `zoneLabel` once the server's rules are in. A letter
/// abbreviation is used only when the table's entry has the offset actually
/// in use (on the phone's own zone the OS has the last word): "PST" on a
/// UTC−7 clock is exactly the bug this guards. Numeric names ("+0545", "-03",
/// or "" from the server) are written from the offset in the viewer's
/// language. Never hand-rolled from an offset alone: abbreviations aren't
/// unique (IST is India, Israel and Irish Standard Time) and flip with DST.
String? zoneLabelAt(String? name, DateTime instant) {
  final off = zoneOffsetAt(name, instant);
  if (off == null) return null;
  final z = _loc(name)?.timeZone(instant.millisecondsSinceEpoch);
  final abbr =
      (z != null && z.offset == off.inMilliseconds) ? z.abbreviation : '';
  if (RegExp(r'^[A-Za-z]{2,6}$').hasMatch(abbr)) return abbr;
  // A zone with no name of its own at UTC+0 is "GMT+0" on the web (ICU), as
  // against London's own "GMT" above (review timezones.md LOW-5).
  return _gmtLabel(off.inMinutes, zero: l10n.common_gmt('+', 0));
}

String _gmtLabel(int mins, {String zero = 'GMT'}) {
  if (mins == 0) return zero;
  final sign = mins < 0 ? '-' : '+';
  final h = mins.abs() ~/ 60;
  final m = mins.abs() % 60;
  return m == 0 ? l10n.common_gmt(sign, h) : l10n.common_gmt2(sign, h, _pad2(m));
}

/// [instant] on the viewer's clock. The result's year/month/day/hour/minute
/// are the viewer's wall clock, so it can go straight into a `DateFormat`.
/// (The phone's own zone and an unknown one: `toLocal()`; a picked zone: a
/// `tz.TZDateTime`.)
DateTime inViewerZone(DateTime instant) =>
    inZone(viewerTimezone, instant) ?? osLocal(instant);

/// "GMT+1", "GMT-4", "GMT+5:45" — [name]'s offset right now (or at [at]);
/// null for an unknown zone.
String? zoneOffsetLabel(String? name, [DateTime? at]) {
  final off = zoneOffsetAt(name, at ?? DateTime.now());
  return off == null ? null : _gmtLabel(off.inMinutes);
}

/// "America/New_York" → "America/New York".
String timezoneDisplayName(String name) => name.replaceAll('_', ' ');

/// The instant at a wall-clock time on the viewer's calendar — e.g. "until
/// the end of the 12th, where I am" from a date picker. Falls back to the
/// phone's own clock when the zone is unknown.
DateTime viewerWallClock(int year, int month, int day,
    [int hour = 0, int minute = 0]) =>
    zonedWallClock(viewerTimezone, year, month, day, hour, minute) ??
    DateTime(year, month, day, hour, minute);

enum InstantStyle {
  /// "3:05 PM"
  time,

  /// "Sat, Oct 12"
  day,

  /// "Sat, Oct 12, 3:05 PM"
  dayTime,

  /// "Oct 12, 2026"
  date,

  /// "Sat, Oct 12, 2026, 3:05 PM"
  full,
}

// en-US forced, as on the web: 12-hour everywhere.
DateFormat get _time => DateFormat('h:mm a', spDateLocale);
DateFormat get _day => DateFormat('EEE, MMM d', spDateLocale);
DateFormat get _dayTime => DateFormat('EEE, MMM d, h:mm a', spDateLocale);
DateFormat get _date => DateFormat('MMM d, y', spDateLocale);
DateFormat get _full => DateFormat('EEE, MMM d, y, h:mm a', spDateLocale);
DateFormat get _weekdayShort => DateFormat('EEE', spDateLocale);
DateFormat get _monthDay => DateFormat('MMM d', spDateLocale);
DateFormat get _dayLong => DateFormat('EEEE, MMMM d', spDateLocale);
DateFormat get _dayLongYear => DateFormat('EEEE, MMMM d, y', spDateLocale);

/// Format an instant in the viewer's zone. Empty for null.
String fmtInstant(DateTime? t, {InstantStyle style = InstantStyle.dayTime}) {
  if (t == null) return '';
  final z = inViewerZone(t);
  switch (style) {
    case InstantStyle.time:
      return _time.format(z);
    case InstantStyle.day:
      return _day.format(z);
    case InstantStyle.dayTime:
      return _dayTime.format(z);
    case InstantStyle.date:
      return _date.format(z);
    case InstantStyle.full:
      return _full.format(z);
  }
}

String _pad2(int n) => n.toString().padLeft(2, '0');

/// "yyyy-MM-dd" of the instant on the viewer's clock — for grouping by day.
String dayKey(DateTime? t) {
  if (t == null) return '';
  return _key(inViewerZone(t));
}

String _key(DateTime z) =>
    '${z.year.toString().padLeft(4, '0')}-${_pad2(z.month)}-${_pad2(z.day)}';

/// [dayKey] of the calendar day before [now]'s, on the viewer's calendar.
/// Calendar arithmetic, not `now - 24h`: on a 25-hour DST day that would
/// still be "today".
String _yesterdayKey(DateTime now) {
  final z = inViewerZone(now);
  return _key(DateTime.utc(z.year, z.month, z.day - 1));
}

/// Short relative time for lists and threads: "just now", "5m", "3h",
/// "Yesterday", "Tue", "Oct 12", "Oct 12, 2025". Day boundaries are the
/// viewer's — "Yesterday" means yesterday where they are.
String fmtRelative(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final n = now ?? DateTime.now();
  final diff = n.difference(t);
  if (diff.inSeconds < 60) return 'just now';
  final min = diff.inMinutes;
  if (min < 60) return '${min}m';
  final today = dayKey(n);
  final day = dayKey(t);
  if (day == today) return '${min ~/ 60}h';
  if (day == _yesterdayKey(n)) return l10n.common_yesterday;
  final z = inViewerZone(t);
  if (diff < const Duration(days: 6)) return _weekdayShort.format(z);
  final sameYear = day.substring(0, 4) == today.substring(0, 4);
  return sameYear ? _monthDay.format(z) : _date.format(z);
}

/// "Today", "Yesterday", "Saturday, October 12" (+ year when not this year) —
/// for day separators in a thread or feed.
String fmtDayLabel(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final n = now ?? DateTime.now();
  final day = dayKey(t);
  final today = dayKey(n);
  if (day == today) return l10n.common_today;
  if (day == _yesterdayKey(n)) return l10n.common_yesterday;
  final z = inViewerZone(t);
  return day.substring(0, 4) == today.substring(0, 4)
      ? _dayLong.format(z)
      : _dayLongYear.format(z);
}
