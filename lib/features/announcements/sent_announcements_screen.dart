import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcement_models.dart';
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart';
import 'package:sportpadi_mobile/features/inbox/announcement_card.dart';
import 'package:sportpadi_mobile/features/settings/timezone_provider.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Announcements sent in a group (staff): admins see all of them, coaches
/// and organisers their own — each with how many have seen it and tapped
/// "Got it". Tap one for the full receipts.
class SentAnnouncementsScreen extends ConsumerWidget {
  const SentAnnouncementsScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    ref.watch(viewerTimezoneProvider); // repaint stamps on a zone change
    final sent = ref.watch(sentAnnouncementsProvider(groupId));
    final composer = ref.watch(announcementComposerProvider(groupId)).valueOrNull;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(
              title: 'Sent announcements',
              subtitle: composer?.groupName,
              actions: [
                if (composer != null)
                  SpRoundButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'New announcement',
                    onTap: () =>
                        context.push('/groups/$groupId/announcements/new'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async =>
                  ref.refresh(sentAnnouncementsProvider(groupId).future),
              child: AsyncView<SentPage>(
                value: sent,
                onRetry: () =>
                    ref.invalidate(sentAnnouncementsProvider(groupId)),
                data: (page) {
                  if (page.items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
                      children: [
                        const Center(
                          child: SpIconTile(Icons.outbox_outlined,
                              size: 60, iconSize: 28),
                        ),
                        const SizedBox(height: 14),
                        Text('Nothing sent yet',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                            'Announcements you send to this group will '
                            'show here, with who has seen them.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.muted, fontSize: 13)),
                        if (composer != null) ...[
                          const SizedBox(height: 18),
                          Center(
                            child: SpButton(
                              label: 'New announcement',
                              icon: Icons.campaign_outlined,
                              onTap: () => context
                                  .push('/groups/$groupId/announcements/new'),
                            ),
                          ),
                        ],
                      ],
                    );
                  }
                  final items = page.items;
                  final notifier =
                      ref.read(sentAnnouncementsProvider(groupId).notifier);
                  return NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (page.hasMore && n.metrics.extentAfter < 600) {
                        // ignore: discarded_futures
                        notifier.loadMore();
                      }
                      return false;
                    },
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      itemCount: items.length + (page.hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        if (i >= items.length) {
                          WidgetsBinding.instance
                              .addPostFrameCallback((_) => notifier.loadMore());
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        final a = items[i];
                        return _SentCard(
                          item: a,
                          onTap: () =>
                              context.push('/inbox/announcements/${a.id}'),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _SentCard extends StatelessWidget {
  const _SentCard({required this.item, required this.onTap});
  final SentAnnouncement item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = item;
    final total = a.recipientCount;
    final meta = [
      if (a.audienceLabel.isNotEmpty) 'To ${a.audienceLabel}',
      if (a.senderName.isNotEmpty) a.senderName,
      fmtRelative(a.createdAt),
    ].where((s) => s.isNotEmpty).join(' · ');
    return RailCard(
      urgent: a.isUrgent,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (a.isUrgent) ...[
            const UrgentPill(),
            const SizedBox(width: 6),
          ],
          if (a.isPinned) ...[
            Icon(Icons.push_pin_rounded, size: 15, color: p.muted),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 11.5)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(a.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: p.ink,
                fontSize: 15,
                height: 1.3,
                fontWeight: FontWeight.w700)),
        if (a.body.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(a.body.trim().replaceAll(RegExp(r'\s*\n\s*'), ' '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.45)),
        ],
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: total == 0
                ? 0.0
                : (a.seen >= total ? 1.0 : a.seen / total),
            minHeight: 5,
            backgroundColor: p.surface2,
            color: p.accent,
          ),
        ),
        const SizedBox(height: 6),
        Text('Seen ${a.seen} of $total · ${a.acked} tapped Got it',
            style: TextStyle(
                color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
