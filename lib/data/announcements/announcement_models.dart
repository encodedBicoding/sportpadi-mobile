import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Announcements (Messaging 1): broadcasts from a group's admins, its team
/// coaches and event organisers. No replies — an optional "Got it" only.
/// Shapes mirror `/api/mobile/announcements` and decode defensively.

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e)
      ]
    : const [];

bool _bool(dynamic v) => v == true;

int _int(dynamic v) => parseInt(v) ?? 0;

/// An image or PDF attached to an announcement.
class AnnouncementAttachment {
  const AnnouncementAttachment(
      {required this.url, required this.kind, this.name});
  final String url;

  /// `image` or `pdf`.
  final String kind;
  final String? name;

  bool get isPdf => kind == 'pdf';

  factory AnnouncementAttachment.fromJson(Map<String, dynamic> j) =>
      AnnouncementAttachment(
        url: parseStr(j['url']) ?? '',
        kind: j['kind'] == 'pdf' ? 'pdf' : 'image',
        name: parseStr(j['name']),
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'kind': kind,
        if (name != null) 'name': name,
      };
}

/// The optional link to an event or team in the same group.
class AnnouncementLink {
  const AnnouncementLink(
      {required this.type, required this.id, required this.label, this.url});

  /// `event` or `team`.
  final String type;
  final String id;
  final String label;

  /// Web path: `/events/<slug>` or `/groups/<g>/teams/<t>`.
  final String? url;

  static AnnouncementLink? fromJson(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    final id = parseStr(j['id']);
    if (id == null) return null;
    return AnnouncementLink(
      type: j['type'] == 'team' ? 'team' : 'event',
      id: id,
      label: parseStr(j['label']) ?? '',
      url: parseStr(j['url']),
    );
  }
}

/// A ward a guardian's copy was for.
class AnnouncementWard {
  const AnnouncementWard({required this.id, required this.name});
  final String id;
  final String name;

  factory AnnouncementWard.fromJson(Map<String, dynamic> j) => AnnouncementWard(
        id: parseStr(j['id']) ?? '',
        name: parseStr(j['name']) ?? 'Ward',
      );
}

/// One announcement as its recipient sees it (inbox row, pinned card, and the
/// base of the detail view).
class AnnouncementItem {
  const AnnouncementItem({
    required this.id,
    required this.groupId,
    required this.groupName,
    this.groupImageUrl,
    required this.senderId,
    required this.senderName,
    this.senderAvatarUrl,
    this.senderRole = 'admin',
    this.audienceKind = 'group',
    this.audienceLabel = '',
    required this.title,
    required this.body,
    this.attachments = const [],
    this.link,
    this.priority = 'normal',
    this.pinnedUntil,
    this.expiresAt,
    this.createdAt,
    this.seenAt,
    this.ackedAt,
    this.forSelf = true,
    this.forWards = const [],
  });

  final String id;
  final String groupId;
  final String groupName;
  final String? groupImageUrl;
  final String senderId;
  final String senderName;
  final String? senderAvatarUrl;

  /// `admin` · `coach` · `organiser`.
  final String senderRole;

  /// `group` · `teams` · `event` · `members`.
  final String audienceKind;

  /// "Everyone", "U12 Lions", "Saturday 5-a-side", "Selected members".
  final String audienceLabel;
  final String title;
  final String body;
  final List<AnnouncementAttachment> attachments;
  final AnnouncementLink? link;

  /// `normal` or `urgent`.
  final String priority;
  final DateTime? pinnedUntil;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? seenAt;
  final DateTime? ackedAt;

  /// Whether this copy was for the viewer themselves (false: only for wards).
  final bool forSelf;

  /// Wards this copy was for (guardians): "For Tobi, Zara".
  final List<AnnouncementWard> forWards;

  bool get isUrgent => priority == 'urgent';
  bool get isUnread => seenAt == null;
  bool get isAcked => ackedAt != null;
  bool get isPinned =>
      pinnedUntil != null && pinnedUntil!.isAfter(DateTime.now());

