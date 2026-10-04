import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/messages/message_models.dart';
import 'package:sportpadi_mobile/data/messages/messages_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/inbox/message_widgets.dart';
import 'package:sportpadi_mobile/features/settings/timezone_provider.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Admins: every conversation in the group, read-only (docs B8 — there is no
/// hidden staff-to-member channel), and the reports made in it.
class GroupMessagesScreen extends ConsumerStatefulWidget {
  const GroupMessagesScreen(
      {super.key, required this.groupId, this.initialTab});
  final String groupId;

  /// `reports` opens on Reports.
  final String? initialTab;

  @override
  ConsumerState<GroupMessagesScreen> createState() =>
      _GroupMessagesScreenState();
}

class _GroupMessagesScreenState extends ConsumerState<GroupMessagesScreen> {
  late int _tab = widget.initialTab == 'reports' ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final group = ref.watch(groupProvider(widget.groupId)).valueOrNull;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(
              title: 'Conversations',
              subtitle: group?.name,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: SpSegmented(
              options: const ['All conversations', 'Reports'],
              icons: const [
                Icons.forum_outlined,
                Icons.flag_outlined,
              ],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          Expanded(
            child: _tab == 0
                ? _OversightList(groupId: widget.groupId)
                : _ReportsList(groupId: widget.groupId),
          ),
        ]),
      ),
    );
  }
}

class _OversightList extends ConsumerWidget {
  const _OversightList({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    ref.watch(viewerTimezoneProvider); // repaint stamps on a zone change
    final provider = groupConversationsProvider(groupId);
    final list = ref.watch(provider);
    // Loading / error aren't scrollable on their own: keep them pullable.
    final bare = list.when(
        data: (_) => false, error: (_, __) => true, loading: () => true);
    final Widget view = AsyncView<ConversationPage>(
      value: list,
      onRetry: () => ref.invalidate(provider),
      data: (page) {
        final note = Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.visibility_outlined, size: 16, color: p.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  "Every conversation between this group's admins or coaches and its "
                  "members. You can read them all; only the people in a "
                  'conversation can reply.',
                  style:
                      TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
            ),
          ]),
        );
        if (page.items.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              note,
              const SizedBox(height: 40),
              const Center(
                child:
                    SpIconTile(Icons.forum_outlined, size: 60, iconSize: 28),
              ),
              const SizedBox(height: 14),
              Text('No conversations yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ],
          );
        }
        final items = page.items;
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (page.hasMore && n.metrics.extentAfter < 600) {
              // ignore: discarded_futures
              ref.read(provider.notifier).loadMore();
            }
            return false;
          },
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: items.length + 1 + (page.hasMore ? 1 : 0),
            separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 0 : 10),
            itemBuilder: (context, i) {
              if (i == 0) return note;
              final k = i - 1;
              if (k >= items.length) {
                final more = ref.read(provider.notifier);
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => more.loadMore());
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final c = items[k];
              return ConversationRow(
                item: c,
                // The admin may be a party to some of them: then it's a
                // normal thread, and the server says so.
                oversight: true,
                onTap: () => context.push('/inbox/messages/${c.id}'),
              );
            },
          ),
        );
      },
    );
    return RefreshIndicator(
      // The list (from its first page again) and the header's group name.
      onRefresh: () {
        ref.invalidate(provider);
        ref.invalidate(groupProvider(groupId));
        return settleAll([
          ref.read(provider.future),
          ref.read(groupProvider(groupId).future),
        ]);
      },
      child: bare ? PullableState(child: view) : view,
    );
  }
}

class _ReportsList extends ConsumerStatefulWidget {
  const _ReportsList({required this.groupId});
  final String groupId;

  @override
  ConsumerState<_ReportsList> createState() => _ReportsListState();
}

class _ReportsListState extends ConsumerState<_ReportsList> {
  static const _statuses = [
    (value: 'open', label: 'Open'),
    (value: 'reviewed', label: 'Reviewed'),
    (value: 'dismissed', label: 'Dismissed'),
  ];
  String _status = 'open';
  final Set<String> _busy = {};

