import '../../shared/format/parse.dart';

class Category {
  const Category({required this.id, required this.name, this.emoji});
  final String id;
  final String name;
  final String? emoji;

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        emoji: parseStr(j['emoji']),
      );
}

class SimpleUser {
  const SimpleUser({
    required this.userId,
    required this.displayName,
    this.username,
    this.avatarUrl,
    this.isWard = false,
    this.invitePending = false,
    this.age,
    this.overAgeLimit = false,
  });
  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;

  /// A ward (no login): adding them to a team invites their guardians.
  final bool isWard;

  /// A team invitation for this ward is already waiting on a guardian.
  final bool invitePending;

  /// Under-18s only (from their date of birth) — adults' ages aren't sent.
  final int? age;

  /// On a kids team with an age group: this child is at or over the limit.
  /// A flag for the admin, not a block.
  final bool overAgeLimit;

  factory SimpleUser.fromJson(Map<String, dynamic> j) => SimpleUser(
        userId: (j['userId'] ?? j['id'] ?? '') as String,
        displayName: (j['displayName'] ?? 'Member') as String,
        username: parseStr(j['username']),
        avatarUrl: parseStr(j['avatarUrl']),
        isWard: j['isWard'] == true,
        invitePending: j['invitePending'] == true,
        age: parseInt(j['age']),
        overAgeLimit: j['overAgeLimit'] == true,
      );
}

class TournamentInvite {
  const TournamentInvite({
    required this.id,
    required this.eventTitle,
    this.eventId,
    this.hostGroupId,
    this.eventDate,
    this.categoryLabel,
    this.hostGroupName,
    this.hostTeamName,
    this.guestTeamId,
    this.guestTeamName,
    this.feeLabel,
    this.feeStatus,
  });
  final String id;
  final String eventTitle;

  /// The tournament this invite is for — with [hostGroupId], the address of
  /// its page (/groups/:hostGroupId/tournaments/:eventId).
  final String? eventId;
  final String? hostGroupId;
  final DateTime? eventDate;
  final String? categoryLabel;
  final String? hostGroupName;
  final String? hostTeamName;

  /// The invited team. With [hostGroupId] and [eventId] this addresses the
  /// squad page accepting should drop the admin on.
  final String? guestTeamId;
  final String? guestTeamName;
  final String? feeLabel;
  final String? feeStatus;

  bool get owesFee => feeLabel != null && feeStatus != 'paid';

  /// This team's tournament-scoped squad page, when we know where it lives.
  String? get squadRoute =>
      (hostGroupId != null && eventId != null && guestTeamId != null)
          ? '/groups/$hostGroupId/tournaments/$eventId/teams/$guestTeamId'
          : null;

  factory TournamentInvite.fromJson(Map<String, dynamic> j) {
    final host = j['hostTeam'];
    final guest = j['guestTeam'];
    final minor = parseInt(j['feeMinor']);
    final currency = parseStr(j['feeCurrency']);
    final exp = parseInt(j['feeCurrencyExponent']);
    String? fee;
    if (minor != null && minor > 0 && currency != null && exp != null) {
      var div = 1;
      for (var i = 0; i < exp; i++) {
        div *= 10;
      }
      final major = minor / div;
      fee = '$currency ${major.toStringAsFixed(exp)}';
    }
    final cat = j['category'];
    return TournamentInvite(
      id: (j['id'] ?? '') as String,
      eventTitle: (j['eventTitle'] ?? 'Tournament') as String,
      eventId: parseStr(j['eventId']),
      hostGroupId: parseStr(j['hostGroupId']),
      eventDate: parseDate(j['eventDate']),
      categoryLabel: cat is Map
          ? '${cat['emoji'] ?? ''} ${cat['name'] ?? ''}'.trim()
          : null,
      hostGroupName: parseStr(j['hostGroupName']),
      hostTeamName: host is Map ? parseStr(host['name']) : null,
      guestTeamId: guest is Map ? parseStr(guest['id']) : null,
      guestTeamName: guest is Map ? parseStr(guest['name']) : null,
      feeLabel: fee,
      feeStatus: parseStr(j['feeStatus']),
    );
  }
}

class WalletStatus {
  const WalletStatus({this.status, this.currency, this.currencyExponent});
  final String? status;
  final String? currency;
  final int? currencyExponent;

  bool get active => status == 'active';
  int get exponent => currencyExponent ?? 2;

  factory WalletStatus.fromJson(Map<String, dynamic> j) => WalletStatus(
        status: parseStr(j['status']),
        currency: parseStr(j['currency']),
        currencyExponent: parseInt(j['currencyExponent']),
      );
}

/// Someone an organiser can check in by hand (events.checkInCandidates):
/// other organisers first, then RSVPs, then matching members. [isMe] is the
/// caller — organisers never check themselves in.
class CheckInCandidate {
  const CheckInCandidate({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.isWard = false,
    this.isOrganiser = false,
    this.isMe = false,
    this.isCreator = false,
    this.rsvp = false,
    this.checkedIn = false,
  });
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool isWard;
  final bool isOrganiser;
  final bool isMe;
  final bool isCreator;
  final bool rsvp;
  final bool checkedIn;

  CheckInCandidate copyWith({bool? checkedIn}) => CheckInCandidate(
        userId: userId,
        displayName: displayName,
        avatarUrl: avatarUrl,
        isWard: isWard,
        isOrganiser: isOrganiser,
        isMe: isMe,
        isCreator: isCreator,
        rsvp: rsvp,
        checkedIn: checkedIn ?? this.checkedIn,
      );

  factory CheckInCandidate.fromJson(Map<String, dynamic> j) => CheckInCandidate(
        userId: (j['userId'] ?? '') as String,
        displayName: parseStr(j['displayName']) ?? 'Player',
        avatarUrl: parseStr(j['avatarUrl']),
        isWard: j['isWard'] == true,
        isOrganiser: j['isOrganiser'] == true,
        isMe: j['isMe'] == true,
        isCreator: j['isCreator'] == true,
        rsvp: j['rsvp'] == true,
        checkedIn: j['checkedIn'] == true,
      );
}