  List<AnnouncementAttachment> get images =>
      [for (final a in attachments) if (!a.isPdf && a.url.isNotEmpty) a];
  List<AnnouncementAttachment> get pdfs =>
      [for (final a in attachments) if (a.isPdf && a.url.isNotEmpty) a];

  /// "Admin", "Coach", "Organiser".
  String get roleLabel => switch (senderRole) {
        'coach' => 'Coach',
        'organiser' => 'Organiser',
        _ => 'Admin',
      };

  /// "For Tobi, Zara" on a guardian's copy; null otherwise.
  String? get wardsLabel => forWards.isEmpty
      ? null
      : 'For ${forWards.map((w) => w.name).join(', ')}';

  AnnouncementItem copyWith({DateTime? seenAt, DateTime? ackedAt}) =>
      AnnouncementItem(
        id: id,
        groupId: groupId,
        groupName: groupName,
        groupImageUrl: groupImageUrl,
        senderId: senderId,
        senderName: senderName,
        senderAvatarUrl: senderAvatarUrl,
        senderRole: senderRole,
        audienceKind: audienceKind,
        audienceLabel: audienceLabel,
        title: title,
        body: body,
        attachments: attachments,
        link: link,
        priority: priority,
        pinnedUntil: pinnedUntil,
        expiresAt: expiresAt,
        createdAt: createdAt,
        seenAt: seenAt ?? this.seenAt,
        ackedAt: ackedAt ?? this.ackedAt,
        forSelf: forSelf,
        forWards: forWards,
      );

  factory AnnouncementItem.fromJson(Map<String, dynamic> j) {
    final role = parseStr(j['senderRole']);
    return AnnouncementItem(
      id: parseStr(j['id']) ?? '',
      groupId: parseStr(j['groupId']) ?? '',
      groupName: parseStr(j['groupName']) ?? 'Group',
      groupImageUrl: parseStr(j['groupImageUrl']),
      senderId: parseStr(j['senderId']) ?? '',
      senderName: parseStr(j['senderName']) ?? 'Group staff',
      senderAvatarUrl: parseStr(j['senderAvatarUrl']),
      senderRole: role == 'coach' || role == 'organiser' ? role! : 'admin',
      audienceKind: parseStr(j['audienceKind']) ?? 'group',
      audienceLabel: parseStr(j['audienceLabel']) ?? '',
      title: parseStr(j['title']) ?? '',
      body: parseStr(j['body']) ?? '',
      attachments: [
        for (final a in _maps(j['attachments']))
          AnnouncementAttachment.fromJson(a)
      ],
      link: AnnouncementLink.fromJson(j['link']),
      priority: j['priority'] == 'urgent' ? 'urgent' : 'normal',
      pinnedUntil: parseDate(j['pinnedUntil']),
      expiresAt: parseDate(j['expiresAt']),
      createdAt: parseDate(j['createdAt']),
      seenAt: parseDate(j['seenAt']),
      ackedAt: parseDate(j['ackedAt']),
      forSelf: j['forSelf'] != false,
      forWards: [
        for (final w in _maps(j['forWards'])) AnnouncementWard.fromJson(w)
      ],
    );
  }
}

/// A page of the inbox.
class AnnouncementPage {
  const AnnouncementPage({required this.items, this.nextCursor});
  final List<AnnouncementItem> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  factory AnnouncementPage.fromJson(Map<String, dynamic> j) => AnnouncementPage(
        items: [
          for (final e in _maps(j['items'])) AnnouncementItem.fromJson(e)
        ],
        nextCursor: parseStr(j['nextCursor']),
      );
}

/// The Inbox badge: unseen announcements, and how many of them are urgent.
class AnnouncementUnread {
  const AnnouncementUnread({this.announcements = 0, this.urgent = 0});
  final int announcements;
  final int urgent;

  static const zero = AnnouncementUnread();

