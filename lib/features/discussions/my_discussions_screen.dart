import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/attention/attention_repository.dart';
import 'package:sportpadi_mobile/data/discussions/discussion_models.dart';
import 'package:sportpadi_mobile/data/discussions/discussions_repository.dart';
import 'package:sportpadi_mobile/features/discussions/discussion_widgets.dart';
import 'package:sportpadi_mobile/features/settings/timezone_provider.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The side menu's Discussions (`/discussions`): every discussion I can see,
/// across all my groups and teams, newest activity first — All or Unread.
/// Each row says where it is (group · team) and what's new for me ("3 new"
/// comments, a "New" dot), and opens the thread; coming back re-reads the
/// list and the menu's badges.
class MyDiscussionsScreen extends ConsumerStatefulWidget {
  const MyDiscussionsScreen({super.key});

  @override
  ConsumerState<MyDiscussionsScreen> createState() =>
      _MyDiscussionsScreenState();
}

class _MyDiscussionsScreenState extends ConsumerState<MyDiscussionsScreen> {
  bool _unreadOnly = false;

  Future<void> _open(String id) async {
    await context.push<Object?>('/discussions/$id');
    if (!mounted) return;
    // Opening it read it (and maybe others were answered meanwhile).
    ref.invalidate(myDiscussionsProvider);
    ref.invalidate(attentionProvider);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    ref.watch(viewerTimezoneProvider); // repaint stamps on a zone change
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(
              title: 'Discussions',
              subtitle: 'From all your groups and teams',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: SpSegmented(
              options: const ['All', 'Unread'],
              icons: const [
                Icons.forum_outlined,
                Icons.mark_chat_unread_outlined,
              ],
              index: _unreadOnly ? 1 : 0,
              onChanged: (i) => setState(() => _unreadOnly = i == 1),
            ),
          ),
          Expanded(child: _list(p)),
        ]),
      ),
    );
  }

  Widget _list(AppPalette p) {
    final provider = myDiscussionsProvider(_unreadOnly);
    final list = ref.watch(provider);
    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(attentionProvider);
        return ref.refresh(provider.future);
      },
      child: AsyncView<DiscussionPage>(
        value: list,
        onRetry: () => ref.invalidate(provider),
        data: (page) {
          if (page.items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 40),
              children: [
                Center(
                  child: SpIconTile(
                      _unreadOnly
                          ? Icons.done_all_rounded
                          : Icons.forum_outlined,
                      size: 60,
                      iconSize: 28),
                ),
                const SizedBox(height: 14),
                Text(_unreadOnly ? 'All caught up' : 'No discussions yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    _unreadOnly
                        ? 'Nothing new since you last looked.'
                        : 'Discussions from your groups and teams show up '
                            'here.',
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
                ref.read(provider.notifier).loadMore();
              }
              return false;
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
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
                final d = items[i];
                return _MyDiscussionRow(item: d, onTap: () => _open(d.id));
              },
            ),
          );
        },
      ),
    );
  }
}

/// One discussion: its group's avatar, "Group · Team", when it last moved,
/// the title (a "New" dot while there's activity I haven't seen), the
/// preview, and pills — "3 new" comments, flair, Resolved — with the
/// comment count and score.
class _MyDiscussionRow extends StatelessWidget {
  const _MyDiscussionRow({required this.item, required this.onTap});
  final DiscussionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = item;
    final group = d.groupName ?? 'Group';
    final team = d.teamName;
    final preview = d.preview.trim();
    final fresh = d.unseen || d.newComments > 0;
    final when = fmtRelative(d.lastActivityAt ?? d.createdAt);
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Crest(logoUrl: d.groupImageUrl, label: group, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(team == null ? group : '$group · $team',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                if (when.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(when,
                      style: TextStyle(
                          color: fresh ? p.greenText : p.muted,
                          fontSize: 11.5,
                          fontWeight:
                              fresh ? FontWeight.w700 : FontWeight.w500)),
                ],
              ]),
              const SizedBox(height: 4),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(d.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 15,
                          height: 1.3,
                          fontWeight:
                              fresh ? FontWeight.w800 : FontWeight.w700)),
                ),
                if (d.unseen) ...[
                  const SizedBox(width: 8),
                  Semantics(
                    label: 'New',
                    child: Container(
                      width: 9,
                      height: 9,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                          color: p.accent, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ]),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
              ],
              const SizedBox(height: 9),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (d.newComments > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: p.accentDeep,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('${d.newComments} new',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800)),
                    ),
                  DiscussionFlairPill(d.flair),
                  if (d.isResolved) const DiscussionResolvedPill(),
                  _Stat(
                      icon: Icons.mode_comment_outlined, value: d.commentCount),
                  _Stat(icon: Icons.arrow_upward_rounded, value: d.score),
                ],
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// A quiet icon + number (comments, score).
class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value});
  final IconData icon;
  final int value;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: p.muted),
        const SizedBox(width: 3),
        Text('$value',
            style: TextStyle(
                color: p.muted, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
