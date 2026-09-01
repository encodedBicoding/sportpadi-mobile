import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/notifications/notifications_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

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
                                    style: TextStyle(
                                        color: p.muted, fontSize: 13)),
                              ),
                            const SizedBox(height: 4),
                            Text(timeAgo(n.createdAt),
                                style: TextStyle(color: p.muted, fontSize: 11)),
                          ],
                        ),
                      ),
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
