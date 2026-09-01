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
      locationName: parseStr(j['locationName']),
      status: parseStr(j['status']),
      categoryEmoji: cat is Map ? parseStr(cat['emoji']) : null,
      categoryName: cat is Map ? parseStr(cat['name']) : null,
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
    );
  }
}

class Attendee {
  const Attendee({
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.checkedInAt,
  });
  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final DateTime? checkedInAt;

  factory Attendee.fromJson(Map<String, dynamic> j) => Attendee(
        userId: (j['userId'] ?? '') as String,
        displayName: (j['displayName'] ?? 'Player') as String,
        username: parseStr(j['username']),
        avatarUrl: parseStr(j['avatarUrl']),
        checkedInAt: parseDate(j['checkedInAt']),
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
    this.myCheckedIn = false,
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
    this.locationLat,
    this.locationLng,
    this.flowType = 'team_match',
    this.isTournament = false,
    this.hasLatePool = false,
    this.canCreateGames = false,
    this.smartShuffle = false,
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
  final bool myCheckedIn;
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
  final double? locationLat;
  final double? locationLng;
  final String flowType; // team_match | attendance
  final bool isTournament;
  // Host-group entitlements (web: groups.entitlements) — gate late pool,
  // game creation and smart-shuffle copy.
  final bool hasLatePool;
  final bool canCreateGames;
  final bool smartShuffle;

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
      myCheckedIn: j['myCheckedIn'] == true,
      myInterested: j['myInterested'] == true,
      interestCount: parseInt(j['interestCount']) ?? 0,
      attendeeCount: parseInt(j['attendeeCount']) ?? 0,
      attendees: rawAtt is List
          ? [for (final e in rawAtt) Attendee.fromJson(Map<String, dynamic>.from(e as Map))]
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
      groupName: grp is Map ? parseStr(grp['name']) : null,
      groupImageUrl: grp is Map ? parseStr(grp['imageUrl']) : null,
      locationLat: parseDouble(j['locationLat']),
      locationLng: parseDouble(j['locationLng']),
      flowType: (cat is Map ? parseStr(cat['flowType']) : null) ?? 'team_match',
      isTournament: j['isTournament'] == true,
      hasLatePool: j['features'] is Map &&
          (j['features'] as Map)['LATE_POOL_ENTRY'] == true,
      canCreateGames: j['features'] is Map &&
          (j['features'] as Map)['LOCAL_GAME_STATS'] == true,
      smartShuffle: j['features'] is Map &&
          (j['features'] as Map)['SMART_TEAM_SHUFFLE'] == true,
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
