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
  });
  final String userId;
  final String displayName;
  final String? username;
  final String? avatarUrl;

  factory SimpleUser.fromJson(Map<String, dynamic> j) => SimpleUser(
        userId: (j['userId'] ?? j['id'] ?? '') as String,
        displayName: (j['displayName'] ?? 'Member') as String,
        username: parseStr(j['username']),
        avatarUrl: parseStr(j['avatarUrl']),
      );
}

class TournamentInvite {
  const TournamentInvite({
    required this.id,
    required this.eventTitle,
    this.hostGroupName,
    this.hostTeamName,
    this.guestTeamName,
    this.feeLabel,
    this.feeStatus,
  });
  final String id;
  final String eventTitle;
  final String? hostGroupName;
  final String? hostTeamName;
  final String? guestTeamName;
  final String? feeLabel;
  final String? feeStatus;

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
    return TournamentInvite(
      id: (j['id'] ?? '') as String,
      eventTitle: (j['eventTitle'] ?? 'Tournament') as String,
      hostGroupName: parseStr(j['hostGroupName']),
      hostTeamName: host is Map ? parseStr(host['name']) : null,
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
