import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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

String? _deviceTz;
String? _pickedTz;
bool _ready = false;
bool _dbLoaded = false;

/// Load the IANA database and read the device's zone. Safe to call more than
/// once; a failure leaves instants on `toLocal()`, which is never wrong for a
/// phone on automatic, just unaware of a picked zone.
Future<void> initTimeZones() async {
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
  _ready = true;
}

/// Re-read the device's zone (the phone may have crossed a border while the
/// app was in the background). Returns the zone, or null when unknown.
Future<String?> refreshDeviceTimezone() async {
  if (!_ready) await initTimeZones();
  try {
    _deviceTz = await FlutterTimezone.getLocalTimezone();
  } catch (_) {
    // Keep the last known zone.
  }
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

/// [instant] on the viewer's clock. The result's year/month/day/hour/minute
/// are the viewer's wall clock, so it can go straight into a `DateFormat`.
/// (A `tz.TZDateTime` when the zone is known, `toLocal()` otherwise.)
DateTime inViewerZone(DateTime instant) {
  final loc = _loc(viewerTimezone);
  if (loc == null) return instant.toLocal();
  return tz.TZDateTime.from(instant, loc);
}

/// "GMT+1", "GMT-4", "GMT+5:45" — [name]'s offset right now (or at [at]);
/// null for an unknown zone.
String? zoneOffsetLabel(String? name, [DateTime? at]) {
  final loc = _loc(name);
  if (loc == null) return null;
  final mins =
      tz.TZDateTime.from(at ?? DateTime.now(), loc).timeZoneOffset.inMinutes;
  if (mins == 0) return 'GMT';
  final sign = mins < 0 ? '-' : '+';
  final h = mins.abs() ~/ 60;
  final m = mins.abs() % 60;
  return m == 0 ? 'GMT$sign$h' : 'GMT$sign$h:${_pad2(m)}';
}

/// "America/New_York" → "America/New York".
String timezoneDisplayName(String name) => name.replaceAll('_', ' ');

/// The instant at a wall-clock time on the viewer's calendar — e.g. "until
/// the end of the 12th, where I am" from a date picker. Falls back to the
/// phone's own clock when the zone is unknown.
DateTime viewerWallClock(int year, int month, int day,
    [int hour = 0, int minute = 0]) {
  final loc = _loc(viewerTimezone);
  if (loc == null) return DateTime(year, month, day, hour, minute);
  return tz.TZDateTime(loc, year, month, day, hour, minute);
}

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
final _time = DateFormat('h:mm a', 'en_US');
final _day = DateFormat('EEE, MMM d', 'en_US');
final _dayTime = DateFormat('EEE, MMM d, h:mm a', 'en_US');
final _date = DateFormat('MMM d, y', 'en_US');
final _full = DateFormat('EEE, MMM d, y, h:mm a', 'en_US');
final _weekdayShort = DateFormat('EEE', 'en_US');
final _monthDay = DateFormat('MMM d', 'en_US');
final _dayLong = DateFormat('EEEE, MMMM d', 'en_US');
final _dayLongYear = DateFormat('EEEE, MMMM d, y', 'en_US');

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
  if (day == _yesterdayKey(n)) return 'Yesterday';
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
  if (day == today) return 'Today';
  if (day == _yesterdayKey(n)) return 'Yesterday';
  final z = inViewerZone(t);
  return day.substring(0, 4) == today.substring(0, 4)
      ? _dayLong.format(z)
      : _dayLongYear.format(z);
}
