import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Everything waiting on me, in one call (`GET /api/mobile/attention`): the
/// dot on the side-menu button and the badges on the menu's rows. Decodes
/// defensively — anything missing is 0.

Map<String, dynamic> _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

int _n(dynamic v) {
  final n = parseInt(v) ?? 0;
  return n < 0 ? 0 : n;
}

/// The Inbox: unseen announcements (and how many are urgent) and
/// conversations with unread messages.
class AttentionInbox {
  const AttentionInbox({
    this.announcements = 0,
    this.urgent = 0,
    this.messages = 0,
    this.total = 0,
  });
  final int announcements;
  final int urgent;
  final int messages;
  final int total;

  factory AttentionInbox.fromJson(Map<String, dynamic> j) {
    final announcements = _n(j['announcements']);
    final messages = _n(j['messages']);
    return AttentionInbox(
      announcements: announcements,
      urgent: _n(j['urgent']),
      messages: messages,
      total: parseInt(j['total']) ?? announcements + messages,
    );
  }
}

/// Tournaments: invites to groups I admin and squad call-ups for me.
class AttentionTournaments {
  const AttentionTournaments({
    this.invites = 0,
    this.callUps = 0,
    this.total = 0,
  });
  final int invites;
  final int callUps;
  final int total;

  factory AttentionTournaments.fromJson(Map<String, dynamic> j) {
    final invites = _n(j['invites']);
    final callUps = _n(j['callUps']);
    return AttentionTournaments(
      invites: invites,
      callUps: callUps,
      total: parseInt(j['total']) ?? invites + callUps,
    );
  }
}

class AttentionSummary {
  const AttentionSummary({
    this.inbox = const AttentionInbox(),
    this.notifications = 0,
    this.discussions = 0,
    this.fines = 0,
    this.tournaments = const AttentionTournaments(),
    this.total = 0,
  });
  final AttentionInbox inbox;

  /// Unread bell notifications.
  final int notifications;

  /// Discussions with new activity.
  final int discussions;

  /// Active (unpaid) fines — mine and my wards'.
  final int fines;
  final AttentionTournaments tournaments;

  /// Everything above, summed.
  final int total;

  /// An urgent announcement is waiting: the menu's dot goes red.
  bool get urgent => inbox.urgent > 0;

  static const none = AttentionSummary();

  factory AttentionSummary.fromJson(Map<String, dynamic> j) {
    final inbox = AttentionInbox.fromJson(_map(j['inbox']));
    final notifications = _n(j['notifications']);
    final discussions = _n(j['discussions']);
    final fines = _n(j['fines']);
    final tournaments = AttentionTournaments.fromJson(_map(j['tournaments']));
    return AttentionSummary(
      inbox: inbox,
      notifications: notifications,
      discussions: discussions,
      fines: fines,
      tournaments: tournaments,
      total: parseInt(j['total']) ??
          inbox.total + notifications + discussions + fines + tournaments.total,
    );
  }
}
