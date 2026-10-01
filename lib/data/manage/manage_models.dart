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
  });
  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;

  /// A ward (no login): adding them to a team invites their guardians.
  final bool isWard;

  /// A team invitation for this ward is already waiting on a guardian.
  final bool invitePending;

  factory SimpleUser.fromJson(Map<String, dynamic> j) => SimpleUser(
        userId: (j['userId'] ?? j['id'] ?? '') as String,
        displayName: (j['displayName'] ?? 'Member') as String,
        username: parseStr(j['username']),
        avatarUrl: parseStr(j['avatarUrl']),
        isWard: j['isWard'] == true,
        invitePending: j['invitePending'] == true,
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
