import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/links/link_resolver.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/notifications/notification_models.dart';
import 'package:sportpadi_mobile/data/notifications/notifications_repository.dart';
import 'package:sportpadi_mobile/features/notifications/notification_permission_sheet.dart';
import 'package:sportpadi_mobile/features/settings/timezone_provider.dart';
import 'package:sportpadi_mobile/features/shell/notification_target.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';

/// `notifications.type = 'announcement'` is SportPadi's own platform news
/// (owner broadcasts). Group announcements live in the Inbox; these must
/// never be called "Announcement" here (docs/design/wards-and-messaging.md B2).
bool isSportPadiNews(AppNotification n) => n.type == 'announcement';

/// The small kind label shown beside the time, when a kind has one.
String? notificationKindLabel(AppNotification n) =>
    isSportPadiNews(n) ? 'SportPadi news' : null;

/// How a notification looks in the list: an icon and its tile colours,
/// picked from its type and title. Unknown kinds get a quiet bell.
({IconData icon, Color bg, Color fg}) notificationLook(
    AppPalette p, AppNotification n) {
  // Platform news first: its title can say anything ("New events near
  // you"…), and the keyword rules below would dress it up as something else.
  if (isSportPadiNews(n)) {
    return (icon: Icons.newspaper_rounded, bg: p.hero, fg: p.onHero);
  }
  // Comments and replies on discussions.
  if (n.type == 'discussion') {
    return (icon: Icons.forum_outlined, bg: p.accentTint, fg: p.greenText);
  }
  // Event reminders, "Are you coming?" nudges and their digest: the event's
  // own title can say anything ("Kick-off…", "Team training"), so the type
  // decides — the calendar look.
  if (n.type == 'event_reminder') {
    return (icon: Icons.calendar_today_outlined, bg: p.surface2, fg: p.muted);
  }
  final k = '${n.type} ${n.title}'.toLowerCase();
  bool has(List<String> words) => words.any(k.contains);
  if (has(['achievement', 'unlocked', 'badge', 'xp', 'level', 'streak', 'quest'])) {
    return (icon: Icons.star_rounded, bg: p.hero, fg: const Color(0xFF6EDC9E));
  }
  if (has(['tournament', 'league', 'invite', 'call-up', 'call up', 'squad', 'fixture'])) {
    return (icon: Icons.emoji_events_outlined, bg: p.orangeTint, fg: p.orangeInk);
  }
  if (has(['officiant', 'officiat', 'called in', 'timekeeper', 'referee', 'scorer'])) {
    return (icon: Icons.timer_outlined, bg: p.accentTint, fg: p.greenText);
  }
  if (has(['fine', 'penalty'])) {
    return (icon: Icons.error_outline_rounded, bg: p.orangeTint, fg: p.orangeInk);
  }
  if (has(['refund', 'failed', 'cancel', 'abandon', 'void'])) {
    return (icon: Icons.event_busy_outlined, bg: p.liveTint, fg: p.danger);
  }
  if (has(['wallet', 'withdraw', 'payout', 'topup', 'top-up', 'clearing', 'onboarding'])) {
    return (icon: Icons.account_balance_wallet_outlined, bg: p.surface2, fg: p.muted);
  }
  if (has(['ticket', 'paid', 'payment', 'receipt', 'purchase'])) {
    return (icon: Icons.confirmation_num_outlined, bg: p.surface2, fg: p.muted);
  }
  if (has(['goal', 'match', 'game', 'score', 'result', 'full time', 'kick'])) {
    return (icon: Icons.sports_soccer_rounded, bg: p.accentTint, fg: p.greenText);
  }
  if (has(['check', 'rsvp'])) {
    return (icon: Icons.how_to_reg_outlined, bg: p.accentTint, fg: p.greenText);
  }
  if (has(['group', 'member', 'follow', 'team', 'join'])) {
    return (icon: Icons.groups_outlined, bg: p.surface2, fg: p.muted);
  }
  if (has(['event'])) {
    return (icon: Icons.calendar_today_outlined, bg: p.surface2, fg: p.muted);
  }
  return (icon: Icons.notifications_none_rounded, bg: p.surface2, fg: p.muted);
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  /// Where a notification's web URL lands in the app. Null = nowhere sensible
  /// to go (the tap still marks it read).
  ///
  /// Thin wrapper over the shared resolver in core/links: deep links opened
  /// from outside the app go through the same function, and when these were
  /// two separate copies one of them always ended up a few routes behind.
  static String? resolveUrl(String? url) => resolveLinkRoute(url);

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _unreadOnly = false;

  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      // Best-effort; navigation must not wait on it.
      // ignore: unawaited_futures
      ref.read(notificationsRepositoryProvider).markRead([n.id]).then((_) {
        ref.invalidate(notificationsFeedProvider);
        ref.invalidate(unreadCountProvider);
      });
    }
    // Always open the full, scrollable message first; its "Open" button
    // takes the user to the destination when there is one. (Jumping
    // straight to the destination meant long messages could never be read.)
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NotificationDetailScreen(notification: n),
    ));
  }

  Future<void> _markAll() async {
    await ref.read(notificationsRepositoryProvider).markAllRead();
    ref.invalidate(notificationsFeedProvider);
    ref.invalidate(unreadCountProvider);
  }

  /// Today / Yesterday / This week / Earlier, on the viewer's own clock.
  static String _bucket(DateTime? at, DateTime now) {
    if (at == null) return 'Earlier';
    // Whole calendar days between the two, on the viewer's calendar (UTC
    // midnights, so a DST change can't shave an hour off a day).
    final diff = DateTime.parse('${dayKey(now)}T00:00:00Z')
        .difference(DateTime.parse('${dayKey(at)}T00:00:00Z'))
        .inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    return 'Earlier';
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(notificationsFeedProvider);
    ref.watch(viewerTimezoneProvider); // repaint stamps on a zone change
    final p = context.palette;
    final items = feed.valueOrNull?.items ?? const <AppNotification>[];
    final unread = items.where((n) => !n.read).length;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(
              title: 'Notifications',
              subtitle: unread > 0 ? '$unread unread' : null,
              actions: [
                if (unread > 0)
                  TextButton(
                    onPressed: _markAll,
                    style: TextButton.styleFrom(
                        foregroundColor: p.greenText,
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    child: const Text('Mark all read'),
                  ),
              ],
            ),
          ),
          const NotificationsOffBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: SpSegmented(
              options: ['All', unread > 0 ? 'Unread · $unread' : 'Unread'],
              index: _unreadOnly ? 1 : 0,
              onChanged: (i) => setState(() => _unreadOnly = i == 1),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(unreadCountProvider);
                return ref.refresh(notificationsFeedProvider.future);
              },
              child: AsyncView(
                value: feed,
                onRetry: () => ref.invalidate(notificationsFeedProvider),
                data: (f) {
                  final list = _unreadOnly
                      ? f.items.where((n) => !n.read).toList()
                      : f.items;
                  if (list.isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
                      children: [
                        Center(
                          child: SpIconTile(
                              _unreadOnly
                                  ? Icons.done_all_rounded
                                  : Icons.notifications_none_rounded,
                              size: 60,
                              iconSize: 28),
                        ),
                        const SizedBox(height: 14),
                        Text(
                            _unreadOnly
                                ? 'You\'re all caught up'
                                : 'No notifications yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                            _unreadOnly
                                ? 'Nothing new since you last looked.'
                                : 'Game reminders, invites and results will show up here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.muted, fontSize: 13)),
                      ],
                    );
                  }
                  // Group into day buckets, keeping the feed's order.
                  final groups = <String, List<AppNotification>>{};
                  final now = DateTime.now();
                  for (final n in list) {
                    groups
                        .putIfAbsent(_bucket(n.createdAt, now), () => [])
                        .add(n);
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      for (final g in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
                          child: Eyebrow(g.key),
                        ),
                        SpListCard(children: [
                          for (final n in g.value) _row(p, n),
                        ]),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _row(AppPalette p, AppNotification n) {
    final look = notificationLook(p, n);
    final preview = (n.fullBody ?? n.body ?? '').trim();
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _open(n),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 13, 10, 13),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SpIconTile(look.icon, bg: look.bg, fg: look.fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: n.read ? FontWeight.w600 : FontWeight.w700)),
                if (preview.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.muted, fontSize: 12.5, height: 1.45)),
                  ),
                const SizedBox(height: 4),
                Text(
                    [
                      if (notificationKindLabel(n) != null)
                        notificationKindLabel(n)!,
                      fmtRelative(n.createdAt),
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: n.read ? Colors.transparent : p.orange,
              shape: BoxShape.circle,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Full notification: title, time, the complete message (scrollable), and an
/// "Open" action when the notification points somewhere.
class NotificationDetailScreen extends ConsumerWidget {
  const NotificationDetailScreen({super.key, required this.notification});
  final AppNotification notification;

  /// Does this notification point anywhere we can open — an app screen, a
  /// tab, one of our web-only pages, or another site?
  static bool hasDestination(String? url) {
    final raw = url?.trim() ?? '';
    if (raw.isEmpty) return false;
    final t = resolveLink(raw);
    if (t.route != null || t.tab != null || t.web) return true;
    final host = raw.startsWith('http') ? Uri.tryParse(raw)?.host ?? '' : '';
    return host.isNotEmpty && !host.endsWith('sportpadi.com');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    ref.watch(viewerTimezoneProvider); // repaint stamps on a zone change
    final n = notification;
    final canOpen = hasDestination(n.url);
    final text = n.fullBody ?? n.body ?? '';
    final look = notificationLook(p, n);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                SpHeader(
                    title: isSportPadiNews(n) ? 'SportPadi news' : 'Notification'),
                const SizedBox(height: 18),
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        SpIconTile(look.icon,
                            bg: look.bg, fg: look.fg, size: 48, iconSize: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            n.createdAt != null
                                ? '${timeAgo(n.createdAt)} · ${fmtInstant(n.createdAt, style: InstantStyle.full)}'
                                : '',
                            style: TextStyle(color: p.muted, fontSize: 12.5),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      Text(n.title,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1.3)),
                      const SizedBox(height: 12),
                      if (text.isNotEmpty)
                        SelectableText(text,
                            style: TextStyle(
                                color: p.ink, fontSize: 15, height: 1.6))
                      else
                        Text('No further details.',
                            style: TextStyle(color: p.muted, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (canOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              // Same rules as tapping the push itself: its screen, its tab,
              // or the browser for a web-only / external page. SpButton, not
              // FilledButton.icon (semantics assertion — see SpButton).
              child: SpButton(
                label: 'Open',
                icon: Icons.north_east_rounded,
                expand: true,
                onTap: () => openNotificationTarget(ref, n.url),
              ),
            ),
        ]),
      ),
    );
  }
}
