import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/notifications/notification_models.dart';
import 'package:sportpadi_mobile/data/notifications/notifications_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  /// Notification `url`s are web paths — translate to the closest mobile
  /// route. Null = nowhere sensible to go (the tap still marks it read).
  static String? resolveUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final path = url.startsWith('http') ? Uri.tryParse(url)?.path ?? url : url;
    RegExpMatch? m;
    // Group money pages → the native wallet/tickets screens.
    m = RegExp(r'^/groups/([^/]+)/wallet(/approvals)?').firstMatch(path);
    if (m != null) return '/groups/${m.group(1)}/wallet';
    m = RegExp(r'^/groups/([^/]+)/tickets').firstMatch(path);
    if (m != null) return '/groups/${m.group(1)}/tickets';
    // Anything else group-scoped → the group page.
    m = RegExp(r'^/groups/([^/]+)').firstMatch(path);
    if (m != null) return '/groups/${m.group(1)}';
    // A single receipt → My purchases (the QR sheet lives there).
    if (path.startsWith('/tickets')) return '/tickets';
    if (path.startsWith('/fines')) return '/fines';
    m = RegExp(r'^/events/([^/]+)').firstMatch(path);
    if (m != null) return '/events/${m.group(1)}';
    if (path.startsWith('/my-qr')) return '/my-qr';
    return null;
  }

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
    final dest = resolveUrl(n.url);
    if (dest != null) {
      if (context.mounted) context.push(dest);
    } else if (n.body != null && n.body!.isNotEmpty) {
      // No destination — show the FULL message in a scrollable sheet, so
      // long announcements are never cut off.
      if (!context.mounted) return;
      final p = context.palette;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: p.bg,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (ctx) => SafeArea(
          child: Container(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: p.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(n.title,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(timeAgo(n.createdAt),
                    style: TextStyle(color: p.muted, fontSize: 12)),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(n.body!,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14.5,
                            height: 1.55)),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: p.accent,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(notificationsFeedProvider);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
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
      body: RefreshIndicator(
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
                            if (n.body != null && n.body!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(n.body!,
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
                      if (resolveUrl(n.url) != null)
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
    );
  }
}
