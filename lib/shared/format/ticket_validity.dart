import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/shared/format/instant.dart';

/// Recurring-ticket VALIDITY helpers — the Dart half of the web's
/// `apps/web/src/lib/ticketValidity.ts`.
///
/// Validity (validFrom–validUntil) is how long a purchase admits you. It is
/// set by SportPadi when a recurring ticket is created (from the start of the
/// first day to the END of the cycle's last day) and never edited. It is NOT
/// the sales window (salesStartAt–salesEndAt), which is only when it can be
/// bought.

bool isRecurringTicket(String? recurrence) =>
    recurrence != null && recurrence != 'one_time' && recurrence != 'once';

/// "month" etc. — the cycle length in words ("renews every month").
String cycleUnit(String recurrence) => switch (recurrence) {
      'weekly' => 'week',
      'monthly' => 'month',
      'quarterly' => 'quarter',
      'yearly' => 'year',
      _ => '',
    };

/// "Monthly pass" — a recurring ticket covers every occurrence in its cycle.
String? passLabel(String recurrence) => switch (recurrence) {
      'weekly' => 'Weekly pass',
      'monthly' => 'Monthly pass',
      'quarterly' => 'Quarterly pass',
      'yearly' => 'Yearly pass',
      _ => null,
    };

final _monthDay = DateFormat('MMM d', 'en_US');
final _monthDayYear = DateFormat('MMM d, y', 'en_US');

String _wallDay(DateTime wall) =>
    wall.year == inViewerZone(DateTime.now()).year
        ? _monthDay.format(wall)
        : _monthDayYear.format(wall);

/// "Sep 27" — with the year only when it isn't this year ("Oct 31, 2027").
/// The calendar day [instant] falls on in the viewer's zone.
String shortDay(DateTime instant) => _wallDay(inViewerZone(instant));

/// "Sep 27 – Oct 26", or null without a validity (one-time tickets).
/// [until] is the last instant (23:59:59.999) of the last day, so it formats
/// as that day.
String? validityRange(DateTime? from, DateTime? until) {
  if (from == null || until == null) return null;
  return '${shortDay(from)} – ${shortDay(until)}';
}

bool isFutureInstant(DateTime? t) => t != null && t.isAfter(DateTime.now());

/// Today on the viewer's calendar, as a plain date (year/month/day only).
DateTime viewerToday() {
  final z = inViewerZone(DateTime.now());
  return DateTime(z.year, z.month, z.day);
}

/// "2026-09-27" — a calendar date as the API's `validFromDate`.
String ymdString(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

int _daysIn(int y, int m) => DateTime.utc(y, m + 1, 0).day;

DateTime _addDays(DateTime v, int n) => DateTime.utc(v.year, v.month, v.day + n);

/// Whole months on, on the series' anchor day (clamped to short months).
DateTime _addMonths(DateTime v, int n, int anchorDay) {
  final idx = v.month - 1 + n;
  final y = v.year + (idx / 12).floor();
  final m = idx % 12 + 1; // Dart's % is never negative for a positive divisor.
  final d = anchorDay < _daysIn(y, m) ? anchorDay : _daysIn(y, m);
  return DateTime.utc(y, m, d);
}

/// First day of the next cycle — the same rule as the server
/// (packages/api/src/tickets/cycles.ts `nextCycleDay`).
DateTime _nextCycleDay(DateTime v, String recurrence, int anchorDay) =>
    switch (recurrence) {
      'weekly' => _addDays(v, 7),
      'monthly' => _addMonths(v, 1, anchorDay),
      'quarterly' => _addMonths(v, 3, anchorDay),
      'yearly' => _addMonths(v, 12, anchorDay),
      _ => v,
    };

String _dayLabel(DateTime v) => _wallDay(DateTime(v.year, v.month, v.day));

/// Preview of a new recurring ticket's validity from its first day: this
/// cycle and the next ("Sep 27 – Oct 26", "Oct 27 – Nov 26"). Null for
/// one-time tickets.
({String current, String next})? cyclePreview(
    String recurrence, DateTime firstDay) {
  if (!isRecurringTicket(recurrence)) return null;
  final start = DateTime.utc(firstDay.year, firstDay.month, firstDay.day);
  final second = _nextCycleDay(start, recurrence, start.day);
  final third = _nextCycleDay(second, recurrence, start.day);
  return (
    current: '${_dayLabel(start)} – ${_dayLabel(_addDays(second, -1))}',
    next: '${_dayLabel(second)} – ${_dayLabel(_addDays(third, -1))}',
  );
}
