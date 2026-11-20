import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Highlights (reels) — the shapes of the REST contract in the workspace's
/// `docs/wiki/highlights.md`. Parsed leniently, like every other model here:
/// a missing or mistyped field becomes a safe default, never a crash.

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e)
      ]
    : <Map<String, dynamic>>[];

/// `Person { userId, displayName, username, avatarUrl }`.
class HighlightPerson {
  const HighlightPerson({
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;

  factory HighlightPerson.fromJson(Map<String, dynamic> j) => HighlightPerson(
        userId: parseStr(j['userId']) ?? '',
        displayName: parseStr(j['displayName']) ?? '',
        username: parseStr(j['username']),
        avatarUrl: parseStr(j['avatarUrl']),
      );
}

/// One file of a post: the video, or one photo.
class HighlightMedia {
  const HighlightMedia({
    required this.type,
    required this.url,
    this.posterUrl,
    this.width,
    this.height,
    this.durationMs,
  });

  /// `video` | `image`.
  final String type;
  final String url;
  final String? posterUrl;
  final int? width;
  final int? height;
  final int? durationMs;

  bool get isVideo => type == 'video';

  /// Width over height when the server knows both, else null.
  double? get aspectRatio {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  factory HighlightMedia.fromJson(Map<String, dynamic> j) => HighlightMedia(
        type: parseStr(j['type']) ?? 'image',
        url: parseStr(j['url']) ?? '',
        posterUrl: parseStr(j['posterUrl']),
        width: parseInt(j['width']),
        height: parseInt(j['height']),
        durationMs: parseInt(j['durationMs']),
      );
}

/// The stat a highlight is pinned to (`StatSummary`).
class HighlightStat {
  const HighlightStat({
    required this.activityId,
    required this.gameId,
    this.eventId,
    this.eventSlug,
    this.eventTitle,
    this.eventDate,
    this.categoryId,
    required this.type,
    required this.label,
    this.icon,
    required this.role,
    required this.actionLabel,
    this.actionIcon,
    this.minute,
  });

  final String activityId;
  final String gameId;

  /// The event's four details ([eventId], [eventSlug], [eventTitle],
  /// [eventDate]) are null TOGETHER when the event is private and the viewer
  /// isn't in its group: the stat can be named, its match can't be opened.
  final String? eventId;
  final String? eventSlug;
  final String? eventTitle;

  /// `YYYY-MM-DD`.
  final String? eventDate;
  final String? categoryId;
  final String type;

  /// What the SUBJECT did: "Goal", or "Assist" for the related player.
  final String label;
  final String? icon;

  /// `player` | `related`.
  final String role;
  final String actionLabel;
  final String? actionIcon;
  final int? minute;

  /// False for a private event's stat seen from outside its group.
  bool get eventVisible =>
      eventId != null || eventTitle != null || eventDate != null;

  factory HighlightStat.fromJson(Map<String, dynamic> j) => HighlightStat(
        activityId: parseStr(j['activityId']) ?? '',
        gameId: parseStr(j['gameId']) ?? '',
        eventId: parseStr(j['eventId']),
        eventSlug: parseStr(j['eventSlug']),
        eventTitle: parseStr(j['eventTitle']),
        eventDate: parseStr(j['eventDate']),
        categoryId: parseStr(j['categoryId']),
        type: parseStr(j['type']) ?? '',
        label: parseStr(j['label']) ?? parseStr(j['actionLabel']) ?? '',
        icon: parseStr(j['icon']),
        role: parseStr(j['role']) ?? 'player',
        actionLabel: parseStr(j['actionLabel']) ?? parseStr(j['label']) ?? '',
        actionIcon: parseStr(j['actionIcon']),
        minute: parseInt(j['minute']),
      );
}

class HighlightPermissions {
  const HighlightPermissions({
    this.canDelete = false,
    this.canEditLink = false,
    this.canReport = false,
  });

  /// The author — or an active guardian of the ward the post is about,
  /// except on a `failed` post: in the report window the server offers
  /// anyone but the author nothing but Report (H2,
  /// docs/wiki/highlights.md), so a guardian gets no delete button there
  /// either.
  final bool canDelete;
  final bool canEditLink;
  final bool canReport;

  factory HighlightPermissions.fromJson(Map<String, dynamic> j) =>
      HighlightPermissions(
        canDelete: j['canDelete'] == true,
        canEditLink: j['canEditLink'] == true,
        canReport: j['canReport'] == true,
      );
}

/// `follow { following, canFollow }` — the viewer and the post's SUBJECT
/// (the player it is about; the ward, on a guardian's post). `canFollow`:
/// the server would take a follow (not me, not from a managed account, a
/// profile I may see in full — the rule `POST /players/:id/follow`
/// enforces). The reel offers "Follow" when `canFollow && !following`. A
/// server from before 2026-11-18 sends neither: no button.
///
/// Since follow requests (2026-11-19): `requested` (my request to them waits)
/// and `canRequest` (a tap would send a request — a private adult). The reel
/// offers the pill on `(canFollow || canRequest) && !following && !requested`
/// (review profile-header-app MED-2). Older servers send neither: false.
class HighlightFollow {
  const HighlightFollow({
    this.following = false,
    this.canFollow = false,
    this.requested = false,
    this.canRequest = false,
  });

  final bool following;
  final bool canFollow;
  final bool requested;
  final bool canRequest;

  factory HighlightFollow.fromJson(Map<String, dynamic> j) => HighlightFollow(
        following: j['following'] == true,
        canFollow: j['canFollow'] == true,
        requested: j['requested'] == true,
        canRequest: j['canRequest'] == true,
      );
}

/// One post (`HighlightItem`).
class HighlightItem {
  const HighlightItem({
    required this.id,
    required this.kind,
    required this.status,
    this.failure,
    this.failureMessage,
    required this.source,
    this.caption,
    required this.author,
    required this.subject,
    required this.media,
    this.thumbnailUrl,
    required this.likeCount,
    required this.commentCount,
    required this.likedByMe,
    this.createdAt,
    this.stat,
    required this.permissions,
    this.follow = const HighlightFollow(),
  });

  final String id;

  /// `video` | `photos`.
  final String kind;

  /// `processing` | `ready` | `failed`. `processing` (a web upload the
  /// server is still converting) only ever reaches the author. An app video
  /// is `ready` at once and can still turn `failed` within about a minute:
  /// the server checks the file after publishing it. `failed` reaches its
  /// author, and — while the files are kept as evidence — anyone who may
  /// report it ([takenDownForReport]).
  final String status;

  /// `unsupported` | `unreadable` | `too_long` | `location` | `error`.
  final String? failure;

  /// Why it failed, already in the viewer's language.
  final String? failureMessage;
  final String source;
  final String? caption;
  final HighlightPerson author;

  /// Who the post is about; differs from [author] for a guardian's post
  /// about a ward.
  final HighlightPerson subject;
  final List<HighlightMedia> media;
  final String? thumbnailUrl;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final DateTime? createdAt;

  /// Null when unlinked, or the stat was removed since.
  final HighlightStat? stat;
  final HighlightPermissions permissions;

  /// Whether the viewer follows [subject], and may (the reel's Follow button).
  final HighlightFollow follow;

  bool get isVideo => kind == 'video';
  bool get isReady => status == 'ready';

  /// A video SportPadi's own check took down, answered to a viewer who may
  /// report it rather than hidden (`failed` + `canReport`:
  /// docs/wiki/highlights.md, H2 — the server only does this while the
  /// files are still kept, and sends no other permission with it). Its
  /// AUTHOR never gets `canReport` on their own post, so this is exactly
  /// "someone else's, taken down, and there is still something to do about
  /// it".
  bool get takenDownForReport => status == 'failed' && permissions.canReport;
  bool get aboutSomeoneElse =>
      subject.userId.isNotEmpty && subject.userId != author.userId;

  /// The video file of a video post (null for photos, or a broken payload).
  HighlightMedia? get video {
    if (!isVideo) return null;
    for (final m in media) {
      if (m.isVideo && m.url.isNotEmpty) return m;
    }
    return null;
  }

  HighlightItem copyWith({
    int? likeCount,
    int? commentCount,
    bool? likedByMe,
  }) =>
      HighlightItem(
        id: id,
        kind: kind,
        status: status,
        failure: failure,
        failureMessage: failureMessage,
        source: source,
        caption: caption,
        author: author,
        subject: subject,
        media: media,
        thumbnailUrl: thumbnailUrl,
        likeCount: likeCount ?? this.likeCount,
        commentCount: commentCount ?? this.commentCount,
        likedByMe: likedByMe ?? this.likedByMe,
        createdAt: createdAt,
        stat: stat,
        permissions: permissions,
        follow: follow,
      );

  factory HighlightItem.fromJson(Map<String, dynamic> j) {
    final author = HighlightPerson.fromJson(_map(j['author']));
    final subject = j['subject'] is Map
        ? HighlightPerson.fromJson(_map(j['subject']))
        : author;
    return HighlightItem(
      id: parseStr(j['id']) ?? '',
      kind: parseStr(j['kind']) ?? 'photos',
      status: parseStr(j['status']) ?? 'ready',
      failure: parseStr(j['failure']),
      failureMessage: parseStr(j['failureMessage']),
      source: parseStr(j['source']) ?? 'app',
      caption: parseStr(j['caption']),
      author: author,
      subject: subject,
      media: [for (final m in _maps(j['media'])) HighlightMedia.fromJson(m)],
      thumbnailUrl: parseStr(j['thumbnailUrl']),
      likeCount: parseInt(j['likeCount']) ?? 0,
      commentCount: parseInt(j['commentCount']) ?? 0,
      likedByMe: j['likedByMe'] == true,
      createdAt: parseDate(j['createdAt']),
      stat: j['stat'] is Map ? HighlightStat.fromJson(_map(j['stat'])) : null,
      permissions: HighlightPermissions.fromJson(_map(j['permissions'])),
      follow: HighlightFollow.fromJson(_map(j['follow'])),
    );
  }
}

/// A page of a cursor-paged list. [nextCursor] null = the end. A page may be
/// short, even empty, and still have a cursor (posts the viewer may not see
/// were skipped) — callers keep paging until it is null.
class HighlightsPage<T> {
  const HighlightsPage({required this.items, this.nextCursor});
  final List<T> items;
  final String? nextCursor;
}

class HighlightComment {
  const HighlightComment({
    required this.id,
    required this.body,
    this.createdAt,
    required this.user,
    required this.mine,
    required this.canDelete,
  });

  final String id;
  final String body;
  final DateTime? createdAt;
  final HighlightPerson user;
  final bool mine;
  final bool canDelete;

  factory HighlightComment.fromJson(Map<String, dynamic> j) => HighlightComment(
        id: parseStr(j['id']) ?? '',
        body: parseStr(j['body']) ?? '',
        createdAt: parseDate(j['createdAt']),
        user: HighlightPerson.fromJson(_map(j['user'])),
        mine: j['mine'] == true,
        canDelete: j['canDelete'] == true,
      );
}

class HighlightCommentsPage {
  const HighlightCommentsPage({
    required this.items,
    this.nextCursor,
    this.commentCount,
  });
  final List<HighlightComment> items;
  final String? nextCursor;
  final int? commentCount;
}

/// The extra allowance for VIDEO posts (`Quota.video`): so many in a rolling
/// 24 hours, and only so many being converted by the server at once. It
/// never stops a photo post.
class HighlightVideoQuota {
  const HighlightVideoQuota({
    this.limit,
    this.used,
    this.remaining,
    this.nextSlotAt,
    this.processing,
    this.maxProcessing,
    this.blockedBy,
  });

  final int? limit;
  final int? used;
  final int? remaining;

  /// When the oldest of today's videos leaves the window (set once none is
  /// left).
  final DateTime? nextSlotAt;
  final int? processing;
  final int? maxProcessing;

  /// Why no video can be posted right now — an OPEN set: `daily` and
  /// `processing` are known today, anything else still means "no video for
  /// now". Null = videos are fine.
  final String? blockedBy;

  factory HighlightVideoQuota.fromJson(Map<String, dynamic> j) =>
      HighlightVideoQuota(
        limit: parseInt(j['limit']),
        used: parseInt(j['used']),
        remaining: parseInt(j['remaining']),
        nextSlotAt: parseDate(j['nextSlotAt']),
        processing: parseInt(j['processing']),
        maxProcessing: parseInt(j['maxProcessing']),
        blockedBy: parseStr(j['blockedBy']),
      );
}

/// The weekly allowance (`Quota`).
class HighlightQuota {
  const HighlightQuota({
    required this.limit,
    required this.used,
    required this.remaining,
    required this.windowDays,
    this.nextSlotAt,
    required this.canPost,
    this.blockedBy,
    this.video,
  });

  final int limit;
  final int used;
  final int remaining;
  final int windowDays;

  /// When the next place frees up (set once the week is used up).
  final DateTime? nextSlotAt;
  final bool canPost;

  /// Why not — an OPEN set: `paused` and `limit` are known today; anything
  /// else gets a generic message.
  final String? blockedBy;

  /// The limits on videos alone. Null (an older server, or nothing sent) =
  /// no extra limit.
  final HighlightVideoQuota? video;

  factory HighlightQuota.fromJson(Map<String, dynamic> j) => HighlightQuota(
        limit: parseInt(j['limit']) ?? 0,
        used: parseInt(j['used']) ?? 0,
        remaining: parseInt(j['remaining']) ?? 0,
        windowDays: parseInt(j['windowDays']) ?? 7,
        nextSlotAt: parseDate(j['nextSlotAt']),
        canPost: j['canPost'] == true,
        blockedBy: parseStr(j['blockedBy']),
        video: j['video'] is Map
            ? HighlightVideoQuota.fromJson(_map(j['video']))
            : null,
      );
}

/// A presigned PUT for one file (`UploadSlot`).
class HighlightUploadSlot {
  const HighlightUploadSlot({
    required this.key,
    required this.uploadUrl,
    required this.headers,
    this.maxBytes,
  });

  final String key;
  final String uploadUrl;

  /// To be sent exactly as given — the URL was signed with them.
  final Map<String, String> headers;
  final int? maxBytes;

  factory HighlightUploadSlot.fromJson(Map<String, dynamic> j) {
    final raw = j['headers'];
    return HighlightUploadSlot(
      key: parseStr(j['key']) ?? '',
      uploadUrl: parseStr(j['uploadUrl']) ?? '',
      headers: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value != null) '${e.key}': '${e.value}',
      },
      maxBytes: parseInt(j['maxBytes']),
    );
  }
}

/// One entry of the stat picker (`LinkableStat`): a stat of mine — or of a
/// ward — that can take a highlight.
class LinkableStat {
  const LinkableStat({
    required this.stat,
    required this.subject,
    this.forWard = false,
    this.recordedAt,
    this.highlightId,
    required this.highlightIsMine,
  });

