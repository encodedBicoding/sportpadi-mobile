import 'package:sportpadi_mobile/data/messages/message_models.dart'
    show MessageAttachment, MessageGroupRef;
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Discussions: reddit-style-ish threads in a group or one of its teams
/// (docs/design/discussions.md). Shapes mirror `/api/mobile/discussions` and
/// decode defensively. Photos reuse [MessageAttachment]; the thread's group
/// reuses [MessageGroupRef].

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e)
      ]
    : const [];

bool _bool(dynamic v) => v == true;

/// -1, 0 or 1.
int _vote(dynamic v) => (parseInt(v) ?? 0).clamp(-1, 1);

/// Flairs, as the server takes them, with their labels.
const discussionFlairs = <({String value, String label})>[
  (value: 'general', label: 'General'),
  (value: 'question', label: 'Question'),
  (value: 'issue', label: 'Issue'),
  (value: 'idea', label: 'Idea'),
];

String discussionFlairLabel(String v) => discussionFlairs
    .firstWhere((f) => f.value == v,
        orElse: () => (value: 'general', label: 'General'))
    .label;

String _flair(dynamic v) =>
    discussionFlairs.any((f) => f.value == v) ? v as String : 'general';

String _status(dynamic v) => v == 'resolved' ? 'resolved' : 'open';

/// The vote a tap on ▲ ([pressed] 1) or ▼ ([pressed] -1) leaves: pressing
/// the one already chosen clears it.
int nextDiscussionVote(int current, int pressed) =>
    current == pressed ? 0 : pressed;

/// Who wrote a discussion or comment. [role] is `admin`, `coach` or null;
/// [guardianOf] is the ward's first name when they post "as Tobi's
/// guardian".
class DiscussionAuthor {
  const DiscussionAuthor({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.role,
    this.guardianOf,
  });
  final String id;
  final String name;
  final String? avatarUrl;
  final String? role;
  final String? guardianOf;

  bool get isAdmin => role == 'admin';
  bool get isCoach => role == 'coach';

  static DiscussionAuthor? fromJson(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    final role = j['role'];
    return DiscussionAuthor(
      id: parseStr(j['id']) ?? '',
      name: parseStr(j['name']) ?? 'Member',
      avatarUrl: parseStr(j['avatarUrl']),
      role: role == 'admin' || role == 'coach' ? role as String : null,
      guardianOf: parseStr(j['guardianOf']),
    );
  }
}

const _unknownAuthor = DiscussionAuthor(id: '', name: 'Member');

/// One discussion in a list.
class DiscussionItem {
  const DiscussionItem({
    required this.id,
    required this.groupId,
    this.teamId,
    this.teamName,
    required this.title,
    this.preview = '',
    this.flair = 'general',
    this.status = 'open',
    this.score = 0,
    this.myVote = 0,
    this.commentCount = 0,
    this.pinned = false,
    this.locked = false,
    this.imageUrl,
    this.author = _unknownAuthor,
    this.mine = false,
    this.createdAt,
    this.lastActivityAt,
    this.unseen = false,
    this.newComments = 0,
    this.groupName,
    this.groupImageUrl,
  });

  final String id;
  final String groupId;
  final String? teamId;
  final String? teamName;
  final String title;
  final String preview;

  /// `general` · `question` · `issue` · `idea`.
  final String flair;

  /// `open` · `resolved`.
  final String status;
  final int score;
  final int myVote;
  final int commentCount;
  final bool pinned;
  final bool locked;
  final String? imageUrl;
  final DiscussionAuthor author;
  final bool mine;
  final DateTime? createdAt;
  final DateTime? lastActivityAt;

  /// New activity here since I last opened it (drives the card's "new" dot).
  final bool unseen;

  /// Comments by others since I last opened it (all of them if I never
  /// did). Only the "mine" list (every group) carries it.
  final int newComments;

  /// The discussion's group — only the "mine" list (every group) carries it.
  final String? groupName;
  final String? groupImageUrl;

  bool get isResolved => status == 'resolved';

  DiscussionItem copyWith({
    String? title,
    String? flair,
    String? status,
    int? score,
    int? myVote,
    int? commentCount,
    bool? pinned,
    bool? locked,
    bool? unseen,
    int? newComments,
  }) =>
      DiscussionItem(
        id: id,
        groupId: groupId,
        teamId: teamId,
        teamName: teamName,
        title: title ?? this.title,
        preview: preview,
        flair: flair ?? this.flair,
        status: status ?? this.status,
        score: score ?? this.score,
        myVote: myVote ?? this.myVote,
        commentCount: commentCount ?? this.commentCount,
        pinned: pinned ?? this.pinned,
        locked: locked ?? this.locked,
        imageUrl: imageUrl,
        author: author,
        mine: mine,
        createdAt: createdAt,
        lastActivityAt: lastActivityAt,
        unseen: unseen ?? this.unseen,
        newComments: newComments ?? this.newComments,
        groupName: groupName,
        groupImageUrl: groupImageUrl,
      );

