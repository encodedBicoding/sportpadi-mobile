import '../../shared/format/parse.dart';

class EventSummary {
  const EventSummary({
    required this.id,
    required this.title,
    required this.slug,
    this.eventDate,
    this.startTime,
    this.endTime,
    this.locationName,
    this.status,
    this.categoryEmoji,
    this.categoryId,
    this.categoryName,
    this.groupName,
    this.groupImageUrl,
    this.isTournament = false,
    this.isPrivate = false,
    this.interestCount,
    this.coverImage,
    this.description,
    this.distanceMiles,
    this.isLive = false,
    this.groupId,
    this.reasons = const [],
    this.forWards = const [],
    this.audienceTeams = const [],
    this.startsAt,
    this.endsAt,
  });

  final String id;
  final String title;
  final String slug;
  final DateTime? eventDate;
  final String? startTime;
  final String? endTime;
  final String? locationName;
  final String? status;
  final String? categoryEmoji;

  /// Sport category id — lets a screen re-query by sport, not just label it.
  final String? categoryId;
  final String? categoryName;
  final String? groupName;
  final String? groupImageUrl;
  final bool isTournament;
  final bool isPrivate;
  final int? interestCount;
  final String? coverImage;
  final String? description;
  final double? distanceMiles;

  /// A game inside this event is live right now (browse feed flag).
  final bool isLive;

  /// Host group id — needed to route a tournament to its own page.
  final String? groupId;

  /// Why this event was suggested ("You play Soccer", "4 miles away"). Only
  /// populated by the suggestions feed; empty everywhere else.
  final List<String> reasons;

  /// Which of my wards this event is on my feed for ("Ward · Tobi").
  final List<WardTag> forWards;

  /// Team event: the teams it's for (empty = the whole group).
  final List<AudienceTeam> audienceTeams;

  /// The real start / end instants (UTC): the stored venue wall clock
  /// resolved in the venue's zone by the server. What "next up" compares
  /// against the viewer's own clock — wherever they are.
  final DateTime? startsAt;
  final DateTime? endsAt;


  factory EventSummary.fromJson(Map<String, dynamic> j) {
    final cat = j['category'];
    final grp = j['group'];
    return EventSummary(
      id: (j['id'] ?? '') as String,
      title: (j['title'] ?? 'Event') as String,
      slug: (j['slug'] ?? '') as String,
      eventDate: parseDate(j['eventDate']),
      startTime: parseStr(j['startTime']),
      endTime: parseStr(j['endTime']),
      startsAt: DateTime.tryParse(j['startsAt'] as String? ?? '')?.toUtc(),
      endsAt: DateTime.tryParse(j['endsAt'] as String? ?? '')?.toUtc(),
      locationName: parseStr(j['locationName']),
      status: parseStr(j['status']),
      categoryEmoji: cat is Map ? parseStr(cat['emoji']) : null,
      categoryName: cat is Map ? parseStr(cat['name']) : null,
      categoryId: cat is Map ? parseStr(cat['id']) : null,
      groupName: grp is Map ? parseStr(grp['name']) : parseStr(j['groupName']),
      groupImageUrl: grp is Map ? parseStr(grp['imageUrl']) : null,
      isTournament: j['isTournament'] == true,
      isLive: j['isLive'] == true,
      isPrivate: j['isPrivate'] == true,
      interestCount: parseInt(j['interestCount']),
      coverImage: parseStr(j['thumbnailUrl']) ??
          (j['images'] is List && (j['images'] as List).isNotEmpty
              ? parseStr((j['images'] as List).first)
              : null),
      description: parseStr(j['description']),
      distanceMiles: parseDouble(j['distanceMiles']),
      groupId:
          parseStr(j['groupId']) ?? (grp is Map ? parseStr(grp['id']) : null),
      reasons: [
        for (final r
            in (j['reasons'] is List ? j['reasons'] as List : const []))
          if (parseStr(r) != null) parseStr(r)!
      ],
      forWards: [
        for (final w
            in (j['forWards'] is List ? j['forWards'] as List : const []))
          if (w is Map) WardTag.fromJson(Map<String, dynamic>.from(w))
      ],
      audienceTeams: parseAudienceTeams(j['audienceTeams']),
    );
  }
}

