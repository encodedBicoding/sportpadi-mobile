/// Lenient JSON parse helpers — the REST bridge returns Prisma rows whose exact
/// shapes vary, so models decode defensively.
DateTime? parseDate(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

double? parseDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? parseInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

String? parseStr(dynamic v) => v is String && v.isNotEmpty ? v : null;

List<String> parseStrList(dynamic v) {
  if (v is List) {
    return [
      for (final x in v)
        if (x != null) x.toString()
    ].where((s) => s.isNotEmpty).toList();
  }
  return const [];
}