  factory AnnouncementUnread.fromJson(Map<String, dynamic> j) =>
      AnnouncementUnread(
        announcements: _int(j['announcements']),
        urgent: _int(j['urgent']),
      );
}

/// One person on the receipts list (a ward counts as seen when any of their
/// guardians opened it).
class ReceiptPerson {
  const ReceiptPerson({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.isWard = false,
    this.guardians = const [],
    this.seen = false,
    this.acked = false,
  });
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool isWard;

  /// Guardians who received it on a ward's behalf.
  final List<String> guardians;
  final bool seen;
  final bool acked;

  factory ReceiptPerson.fromJson(Map<String, dynamic> j) => ReceiptPerson(
        userId: parseStr(j['userId']) ?? '',
        displayName: parseStr(j['displayName']) ?? 'Member',
        avatarUrl: parseStr(j['avatarUrl']),
        isWard: _bool(j['isWard']),
        guardians: parseStrList(j['guardians']),
        seen: _bool(j['seen']),
        acked: _bool(j['acked']),
      );
}

/// Seen / "Got it" for the sender and the group's admins.
class AnnouncementReceipts {
  const AnnouncementReceipts({
    this.total = 0,
    this.seen = 0,
    this.acked = 0,
    this.deliveries = 0,
    this.pushed = 0,
    this.emailed = 0,
    this.people = const [],
  });
  final int total;
  final int seen;
  final int acked;
  final int deliveries;
  final int pushed;
  final int emailed;
  final List<ReceiptPerson> people;

  static AnnouncementReceipts? fromJson(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return AnnouncementReceipts(
      total: _int(j['total']),
      seen: _int(j['seen']),
      acked: _int(j['acked']),
      deliveries: _int(j['deliveries']),
      pushed: _int(j['pushed']),
      emailed: _int(j['emailed']),
      people: [for (final p in _maps(j['people'])) ReceiptPerson.fromJson(p)],
    );
  }
}

/// The detail view: the announcement, whether the viewer received it, and
/// (for its sender and the group's admins) receipts.
class AnnouncementDetail {
  const AnnouncementDetail({
    required this.item,
    this.isRecipient = false,
    this.canManage = false,
    this.receipts,
  });
  final AnnouncementItem item;
  final bool isRecipient;
  final bool canManage;
  final AnnouncementReceipts? receipts;

  factory AnnouncementDetail.fromJson(Map<String, dynamic> j) =>
      AnnouncementDetail(
        item: AnnouncementItem.fromJson(j),
        isRecipient: _bool(j['isRecipient']),
        canManage: _bool(j['canManage']),
        receipts: AnnouncementReceipts.fromJson(j['receipts']),
      );
}

// ── Composer ────────────────────────────────────────────────────────────────

class ComposerTeam {
  const ComposerTeam(
      {required this.id, required this.name, this.logoUrl, this.players = 0});
  final String id;
  final String name;
  final String? logoUrl;
  final int players;

  factory ComposerTeam.fromJson(Map<String, dynamic> j) => ComposerTeam(
        id: parseStr(j['id']) ?? '',
        name: parseStr(j['name']) ?? 'Team',
        logoUrl: parseStr(j['logoUrl']),
        players: _int(j['players']),
      );
}

class ComposerEvent {
  const ComposerEvent({
    required this.id,
    required this.title,
    this.date,
    this.time,
    this.going = 0,
    this.checkedIn = 0,
  });
  final String id;
  final String title;

  /// `YYYY-MM-DD` (the event's own calendar day).
  final String? date;

  /// `HH:MM`, or null.
  final String? time;
  final int going;
  final int checkedIn;

  factory ComposerEvent.fromJson(Map<String, dynamic> j) => ComposerEvent(
        id: parseStr(j['id']) ?? '',
        title: parseStr(j['title']) ?? 'Event',
        date: parseStr(j['date']),
        time: parseStr(j['time']),
        going: _int(j['going']),
        checkedIn: _int(j['checkedIn']),
      );
}