  factory DiscussionItem.fromJson(Map<String, dynamic> j) => DiscussionItem(
        id: parseStr(j['id']) ?? '',
        groupId: parseStr(j['groupId']) ?? '',
        teamId: parseStr(j['teamId']),
        teamName: parseStr(j['teamName']),
        title: parseStr(j['title']) ?? 'Discussion',
        preview: j['preview'] is String ? j['preview'] as String : '',
        flair: _flair(j['flair']),
        status: _status(j['status']),
        score: parseInt(j['score']) ?? 0,
        myVote: _vote(j['myVote']),
        commentCount: parseInt(j['commentCount']) ?? 0,
        pinned: _bool(j['pinned']),
        locked: _bool(j['locked']),
        imageUrl: parseStr(j['imageUrl']),
        author: DiscussionAuthor.fromJson(j['author']) ?? _unknownAuthor,
        mine: _bool(j['mine']),
        createdAt: parseDate(j['createdAt']),
        lastActivityAt: parseDate(j['lastActivityAt']),
        unseen: _bool(j['unseen']),
        newComments: parseInt(j['newComments']) ?? 0,
        groupName: parseStr(j['groupName']),
        groupImageUrl: parseStr(j['groupImageUrl']),
      );
}

/// A page of discussions; [nextCursor] is an offset.
class DiscussionPage {
  const DiscussionPage({this.items = const [], this.nextCursor});
  final List<DiscussionItem> items;
  final int? nextCursor;

  bool get hasMore => nextCursor != null;

  DiscussionPage copyWith({List<DiscussionItem>? items}) =>
      DiscussionPage(items: items ?? this.items, nextCursor: nextCursor);

  factory DiscussionPage.fromJson(Map<String, dynamic> j) => DiscussionPage(
        items: [for (final d in _maps(j['items'])) DiscussionItem.fromJson(d)]
            .where((d) => d.id.isNotEmpty)
            .toList(),
        nextCursor: parseInt(j['nextCursor']),
      );
}

/// A ward of mine on a team, when I'm in its space only through them.
class DiscussionWardRef {
  const DiscussionWardRef({required this.id, required this.name});
  final String id;
  final String name;

  String get firstName {
    final t = name.trim();
    final i = t.indexOf(' ');
    return i > 0 ? t.substring(0, i) : t;
  }

  factory DiscussionWardRef.fromJson(Map<String, dynamic> j) =>
      DiscussionWardRef(
          id: parseStr(j['id']) ?? '', name: parseStr(j['name']) ?? 'Ward');
}

/// A team space I can see (and post in).
class DiscussionSpaceTeam {
  const DiscussionSpaceTeam({
    required this.id,
    required this.name,
    this.logoUrl,
    this.canModerate = false,
    this.asGuardianOf = const [],
  });
  final String id;
  final String name;
  final String? logoUrl;
  final bool canModerate;

  /// Set when I'm only here through my wards: I post as their guardian.
  final List<DiscussionWardRef> asGuardianOf;

  factory DiscussionSpaceTeam.fromJson(Map<String, dynamic> j) =>
      DiscussionSpaceTeam(
        id: parseStr(j['id']) ?? '',
        name: parseStr(j['name']) ?? 'Team',
        logoUrl: parseStr(j['logoUrl']),
        canModerate: _bool(j['canModerate']),
        asGuardianOf: [
          for (final w in _maps(j['asGuardianOf'])) DiscussionWardRef.fromJson(w)
        ].where((w) => w.id.isNotEmpty).toList(),
      );
}

/// Where I can read and post in a group: group-wide ([group]) and teams.
class DiscussionSpaces {
  const DiscussionSpaces(
      {this.isAdmin = false, this.group = false, this.teams = const []});
  final bool isAdmin;
  final bool group;
  final List<DiscussionSpaceTeam> teams;

  /// Anywhere at all to read or post.
  bool get any => group || teams.isNotEmpty;

  DiscussionSpaceTeam? team(String? id) {
    if (id == null) return null;
    for (final t in teams) {
      if (t.id == id) return t;
    }
    return null;
  }