  final HighlightStat stat;
  final HighlightPerson subject;

  /// The stat is my ward's and I may attach a highlight for them: the link
  /// then carries `subject.userId`, and the post is ABOUT the ward.
  final bool forWard;
  final DateTime? recordedAt;

  /// Set = this (stat, subject) already has a highlight.
  final String? highlightId;
  final bool highlightIsMine;

  bool get taken => highlightId != null;

  factory LinkableStat.fromJson(Map<String, dynamic> j) => LinkableStat(
        stat: HighlightStat.fromJson(j),
        subject: HighlightPerson.fromJson(_map(j['subject'])),
        forWard: j['forWard'] == true,
        recordedAt: parseDate(j['recordedAt']),
        highlightId: parseStr(j['highlightId']),
        highlightIsMine: j['highlightIsMine'] == true,
      );
}

/// What to send as a post's `link`.
class HighlightLink {
  const HighlightLink({required this.activityId, this.subjectUserId});
  final String activityId;

  /// Only needed to choose between me and a ward on the same stat.
  final String? subjectUserId;

  Map<String, dynamic> toJson() => {
        'activityId': activityId,
        if (subjectUserId != null) 'subjectUserId': subjectUserId,
      };
}

/// A highlight on a match's timeline (`byGame`).
class GameHighlightRef {
  const GameHighlightRef({
    required this.activityId,
    required this.id,
    required this.kind,
    required this.subject,
    this.thumbnailUrl,
  });

  final String activityId;
  final String id;
  final String kind;
  final HighlightPerson subject;
  final String? thumbnailUrl;

  factory GameHighlightRef.fromJson(Map<String, dynamic> j) => GameHighlightRef(
        activityId: parseStr(j['activityId']) ?? '',
        id: parseStr(j['id']) ?? '',
        kind: parseStr(j['kind']) ?? 'video',
        subject: HighlightPerson.fromJson(_map(j['subject'])),
        thumbnailUrl: parseStr(j['thumbnailUrl']),
      );
}

/// Helpers shared by the repository.
List<Map<String, dynamic>> highlightMaps(dynamic v) => _maps(v);
Map<String, dynamic> highlightMap(dynamic v) => _map(v);