/// The group's urgent quota (5 a rolling day on Free; unlimited on paid plans).
class UrgentQuota {
  const UrgentQuota({
    this.unlimited = false,
    this.used = 0,
    this.limit,
    this.remaining,
    this.nextFreeAt,
  });
  final bool unlimited;
  final int used;
  final int? limit;
  final int? remaining;

  /// When the next urgent slot frees up (only when none are left).
  final DateTime? nextFreeAt;

  bool get canSend => unlimited || (remaining ?? 0) > 0;

  factory UrgentQuota.fromJson(Map<String, dynamic> j) => UrgentQuota(
        unlimited: _bool(j['unlimited']),
        used: _int(j['used']),
        limit: parseInt(j['limit']),
        remaining: parseInt(j['remaining']),
        nextFreeAt: parseDate(j['nextFreeAt']),
      );
}

/// What the caller may send in a group (staff only — the server answers 403
/// to everyone else, which is how entry points decide to hide).
class ComposerInfo {
  const ComposerInfo({
    required this.groupId,
    required this.groupName,
    this.groupImageUrl,
    this.isAdmin = false,
    this.isCoach = false,
    this.canGroup = false,
    this.canTeams = false,
    this.canEvent = false,
    this.canMembers = false,
    this.teams = const [],
    this.events = const [],
    this.urgent = const UrgentQuota(),
  });
  final String groupId;
  final String groupName;
  final String? groupImageUrl;
  final bool isAdmin;
  final bool isCoach;
  final bool canGroup;
  final bool canTeams;
  final bool canEvent;
  final bool canMembers;
  final List<ComposerTeam> teams;
  final List<ComposerEvent> events;
  final UrgentQuota urgent;

  bool canAddressTeam(String teamId) =>
      canTeams && teams.any((t) => t.id == teamId);
  bool canAddressEvent(String eventId) =>
      canEvent && events.any((e) => e.id == eventId);

  factory ComposerInfo.fromJson(Map<String, dynamic> j) {
    final g = _map(j['group']);
    final a = _map(j['audiences']);
    return ComposerInfo(
      groupId: parseStr(g['id']) ?? '',
      groupName: parseStr(g['name']) ?? 'Group',
      groupImageUrl: parseStr(g['imageUrl']),
      isAdmin: _bool(j['isAdmin']),
      isCoach: _bool(j['isCoach']),
      canGroup: _bool(a['group']),
      canTeams: _bool(a['teams']),
      canEvent: _bool(a['event']),
      canMembers: _bool(a['members']),
      teams: [for (final t in _maps(j['teams'])) ComposerTeam.fromJson(t)],
      events: [for (final e in _maps(j['events'])) ComposerEvent.fromJson(e)],
      urgent: UrgentQuota.fromJson(_map(j['urgent'])),
    );
  }
}

/// Someone the caller can hand-pick.
class PickablePerson {
  const PickablePerson({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.isWard = false,
  });
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool isWard;

  factory PickablePerson.fromJson(Map<String, dynamic> j) => PickablePerson(
        userId: parseStr(j['userId']) ?? '',
        displayName: parseStr(j['displayName']) ?? 'Member',
        avatarUrl: parseStr(j['avatarUrl']),
        isWard: _bool(j['isWard']),
      );
}

/// Who an announcement goes to.
class AnnouncementAudience {
  const AnnouncementAudience._(
    this.kind, {
    this.teamIds = const [],
    this.eventId,
    this.scope = 'all',
    this.userIds = const [],
  });

  const AnnouncementAudience.group() : this._('group');
  const AnnouncementAudience.teams(List<String> teamIds)
      : this._('teams', teamIds: teamIds);

  /// [scope]: `going` · `checked_in` · `all`.
  const AnnouncementAudience.event(String eventId, {String scope = 'all'})
      : this._('event', eventId: eventId, scope: scope);
  const AnnouncementAudience.members(List<String> userIds)
      : this._('members', userIds: userIds);

