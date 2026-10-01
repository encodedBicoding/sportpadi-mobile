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
    this.fullBody,
  });

  final String id;
  final String type;
  final String title;
  final bool read;

  /// Short preview (the server caps `bodyText` at ~240 chars).
  final String? body;

  /// Full message as plain text with paragraph breaks — derived from the
  /// server's `bodyHtml`, which is the complete content. Falls back to [body].
  final String? fullBody;
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
      fullBody: htmlToPlainText(parseStr(j['bodyHtml'])) ??
          parseStr(j['bodyText']) ??
          parseStr(j['body']),
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

/// Turn notification HTML into readable plain text: block elements become
/// paragraph/line breaks, list items get bullets, tags are stripped and the
/// common entities decoded. Null for null/blank input.
String? htmlToPlainText(String? html) {
  if (html == null || html.trim().isEmpty) return null;
  var t = html
      .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ')
      .replaceAll(
          RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(
          RegExp(r'</(p|div|h[1-6]|tr|blockquote)>', caseSensitive: false),
          '\n\n')
      .replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '\n• ')
      .replaceAll(RegExp(r'</(li|ul|ol)>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&rsquo;', '\u2019')
      .replaceAll('&lsquo;', '\u2018')
      .replaceAll('&rdquo;', '\u201D')
      .replaceAll('&ldquo;', '\u201C')
      .replaceAll('&mdash;', '\u2014')
      .replaceAll('&ndash;', '\u2013')
      .replaceAll('&hellip;', '\u2026');
  // Collapse horizontal whitespace, cap runs of blank lines at one.
  t = t
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  return t.isEmpty ? null : t;
}
