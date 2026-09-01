import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/groups/members_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Members / followers of a group — mirrors the web pages: role-badged member
/// rows; followers get the admin tip + "Make member" promotion.
class GroupPeopleScreen extends ConsumerWidget {
  const GroupPeopleScreen(
      {super.key, required this.groupId, required this.kind});
  final String groupId;
  final String kind; // members | followers

  bool get isMembers => kind == 'members';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final group = ref.watch(groupProvider(groupId)).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isMembers ? 'Members' : 'Followers',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            if (group != null)
              Text(group.name,
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
          ],
        ),
      ),
      body: isMembers
          ? _MembersList(groupId: groupId)
          : _FollowersList(
              groupId: groupId, canManage: group?.canManage ?? false),
    );
  }
}

class _MembersList extends ConsumerWidget {
  const _MembersList({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(groupMembersProvider(groupId));
    return AsyncView(
      value: page,
      onRetry: () => ref.invalidate(groupMembersProvider(groupId)),
      data: (data) => RefreshIndicator(
        onRefresh: () async =>
            ref.refresh(groupMembersProvider(groupId).future),
        child: _PeopleList(items: data.items, showRole: true),
      ),
    );
  }
}

class _FollowersList extends ConsumerWidget {
  const _FollowersList({required this.groupId, required this.canManage});
  final String groupId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final list = ref.watch(groupFollowersProvider(groupId));
    return AsyncView(
      value: list,
      onRetry: () => ref.invalidate(groupFollowersProvider(groupId)),
      data: (items) => RefreshIndicator(
        onRefresh: () async =>
            ref.refresh(groupFollowersProvider(groupId).future),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (canManage && items.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(23, 166, 94, 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color.fromRGBO(23, 166, 94, 0.3)),
                ),
                child: Text(
                  'Tip: promote followers into group members so they can access member-only features — tap "Make member".',
                  style: TextStyle(
                      color: p.ink, fontSize: 12, height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 100),
                child: Center(
                  child: Text('No followers yet.',
                      style: TextStyle(color: p.muted, fontSize: 13)),
                ),
              )
            else
              for (final f in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PersonRow(
                    person: f,
                    trailing: canManage
                        ? _MakeMemberButton(groupId: groupId, person: f)
                        : null,
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _MakeMemberButton extends ConsumerStatefulWidget {
  const _MakeMemberButton({required this.groupId, required this.person});
  final String groupId;
  final GroupMemberItem person;

  @override
  ConsumerState<_MakeMemberButton> createState() =>
      _MakeMemberButtonState();
}

class _MakeMemberButtonState extends ConsumerState<_MakeMemberButton> {
  bool _busy = false;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_done) {
      return Icon(Icons.check_circle_rounded, color: p.accent, size: 20);
    }
    return Material(
      color: p.surface2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _busy
            ? null
            : () async {
                final messenger = ScaffoldMessenger.of(context);
                setState(() => _busy = true);
                try {
                  await ref
                      .read(membersRepositoryProvider)
                      .promoteFollowers(
                          widget.groupId, [widget.person.userId]);
                  if (mounted) setState(() => _done = true);
                  ref.invalidate(groupMembersProvider(widget.groupId));
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('$e')));
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Make member',
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _PeopleList extends StatelessWidget {
  const _PeopleList({required this.items, required this.showRole});
  final List<GroupMemberItem> items;
  final bool showRole;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (items.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 100),
        Center(
          child: Text('Nobody here yet.',
              style: TextStyle(color: p.muted, fontSize: 13)),
        ),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _PersonRow(
        person: items[i],
        trailing: showRole ? _roleBadge(context, items[i].role) : null,
      ),
    );
  }

  Widget _roleBadge(BuildContext context, String? role) {
    final p = context.palette;
    final admin = role == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: admin
            ? const Color.fromRGBO(23, 166, 94, 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: admin ? p.accent : p.line),
      ),
      child: Text(
        admin ? 'Admin' : 'Member',
        style: TextStyle(
          color: admin ? p.accent : p.muted,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, this.trailing});
  final GroupMemberItem person;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = person;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        ClipOval(
          child:
              Crest(logoUrl: m.avatarUrl, label: m.displayName, size: 36),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
              if (m.username != null)
                Text('@${m.username}',
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}
