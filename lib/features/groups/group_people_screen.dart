import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/groups/members_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
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

class _FollowersList extends ConsumerStatefulWidget {
  const _FollowersList({required this.groupId, required this.canManage});
  final String groupId;
  final bool canManage;

  @override
  ConsumerState<_FollowersList> createState() => _FollowersListState();
}

/// Mirrors the web followers page: search, Member/Follower badge with
/// "followed X ago", "Make member" only for people who aren't members yet,
/// multi-select with a bottom bar to promote several at once.
class _FollowersListState extends ConsumerState<_FollowersList> {
  final _search = TextEditingController();
  final Set<String> _selected = {};
  bool _promoting = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _promote(List<String> userIds) async {
    if (userIds.isEmpty || _promoting) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _promoting = true);
    try {
      await ref
          .read(membersRepositoryProvider)
          .promoteFollowers(widget.groupId, userIds);
      messenger.showSnackBar(SnackBar(
          content: Text(userIds.length == 1
              ? 'Added as member!'
              : 'Added ${userIds.length} members!')));
      setState(() => _selected.removeAll(userIds));
      ref.invalidate(groupFollowersProvider(widget.groupId));
      ref.invalidate(groupMembersProvider(widget.groupId));
      ref.invalidate(groupProvider(widget.groupId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _promoting = false);
    }
  }

  void _toggle(String userId) {
    setState(() {
      if (!_selected.remove(userId)) _selected.add(userId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final list = ref.watch(groupFollowersProvider(widget.groupId));
    final canManage = widget.canManage;
    return AsyncView(
      value: list,
      onRetry: () => ref.invalidate(groupFollowersProvider(widget.groupId)),
      data: (items) {
        final q = _search.text.trim().toLowerCase();
        final filtered = q.isEmpty
            ? items
            : [
                for (final f in items)
                  if (f.displayName.toLowerCase().contains(q) ||
                      (f.username ?? '').toLowerCase().contains(q))
                    f,
              ];
        final promotable = [for (final f in filtered) if (!f.isMember) f];
        final allSelected = promotable.isNotEmpty &&
            promotable.every((f) => _selected.contains(f.userId));
        // Drop selections that no longer exist (promoted / refetched).
        _selected.removeWhere((id) => !items.any((f) => f.userId == id && !f.isMember));

        return Stack(children: [
          RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(groupFollowersProvider(widget.groupId).future),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, _selected.isNotEmpty ? 96 : 16),
              children: [
                if (canManage && promotable.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(23, 166, 94, 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color.fromRGBO(23, 166, 94, 0.3)),
                    ),
                    child: Text(
                      'Tip: promote followers into group members so they can access member-only features — tap "Make member" on a follower, or select several and use the bar below.',
                      style:
                          TextStyle(color: p.ink, fontSize: 12, height: 1.4),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (items.isNotEmpty) ...[
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search followers...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      isDense: true,
                      suffixIcon: q.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _search.clear();
                                setState(() {});
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (canManage && promotable.isNotEmpty) ...[
                  Row(children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() {
                        if (allSelected) {
                          _selected.clear();
                        } else {
                          _selected.addAll(promotable.map((f) => f.userId));
                        }
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(
                              allSelected
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 18,
                              color: allSelected ? p.accent : p.muted),
                          const SizedBox(width: 6),
                          Text('Select all eligible',
                              style:
                                  TextStyle(color: p.muted, fontSize: 12)),
                        ]),
                      ),
                    ),
                    const Spacer(),
                    Text('${_selected.length} selected',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ]),
                  const SizedBox(height: 8),
                ],
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 100),
                    child: Column(children: [
                      Icon(Icons.how_to_reg_rounded,
                          size: 44, color: p.muted.withAlpha(120)),
                      const SizedBox(height: 10),
                      Text('No followers yet.',
                          style: TextStyle(color: p.muted, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        'When people follow your group or check into events, they\'ll appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: p.muted.withAlpha(180), fontSize: 11.5),
                      ),
                    ]),
                  )
                else if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text('No followers match "${_search.text.trim()}"',
                          style: TextStyle(color: p.muted, fontSize: 13)),
                    ),
                  )
                else
                  for (final f in filtered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FollowerRow(
                        person: f,
                        canManage: canManage,
                        selected: _selected.contains(f.userId),
                        selecting: _selected.isNotEmpty,
                        promoting: _promoting,
                        onToggle: () => _toggle(f.userId),
                        onPromote: () => _promote([f.userId]),
                      ),
                    ),
              ],
            ),
          ),
          if (_selected.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
                decoration: BoxDecoration(
                  color: p.bg,
                  border: Border(top: BorderSide(color: p.line)),
                ),
                child: Row(children: [
                  TextButton(
                    onPressed: _promoting
                        ? null
                        : () => setState(() => _selected.clear()),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SpButton(
                      label: _promoting
                          ? 'Adding…'
                          : 'Make ${_selected.length} member${_selected.length == 1 ? '' : 's'}',
                      icon: Icons.person_add_alt_1_rounded,
                      expand: true,
                      onTap: _promoting
                          ? null
                          : () => _promote(_selected.toList()),
                    ),
                  ),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}

class _FollowerRow extends StatelessWidget {
  const _FollowerRow({
    required this.person,
    required this.canManage,
    required this.selected,
    required this.selecting,
    required this.promoting,
    required this.onToggle,
    required this.onPromote,
  });
  final GroupMemberItem person;
  final bool canManage;
  final bool selected;
  final bool selecting;
  final bool promoting;
  final VoidCallback onToggle;
  final VoidCallback onPromote;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final f = person;
    final eligible = canManage && !f.isMember;
    final followed = f.createdAt != null ? timeAgo(f.createdAt) : '';
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: eligible ? onToggle : null,
      child: Row(children: [
        if (canManage) ...[
          eligible
              ? Icon(
                  selected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 20,
                  color: selected ? p.accent : p.muted)
              : const SizedBox(width: 20),
          const SizedBox(width: 8),
        ],
        ClipOval(
          child: Crest(logoUrl: f.avatarUrl, label: f.displayName, size: 36),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(f.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
              if (f.username != null)
                Text('@${f.username}',
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(f.isMember ? 'MEMBER' : 'FOLLOWER',
              style: TextStyle(
                  color: f.isMember ? p.accent : p.muted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
          if (followed.isNotEmpty)
            Text(followed, style: TextStyle(color: p.muted, fontSize: 10)),
        ]),
        if (eligible && !selecting) ...[
          const SizedBox(width: 8),
          Material(
            color: p.surface2,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: promoting ? null : onPromote,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.person_add_alt_1_rounded,
                      size: 14, color: p.accent),
                  const SizedBox(width: 4),
                  Text('Make member',
                      style: TextStyle(
                          color: p.accent,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ],
      ]),
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
