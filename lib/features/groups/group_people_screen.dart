import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/groups/members_repository.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/groups/group_detail_screen.dart'
    show showGroupInviteSheet;
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/inbox/message_entry_points.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';

/// Members / followers of a group (2026, the web /groups/[id]/members and
/// /followers pages): the round-back header with "Group · N members", a
/// search card, and rows in one card — members with Admin / Ward tags and
/// earned titles; followers with select-to-promote and a "Make N members"
/// bar.
class GroupPeopleScreen extends ConsumerWidget {
  const GroupPeopleScreen(
      {super.key, required this.groupId, required this.kind});
  final String groupId;
  final String kind; // members | followers

  bool get isMembers => kind == 'members';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupProvider(groupId)).valueOrNull;
    final name = group?.name ?? 'Group';
    final canManage = group?.canManage ?? false;
    final int? count = isMembers
        ? group?.memberCount
        : ref.watch(groupFollowersProvider(groupId)).valueOrNull?.length ??
            group?.followerCount;
    final noun = isMembers ? 'member' : 'follower';
    return SpSubPage(
      title: isMembers ? 'Members' : 'Followers',
      subtitle:
          count != null ? '$name · $count $noun${count == 1 ? '' : 's'}' : name,
      actions: [
        if (isMembers && canManage)
          SpPill(
            label: 'Invite',
            icon: Icons.person_add_alt_1_rounded,
            onTap: () => showGroupInviteSheet(context, groupId),
          ),
      ],
      body: isMembers
          ? _MembersList(
              groupId: groupId,
              canManage: canManage,
              creatorId: group?.createdBy,
              myUserId: ref.watch(meProvider).valueOrNull?.userId)
          : _FollowersList(groupId: groupId, canManage: canManage),
    );
  }
}

