import '../../shared/format/parse.dart';

class TournamentSummary {
  const TournamentSummary({
    required this.eventId,
    required this.title,
    this.slug,
    this.eventDate,
    this.status,
    this.categoryEmoji,
    this.categoryName,
    this.isHost = false,
    this.hostTeamName,
    this.guestTeamName,
    this.guestStatus,
    this.hostTeamLogo,
    this.hostKitPrimary,
    this.guestTeamLogo,
    this.guestKitPrimary,
  });

  final String eventId;
  final String title;
  final String? slug;
  final DateTime? eventDate;
  final String? status;
  final String? categoryEmoji;
  final String? categoryName;
  final bool isHost;
  final String? hostTeamName;
  final String? guestTeamName;
  final String? guestStatus;
  final String? hostTeamLogo;
  final String? hostKitPrimary;
  final String? guestTeamLogo;
  final String? guestKitPrimary;

  factory TournamentSummary.fromJson(Map<String, dynamic> j) {
    final cat = j['category'];
    final host = j['hostTeam'];
    final guest = j['guestTeam'];
    return TournamentSummary(
      eventId: (j['eventId'] ?? '') as String,
      title: (j['title'] ?? 'Tournament') as String,
      slug: parseStr(j['slug']),
      eventDate: parseDate(j['eventDate']),
      status: parseStr(j['status']),
      categoryEmoji: cat is Map ? parseStr(cat['emoji']) : null,
      categoryName: cat is Map ? parseStr(cat['name']) : null,
      isHost: j['isHost'] == true,
      hostTeamName: host is Map ? parseStr(host['name']) : null,
      guestTeamName: guest is Map ? parseStr(guest['name']) : null,
      guestStatus: parseStr(j['guestStatus']),
      hostTeamLogo: host is Map ? parseStr(host['logoUrl']) : null,
      hostKitPrimary: host is Map ? parseStr(host['kitPrimary']) : null,
      guestTeamLogo: guest is Map ? parseStr(guest['logoUrl']) : null,
      guestKitPrimary: guest is Map ? parseStr(guest['kitPrimary']) : null,
    );
  }
}
