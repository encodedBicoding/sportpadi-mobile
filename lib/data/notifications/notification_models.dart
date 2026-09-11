import '../../shared/format/parse.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.read,
    this.body,
    this.url,
    this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final bool read;
  final String? body;
  final String? url;
  final DateTime? createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final data = j['data'];
    final url = data is Map ? parseStr(data['url']) : null;
    return AppNotification(
      id: (j['id'] ?? '') as String,
      type: (j['type'] ?? 'info') as String,
      title: (j['title'] ?? '') as String,
      read: j['readAt'] != null || j['read'] == true,
      body: parseStr(j['bodyText']) ?? parseStr(j['body']),
      // The API stores the destination on the row's own `url` column; some
      // older rows carried it inside `data`.
      url: parseStr(j['url']) ?? url,
      createdAt: parseDate(j['createdAt']),
    );
  }
}

class NotificationFeed {
  const NotificationFeed({required this.items, this.nextCursor});
  final List<AppNotification> items;
  final String? nextCursor;

  factory NotificationFeed.fromJson(Map<String, dynamic> j) {
    final raw = j['items'];
    return NotificationFeed(
      items: raw is List
          ? [
              for (final e in raw)
                AppNotification.fromJson(Map<String, dynamic>.from(e as Map))
            ]
          : const [],
      nextCursor: parseStr(j['nextCursor']),
    );
  }
}
