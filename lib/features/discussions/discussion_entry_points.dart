import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcement_models.dart';
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart';
import 'package:sportpadi_mobile/data/discussions/discussion_models.dart';
import 'package:sportpadi_mobile/data/discussions/discussions_repository.dart';
import 'package:sportpadi_mobile/features/discussions/discussion_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Where discussions surface outside their own screens: the group and team
/// pages' Talk sheets (the top 5 hot ones I can see there), and Settings.
/// Everything reads `view=spaces`, so a section only shows to people who can
/// read and post there.

/// Group page (its Talk section's Discussions sheet): the top [limit] hot,
/// "See all" (with [showTitle]) and "Start a discussion". Hidden unless I'm
/// in the group-wide space or a team's. Inside a sheet, pass [launch] so the
/// sheet closes before anything opens.
class GroupDiscussionsSection extends ConsumerWidget {
  const GroupDiscussionsSection({
    super.key,
    required this.groupId,
    this.limit = 3,
    this.showTitle = true,
    this.launch,
    this.padding = const EdgeInsets.only(bottom: 14),
  });
  final String groupId;
  final int limit;
  final bool showTitle;
  final SheetLaunch? launch;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(discussionSpacesProvider(groupId)).valueOrNull;
    if (spaces == null || !spaces.any) return const SizedBox.shrink();
    return _DiscussionsPreview(
      groupId: groupId,
      space: '',
      padding: padding,
      limit: limit,
      showTitle: showTitle,
      launch: launch,
    );
  }
}

/// Team page (its Talk section's Discussions sheet): the same, for this
/// team's discussions — "See all" opens the team's space and "Start a
/// discussion" preselects it. Hidden unless the team is one of my spaces
/// (its players, their guardians, coaches, admins).
class TeamDiscussionsSection extends ConsumerWidget {
  const TeamDiscussionsSection({
    super.key,
    required this.groupId,
    required this.teamId,
    this.limit = 3,
    this.showTitle = true,
    this.launch,
    this.padding = const EdgeInsets.fromLTRB(20, 10, 20, 4),
  });
  final String groupId;
  final String teamId;
  final int limit;
  final bool showTitle;
  final SheetLaunch? launch;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(discussionSpacesProvider(groupId)).valueOrNull;
    if (spaces?.team(teamId) == null) return const SizedBox.shrink();
    return _DiscussionsPreview(
      groupId: groupId,
      space: teamId,
      padding: padding,
      limit: limit,
      showTitle: showTitle,
      launch: launch,
    );
  }
}

class _DiscussionsPreview extends ConsumerWidget {
  const _DiscussionsPreview({
    required this.groupId,
    required this.space,
    required this.padding,
    this.limit = 3,
    this.showTitle = true,
    this.launch,
  });
  final String groupId;

  /// '' = everything I can see in the group, or a team id.
  final String space;
  final EdgeInsets padding;
  final int limit;
  final bool showTitle;
  final SheetLaunch? launch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final DiscussionListKey key = (
      groupId: groupId,
      space: space,
      sort: 'hot',
      flair: null,
      status: null,
    );
    final page = ref.watch(discussionListProvider(key)).valueOrNull;
    final items =
        (page?.items ?? const <DiscussionItem>[]).take(limit).toList();
    final q = space.isEmpty ? '' : '?team=$space';
    void open(String route) =>
        runFromSheet(context, launch, (c) => c.push(route));

    Future<void> vote(String id, int pressed) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref.read(discussionListProvider(key).notifier).vote(id, pressed);
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('$e')));
      }
    }

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle) ...[
            SpSectionTitle(
              'Discussions',
              trailing: TextButton(
                onPressed: () => open('/groups/$groupId/discussions$q'),
                child: const Text('See all'),
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (page != null && items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                  'No discussions yet. Ask a question, raise an issue or '
                  'share an idea.',
                  style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
            ),
          for (final d in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DiscussionCard(
                item: d,
                compact: true,
                showTeam: space.isEmpty,
                onTap: () => open('/discussions/${d.id}'),
                onVote: (v) => vote(d.id, v),
              ),
            ),
          _QuietButton(
            label: 'Start a discussion',
            icon: Icons.add_comment_outlined,
            onTap: () => open('/groups/$groupId/discussions/new$q'),
          ),
        ],
      ),
    );
  }
}

/// Settings → Discussions: one on/off switch for comment and reply
/// notifications (in-app + push). Stored as the `discussions` category's
/// push flag; defaults on.
class DiscussionNotificationsCard extends ConsumerStatefulWidget {
  const DiscussionNotificationsCard({super.key});

  @override
  ConsumerState<DiscussionNotificationsCard> createState() =>
      _DiscussionNotificationsCardState();
}

class _DiscussionNotificationsCardState
    extends ConsumerState<DiscussionNotificationsCard> {
  bool? _pending;

  Future<void> _set(bool v) async {
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _pending = v);
    try {
      await ref
          .read(announcementsRepositoryProvider)
          .setPreference('discussions', push: v);
      container.invalidate(notificationPreferencesProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pending = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final list = ref.watch(notificationPreferencesProvider).valueOrNull;
    final saved = list
            ?.firstWhere((x) => x.category == 'discussions',
                orElse: () =>
                    const NotificationPreference(category: 'discussions'))
            .push ??
        true;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Comments and replies',
            style: TextStyle(
                color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
        subtitle: Text(
            'When someone comments on your discussion or replies to your '
            'comment. New discussions never notify anyone.',
            style: TextStyle(color: p.muted, fontSize: 12)),
        value: _pending ?? saved,
        onChanged: list == null ? null : _set,
      ),
    );
  }
}

/// A quiet outlined pill button.
class _QuietButton extends StatelessWidget {
  const _QuietButton(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface,
      shape: StadiumBorder(side: BorderSide(color: p.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 17, color: p.ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}
