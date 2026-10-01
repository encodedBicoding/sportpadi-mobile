import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/discussions/discussion_models.dart';
import 'package:sportpadi_mobile/data/discussions/discussions_repository.dart';
import 'package:sportpadi_mobile/features/discussions/discussion_widgets.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// A group's discussions (docs/design/discussions.md): everything I can see
/// — group-wide and my teams — or one space, sorted Hot / New / Top with
/// pinned ones first, filtered by flair and open / resolved.
/// `/groups/:id/discussions?team=<teamId|group>` opens on one space.
class DiscussionsScreen extends ConsumerStatefulWidget {
  const DiscussionsScreen(
      {super.key, required this.groupId, this.initialSpace});
  final String groupId;

  /// `group`, a team id, or null for everything.
  final String? initialSpace;

  @override
  ConsumerState<DiscussionsScreen> createState() => _DiscussionsScreenState();
}

class _DiscussionsScreenState extends ConsumerState<DiscussionsScreen> {
  static const _sorts = ['hot', 'new', 'top'];

  late String _space = widget.initialSpace ?? '';
  String _sort = 'hot';
  String? _flair;
  String? _status;

  DiscussionListKey get _key => (
        groupId: widget.groupId,
        space: _space,
        sort: _sort,
        flair: _flair,
        status: _status,
      );

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _vote(String id, int pressed) async {
    try {
      await ref.read(discussionListProvider(_key).notifier).vote(id, pressed);
    } catch (e) {
      _snack('$e');
    }
  }

  void _compose() {
    final q = _space.isEmpty ? '' : '?team=$_space';
    context.push('/groups/${widget.groupId}/discussions/new$q');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final groupName =
        ref.watch(groupProvider(widget.groupId)).valueOrNull?.name;
    final spaces =
        ref.watch(discussionSpacesProvider(widget.groupId)).valueOrNull;
    final canPost = spaces?.any ?? false;
    return Scaffold(
      backgroundColor: p.bg,
      floatingActionButton: canPost
          ? SpButton(
              label: 'New discussion',
              icon: Icons.add_rounded,
              tone: SpButtonTone.brand,
              onTap: _compose,
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(title: 'Discussions', subtitle: groupName),
          ),
          if (spaces != null && spaces.teams.isNotEmpty) _spacesRow(spaces),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: SpSegmented(
              options: const ['Hot', 'New', 'Top'],
              icons: const [
                Icons.local_fire_department_outlined,
                Icons.schedule_rounded,
                Icons.trending_up_rounded,
              ],
              index: _sorts.indexOf(_sort),
              onChanged: (i) => setState(() => _sort = _sorts[i]),
            ),
          ),
          _filtersRow(),
          Expanded(child: _list(p)),
        ]),
      ),
    );
  }

  Widget _spacesRow(DiscussionSpaces spaces) {
    final pills = <Widget>[
      DiscussionPill(
        label: 'All',
        icon: Icons.forum_outlined,
        selected: _space.isEmpty,
        onTap: () => setState(() => _space = ''),
      ),
      if (spaces.group)
        DiscussionPill(
          label: 'Group',
          icon: Icons.groups_outlined,
          selected: _space == 'group',
          onTap: () => setState(() => _space = 'group'),
        ),
      for (final t in spaces.teams)
        DiscussionPill(
          label: t.name,
          leading: Crest(logoUrl: t.logoUrl, label: t.name, size: 18),
          selected: _space == t.id,
          onTap: () => setState(() => _space = t.id),
        ),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
        itemCount: pills.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => pills[i],
      ),
    );
  }

  Widget _filtersRow() {
    final pills = <Widget>[
      DiscussionPill(
        label: 'Open',
        icon: Icons.radio_button_unchecked_rounded,
        selected: _status == 'open',
        onTap: () =>
            setState(() => _status = _status == 'open' ? null : 'open'),
      ),
      DiscussionPill(
        label: 'Resolved',
        icon: Icons.check_circle_outline_rounded,
        selected: _status == 'resolved',
        onTap: () =>
            setState(() => _status = _status == 'resolved' ? null : 'resolved'),
      ),
      for (final f in discussionFlairs)
        DiscussionPill(
          label: f.label,
          icon: discussionFlairIcon(f.value),
          selected: _flair == f.value,
          onTap: () =>
              setState(() => _flair = _flair == f.value ? null : f.value),
        ),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
        itemCount: pills.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => pills[i],
      ),
    );
  }

  Widget _list(AppPalette p) {
    final provider = discussionListProvider(_key);
    final list = ref.watch(provider);
    final filtered = _flair != null || _status != null;
    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(discussionSpacesProvider(widget.groupId));
        return ref.refresh(provider.future);
      },
      child: AsyncView<DiscussionPage>(
        value: list,
        onRetry: () => ref.invalidate(provider),
        data: (page) {
          if (page.items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 96),
              children: [
                const Center(
                  child:
                      SpIconTile(Icons.forum_outlined, size: 60, iconSize: 28),
                ),
                const SizedBox(height: 14),
                Text(filtered ? 'Nothing matches' : 'No discussions yet',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    filtered
                        ? 'Try other filters.'
                        : 'Ask a question, raise an issue or share an idea '
                            'with everyone here.',
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
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
                return DiscussionCard(
                  item: d,
                  // One team's list doesn't need its name on every card.
                  showTeam: _space.isEmpty,
                  onTap: () => context.push('/discussions/${d.id}'),
                  onVote: (v) => _vote(d.id, v),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
