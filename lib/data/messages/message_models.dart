import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Messages (Messaging 2): conversations between a group's STAFF (admins,
/// team coaches) and ONE member — or a ward's guardians, "About Tobi".
/// Members never message other members. Shapes mirror `/api/mobile/messages`
/// and decode defensively.

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e)
      ]
    : const [];

bool _bool(dynamic v) => v == true;

/// The ward a conversation is about ("About Tobi").
class MessageWardRef {
  const MessageWardRef({required this.id, required this.name});
  final String id;
  final String name;

  static MessageWardRef? fromJson(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    final id = parseStr(j['id']);
    if (id == null) return null;
    return MessageWardRef(id: id, name: parseStr(j['name']) ?? 'Ward');
  }

  String get firstName {
    final t = name.trim();
    final i = t.indexOf(' ');
    return i > 0 ? t.substring(0, i) : t;
  }
}

/// One row of the Messages tab (and of an admin's oversight list).
class ConversationItem {
  const ConversationItem({
    required this.id,
    required this.groupId,
    required this.groupName,
    this.groupImageUrl,
    this.kind = 'direct',
    this.status = 'open',
    this.mySide = 'member',
    required this.title,
    this.avatarUrl,
    this.subtitle = '',
    this.aboutWard,
    this.lastMessageAt,
    this.lastPreview,
    this.lastFromMe = false,
    this.unread = false,
    this.muted = false,
    this.createdAt,
    this.staffName,
  });

  final String id;
  final String groupId;
  final String groupName;
  final String? groupImageUrl;

  /// `direct` or `contact_admins`.
  final String kind;

  /// `open` · `closed` · `locked`.
  final String status;

  /// `member` or `staff` — which side of the conversation I'm on.
  final String mySide;

  /// The other party: "Coach Sam", "Lagos FC admins", "Ada Obi".
  final String title;
  final String? avatarUrl;

  /// "Coach · U12 Lions", "Admin", "Contact the admins", a team or group.
  final String subtitle;
  final MessageWardRef? aboutWard;
  final DateTime? lastMessageAt;
  final String? lastPreview;
  final bool lastFromMe;
  final bool unread;
  final bool muted;
  final DateTime? createdAt;

  /// Oversight list only: who's on the staff side ("Coach Sam", "Admins").
  final String? staffName;

  bool get isContactAdmins => kind == 'contact_admins';
  bool get isOpen => status == 'open';
  bool get isClosed => status == 'closed';
  bool get isLocked => status == 'locked';

  ConversationItem copyWith({bool? unread}) => ConversationItem(
        id: id,
        groupId: groupId,
        groupName: groupName,
        groupImageUrl: groupImageUrl,
        kind: kind,
        status: status,
        mySide: mySide,
        title: title,
        avatarUrl: avatarUrl,
        subtitle: subtitle,
        aboutWard: aboutWard,
        lastMessageAt: lastMessageAt,
        lastPreview: lastPreview,
        lastFromMe: lastFromMe,
        unread: unread ?? this.unread,
        muted: muted,
        createdAt: createdAt,
        staffName: staffName,
      );

  factory ConversationItem.fromJson(Map<String, dynamic> j) => ConversationItem(
        id: parseStr(j['id']) ?? '',
        groupId: parseStr(j['groupId']) ?? '',
        groupName: parseStr(j['groupName']) ?? 'Group',
        groupImageUrl: parseStr(j['groupImageUrl']),
        kind: j['kind'] == 'contact_admins' ? 'contact_admins' : 'direct',
        status: switch (j['status']) {
          'closed' => 'closed',
          'locked' => 'locked',
          _ => 'open',
        },
        mySide: j['mySide'] == 'staff' ? 'staff' : 'member',
        title: parseStr(j['title']) ?? 'Conversation',
        avatarUrl: parseStr(j['avatarUrl']),
        subtitle: parseStr(j['subtitle']) ?? '',
        aboutWard: MessageWardRef.fromJson(j['aboutWard']),
        lastMessageAt: parseDate(j['lastMessageAt']),
        lastPreview: parseStr(j['lastPreview']),
        lastFromMe: _bool(j['lastFromMe']),
        unread: _bool(j['unread']),
        muted: _bool(j['muted']),
        createdAt: parseDate(j['createdAt']),
        staffName: parseStr(j['staffName']),
      );
}