/// A team a team event is for: `{ id, name }`.
class AudienceTeam {
  const AudienceTeam({required this.id, required this.name});
  final String id;
  final String name;

  factory AudienceTeam.fromJson(Map<String, dynamic> j) => AudienceTeam(
        id: parseStr(j['id']) ?? '',
        name: parseStr(j['name']) ?? 'Team',
      );
}

/// Tolerant `audienceTeams` parse — anything but a list of maps is "none".
List<AudienceTeam> parseAudienceTeams(dynamic v) => [
      for (final t in (v is List ? v : const []))
        if (t is Map) AudienceTeam.fromJson(Map<String, dynamic>.from(t))
    ].where((t) => t.id.isNotEmpty).toList();

/// "For U12 Lions" / "For U12 Lions, U14 Hawks" — null for whole-group events.
String? audienceLabel(List<AudienceTeam> teams) =>
    teams.isEmpty ? null : 'For ${teams.map((t) => t.name).join(', ')}';

/// A ward a feed event is for: `{ userId, name }` (name is the first name).
class WardTag {
  const WardTag({required this.userId, required this.name});
  final String userId;
  final String name;

  factory WardTag.fromJson(Map<String, dynamic> j) => WardTag(
        userId: parseStr(j['userId']) ?? '',
        name: parseStr(j['name']) ?? 'Ward',
      );
}

/// One of my wards as seen from an event (guardians only): whether they've
/// RSVP'd and whether they're checked in.
class EventWard {
  const EventWard({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.age,
    this.interested = false,
    this.checkedIn = false,
  });
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int? age;
  final bool interested;
  final bool checkedIn;

  String get firstName {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? displayName : parts.first;
  }

  factory EventWard.fromJson(Map<String, dynamic> j) => EventWard(
        userId: parseStr(j['userId']) ?? '',
        displayName: parseStr(j['displayName']) ?? 'Player',
        avatarUrl: parseStr(j['avatarUrl']),
        age: parseInt(j['age']),
        interested: j['interested'] == true,
        checkedIn: j['checkedIn'] == true,
      );
}

class Attendee {
  const Attendee({
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.checkedInAt,
    this.isWard = false,
    this.letInBy,
    this.checkedIn = false,
    this.paying = false,
    this.paid = false,
  });
  final String userId;
  final String displayName;

  /// On the RSVP list: paid the event's ticket — locked in (a no-show is
  /// refunded after the event, never released).
  final bool paid;

  /// On the RSVP list: already checked in (so their spot can't be released).
  final bool checkedIn;

  /// On the RSVP list: the spot is held while they pay (expires by itself).
  final bool paying;

  /// The organiser who let them in (whose QR they scanned, or who checked
  /// them in by hand). Null for older check-ins.
  final String? letInBy;

  /// Null when there's none to show (limited wards come back with "").
  final String? username;
  final String? avatarUrl;
  final DateTime? checkedInAt;

  /// A ward (a player a guardian runs).
  final bool isWard;

  factory Attendee.fromJson(Map<String, dynamic> j) => Attendee(
        userId: (j['userId'] ?? '') as String,
        displayName: (j['displayName'] ?? 'Player') as String,
        username: parseStr(j['username']),
        avatarUrl: parseStr(j['avatarUrl']),
        checkedInAt: parseDate(j['checkedInAt']),
        isWard: j['isWard'] == true,
        letInBy: parseStr(j['letInBy']),
        checkedIn: j['checkedIn'] == true,
        paying: j['paying'] == true,
        paid: j['paid'] == true,
      );
}

