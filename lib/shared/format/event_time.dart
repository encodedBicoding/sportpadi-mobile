import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Zone-aware event times — the Dart half of `packages/lib/src/time.ts`.
///
/// An event's date and start/end are stored as a NAIVE WALL CLOCK ("2:30 PM on
/// 12 Oct") alongside the venue's IANA zone, not as a UTC instant. That is
/// deliberate: governments change offsets and DST rules several times a year,
/// and a UTC instant stored months ahead silently drifts against the local
/// clock when a rule moves. A wall clock re-resolved at render time stays true
/// to "kick-off at that pitch", which is what the event actually is.
///
/// So the venue time needs no conversion — it IS the stored wall clock. What
/// needs computing is the zone's label at that moment (DST-dependent) and the
/// same instant on the viewer's own clock.
///
/// Flutter has no tz database of its own, which is why this needs the
/// `timezone` package; the web side gets the same data free from ICU.

String? _deviceTz;
bool _ready = false;

/// Load the tz database and read the device's zone. Safe to call more than
/// once; failures leave the app on venue-time-only, which is never wrong, just
/// less helpful.
Future<void> initEventTime() async {
  if (_ready) return;
  try {
    // latest_10y: the full database is ~1MB, this trim is a fraction of that
    // and covers every event anyone will schedule.
    tzdata.initializeTimeZones();
    _deviceTz = await FlutterTimezone.getLocalTimezone();
    _ready = true;
  } catch (_) {
    _ready = true; // don't retry on every frame
  }
}

tz.Location? _loc(String? name) {
  if (name == null || name.isEmpty) return null;
  try {
    return tz.getLocation(name);
  } catch (_) {
    return null;
  }
}

/// "GMT+1", "PDT", "GMT+5:45" — the zone's name at that instant.
///
/// Never hand-rolled from an offset: abbreviations aren't unique (IST is India,
/// Israel and Irish Standard Time), they flip with DST, and the half- and
/// quarter-hour zones have none at all.
String _zoneLabel(tz.TZDateTime at) {
  final abbr = at.timeZoneName;
  // The database gives a real abbreviation where one exists ("PDT", "WAT") and
  // a numeric form like "+0545" otherwise — render that as GMT+5:45.
  final m = RegExp(r'^([+-])(\d{2})(\d{2})$').firstMatch(abbr);
  if (m == null) return abbr;
  final sign = m.group(1);
  final h = int.parse(m.group(2)!);
  final min = int.parse(m.group(3)!);
  return min == 0 ? 'GMT$sign$h' : 'GMT$sign$h:${m.group(3)}';
}

class EventTimeParts {
  const EventTimeParts({
    required this.day,
    this.venueTime,
    this.venueZone,
    this.viewerTime,
    this.sameZone = true,
  });

  /// "Sat, Oct 12" at the venue.
  final String day;

  /// "2:30 PM" or "2:30 PM – 4:00 PM" at the venue; null when no time is set.
  final String? venueTime;

  /// "GMT+1" — only when there is a time AND a known zone.
  final String? venueZone;

  /// The same moment on the viewer's clock, ONLY when their zone differs.
  final String? viewerTime;
  final bool sameZone;

  /// "Sat, Oct 12 · 2:30 PM GMT+1" — the venue line on its own.
  String get line {
    if (venueTime == null) return '$day · time TBC';
    return '$day · $venueTime${venueZone != null ? ' $venueZone' : ''}';
  }
}

/// Format an event: venue clock first (you turn up at the pitch at the local
/// time), with the viewer's own time added only when the zones genuinely
/// differ. A missing venue zone yields a bare wall clock and no label — never a
/// guess, since a wrong zone is worse than no zone.
EventTimeParts formatEventTime({
  required DateTime? eventDate,
  DateTime? startTime,
  DateTime? endTime,
  String? timezone,
}) {
  final day = eventDate != null ? formatDay(eventDate) : 'Date TBC';
  final a = formatClock(startTime);
  final b = formatClock(endTime);
  final venueTime = a == null ? null : (b != null ? '$a – $b' : a);

  final venue = _loc(timezone);
  if (venueTime == null || venue == null || eventDate == null || startTime == null) {
    return EventTimeParts(day: day, venueTime: venueTime);
  }

  // Rebuild the wall clock inside the venue's zone to get the real instant.
  final d = eventDate.toUtc();
  final t = startTime.toUtc();
  final instant =
      tz.TZDateTime(venue, d.year, d.month, d.day, t.hour, t.minute);
  final venueZone = _zoneLabel(instant);

  final viewer = _loc(_deviceTz);
  if (viewer == null ||
      viewer.name == venue.name ||
      instant.timeZoneOffset == tz.TZDateTime.from(instant, viewer).timeZoneOffset) {
    return EventTimeParts(
        day: day, venueTime: venueTime, venueZone: venueZone);
  }

  final mine = tz.TZDateTime.from(instant, viewer);
  // Include the weekday when the conversion lands on another day — a bare
  // "9:30 AM" would be quietly wrong.
  final rolled = mine.day != instant.day;
  final viewerTime =
      rolled ? '${formatDay(mine)}, ${formatClock(mine)}' : formatClock(mine);

  return EventTimeParts(
    day: day,
    venueTime: venueTime,
    venueZone: venueZone,
    viewerTime: viewerTime,
    sameZone: false,
  );
}

/// Convenience for JSON maps straight off the bridge.
EventTimeParts formatEventTimeJson(Map<String, dynamic> e) => formatEventTime(
      eventDate: parseDate(e['eventDate']),
      startTime: parseDate(e['startTime']),
      endTime: parseDate(e['endTime']),
      timezone: parseStr(e['timezone']),
    );