class ConversationPage {
  const ConversationPage({this.items = const [], this.nextCursor});
  final List<ConversationItem> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  factory ConversationPage.fromJson(Map<String, dynamic> j) => ConversationPage(
        items: [for (final c in _maps(j['items'])) ConversationItem.fromJson(c)]
            .where((c) => c.id.isNotEmpty)
            .toList(),
        nextCursor: parseStr(j['nextCursor']),
      );
}

/// An image on a message (text + images only in v1).
class MessageAttachment {
  const MessageAttachment({required this.url, this.kind = 'image'});
  final String url;
  final String kind;

  factory MessageAttachment.fromJson(Map<String, dynamic> j) =>
      MessageAttachment(
          url: parseStr(j['url']) ?? '', kind: parseStr(j['kind']) ?? 'image');

  Map<String, dynamic> toJson() => {'url': url, 'kind': kind};
}

class MessageGroupRef {
  const MessageGroupRef({required this.id, required this.name, this.imageUrl});
  final String id;
  final String name;
  final String? imageUrl;

  factory MessageGroupRef.fromJson(Map<String, dynamic> j) => MessageGroupRef(
        id: parseStr(j['id']) ?? '',
        name: parseStr(j['name']) ?? 'Group',
        imageUrl: parseStr(j['imageUrl']),
      );
}

/// A guardian on a ward thread.
class ConversationPerson {
  const ConversationPerson({required this.userId, required this.name});
  final String userId;
  final String name;

  factory ConversationPerson.fromJson(Map<String, dynamic> j) =>
      ConversationPerson(
        userId: parseStr(j['userId']) ?? '',
        name: parseStr(j['name']) ?? 'Guardian',
      );
}

/// The thread's header and what I may do in it.
class ConversationInfo {
  const ConversationInfo({
    required this.id,
    required this.group,
    this.teamName,
    this.kind = 'direct',
    this.status = 'open',
    required this.title,
    this.avatarUrl,
    this.aboutWard,
    this.guardians = const [],
    this.staffName = 'Admin or coach',
    this.mySide = 'member',
    this.canReply = false,
    this.canClose = false,
    this.isAdmin = false,
    this.mutedUntil,
  });

  final String id;
  final MessageGroupRef group;
  final String? teamName;
  final String kind;
  final String status;
  final String title;
  final String? avatarUrl;
  final MessageWardRef? aboutWard;
  final List<ConversationPerson> guardians;
  final String staffName;

  /// `member` · `staff` · `oversight` (a group admin reading, not a party).
  final String mySide;
  final bool canReply;
  final bool canClose;
  final bool isAdmin;
  final DateTime? mutedUntil;

  bool get isContactAdmins => kind == 'contact_admins';
  bool get isOversight => mySide == 'oversight';
  bool get isStaffSide => mySide == 'staff';
  bool get isClosed => status == 'closed';
  bool get isLocked => status == 'locked';
  bool get isMuted => mutedUntil != null && mutedUntil!.isAfter(DateTime.now());

  /// "Muted until turned back on" is stored as a date far in the future.
  bool get isMutedForever =>
      isMuted &&
      mutedUntil!.isAfter(DateTime.now().add(const Duration(days: 3650)));