/// The event's spots (server `capacity`): a cap on players and whether an
/// RSVP holds a spot. `line` is the server's ready-made "2 of 12 spots left"
/// / "Full" copy so every screen says the same thing.
class EventCapacity {
  const EventCapacity({
    this.maxPlayers,
    this.rsvpPolicy = 'open',
    this.rsvpCount = 0,
    this.checkedInCount = 0,
    this.spotsLeft,
    this.full = false,
    this.line,
    this.pendingHolds = 0,
  });
  final int? maxPlayers;

  /// Spots held while someone pays (counted in [rsvpCount]).
  final int pendingHolds;

  /// 'open' (RSVP = interest) | 'required' (RSVP holds a spot, gates check-in).
  final String rsvpPolicy;
  final int rsvpCount;
  final int checkedInCount;
  final int? spotsLeft;
  final bool full;
  final String? line;

  bool get rsvpRequired => rsvpPolicy == 'required';
  bool get capped => maxPlayers != null;

  /// Anything to say at all (an open, uncapped event shows nothing).
  bool get shows => rsvpRequired || capped;

  static const none = EventCapacity();

  factory EventCapacity.fromJson(Map<String, dynamic> j) => EventCapacity(
        maxPlayers: parseInt(j['maxPlayers']),
        rsvpPolicy: parseStr(j['rsvpPolicy']) ?? 'open',
        rsvpCount: parseInt(j['rsvpCount']) ?? 0,
        checkedInCount: parseInt(j['checkedInCount']) ?? 0,
        spotsLeft: parseInt(j['spotsLeft']),
        full: j['full'] == true,
        line: parseStr(j['line']),
        pendingHolds: parseInt(j['pendingHolds']) ?? 0,
      );
}

class EventDetail {
  const EventDetail({
    required this.id,
    required this.title,
    required this.slug,
    this.groupId,
    this.description,
    this.eventDate,
    this.startTime,
    this.endTime,
    this.locationName,
    this.status,
    this.categoryEmoji,
    this.categoryName,
    this.canManage = false,
    this.isCreator = false,
    this.myCheckedIn = false,
    this.hasEnded,
    this.calendarStart,
    this.calendarEnd,
    this.calendarAllDay = false,
    this.myInterested = false,
    this.interestCount = 0,
    this.attendeeCount = 0,
    this.attendees = const [],
    this.interestedPeople = const [],
    this.images = const [],
    this.thumbnailUrl,
    this.isPrivate = false,
    this.competitiveLevel,
    this.recurrence = 'once',
    this.qrCode,
    this.typicalAttendance,
    this.groupName,
    this.groupImageUrl,
    this.groupVerified = false,
    this.locationLat,
    this.locationLng,
    this.flowType = 'team_match',
    this.maxTeamsPerGame,
    this.isTournament = false,
    this.hasLatePool = false,
    this.canCreateGames = false,
    this.smartShuffle = false,
    this.myWards = const [],
    this.audienceTeams = const [],
    this.capacity = EventCapacity.none,
  });

  final String id;
  final String title;
  final String slug;
  final String? groupId;
  final String? description;
  final DateTime? eventDate;
  final String? startTime;
  final String? endTime;
  final String? locationName;
  final String? status;
  final String? categoryEmoji;
  final String? categoryName;
  final bool canManage;
  /// The caller created this event — the one person who can't scan its QR
  /// to check in (another admin checks them in).
  final bool isCreator;
  final bool myCheckedIn;
  // Server truth: past its end time (or end of its day) in the VENUE's zone.
  final bool? hasEnded;

  /// When it really runs (server `calendar`), for "Add to calendar". Null on
  /// older servers.
  final DateTime? calendarStart;
  final DateTime? calendarEnd;

  /// No start time: a whole-day event (start/end are that UTC date and the next).
  final bool calendarAllDay;
  final bool myInterested;
  final int interestCount;
  final int attendeeCount;
  final List<Attendee> attendees;
  final List<Attendee> interestedPeople;
  final List<String> images;
  final String? thumbnailUrl;
  final bool isPrivate;
  final String? competitiveLevel;
  final String recurrence;
  final String? qrCode;
  final int? typicalAttendance;
  final String? groupName;
  final String? groupImageUrl;

