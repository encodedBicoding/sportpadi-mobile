import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Sharing (docs/wiki/sharing.md in the workspace) — the shapes of
/// `/api/mobile/share`, read leniently.

/// What a link is, as THIS viewer may see it. Unavailable = not one of ours,
/// gone, or not theirs to see (the server never says which).
class SharePreview {
  const SharePreview({
    required this.available,
    this.kind,
    this.id,
    this.url,
    this.title,
    this.subtitle,
    this.imageUrl,
  });

  static const unavailable = SharePreview(available: false);

  final bool available;

  /// event · group · group_invite · tournament · league · competition ·
  /// highlight · ticket · team_invite · call_for_teams · player · match · team
  final String? kind;
  final String? id;

  /// Canonical and absolute: what an in-app send carries.
  final String? url;
  final String? title;

  /// Names and places only; the kind's own word comes from [kind].
  final String? subtitle;
  final String? imageUrl;

  factory SharePreview.fromJson(Map<String, dynamic> j) {
    final url = parseStr(j['url']);
    final title = parseStr(j['title']);
    if (j['available'] != true || url == null || title == null) {
      return unavailable;
    }
    return SharePreview(
      available: true,
      kind: parseStr(j['kind']),
      id: parseStr(j['id']),
      url: url,
      title: title,
      subtitle: parseStr(j['subtitle']),
      imageUrl: parseStr(j['imageUrl']),
    );
  }
}

/// Someone the share can go to: a thread I'm in ([conversationId]) or a
/// person I could start a profile DM with ([userId] only).
class ShareRecipient {
  const ShareRecipient({
    this.conversationId,
    this.userId,
    required this.name,
    this.avatarUrl,
    this.context,
    this.threadKind,
    this.aboutWard,
  });

  final String? conversationId;

  /// The one person on the other side, when there is one.
  final String? userId;
  final String name;
  final String? avatarUrl;

  /// A group thread: the group's name. Null for people.
  final String? context;

  /// direct · contact_admins · profile · null (a person, no thread yet).
  final String? threadKind;

  /// A guardian's "About Tobi" thread: the ward's name.
  final String? aboutWard;

  /// One key per recipient (a thread, or a person).
  String get key => conversationId != null ? 'c:$conversationId' : 'u:$userId';

  /// What `send` takes for this recipient.
  Map<String, String?> get to => conversationId != null
      ? {'conversationId': conversationId}
      : {'userId': userId};

  factory ShareRecipient.fromJson(Map<String, dynamic> j) => ShareRecipient(
        conversationId: parseStr(j['conversationId']),
        userId: parseStr(j['userId']),
        name: parseStr(j['name']) ?? '',
        avatarUrl: parseStr(j['avatarUrl']),
        context: parseStr(j['context']),
        threadKind: parseStr(j['threadKind']),
        aboutWard: parseStr(j['aboutWard']),
      );
}

/// One recipient's answer, in the order they were sent.
class ShareSendResult {
  const ShareSendResult(
      {required this.ok, this.conversationId, this.error, this.code});
  final bool ok;
  final String? conversationId;

  /// Why not, already in the user's language.
  final String? error;
  final String? code;

  factory ShareSendResult.fromJson(Map<String, dynamic> j) => ShareSendResult(
        ok: j['ok'] == true,
        conversationId: parseStr(j['conversationId']),
        error: parseStr(j['error']),
        code: parseStr(j['code']),
      );
}

class ShareSendOutcome {
  const ShareSendOutcome(
      {required this.url, required this.sent, required this.results});
  final String url;
  final int sent;
  final List<ShareSendResult> results;
}
