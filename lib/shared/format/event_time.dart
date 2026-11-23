import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
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
/// Flutter has no tz database of its own: the `timezone` package bakes one
/// into the build, and it goes stale when a government changes its clock (BC,
/// November 2026: the app said "8:15 AM PST" and "9:15 AM your time" where
/// the web said "8:15 AM PDT"). So every zone lookup goes through
/// `instant.dart`: the phone's own zone from the OS, any other from the
/// bundled table with the server's current rules laid over it
/// (`zone_rules.dart`). The web side gets the same data from the browser's ICU.

/// Load the tz database, read the device's zone and apply the server's zone
/// rules (shared with instant formatting — see `instant.dart`). Safe to call
/// more than once; failures leave the app on venue-time-only, which is never
/// wrong, just less helpful.
Future<void> initEventTime({String? apiBaseUrl}) =>
    initTimeZones(apiBaseUrl: apiBaseUrl);

/// Same shape as `formatDay` ("Sat, 12 Oct"), for the viewer's own day.
DateFormat get _viewerDay => DateFormat('EEE, d MMM');

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

  if (venueTime == null || eventDate == null || startTime == null) {
    return EventTimeParts(day: day, venueTime: venueTime);
  }

  // Rebuild the wall clock inside the venue's zone to get the real instant
  // (null: no zone, or one no table knows — venue time only).
  final d = eventDate.toUtc();
  final t = startTime.toUtc();
  final instant =
      zonedWallClock(timezone, d.year, d.month, d.day, t.hour, t.minute);
  if (instant == null) return EventTimeParts(day: day, venueTime: venueTime);
  final venueZone = zoneLabelAt(timezone, instant);

  // The viewer's zone: the one they picked in Settings, else the device's —
  // the same zone every message and notification timestamp is shown in
  // (unknown: the phone's own clock).
  final viewer = viewerTimezone;
  final viewerOffset = viewer == null
      ? osLocal(instant).timeZoneOffset
      : zoneOffsetAt(viewer, instant);
  if (viewer == timezone ||
      viewerOffset == null ||
      viewerOffset == zoneOffsetAt(timezone, instant)) {
    return EventTimeParts(day: day, venueTime: venueTime, venueZone: venueZone);
  }

  final mine = inViewerZone(instant);
  // Include the weekday when the conversion lands on another day — a bare
  // "9:30 AM" would be quietly wrong.
  final rolled =
      mine.year != d.year || mine.month != d.month || mine.day != d.day;
  // Format [mine]'s own fields: formatDay()/formatClock() read the UTC face
  // (right for the stored venue wall clock, wrong for a zoned instant).
  final clock = formatTime12('${mine.hour}:${mine.minute}');
  final viewerTime = rolled ? '${_viewerDay.format(mine)}, $clock' : clock;

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