  /// The hosting group carries the gold verification badge.
  final bool groupVerified;
  final double? locationLat;
  final double? locationLng;
  final String flowType; // team_match | attendance
  final int?
      maxTeamsPerGame; // 2 = VS sports (soccer): explicit home/away pickers
  final bool isTournament;
  // Host-group entitlements (web: groups.entitlements) — gate late pool,
  // game creation and smart-shuffle copy.
  final bool hasLatePool;
  final bool canCreateGames;
  final bool smartShuffle;

  /// Guardians only: each of my wards' RSVP / check-in for this event.
  final List<EventWard> myWards;

  /// Team event: the teams it's for (empty = the whole group).
  final List<AudienceTeam> audienceTeams;

  /// Spots: cap + RSVP rule (eventCapacity.ts on the server).
  final EventCapacity capacity;

  bool get isTeamFlow => flowType == 'team_match';
  bool get repeats => recurrence.isNotEmpty && recurrence != 'once';

  factory EventDetail.fromJson(Map<String, dynamic> j) {
    final cat = j['category'];
    final grp = j['group'];
    final rawAtt = j['attendees'];
    return EventDetail(
      id: (j['id'] ?? '') as String,
      title: (j['title'] ?? 'Event') as String,
      slug: (j['slug'] ?? '') as String,
      groupId: parseStr(j['groupId']),
      description: parseStr(j['description']),
      eventDate: parseDate(j['eventDate']),
      startTime: parseStr(j['startTime']),
      endTime: parseStr(j['endTime']),
      locationName: parseStr(j['locationName']),
      status: parseStr(j['status']),
      categoryEmoji: cat is Map ? parseStr(cat['emoji']) : null,
      categoryName: cat is Map ? parseStr(cat['name']) : null,
      canManage: j['canManage'] == true,
      isCreator: j['isCreator'] == true,
      myCheckedIn: j['myCheckedIn'] == true,
      hasEnded: j['hasEnded'] is bool ? j['hasEnded'] as bool : null,
      calendarStart: j['calendar'] is Map
          ? parseDate((j['calendar'] as Map)['startsAt'])
          : null,
      calendarEnd: j['calendar'] is Map
          ? parseDate((j['calendar'] as Map)['endsAt'])
          : null,
      calendarAllDay:
          j['calendar'] is Map && (j['calendar'] as Map)['allDay'] == true,
      myInterested: j['myInterested'] == true,
      interestCount: parseInt(j['interestCount']) ?? 0,
      attendeeCount: parseInt(j['attendeeCount']) ?? 0,
      attendees: rawAtt is List
          ? [
              for (final e in rawAtt)
                Attendee.fromJson(Map<String, dynamic>.from(e as Map))
            ]
          : const [],
      interestedPeople: j['interestedPeople'] is List
          ? [
              for (final e in j['interestedPeople'] as List)
                Attendee.fromJson(Map<String, dynamic>.from(e as Map))
            ]
          : const [],
      images: parseStrList(j['images']),
      thumbnailUrl: parseStr(j['thumbnailUrl']),
      isPrivate: j['isPrivate'] == true,
      competitiveLevel: parseStr(j['competitiveLevel']),
      recurrence: parseStr(j['recurrence']) ?? 'once',
      qrCode: parseStr(j['qrCode']),
      typicalAttendance: parseInt(j['typicalAttendance']),
      capacity: j['capacity'] is Map
          ? EventCapacity.fromJson(Map<String, dynamic>.from(j['capacity'] as Map))
          : EventCapacity.none,
      groupName: grp is Map ? parseStr(grp['name']) : null,
      groupImageUrl: grp is Map ? parseStr(grp['imageUrl']) : null,
      groupVerified: grp is Map &&
          grp['verificationBadge'] is String &&
          (grp['verificationBadge'] as String).isNotEmpty &&
          grp['verificationBadge'] != 'none',
      locationLat: parseDouble(j['locationLat']),
      locationLng: parseDouble(j['locationLng']),
      flowType: (cat is Map ? parseStr(cat['flowType']) : null) ?? 'team_match',
      maxTeamsPerGame: cat is Map ? parseInt(cat['maxTeamsPerGame']) : null,
      isTournament: j['isTournament'] == true,
      hasLatePool: j['features'] is Map &&
          (j['features'] as Map)['LATE_POOL_ENTRY'] == true,
      canCreateGames: j['features'] is Map &&
          (j['features'] as Map)['LOCAL_GAME_STATS'] == true,
      smartShuffle: j['features'] is Map &&
          (j['features'] as Map)['SMART_TEAM_SHUFFLE'] == true,
      myWards: [
        for (final w
            in (j['myWards'] is List ? j['myWards'] as List : const []))
          if (w is Map) EventWard.fromJson(Map<String, dynamic>.from(w))
      ],
      audienceTeams: parseAudienceTeams(j['audienceTeams']),
    );
  }
}