  factory DiscussionSpaces.fromJson(Map<String, dynamic> j) => DiscussionSpaces(
        isAdmin: _bool(j['isAdmin']),
        group: _bool(j['group']),
        teams: [for (final t in _maps(j['teams'])) DiscussionSpaceTeam.fromJson(t)]
            .where((t) => t.id.isNotEmpty)
            .toList(),
      );
}

/// The discussion itself, on its thread.
class DiscussionDetail {
  const DiscussionDetail({
    required this.id,
    required this.group,
    this.teamId,
    this.teamName,
    required this.title,
    this.body = '',
    this.flair = 'general',
    this.status = 'open',
    this.attachments = const [],
    this.score = 0,
    this.myVote = 0,
    this.commentCount = 0,
    this.pinned = false,
    this.locked = false,
    this.author = _unknownAuthor,
    this.createdAt,
    this.editedAt,
  });

  final String id;
  final MessageGroupRef group;
  final String? teamId;
  final String? teamName;
  final String title;
  final String body;
  final String flair;
  final String status;
  final List<MessageAttachment> attachments;
  final int score;
  final int myVote;
  final int commentCount;
  final bool pinned;
  final bool locked;
  final DiscussionAuthor author;
  final DateTime? createdAt;
  final DateTime? editedAt;

  bool get isResolved => status == 'resolved';

  DiscussionDetail copyWith({
    String? title,
    String? body,
    String? flair,
    String? status,
    int? score,
    int? myVote,
    int? commentCount,
    bool? pinned,
    bool? locked,
    DateTime? editedAt,
  }) =>
      DiscussionDetail(
        id: id,
        group: group,
        teamId: teamId,
        teamName: teamName,
        title: title ?? this.title,
        body: body ?? this.body,
        flair: flair ?? this.flair,
        status: status ?? this.status,
        attachments: attachments,
        score: score ?? this.score,
        myVote: myVote ?? this.myVote,
        commentCount: commentCount ?? this.commentCount,
        pinned: pinned ?? this.pinned,
        locked: locked ?? this.locked,
        author: author,
        createdAt: createdAt,
        editedAt: editedAt ?? this.editedAt,
      );

  factory DiscussionDetail.fromJson(Map<String, dynamic> j) => DiscussionDetail(
        id: parseStr(j['id']) ?? '',
        group: MessageGroupRef.fromJson(_map(j['group'])),
        teamId: parseStr(j['teamId']),
        teamName: parseStr(j['teamName']),
        title: parseStr(j['title']) ?? 'Discussion',
        body: j['body'] is String ? j['body'] as String : '',
        flair: _flair(j['flair']),
        status: _status(j['status']),
        attachments: [
          for (final a in _maps(j['attachments'])) MessageAttachment.fromJson(a)
        ].where((a) => a.url.isNotEmpty).toList(),
        score: parseInt(j['score']) ?? 0,
        myVote: _vote(j['myVote']),
        commentCount: parseInt(j['commentCount']) ?? 0,
        pinned: _bool(j['pinned']),
        locked: _bool(j['locked']),
        author: DiscussionAuthor.fromJson(j['author']) ?? _unknownAuthor,
        createdAt: parseDate(j['createdAt']),
        editedAt: parseDate(j['editedAt']),
      );
}

/// What I may do on a thread.
class DiscussionPermissions {
  const DiscussionPermissions({
    this.isOP = false,
    this.canComment = false,
    this.canModerate = false,
    this.canEdit = false,
    this.canDelete = false,
    this.canResolve = false,
  });
  final bool isOP;
  final bool canComment;
  final bool canModerate;
  final bool canEdit;
  final bool canDelete;
  final bool canResolve;

  factory DiscussionPermissions.fromJson(Map<String, dynamic> j) =>
      DiscussionPermissions(
        isOP: _bool(j['isOP']),
        canComment: _bool(j['canComment']),
        canModerate: _bool(j['canModerate']),
        canEdit: _bool(j['canEdit']),
        canDelete: _bool(j['canDelete']),
        canResolve: _bool(j['canResolve']),
      );
}

/// One comment. A [deleted] one is a "[removed]" placeholder that keeps its
/// replies (no body, no author).
class DiscussionComment {
  const DiscussionComment({
    required this.id,
    this.parentId,
    this.depth = 0,
    this.deleted = false,
    this.body = '',
    this.author,
    this.isOP = false,
    this.mine = false,
    this.score = 0,
    this.myVote = 0,
    this.createdAt,
    this.editedAt,
    this.canEdit = false,
    this.canDelete = false,
    this.pending = false,
  });

  final String id;
  final String? parentId;