  final String kind;
  final List<String> teamIds;
  final String? eventId;
  final String scope;
  final List<String> userIds;

  /// Enough is chosen to send (or preview).
  bool get isComplete => switch (kind) {
        'teams' => teamIds.isNotEmpty,
        'event' => eventId != null && eventId!.isNotEmpty,
        'members' => userIds.isNotEmpty,
        _ => true,
      };

  Map<String, dynamic> toJson() => switch (kind) {
        'teams' => {'kind': 'teams', 'teamIds': teamIds},
        'event' => {'kind': 'event', 'eventId': eventId, 'scope': scope},
        'members' => {'kind': 'members', 'userIds': userIds},
        _ => {'kind': 'group'},
      };
}

/// How many people an audience reaches.
class AudiencePreview {
  const AudiencePreview(
      {this.people = 0, this.wards = 0, this.guardians = 0, this.deliveries = 0});
  final int people;
  final int wards;
  final int guardians;
  final int deliveries;

  factory AudiencePreview.fromJson(Map<String, dynamic> j) => AudiencePreview(
        people: _int(j['people']),
        wards: _int(j['wards']),
        guardians: _int(j['guardians']),
        deliveries: _int(j['deliveries']),
      );
}

/// A sent announcement, for the staff list.
class SentAnnouncement {
  const SentAnnouncement({
    required this.id,
    required this.title,
    this.body = '',
    this.priority = 'normal',
    this.senderName = '',
    this.audienceLabel = '',
    this.createdAt,
    this.recipientCount = 0,
    this.seen = 0,
    this.acked = 0,
    this.pinnedUntil,
  });
  final String id;
  final String title;
  final String body;
  final String priority;
  final String senderName;
  final String audienceLabel;
  final DateTime? createdAt;

  /// People reached (a ward counts as one person), the same basis as the
  /// receipts' `total`.
  final int recipientCount;
  final int seen;
  final int acked;
  final DateTime? pinnedUntil;

  bool get isUrgent => priority == 'urgent';
  bool get isPinned =>
      pinnedUntil != null && pinnedUntil!.isAfter(DateTime.now());

  factory SentAnnouncement.fromJson(Map<String, dynamic> j) => SentAnnouncement(
        id: parseStr(j['id']) ?? '',
        title: parseStr(j['title']) ?? '',
        body: parseStr(j['body']) ?? '',
        priority: j['priority'] == 'urgent' ? 'urgent' : 'normal',
        senderName: parseStr(j['senderName']) ?? '',
        audienceLabel: parseStr(j['audienceLabel']) ?? '',
        createdAt: parseDate(j['createdAt']),
        recipientCount: _int(j['recipientCount']),
        seen: _int(j['seen']),
        acked: _int(j['acked']),
        pinnedUntil: parseDate(j['pinnedUntil']),
      );
}

class SentPage {
  const SentPage({required this.items, this.nextCursor});
  final List<SentAnnouncement> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  factory SentPage.fromJson(Map<String, dynamic> j) => SentPage(
        items: [
          for (final e in _maps(j['items'])) SentAnnouncement.fromJson(e)
        ],
        nextCursor: parseStr(j['nextCursor']),
      );
}

/// Push / email for one category (`announcements`, `announcements_urgent`,
/// `messages`, `activity`).
class NotificationPreference {
  const NotificationPreference(
      {required this.category, this.push = true, this.email = true});
  final String category;
  final bool push;
  final bool email;

  NotificationPreference copyWith({bool? push, bool? email}) =>
      NotificationPreference(
          category: category,
          push: push ?? this.push,
          email: email ?? this.email);

  factory NotificationPreference.fromJson(Map<String, dynamic> j) =>
      NotificationPreference(
        category: parseStr(j['category']) ?? '',
        push: j['push'] != false,
        email: j['email'] != false,
      );
}