  factory ConversationInfo.fromJson(Map<String, dynamic> j) => ConversationInfo(
        id: parseStr(j['id']) ?? '',
        group: MessageGroupRef.fromJson(_map(j['group'])),
        teamName: parseStr(j['teamName']),
        kind: j['kind'] == 'contact_admins' ? 'contact_admins' : 'direct',
        status: switch (j['status']) {
          'closed' => 'closed',
          'locked' => 'locked',
          _ => 'open',
        },
        title: parseStr(j['title']) ?? 'Conversation',
        avatarUrl: parseStr(j['avatarUrl']),
        aboutWard: MessageWardRef.fromJson(j['aboutWard']),
        guardians: [
          for (final g in _maps(j['guardians'])) ConversationPerson.fromJson(g)
        ],
        staffName: parseStr(j['staffName']) ?? 'Admin or coach',
        mySide: switch (j['mySide']) {
          'staff' => 'staff',
          'oversight' => 'oversight',
          _ => 'member',
        },
        canReply: _bool(j['canReply']),
        canClose: _bool(j['canClose']),
        isAdmin: _bool(j['isAdmin']),
        mutedUntil: parseDate(j['mutedUntil']),
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    this.senderAvatarUrl,
    this.senderSide = 'member',
    this.mine = false,
    this.deleted = false,
    this.body = '',
    this.attachments = const [],
    this.replyToId,
    this.createdAt,
    this.canDelete = false,
  });

  final String id;
  final String senderId;
  final String senderName;
  final String? senderAvatarUrl;

  /// `member` or `staff`.
  final String senderSide;
  final bool mine;
  final bool deleted;
  final String body;
  final List<MessageAttachment> attachments;
  final String? replyToId;
  final DateTime? createdAt;
  final bool canDelete;

  /// The same message, as it reads once deleted.
  ChatMessage asDeleted() => ChatMessage(
        id: id,
        senderId: senderId,
        senderName: senderName,
        senderAvatarUrl: senderAvatarUrl,
        senderSide: senderSide,
        mine: mine,
        deleted: true,
        replyToId: replyToId,
        createdAt: createdAt,
      );

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: parseStr(j['id']) ?? '',
        senderId: parseStr(j['senderId']) ?? '',
        senderName: parseStr(j['senderName']) ?? 'Member',
        senderAvatarUrl: parseStr(j['senderAvatarUrl']),
        senderSide: j['senderSide'] == 'staff' ? 'staff' : 'member',
        mine: _bool(j['mine']),
        deleted: _bool(j['deleted']),
        body: j['body'] is String ? j['body'] as String : '',
        attachments: [
          for (final a in _maps(j['attachments'])) MessageAttachment.fromJson(a)
        ].where((a) => a.url.isNotEmpty).toList(),
        replyToId: parseStr(j['replyToId']),
        createdAt: parseDate(j['createdAt']),
        canDelete: _bool(j['canDelete']),
      );
}

/// A conversation with a page of its messages, oldest first. [nextBefore]
/// pages back through older ones.
class ConversationThread {
  const ConversationThread({
    required this.conversation,
    this.messages = const [],
    this.nextBefore,
  });
  final ConversationInfo conversation;
  final List<ChatMessage> messages;
  final String? nextBefore;

  bool get hasEarlier => nextBefore != null;

  ConversationThread copyWith({
    ConversationInfo? conversation,
    List<ChatMessage>? messages,
  }) =>
      ConversationThread(
        conversation: conversation ?? this.conversation,
        messages: messages ?? this.messages,
        nextBefore: nextBefore,
      );

  factory ConversationThread.fromJson(Map<String, dynamic> j) =>
      ConversationThread(
        conversation: ConversationInfo.fromJson(_map(j['conversation'])),
        messages: [
          for (final m in _maps(j['messages'])) ChatMessage.fromJson(m)
        ].where((m) => m.id.isNotEmpty).toList(),
        nextBefore: parseStr(j['nextBefore']),
      );
}

// ── Starting a conversation ────────────────────────────────────────────────

/// Who a member-side thread is for: me (`wardId == null`) or one of my wards.
class StartFor {
  const StartFor({this.wardId, required this.name});
  final String? wardId;
  final String name;

