import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcement_models.dart';
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart';
import 'package:sportpadi_mobile/data/messages/message_models.dart';
import 'package:sportpadi_mobile/data/messages/messages_repository.dart';
import 'package:sportpadi_mobile/features/inbox/announcement_card.dart';
import 'package:sportpadi_mobile/features/inbox/message_start.dart';
import 'package:sportpadi_mobile/features/inbox/message_widgets.dart';
import 'package:sportpadi_mobile/features/settings/timezone_provider.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The Inbox's tabs (docs B6): Announcements (Messaging 1) and Messages —
/// conversations with a group's staff (Messaging 2). Each has its own badge.
enum InboxTab { announcements, messages }

/// Inbox — announcements from your groups, teams and events, and your
/// conversations with admins and coaches. Separate from the Notifications
/// bell by design (docs B2): these are what staff send you; the bell is what
/// the app tells you. `/inbox?tab=messages` opens on Messages.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key, this.initialTab});

  /// `messages` or `announcements` (the default).
  final String? initialTab;

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  static const _tabs = InboxTab.values;
  late InboxTab _tab = widget.initialTab == 'messages'
      ? InboxTab.messages
      : InboxTab.announcements;

  String _label(InboxTab t) => switch (t) {
        InboxTab.announcements => 'Announcements',
        InboxTab.messages => 'Messages',
      };

  void _select(InboxTab t) {
    if (t == _tab) return;
    setState(() => _tab = t);
    // Cheap, and keeps both badges honest between polls.
    ref.invalidate(announcementsUnreadProvider);
    ref.invalidate(messagesUnreadProvider);
  }

  Future<void> _markAll() async {
    try {
      await ref.read(announcementsInboxProvider.notifier).markAllSeen();
      if (!mounted) return;
      ref.invalidate(announcementsUnreadProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final annUnread =
        ref.watch(announcementsUnreadProvider).valueOrNull?.announcements ?? 0;
    final msgUnread = ref.watch(messagesUnreadProvider).valueOrNull ?? 0;
    final unread = _tab == InboxTab.messages ? msgUnread : annUnread;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(
              title: 'Inbox',
              subtitle: unread > 0
                  ? '${_label(_tab)} · $unread unread'
                  : _label(_tab),
              actions: [
                if (_tab == InboxTab.announcements && unread > 0)
                  TextButton(
                    onPressed: _markAll,
                    style: TextButton.styleFrom(
                        foregroundColor: p.greenText,
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    child: const Text('Mark all read'),
                  ),
                if (_tab == InboxTab.messages)
                  SpRoundButton(
                    icon: Icons.edit_outlined,
                    tooltip: 'New message',
                    onTap: () => startNewMessage(context),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: _InboxTabs(
              labels: [for (final t in _tabs) _label(t)],
              icons: const [
                Icons.campaign_outlined,
                Icons.chat_bubble_outline_rounded,
              ],
              counts: [annUnread, msgUnread],
              index: _tabs.indexOf(_tab),
              onChanged: (i) => _select(_tabs[i]),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: switch (_tab) {
              InboxTab.announcements => const _AnnouncementsList(),
              InboxTab.messages => const _MessagesList(),
            },
          ),
        ]),
      ),
    );
  }
}

class _AnnouncementsList extends ConsumerWidget {
  const _AnnouncementsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    ref.watch(viewerTimezoneProvider); // repaint stamps on a zone change
    final inbox = ref.watch(announcementsInboxProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(announcementsUnreadProvider);
        return ref.refresh(announcementsInboxProvider.future);
      },
      child: AsyncView<AnnouncementPage>(
        value: inbox,
        onRetry: () => ref.invalidate(announcementsInboxProvider),
        data: (page) {
          if (page.items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
              children: [
                const Center(
                  child: SpIconTile(Icons.campaign_outlined,
                      size: 60, iconSize: 28),
                ),
                const SizedBox(height: 14),
                Text('No announcements yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    'News from your groups, coaches and event organisers '
                    'will land here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 13)),
              ],
            );
          }
          final items = page.items;
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (page.hasMore && n.metrics.extentAfter < 600) {
                // ignore: discarded_futures
                ref.read(announcementsInboxProvider.notifier).loadMore();
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
                  // A short first page never scrolls: ask for the next one
                  // as soon as the loader row itself is on screen.
                  final more = ref.read(announcementsInboxProvider.notifier);
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
                final a = items[i];
                return AnnouncementCard(
                  item: a,
                  onTap: () => context.push('/inbox/announcements/${a.id}'),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// The Inbox switcher: the segmented pill, with an unread count per tab.
class _InboxTabs extends StatelessWidget {
  const _InboxTabs({
    required this.labels,
    required this.icons,
    required this.counts,
    required this.index,
    required this.onChanged,
  });
  final List<String> labels;
  final List<IconData> icons;
  final List<int> counts;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dark ? p.surface2 : const Color(0xFFE6EBE8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: i == index,
              label: i < counts.length && counts[i] > 0
                  ? '${labels[i]}, ${counts[i]} unread'
                  : labels[i],
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 38,
                  decoration: BoxDecoration(
                    color: i == index ? p.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: i == index && !dark
                        ? const [
                            BoxShadow(
                                color: Color(0x140E1411),
                                blurRadius: 2,
                                offset: Offset(0, 1))
                          ]
                        : null,
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (i < icons.length) ...[
                          Icon(icons[i],
                              size: 15, color: i == index ? p.ink : p.muted),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(labels[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: i == index ? p.ink : p.muted,
                                  fontSize: 13,
                                  fontWeight: i == index
                                      ? FontWeight.w700
                                      : FontWeight.w600)),
                        ),
                        if (i < counts.length && counts[i] > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            constraints: const BoxConstraints(minWidth: 18),
                            decoration: BoxDecoration(
                              color: i == 0 ? p.orange : p.accentDeep,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                                counts[i] > 99 ? '99+' : '${counts[i]}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Messages tab: my conversations with admins and coaches, newest activity
/// first, with an All / Unread filter.
class _MessagesList extends ConsumerStatefulWidget {
  const _MessagesList();

  @override
  ConsumerState<_MessagesList> createState() => _MessagesListState();
}

class _MessagesListState extends ConsumerState<_MessagesList> {
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    ref.watch(viewerTimezoneProvider); // repaint stamps on a zone change
    final provider = messagesListProvider(_unreadOnly);
    final list = ref.watch(provider);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Row(children: [
          for (final unread in const [false, true]) ...[
            ChoiceChip(
              label: Text(unread ? 'Unread' : 'All'),
              selected: _unreadOnly == unread,
              showCheckmark: false,
              onSelected: (_) => setState(() => _unreadOnly = unread),
            ),
            const SizedBox(width: 8),
          ],
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(messagesUnreadProvider);
            return ref.refresh(provider.future);
          },
          child: AsyncView<ConversationPage>(
            value: list,
            onRetry: () => ref.invalidate(provider),
            data: (page) {
              if (page.items.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 64, 20, 20),
                  children: [
                    const Center(
                      child: SpIconTile(Icons.chat_bubble_outline_rounded,
                          size: 60, iconSize: 28),
                    ),
                    const SizedBox(height: 14),
                    Text(
                        _unreadOnly
                            ? "You're all caught up"
                            : 'No messages yet',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                        'Conversations with your group admins and coaches '
                        'land here. Members never message each other.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.muted, fontSize: 13)),
                    if (!_unreadOnly) ...[
                      const SizedBox(height: 18),
                      Center(
                        child: SpButton(
                          label: 'New message',
                          icon: Icons.edit_outlined,
                          onTap: () => startNewMessage(context),
                        ),
                      ),
                    ],
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
                  itemCount: items.length + (page.hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    if (i >= items.length) {
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
                    final c = items[i];
                    return ConversationRow(
                      item: c,
                      onTap: () {
                        ref.read(provider.notifier).markRead(c.id);
                        context.push('/inbox/messages/${c.id}');
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    ]);
  }
}