  /// 0–4.
  final int depth;
  final bool deleted;
  final String body;
  final DiscussionAuthor? author;

  /// Written by the original poster.
  final bool isOP;
  final bool mine;
  final int score;
  final int myVote;
  final DateTime? createdAt;
  final DateTime? editedAt;
  final bool canEdit;
  final bool canDelete;

  /// Shown optimistically while it's being posted.
  final bool pending;

  DiscussionComment copyWith({
    String? body,
    int? score,
    int? myVote,
    DateTime? editedAt,
  }) =>
      DiscussionComment(
        id: id,
        parentId: parentId,
        depth: depth,
        deleted: deleted,
        body: body ?? this.body,
        author: author,
        isOP: isOP,
        mine: mine,
        score: score ?? this.score,
        myVote: myVote ?? this.myVote,
        createdAt: createdAt,
        editedAt: editedAt ?? this.editedAt,
        canEdit: canEdit,
        canDelete: canDelete,
        pending: pending,
      );

  /// The same comment, as it reads once removed.
  DiscussionComment asDeleted() => DiscussionComment(
        id: id,
        parentId: parentId,
        depth: depth,
        deleted: true,
        mine: mine,
        score: score,
        createdAt: createdAt,
      );

  factory DiscussionComment.fromJson(Map<String, dynamic> j) {
    final deleted = _bool(j['deleted']);
    return DiscussionComment(
      id: parseStr(j['id']) ?? '',
      parentId: parseStr(j['parentId']),
      depth: (parseInt(j['depth']) ?? 0).clamp(0, 4),
      deleted: deleted,
      body: !deleted && j['body'] is String ? j['body'] as String : '',
      author: deleted ? null : DiscussionAuthor.fromJson(j['author']),
      isOP: _bool(j['isOP']),
      mine: _bool(j['mine']),
      score: parseInt(j['score']) ?? 0,
      myVote: _vote(j['myVote']),
      createdAt: parseDate(j['createdAt']),
      editedAt: parseDate(j['editedAt']),
      canEdit: _bool(j['canEdit']),
      canDelete: _bool(j['canDelete']),
    );
  }
}

/// A discussion with my permissions and its comments (flat, in the chosen
/// sort order; the thread builds the tree from `parentId`).
class DiscussionThread {
  const DiscussionThread({
    required this.discussion,
    this.me = const DiscussionPermissions(),
    this.comments = const [],
  });
  final DiscussionDetail discussion;
  final DiscussionPermissions me;
  final List<DiscussionComment> comments;

  DiscussionThread copyWith({
    DiscussionDetail? discussion,
    List<DiscussionComment>? comments,
  }) =>
      DiscussionThread(
        discussion: discussion ?? this.discussion,
        me: me,
        comments: comments ?? this.comments,
      );

  factory DiscussionThread.fromJson(Map<String, dynamic> j) => DiscussionThread(
        discussion: DiscussionDetail.fromJson(_map(j['discussion'])),
        me: DiscussionPermissions.fromJson(_map(j['me'])),
        comments: [
          for (final c in _maps(j['comments'])) DiscussionComment.fromJson(c)
        ].where((c) => c.id.isNotEmpty).toList(),
      );
}

/// A change made on a thread, broadcast so lists already on screen (the
/// Discussions list, the group and team sections) show it without a refetch.
/// Null fields didn't change; [removed] drops it from lists.
class DiscussionChange {
  const DiscussionChange({
    required this.id,
    this.title,
    this.flair,
    this.status,
    this.score,
    this.myVote,
    this.commentCount,
    this.pinned,
    this.locked,
    this.removed = false,
    this.seen = false,
  });
  final String id;
  final String? title;
  final String? flair;
  final String? status;
  final int? score;
  final int? myVote;
  final int? commentCount;
  final bool? pinned;
  final bool? locked;
  final bool removed;

  /// The thread was opened (so its card's "new" dot goes).
  final bool seen;

  /// Everything a thread knows that a list card shows.
  factory DiscussionChange.of(DiscussionDetail d) => DiscussionChange(
        id: d.id,
        title: d.title,
        flair: d.flair,
        status: d.status,
        score: d.score,
        myVote: d.myVote,
        commentCount: d.commentCount,
        pinned: d.pinned,
        locked: d.locked,
        seen: true,
      );

  DiscussionItem applyTo(DiscussionItem i) => i.copyWith(
        title: title,
        flair: flair,
        status: status,
        score: score,
        myVote: myVote,
        commentCount: commentCount,
        pinned: pinned,
        locked: locked,
        unseen: seen ? false : null,
        newComments: seen ? 0 : null,
      );
}