  Future<void> _resolve(MessageReport r, String status) async {
    setState(() => _busy.add(r.id));
    try {
      await ref.read(messagesRepositoryProvider).resolveReport(r.id, status);
      if (!mounted) return;
      ref.invalidate(messageReportsProvider);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == 'dismissed'
              ? 'Report dismissed.'
              : 'Marked as reviewed.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    ref.watch(viewerTimezoneProvider); // repaint stamps on a zone change
    final key = (groupId: widget.groupId, status: _status);
    final reports = ref.watch(messageReportsProvider(key));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        child: Row(children: [
          for (final s in _statuses) ...[
            ChoiceChip(
              label: Text(s.label),
              selected: _status == s.value,
              showCheckmark: false,
              onSelected: (_) => setState(() => _status = s.value),
            ),
            const SizedBox(width: 8),
          ],
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () {
            ref.invalidate(messageReportsProvider(key));
            ref.invalidate(groupProvider(widget.groupId));
            return settleAll([
              ref.read(messageReportsProvider(key).future),
              ref.read(groupProvider(widget.groupId).future),
            ]);
          },
          child: _pullable(reports, AsyncView<List<MessageReport>>(
            value: reports,
            onRetry: () => ref.invalidate(messageReportsProvider(key)),
            data: (list) {
              if (list.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
                  children: [
                    const Center(
                      child: SpIconTile(Icons.flag_outlined,
                          size: 60, iconSize: 28),
                    ),
                    const SizedBox(height: 14),
                    Text(_status == 'open' ? 'No open reports' : 'Nothing here',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        'When someone reports a message, an announcement or '
                        'a discussion in this group, it shows up here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.muted, fontSize: 13)),
                  ],
                );
              }
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _reportCard(p, list[i]),
              );
            },
          )),
        ),
      ),
    ]);
  }

  /// Loading / error aren't scrollable on their own: keep them pullable.
  Widget _pullable(AsyncValue<Object?> value, Widget view) =>
      value.when(
              data: (_) => false, error: (_, __) => true, loading: () => true)
          ? PullableState(child: view)
          : view;

  Widget _reportCard(AppPalette p, MessageReport r) {
    final busy = _busy.contains(r.id);
    final discussionTitle = r.discussionTitle ?? 'a discussion';
    final what = r.isAnnouncement
        ? 'Announcement: ${r.announcementTitle ?? 'Untitled'}'
        : r.isDiscussionComment
            ? 'Comment on "$discussionTitle"'
            : r.isDiscussion
                ? 'Discussion: $discussionTitle'
                : r.messageDeleted
                    ? 'Message from ${r.messageSenderName ?? 'a member'} (deleted)'
                    : 'Message from ${r.messageSenderName ?? 'a member'}';
    // The reported text: a message, or a discussion comment.
    final quoted = (r.isDiscussion
            ? (r.isDiscussionComment ? r.discussionCommentBody : null)
            : r.isAnnouncement
                ? null
                : r.messageBody)
        ?.trim();
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SpBadge(r.reasonLabel, icon: Icons.flag_outlined, tone: p.danger),
            const Spacer(),
            Text(fmtRelative(r.createdAt),
                style: TextStyle(color: p.muted, fontSize: 11.5)),
          ]),
          const SizedBox(height: 10),
          Text(what,
              style: TextStyle(
                  color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          if (quoted != null && quoted.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(quoted,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.ink, fontSize: 13, height: 1.4)),
            ),
          ],
          const SizedBox(height: 8),
          Text('Reported by ${r.reporterName ?? 'a member'}',
              style: TextStyle(color: p.muted, fontSize: 12)),
          if (r.details != null) ...[
            const SizedBox(height: 4),
            Text('"${r.details}"',
                style: TextStyle(
                    color: p.muted,
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 4, runSpacing: 4, children: [
            if (r.conversationId != null)
              TextButton.icon(
                onPressed: () =>
                    context.push('/inbox/messages/${r.conversationId}'),
                icon: const Icon(Icons.forum_outlined, size: 17),
                label: const Text('Open conversation'),
              ),
            if (r.announcementId != null)
              TextButton.icon(
                onPressed: () =>
                    context.push('/inbox/announcements/${r.announcementId}'),
                icon: const Icon(Icons.campaign_outlined, size: 17),
                label: const Text('Open announcement'),
              ),
            if (r.discussionId != null)
              TextButton.icon(
                onPressed: () => context.push('/discussions/${r.discussionId}'),
                icon: const Icon(Icons.forum_outlined, size: 17),
                label: const Text('Open discussion'),
              ),
            if (r.isOpen) ...[
              TextButton.icon(
                onPressed: busy ? null : () => _resolve(r, 'reviewed'),
                icon: const Icon(Icons.check_rounded, size: 17),
                label: const Text('Reviewed'),
              ),
              TextButton.icon(
                onPressed: busy ? null : () => _resolve(r, 'dismissed'),
                icon: const Icon(Icons.close_rounded, size: 17),
                label: const Text('Dismiss'),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: SpBadge(
                    r.status == 'dismissed' ? 'Dismissed' : 'Reviewed',
                    icon: r.status == 'dismissed'
                        ? Icons.close_rounded
                        : Icons.check_rounded),
              ),
          ]),
        ],
      ),
    );
  }
}
