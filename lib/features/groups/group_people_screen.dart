import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/groups/members_repository.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/inbox/message_entry_points.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';

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
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isMembers ? 'Members' : 'Followers',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (group != null)
              Text(group.name,
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
          ],
        ),
      ),
      body: isMembers
          ? _MembersList(
              groupId: groupId,
              canManage: group?.canManage ?? false,
              myUserId: ref.watch(meProvider).valueOrNull?.userId)
          : _FollowersList(
              groupId: groupId, canManage: group?.canManage ?? false),
    );
  }
}

class _MembersList extends ConsumerStatefulWidget {
  const _MembersList({
    required this.groupId,
    required this.canManage,
    this.myUserId,
  });
  final String groupId;
  final bool canManage;
  final String? myUserId;

  @override
  ConsumerState<_MembersList> createState() => _MembersListState();
}

/// Members, paged as you scroll (18 at a time, like the web) and searchable
/// by name / @username on the server — so search reaches every member, not
/// just the pages loaded so far.
class _MembersListState extends ConsumerState<_MembersList> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  String _term = '';
  final List<GroupMemberItem> _items = [];
  int? _next;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;

  /// Bumped on every fresh load so a slow old page can't land in a new list.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 600) _loadMore();
  }

  void _onSearch(String v) {
    setState(() {}); // the clear button
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final t = v.trim();
      if (t == _term) return;
      _term = t;
      _reload();
    });
  }

  Future<void> _reload() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _loadingMore = false; // an older page still in flight is dropped
      _error = null;
    });
    try {
      final page = await ref
          .read(membersRepositoryProvider)
          .forGroup(widget.groupId, q: _term);
      if (!mounted || gen != _gen) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _next = page.nextCursor;
        _loading = false;
      });
      // A short first page may not fill the screen — keep going.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScroll();
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _next;
    if (cursor == null || _loading || _loadingMore) return;
    final gen = _gen;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(membersRepositoryProvider)
          .forGroup(widget.groupId, cursor: cursor, q: _term);
      if (!mounted || gen != _gen) return;
      setState(() {
        final have = {for (final m in _items) m.userId};
        _items.addAll(page.items.where((m) => !have.contains(m.userId)));
        _next = page.nextCursor;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted && gen == _gen) setState(() => _loadingMore = false);
    }
  }

  Future<void> _setRole(GroupMemberItem m, String role) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(membersRepositoryProvider)
          .setRole(widget.groupId, m.userId, role);
      messenger.showSnackBar(SnackBar(
          content: Text(role == 'admin'
              ? '${m.displayName} is now an admin — they can check you in and run events.'
              : '${m.displayName} is a member again.')));
      ref.invalidate(groupMembersProvider(widget.groupId));
      ref.invalidate(groupProvider(widget.groupId));
      await _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _trailing(GroupMemberItem m) {
    final p = context.palette;
    final titles = ref
            .watch(groupProgressionProvider(widget.groupId))
            .valueOrNull
            ?.titles[m.userId] ??
        const <String>[];
    final role = _roleBadge(context, m.role);
    // Community titles earned in this group (gamification).
    final badge = titles.isEmpty
        ? role
        : Row(mainAxisSize: MainAxisSize.min, children: [
            for (final t in titles.take(1))
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                      color: p.amber.withAlpha(36),
                      borderRadius: BorderRadius.circular(99)),
                  child: Text(t,
                      style: TextStyle(
                          color: p.amber,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            role,
          ]);
    // Staff: message this member (a ward: their guardians). Hides itself for
    // anyone the viewer can't reach.
    final message = MessageMemberButton(
      groupId: widget.groupId,
      memberId: m.userId,
      name: m.displayName,
      isWard: m.isWard,
    );
    final withMessage =
        Row(mainAxisSize: MainAxisSize.min, children: [message, badge]);
    // Nobody edits their own row (the server also refuses to change the
    // creator's role). Wards can't sign in, so they're never made admins.
    if (!widget.canManage || m.userId == widget.myUserId) return withMessage;
    if (m.isWard && m.role != 'admin') return withMessage;
    final isAdmin = m.role == 'admin';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      message,
      badge,
      PopupMenuButton<String>(
        tooltip: 'Role',
        icon: Icon(Icons.more_vert_rounded, size: 18, color: p.muted),
        onSelected: (v) => _setRole(m, v),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: isAdmin ? 'member' : 'admin',
            child: Text(isAdmin ? 'Remove admin' : 'Make admin'),
          ),
        ],
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final admins = _items.where((m) => m.role == 'admin').length;
    // Single-admin groups get told why a second admin matters: nobody can
    // check themselves in, including the organiser.
    final tip = widget.canManage && _term.isEmpty && !_loading && admins <= 1
        ? Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassCard(
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.admin_panel_settings_outlined,
                    size: 18, color: p.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "You're the only admin. Nobody can check themselves in — so make a trusted member an admin (tap the ⋮ on their row) and they can check you in on match day, and run things when you're away.",
                    style:
                        TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
                  ),
                ),
              ]),
            ),
          )
        : null;

    // Keyed so the field keeps focus while the tip above it comes and goes.
    final search = Padding(
      key: const ValueKey('members-search'),
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _search,
        onChanged: _onSearch,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search members...',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _search.clear();
                    _onSearch('');
                  },
                ),
          isDense: true,
        ),
      ),
    );

    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.only(top: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(children: [
          Text('$_error',
              textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
          TextButton(onPressed: _reload, child: const Text('Try again')),
        ]),
      );
    } else if (_items.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Center(
          child: Text(
              _term.isEmpty ? 'Nobody here yet.' : 'No members match “$_term”.',
              style: TextStyle(color: p.muted, fontSize: 13)),
        ),
      );
    } else {
      body = const SizedBox.shrink();
    }

    final showRows = !_loading && _error == null && _items.isNotEmpty;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: 1 + (showRows ? _items.length : 0) + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            return Column(children: [
              if (tip != null) tip,
              search,
              if (!showRows) body,
            ]);
          }
          final idx = i - 1;
          if (showRows && idx < _items.length) {
            final m = _items[idx];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PersonRow(person: m, trailing: _trailing(m)),
            );
          }
          // Footer: the next page loading.
          return _loadingMore
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              : const SizedBox(height: 8);
        },
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
        final promotable = [
          for (final f in filtered)
            if (!f.isMember) f
        ];
        final allSelected = promotable.isNotEmpty &&
            promotable.every((f) => _selected.contains(f.userId));
        // Drop selections that no longer exist (promoted / refetched).
        _selected.removeWhere(
            (id) => !items.any((f) => f.userId == id && !f.isMember));

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
                      style: TextStyle(color: p.ink, fontSize: 12, height: 1.4),
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
                              style: TextStyle(color: p.muted, fontSize: 12)),
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
        // Avatar + name open their profile; the rest of the row selects.
        PlayerTap(
          userId: f.userId,
          borderRadius: 18,
          child: ClipOval(
            child: Crest(logoUrl: f.avatarUrl, label: f.displayName, size: 36),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: PlayerTap(
              userId: f.userId,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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

/// Admin / Member pill (shared by the members list and its role menu).
Widget _roleBadge(BuildContext context, String? role) {
  final p = context.palette;
  final admin = role == 'admin';
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color:
          admin ? const Color.fromRGBO(23, 166, 94, 0.12) : Colors.transparent,
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

class _PersonRow extends ConsumerWidget {
  const _PersonRow({required this.person, this.trailing});
  final GroupMemberItem person;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final m = person;
    // The row opens their profile (yours: your Profile tab); the trailing
    // buttons keep their own taps.
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      onTap: () => openPlayerProfile(context, ref, m.userId),
      child: Row(children: [
        ClipOval(
          child: Crest(logoUrl: m.avatarUrl, label: m.displayName, size: 36),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(m.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                ),
                if (m.isWard) ...[
                  const SizedBox(width: 6),
                  const WardBadge(),
                ],
              ]),
              if (m.isWard && m.wardOf != null)
                Text('Ward of ${m.wardOf}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.wardInk, fontSize: 11.5))
              else if (m.username != null)
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