/// A team generated for an event (random/smart shuffle), with its players.
class EventTeam {
  const EventTeam({
    required this.id,
    required this.name,
    this.color,
    this.players = const [],
  });
  final String id;
  final String name;
  final String? color;
  final List<EventTeamPlayer> players;

  factory EventTeam.fromJson(Map<String, dynamic> j) => EventTeam(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? 'Team') as String,
        color: parseStr(j['color']),
        players: j['players'] is List
            ? [
                for (final p in j['players'] as List)
                  EventTeamPlayer.fromJson(Map<String, dynamic>.from(p as Map))
              ]
            : const [],
      );
}

class EventTeamPlayer {
  const EventTeamPlayer({
    required this.userId,
    required this.displayName,
    this.isSub = false,
    this.avatarUrl,
  });
  final String userId;
  final String displayName;
  final bool isSub;
  final String? avatarUrl;

  factory EventTeamPlayer.fromJson(Map<String, dynamic> j) => EventTeamPlayer(
        userId: (j['userId'] ?? '') as String,
        displayName: (j['displayName'] ?? 'Player') as String,
        isSub: j['isSub'] == true,
        avatarUrl: parseStr(j['avatarUrl']),
      );
}

/// A checked-in player waiting in the late-arrival pool.
class PoolPlayer {
  const PoolPlayer({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.checkedInAt,
    this.positions = const [],
  });
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final DateTime? checkedInAt;
  final List<String> positions;

  factory PoolPlayer.fromJson(Map<String, dynamic> j) => PoolPlayer(
        userId: (j['userId'] ?? '') as String,
        displayName: (j['displayName'] ?? 'Player') as String,
        avatarUrl: parseStr(j['avatarUrl']),
        checkedInAt: parseDate(j['checkedInAt']),
        positions: parseStrList(j['positions']),
      );
}

/// An event's reminder schedule (`?view=reminders`): the slots in effect
/// (`d5` `d3` `d2` `d1` `h2`, farthest first; empty = none), their labels,
/// and whether the signed-in viewer muted this event's reminders.
class EventReminders {
  const EventReminders({
    this.slots = const [],
    this.labels = const [],
    this.isDefault = true,
    this.defaultSlots = const ['d2', 'h2'],
    this.muted = false,
  });
  final List<String> slots;
  final List<String> labels;
  final bool isDefault;
  final List<String> defaultSlots;
  final bool muted;

  factory EventReminders.fromJson(Map<String, dynamic> j) => EventReminders(
        slots: parseStrList(j['slots']),
        labels: parseStrList(j['labels']),
        isDefault: j['isDefault'] != false,
        defaultSlots: j['defaultSlots'] is List
            ? parseStrList(j['defaultSlots'])
            : const ['d2', 'h2'],
        muted: j['muted'] == true,
      );
}
