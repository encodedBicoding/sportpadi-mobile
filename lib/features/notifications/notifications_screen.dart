import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/links/link_resolver.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/notifications/notification_models.dart';
import 'package:sportpadi_mobile/data/notifications/notifications_repository.dart';
import 'package:sportpadi_mobile/features/notifications/notification_permission_sheet.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  /// Where a notification's web URL lands in the app. Null = nowhere sensible
  /// to go (the tap still marks it read).
  ///
  /// Thin wrapper over the shared resolver in core/links: deep links opened
  /// from outside the app go through the same function, and when these were
  /// two separate copies one of them always ended up a few routes behind.
  static String? resolveUrl(String? url) => resolveLinkRoute(url);

  Future<void> _open(
      BuildContext context, WidgetRef ref, AppNotification n) async {
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
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NotificationDetailScreen(notification: n),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(notificationsFeedProvider);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(notificationsRepositoryProvider).markAllRead();
              ref.invalidate(notificationsFeedProvider);
              ref.invalidate(unreadCountProvider);
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: Column(children: [
        const NotificationsOffBanner(),
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
            if (f.items.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 140),
                Center(child: Text('No notifications yet.')),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: f.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final n = f.items[i];
                return GlassCard(
                  padding: const EdgeInsets.all(12),
                  onTap: () => _open(context, ref, n),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 5, right: 10),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: n.read ? Colors.transparent : p.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                            if ((n.fullBody ?? n.body) != null &&
                                (n.fullBody ?? n.body)!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text((n.fullBody ?? n.body)!,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.muted, fontSize: 13)),
                              ),
                            const SizedBox(height: 4),
                            Text(timeAgo(n.createdAt),
                                style: TextStyle(color: p.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: p.muted),
                    ],
                  ),
                );
              },
            );
          },
        ),
          ),
        ),
      ]),
    );
  }
}

/// Full notification: title, time, the complete message (scrollable), and an
/// "Open" action when the notification points somewhere.
class NotificationDetailScreen extends StatelessWidget {
  const NotificationDetailScreen({super.key, required this.notification});
  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = notification;
    final dest = NotificationsScreen.resolveUrl(n.url);
    final text = n.fullBody ?? n.body ?? '';
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Notification',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          height: 1.3)),
                  const SizedBox(height: 4),
                  Text(
                    n.createdAt != null
                        ? '${timeAgo(n.createdAt)} · ${formatDayYear(n.createdAt)}'
                        : '',
                    style: TextStyle(color: p.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  if (text.isNotEmpty)
                    SelectableText(text,
                        style: TextStyle(
                            color: p.ink, fontSize: 15, height: 1.55))
                  else
                    Text('No further details.',
                        style: TextStyle(color: p.muted, fontSize: 13)),
                ],
              ),
            ),
          ),
          if (dest != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.push(dest),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open'),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