  bool get isMe => wardId == null;

  factory StartFor.fromJson(Map<String, dynamic> j) => StartFor(
        wardId: parseStr(j['wardId']),
        name: parseStr(j['name']) ?? 'Me',
      );
}

class CoachTeamRef {
  const CoachTeamRef({required this.id, required this.name});
  final String id;
  final String name;

  factory CoachTeamRef.fromJson(Map<String, dynamic> j) => CoachTeamRef(
      id: parseStr(j['id']) ?? '', name: parseStr(j['name']) ?? 'Team');
}

/// I'm staff here: an admin (anyone in the group) and/or a coach.
class StaffStartInfo {
  const StaffStartInfo({this.isAdmin = false, this.coachTeams = const []});
  final bool isAdmin;
  final List<CoachTeamRef> coachTeams;

  bool coaches(String teamId) => coachTeams.any((t) => t.id == teamId);

  static StaffStartInfo? fromJson(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return StaffStartInfo(
      isAdmin: _bool(j['isAdmin']),
      coachTeams: [
        for (final t in _maps(j['coachTeams'])) CoachTeamRef.fromJson(t)
      ],
    );
  }
}

/// A coach I (or a ward of mine) can message.
class CoachOption {
  const CoachOption({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.teams = const [],
    this.teamIds = const [],
    this.forWho = const [],
  });
  final String userId;
  final String name;
  final String? avatarUrl;

  /// Team names they coach that I (or my ward) play on (for display).
  final List<String> teams;

  /// The same teams' ids — what matching a coach to a team uses.
  final List<String> teamIds;

  /// Coaches [teamId] (a team I or my ward play on).
  bool coachesTeam(String teamId) => teamIds.contains(teamId);

  /// Me and / or the wards this coach is reachable for.
  final List<StartFor> forWho;

  factory CoachOption.fromJson(Map<String, dynamic> j) => CoachOption(
        userId: parseStr(j['userId']) ?? '',
        name: parseStr(j['name']) ?? 'Coach',
        avatarUrl: parseStr(j['avatarUrl']),
        teams: parseStrList(j['teams']),
        teamIds: parseStrList(j['teamIds']),
        forWho: [for (final f in _maps(j['for'])) StartFor.fromJson(f)],
      );
}

/// What I can start in one group.
class StartOptions {
  const StartOptions({
    required this.group,
    this.asStaff,
    this.contactAdmins = const [],
    this.coaches = const [],
    this.selfBlockedReason,
  });
  final MessageGroupRef group;
  final StaffStartInfo? asStaff;

  /// Set when I'm a supervised player (claimed my account under 18, Wards 3):
  /// why I can't message staff myself. Show it instead of the member-side
  /// "Contact the admins" / "Message coach".
  final String? selfBlockedReason;

  /// One "Contact the admins" thread each: me, and each of my wards here.
  final List<StartFor> contactAdmins;
  final List<CoachOption> coaches;

  bool get isStaff => asStaff != null;
  bool get isAdmin => asStaff?.isAdmin ?? false;

  /// Contact-the-admins entries worth offering: an admin doesn't write to
  /// the admins about themselves (their wards still can be).
  List<StartFor> get adminContacts => [
        for (final c in contactAdmins)
          if (!(c.isMe && isAdmin)) c
      ];

  factory StartOptions.fromJson(Map<String, dynamic> j) => StartOptions(
        group: MessageGroupRef.fromJson(_map(j['group'])),
        asStaff: StaffStartInfo.fromJson(j['asStaff']),
        contactAdmins: [
          for (final c in _maps(j['contactAdmins'])) StartFor.fromJson(c)
        ],
        coaches: [for (final c in _maps(j['coaches'])) CoachOption.fromJson(c)]
            .where((c) => c.userId.isNotEmpty)
            .toList(),
        selfBlockedReason: parseStr(j['selfBlockedReason']),
      );
}

