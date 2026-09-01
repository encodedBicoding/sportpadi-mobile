import 'package:intl/intl.dart';

import 'parse.dart';

final _day = DateFormat('EEE, d MMM');
final _dayYear = DateFormat('d MMM yyyy');

/// Event dates are UTC wall-clock values (the web renders them with
/// timeZone: "UTC") — format the UTC face, never the device-local shift.
String formatDay(dynamic v) {
  final d = v is DateTime ? v : parseDate(v);
  return d == null ? '' : _day.format(d.toUtc());
}

String formatDayYear(dynamic v) {
  final d = v is DateTime ? v : parseDate(v);
  return d == null ? '' : _dayYear.format(d.toUtc());
}

/// Event start/end times arrive as ISO datetimes (often on the 1970 epoch day);
/// we only want the wall-clock time — displayed 12-hour ("8:00 PM").
String? formatClock(dynamic v) {
  final d = parseDate(v);
  if (d == null) return null;
  final u = d.toUtc();
  return _to12h(u.hour, u.minute);
}

/// Machine form ("HH:mm", 24-hour) — for edit fields and API payloads.
String? formatClock24(dynamic v) {
  final d = parseDate(v);
  if (d == null) return null;
  final u = d.toUtc();
  final h = u.hour.toString().padLeft(2, '0');
  final m = u.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Render a raw "HH:mm" schedule string 12-hour ("8:00 PM").
String formatTime12(String hhmm) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return hhmm;
  return _to12h(h, m);
}

String _to12h(int h, int m) {
  final suffix = h >= 12 ? 'PM' : 'AM';
  var hour = h % 12;
  if (hour == 0) hour = 12;
  return '$hour:${m.toString().padLeft(2, '0')} $suffix';
}

/// "2 hours ago" style relative time for the notification feed.
String timeAgo(dynamic v) {
  final d = v is DateTime ? v : parseDate(v);
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDayYear(d);
}