class _MembersList extends ConsumerStatefulWidget {
  const _MembersList({
    required this.groupId,
    required this.canManage,
    this.creatorId,
    this.myUserId,
  });
  final String groupId;
  final bool canManage;
  final String? creatorId;
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
      _next = null; // a failed reload must not page on with the old cursor
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
      // Still not filling the screen? Keep going.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScroll();
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
      if (!mounted) return;
      ref.invalidate(groupMembersProvider(widget.groupId));
      ref.invalidate(groupProvider(widget.groupId));
      await _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Message (staff), and for admins a role menu — never on your own row
  /// (the server also refuses to change the creator's role); wards can't
  /// sign in, so they're never made admins.
  /// Admins: remove someone from the group (web: the red bin on the row).
  /// Confirmed first — it also takes the wards who joined through them.
  Future<void> _remove(GroupMemberItem m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${m.displayName}?'),
        content: Text(m.isWard
            ? 'They leave the group and its teams.'
            : 'They leave the group, along with any wards who joined through '
                'them (unless another guardian is still a member).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                  foregroundColor: context.palette.danger),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final wards = await ref
          .read(membersRepositoryProvider)
          .removeMember(widget.groupId, m.userId);
      messenger.showSnackBar(SnackBar(
          content: Text(wards > 0
              ? 'Member removed, with $wards ward${wards == 1 ? '' : 's'} who joined through them'
              : 'Member removed')));
      if (!mounted) return;
      ref.invalidate(groupMembersProvider(widget.groupId));
      ref.invalidate(groupProvider(widget.groupId));
      await _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// The row's right side, as on the web: Message (staff), then for admins
  /// a shield (make / remove admin; wards can't be admins) and a red bin
  /// (remove from the group). Never on the creator's row or your own.
  Widget _trailing(GroupMemberItem m) {
    // Staff: message this member (a ward: their guardians). Hides itself for
    // anyone the viewer can't reach.
    final message = MessageMemberButton(
      groupId: widget.groupId,
      memberId: m.userId,
      name: m.displayName,
      isWard: m.isWard,
    );
    final isCreator = m.userId == widget.creatorId;
    if (!widget.canManage || isCreator || m.userId == widget.myUserId) {
      return message;
    }
    final p = context.palette;
    final isAdmin = m.role == 'admin';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      message,
      if (!m.isWard || isAdmin) ...[
        _RoundAction(
          icon: isAdmin ? Icons.remove_moderator_outlined : Icons.shield_outlined,
          tooltip: isAdmin ? 'Demote to member' : 'Promote to admin',
          bg: p.surface2,
          fg: p.ink,
          onTap: () => _setRole(m, isAdmin ? 'member' : 'admin'),
        ),
        const SizedBox(width: 6),
      ],
      _RoundAction(
        icon: Icons.delete_outline_rounded,
        tooltip: 'Remove from group',
        bg: p.liveTint,
        fg: p.danger,
        onTap: () => _remove(m),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final titles =
        ref.watch(groupProgressionProvider(widget.groupId)).valueOrNull?.titles;
    final admins = _items.where((m) => m.role == 'admin').length;
    // Single-admin groups get told why a second admin matters: nobody can
    // check themselves in, including the organiser.
    final showTip = widget.canManage &&
        _term.isEmpty &&
        !_loading &&
        _error == null &&
        _items.isNotEmpty &&
        admins <= 1;

    Widget content;
    // A refresh keeps the rows on screen (the pull indicator shows instead).
    if (_loading && _items.isEmpty) {
      content = const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (_error != null) {
      content = GlassCard(
        child: Column(children: [
          Text('$_error',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13)),
          TextButton(onPressed: _reload, child: const Text('Try again')),
        ]),
      );
    } else if (_items.isEmpty) {
      content = SpEmpty(
        icon: _term.isEmpty ? Icons.people_outline_rounded : Icons.search_rounded,
        text: _term.isEmpty ? 'No members yet.' : 'No members match “$_term”.',
      );
    } else {
      content = Column(children: [
        SpListCard(children: [
          for (final m in _items)
            _MemberRow(
              person: m,
              isCreator: m.userId == widget.creatorId,
              titles: titles?[m.userId] ?? const <String>[],
              trailing: _trailing(m),
            ),
        ]),
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
      ]);
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, 32 + MediaQuery.of(context).padding.bottom),
        children: [
          // The tip's slot is always here so the search card below keeps its
          // place (and focus) when the tip comes and goes.
          showTip
              ? const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: SpTipCard(
                    "You're the only admin. Nobody can check themselves in — so make a trusted member an admin (tap the shield on their row) and they can check you in on match day, and run things when you're away.",
                    icon: Icons.admin_panel_settings_outlined,
                  ),
                )
              : const SizedBox.shrink(),
          SpSearchCard(
            controller: _search,
            hint: 'Search members',
            onChanged: _onSearch,
          ),
          const SizedBox(height: 12),
          content,
        ],
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
      if (!mounted) return;
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
        final bottomInset = MediaQuery.of(context).padding.bottom;

        return Stack(children: [
          RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(groupFollowersProvider(widget.groupId).future),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, (_selected.isNotEmpty ? 96 : 32) + bottomInset),
              children: [
                if (items.isNotEmpty) ...[
                  // Fixed slot, judged on the whole list (not the search
                  // results), so the search card never moves while typing.
                  canManage && items.any((f) => !f.isMember)
                      ? const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: SpTipCard(
                              'Promote followers into group members so they can access member-only features. Add any follower on their row, or select several and use the bar at the bottom.'),
                        )
                      : const SizedBox.shrink(),
                  SpSearchCard(
                    key: const ValueKey('followers-search'),
                    controller: _search,
                    hint: 'Search followers',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
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
                          child:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            _Check(checked: allSelected, size: 18),
                            const SizedBox(width: 8),
                            Text('Select all eligible',
                                style: TextStyle(
                                    color: p.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                      const Spacer(),
                      Text('${_selected.length} selected',
                          style: TextStyle(color: p.muted, fontSize: 12)),
                      const SizedBox(width: 4),
                    ]),
                    const SizedBox(height: 8),
                  ],
                ],
                if (items.isEmpty)
                  const SpEmpty(
                    icon: Icons.how_to_reg_rounded,
                    title: 'No followers yet',
                    text:
                        "When people follow your group or check into events, they'll appear here.",
                  )
                else if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('No followers match “${_search.text.trim()}”',
                          style: TextStyle(color: p.muted, fontSize: 13.5)),
                    ),
                  )
                else
                  SpListCard(children: [
                    for (final f in filtered)
                      _FollowerRow(
                        person: f,
                        canManage: canManage,
                        selected: _selected.contains(f.userId),
                        selecting: _selected.isNotEmpty,
                        promoting: _promoting,
                        onToggle: () => _toggle(f.userId),
                        onPromote: () => _promote([f.userId]),
                      ),
                  ]),
              ],
            ),
          ),
          if (_selected.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              // Web's sticky footer: Cancel + "Make N members".
              child: Container(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 12 + bottomInset),
                color: p.bg.withAlpha(235),
                child: Row(children: [
                  SpPill(
                    label: 'Cancel',
                    tone: SpPillTone.soft,
                    height: 46,
                    onTap: _promoting
                        ? null
                        : () => setState(() => _selected.clear()),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SpPill(
                      label: _promoting
                          ? 'Adding…'
                          : 'Make ${_selected.length} member${_selected.length == 1 ? '' : 's'}',
                      icon: Icons.person_add_alt_1_rounded,
                      expand: true,
                      height: 46,
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

/// A rounded checkbox in the brand green.
class _Check extends StatelessWidget {
  const _Check({required this.checked, this.size = 20});
  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: checked ? p.accentDeep : p.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: checked ? p.accentDeep : p.line, width: 1.5),
      ),
      child: checked
          ? Icon(Icons.check_rounded, size: size - 5, color: Colors.white)
          : null,
    );
  }
}

/// One follower: a checkbox for those who can be promoted, avatar + name
/// (open their profile), "@handle · followed X ago", then a Member tag or a
/// "Make member" pill (a plain "Follower" label while selecting).
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
    final sub = [
      if (f.username != null && f.username!.isNotEmpty) '@${f.username}',
      if (followed.isNotEmpty) followed,
    ].join(' · ');
    return Material(
      color: selected ? p.accentTint : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: eligible ? onToggle : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(children: [
            if (canManage) ...[
              eligible
                  ? _Check(checked: selected)
                  : const SizedBox(width: 20),
              const SizedBox(width: 12),
            ],
            // Avatar + name open their profile; the rest of the row selects.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: PlayerTap(
                  userId: f.userId,
                  borderRadius: 22,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    PersonAvatar(url: f.avatarUrl, name: f.displayName),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                          if (sub.isNotEmpty)
                            Text(sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(color: p.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (f.isMember)
              SpTag('Member', bg: p.accentTint, fg: p.greenText)
            else if (eligible && !selecting)
              SpPill(
                label: 'Add',
                icon: Icons.person_add_alt_1_rounded,
                tone: SpPillTone.outline,
                height: 34,
                onTap: promoting ? null : onPromote,
              )
            else
              Text('FOLLOWER',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 10,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// One member: avatar, name with Admin / Ward tags, "@handle · Ward of X",
/// the titles they've earned here — the row opens their profile (yours: your
/// Profile tab); the trailing buttons keep their own taps.
class _MemberRow extends ConsumerWidget {
  const _MemberRow(
      {required this.person,
      this.isCreator = false,
      this.titles = const [],
      this.trailing});
  final GroupMemberItem person;
  final bool isCreator;
  final List<String> titles;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final m = person;
    final sub = [
      if (m.username != null && m.username!.isNotEmpty) '@${m.username}',
      if (m.isWard && m.wardOf != null) 'Ward of ${m.wardOf}',
    ].join(' · ');
    // Transparent material so the ripple shows on the card's white.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => openPlayerProfile(context, ref, m.userId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(children: [
          PersonAvatar(url: m.avatarUrl, name: m.displayName),
          const SizedBox(width: 12),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (isCreator) ...[
                    const SizedBox(width: 6),
                    SpTag('Creator', bg: p.orangeTint, fg: p.orangeInk),
                  ] else if (m.role == 'admin') ...[
                    const SizedBox(width: 6),
                    SpTag('Admin', bg: p.accentTint, fg: p.greenText),
                  ],
                  if (m.isWard) ...[
                    const SizedBox(width: 6),
                    const WardBadge(),
                  ],
                ]),
                if (sub.isNotEmpty)
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: m.isWard && m.username == null
                              ? p.wardInk
                              : p.muted,
                          fontSize: 12)),
                // Community titles earned in this group (gamification).
                if (titles.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, runSpacing: 4, children: [
                    for (final t in titles)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                            color: p.orangeTint,
                            borderRadius: BorderRadius.circular(99)),
                        child: Text(t,
                            style: TextStyle(
                                color: p.orangeInk,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                  ]),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ]),
      ),
      ),
    );
  }
}

/// A 36px round icon button (the members row's admin actions).
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.bg,
    required this.fg,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
                width: 36, height: 36, child: Icon(icon, size: 18, color: fg)),
          ),
        ),
      );
}