/// Staff: a member I can message (a ward's thread goes to their guardians).
class ReachablePerson {
  const ReachablePerson({
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.isWard = false,
  });
  final String userId;
  final String name;
  final String? avatarUrl;
  final bool isWard;

  factory ReachablePerson.fromJson(Map<String, dynamic> j) => ReachablePerson(
        userId: parseStr(j['userId']) ?? '',
        name: parseStr(j['name']) ?? 'Member',
        avatarUrl: parseStr(j['avatarUrl']),
        isWard: _bool(j['isWard']),
      );
}

// ── Reports ────────────────────────────────────────────────────────────────

/// Report reasons, as the server takes them, with their labels.
const messageReportReasons = <({String value, String label})>[
  (value: 'inappropriate', label: 'Inappropriate'),
  (value: 'harassment', label: 'Harassment or bullying'),
  (value: 'spam', label: 'Spam'),
  (value: 'safeguarding', label: 'Safeguarding concern'),
  (value: 'other', label: 'Something else'),
];

String messageReportReasonLabel(String v) => messageReportReasons
    .firstWhere((r) => r.value == v,
        orElse: () => (value: v, label: 'Something else'))
    .label;

/// A report in a group (admins).
class MessageReport {
  const MessageReport({
    required this.id,
    this.groupId,
    this.groupName,
    this.reporterId,
    this.reporterName,
    this.reason = 'other',
    this.details,
    this.status = 'open',
    this.createdAt,
    this.messageId,
    this.messageBody,
    this.messageSenderName,
    this.messageDeleted = false,
    this.conversationId,
    this.announcementId,
    this.announcementTitle,
    this.discussionId,
    this.discussionTitle,
    this.discussionCommentId,
    this.discussionCommentBody,
  });

  final String id;
  final String? groupId;
  final String? groupName;
  final String? reporterId;
  final String? reporterName;
  final String reason;
  final String? details;

  /// `open` · `reviewed` · `dismissed`.
  final String status;
  final DateTime? createdAt;
  final String? messageId;
  final String? messageBody;
  final String? messageSenderName;
  final bool messageDeleted;
  final String? conversationId;
  final String? announcementId;
  final String? announcementTitle;

  /// A reported discussion, or the discussion of a reported comment.
  final String? discussionId;
  final String? discussionTitle;
  final String? discussionCommentId;
  final String? discussionCommentBody;

  bool get isOpen => status == 'open';
  bool get isAnnouncement => announcementId != null;
  bool get isDiscussion => discussionId != null;
  bool get isDiscussionComment => discussionCommentId != null;
  String get reasonLabel => messageReportReasonLabel(reason);

  factory MessageReport.fromJson(Map<String, dynamic> j) => MessageReport(
        id: parseStr(j['id']) ?? '',
        groupId: parseStr(j['groupId']),
        groupName: parseStr(j['groupName']),
        reporterId: parseStr(j['reporterId']),
        reporterName: parseStr(j['reporterName']),
        reason: parseStr(j['reason']) ?? 'other',
        details: parseStr(j['details']),
        status: parseStr(j['status']) ?? 'open',
        createdAt: parseDate(j['createdAt']),
        messageId: parseStr(j['messageId']),
        messageBody:
            j['messageBody'] is String ? j['messageBody'] as String : null,
        messageSenderName: parseStr(j['messageSenderName']),
        messageDeleted: _bool(j['messageDeleted']),
        conversationId: parseStr(j['conversationId']),
        announcementId: parseStr(j['announcementId']),
        announcementTitle: parseStr(j['announcementTitle']),
        discussionId: parseStr(j['discussionId']),
        discussionTitle: parseStr(j['discussionTitle']),
        discussionCommentId: parseStr(j['discussionCommentId']),
        discussionCommentBody: j['discussionCommentBody'] is String
            ? j['discussionCommentBody'] as String
            : null,
      );
}
