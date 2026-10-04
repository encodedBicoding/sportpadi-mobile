import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/features/groups/group_invitations.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_app_bar.dart'
    show SideMenuButton;
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/verified_badge.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

class GroupsListScreen extends ConsumerStatefulWidget {
  const GroupsListScreen({super.key});

  @override
  ConsumerState<GroupsListScreen> createState() => _GroupsListScreenState();
}

class _GroupsListScreenState extends ConsumerState<GroupsListScreen> {
  String _query = '';
  int _tab = 0; // 0 = mine, 1 = discover, 2 = invites
  final _scroll = ScrollController();
  final _invites = GlobalKey<InvitationsTabState>();

  @override
  void initState() {
    super.initState();
    // Invites page as you scroll.
    _scroll.addListener(_maybeMoreInvites);
    // Opened from a "You've been invited" notification → Invites.
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeTabRequest());
  }

  /// Near the end of the list (or it doesn't fill the screen yet): the next
  /// page of invitations.
  void _maybeMoreInvites() {
    if (_tab != 2 || !_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 500) _invites.currentState?.loadMore();
  }

  void _takeTabRequest() {
    if (!mounted) return;
    final want = ref.read(groupsTabRequestProvider);
    if (want == null) return;
    ref.read(groupsTabRequestProvider.notifier).state = null;
    setState(() => _tab = want);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _match(GroupSummary g) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return g.name.toLowerCase().contains(q) ||
        (g.description ?? '').toLowerCase().contains(q);
  }

  Future<void> _refresh() {
    ref.invalidate(myGroupsProvider);
    ref.invalidate(discoverGroupsProvider);
    ref.invalidate(groupInvitationCountProvider);
    return settleAll([
      ref.read(myGroupsProvider.future),
      ref.read(discoverGroupsProvider.future),
      ref.read(groupInvitationCountProvider.future),
      if (_invites.currentState != null) _invites.currentState!.reload(),
    ]);
  }

  /// Loading / error aren't scrollable on their own: keep them pullable.
  Widget _pullable(AsyncValue<Object?> value, Widget view) =>
      value.when(
              data: (_) => false, error: (_, __) => true, loading: () => true)
          ? PullableState(child: view)
          : view;

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(myGroupsProvider);
    final discover = ref.watch(discoverGroupsProvider);
    final inviteCount = ref.watch(groupInvitationCountProvider).valueOrNull ?? 0;
    ref.listen<int?>(groupsTabRequestProvider, (_, next) {
      // After this frame: never change a provider while it's notifying.
      if (next != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _takeTabRequest());
      }
    });
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: _pullable(mine, AsyncView(
            value: mine,
            onRetry: () => ref.invalidate(myGroupsProvider),
            data: (myList) {
              final myFiltered = myList.where(_match).toList();
              final myIds = myList.map((g) => g.id).toSet();
              final discoverList = (discover.valueOrNull ?? [])
                  .where((g) => !myIds.contains(g.id))
                  .where(_match)
                  .toList();

              return ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                children: [
                  // Tab title, New, and the side menu (this tab has no app bar).
                  Row(children: [
                    Expanded(
                      child: Text('Groups',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5)),
                    ),
                    Material(
                      color: p.hero,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => _openCreate(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 11),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.add_rounded, size: 18, color: p.onHero),
                            const SizedBox(width: 5),
                            Text('New',
                                style: TextStyle(
                                    color: p.onHero,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SideMenuButton(),
                  ]),
                  const SizedBox(height: 2),
                  Text('Your crews, and new ones to find.',
                      style: TextStyle(color: p.muted, fontSize: 13)),
                  const SizedBox(height: 14),
                  // Search.
                  Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: dark ? Border.all(color: p.line) : null,
                      boxShadow: cardShadow(context),
                    ),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      style: TextStyle(color: p.ink, fontSize: 14.5),
                      decoration: InputDecoration(
                        hintText: 'Search groups',
                        hintStyle: TextStyle(color: p.muted, fontSize: 14.5),
                        prefixIcon: Icon(Icons.search_rounded,
                            size: 21, color: p.muted),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SpSegmented(
                    options: [
                      'Mine · ${myFiltered.length}',
                      discover.hasValue
                          ? 'Discover · ${discoverList.length}'
                          : 'Discover',
                      'Invites',
                    ],
                    // Invitations waiting, on the Invites tab.
                    badges: [null, null, inviteCount],
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                  const SizedBox(height: 14),
                  if (_tab == 2) ...[
                    // Invitations group admins sent me — what they are, and
                    // accept / decline each (pages as you scroll).
                    InvitationsTab(key: _invites, onLoaded: _maybeMoreInvites),
                  ] else if (_tab == 0) ...[
                    if (myFiltered.isEmpty)
                      _EmptyBox(
                        icon: Icons.groups_outlined,
                        text: _query.isEmpty
                            ? "You're not in any groups yet. Create one, or find one in Discover."
                            : 'No groups of yours match that search.',
                        action: _query.isEmpty
                            ? SpButton(
                                label: 'Discover groups',
                                icon: Icons.explore_outlined,
                                onTap: () => setState(() => _tab = 1),
                              )
                            : null,
                      )
                    else
                      for (final g in myFiltered)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _GroupCard(
                            group: g,
                            onTap: () => context.push('/groups/${g.id}'),
                          ),
                        ),
                  ] else ...[
                    if (discover.hasError)
                      const _EmptyBox(
                          icon: Icons.error_outline_rounded,
                          text: 'Could not load groups.')
                    else if (discover.isLoading && !discover.hasValue)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (discoverList.isEmpty)
                      _EmptyBox(
                        icon: Icons.search_rounded,
                        text: _query.isEmpty
                            ? 'No other groups to discover yet.'
                            : 'No groups match that search.',
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: 206,
                        ),
                        itemCount: discoverList.length,
                        itemBuilder: (_, i) => _GroupTile(
                          group: discoverList[i],
                          onTap: () =>
                              context.push('/groups/${discoverList[i].id}'),
                        ),
                      ),
                  ],
                ],
              );
            },
          )),
        ),
      ),
    );
  }

  void _openCreate(BuildContext context) {
    showSpSheet<void>(
      context,
      builder: (_) => const _CreateGroupSheet(),
    );
  }
}

bool _verified(GroupSummary g) => isVerifiedBadge(g.verificationBadge);

/// One of your groups: crest (or cover-tinted crest), name with role and
/// verification, and its size — a row card you tap into.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, this.onTap});
  final GroupSummary group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = group;
    final admin = g.role == 'admin' || g.role == 'owner';
    final meta = [
      if (g.memberCount != null)
        '${g.memberCount} member${g.memberCount == 1 ? '' : 's'}',
      if (g.followerCount != null && g.followerCount! > 0)
        '${g.followerCount} follower${g.followerCount == 1 ? '' : 's'}',
    ].join(' · ');
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        // Cover as a small banner behind the crest when there is one.
        SizedBox(
          width: 64,
          height: 64,
          child: Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: g.coverImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: g.coverImageUrl!,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          Container(color: p.accentTint),
                    )
                  : Container(width: 64, height: 64, color: p.accentTint),
            ),
            Center(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.surface, width: 2),
                ),
                child: Crest(logoUrl: g.logoUrl, label: g.name, size: 44),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
                if (_verified(g)) ...[
                  const SizedBox(width: 4),
                  const VerifiedBadge(size: 17),
                ],
              ]),
              if (meta.isNotEmpty)
                Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
              if (admin) ...[
                const SizedBox(height: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: p.accentTint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('ADMIN',
                      style: TextStyle(
                          color: p.greenText,
                          fontSize: 10,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w800)),
                ),
              ],
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
      ]),
    );
  }
}

/// A group to discover (2-column grid): inset cover — photo or a green
/// wash — with the crest overlapping its edge, then name and size.
class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, this.onTap});
  final GroupSummary group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = group;
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 104,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              bottom: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: g.coverImageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: g.coverImageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _wash(),
                      )
                    : _wash(),
              ),
            ),
            if (g.isMember)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xEBFFFFFF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('Member',
                      style: TextStyle(
                          color: Color(0xFF0F7A45),
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            Positioned(
              left: 10,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.surface, width: 3),
                ),
                child: Crest(logoUrl: g.logoUrl, label: g.name, size: 38),
              ),
            ),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
                if (_verified(g)) ...[
                  const SizedBox(width: 3),
                  const VerifiedBadge(size: 15),
                ],
              ]),
              if ((g.description ?? '').isNotEmpty)
                Text(g.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.muted, fontSize: 11.5, height: 1.35)),
              const Spacer(),
              if (g.memberCount != null)
                Text('${g.memberCount} member${g.memberCount == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: p.greenText,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _wash() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1E6B45), Color(0xFF17A65E)],
          ),
        ),
        child: Center(
          child: Icon(Icons.groups_rounded, size: 30, color: Color(0x80FFFFFF)),
        ),
      );
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
      child: Column(
        children: [
          SpIconTile(icon, size: 52, iconSize: 24),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.45),
          ),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

class _CreateGroupSheet extends ConsumerStatefulWidget {
  const _CreateGroupSheet();

  @override
  ConsumerState<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<_CreateGroupSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(groupsRepositoryProvider)
          .createGroup(name, _desc.text.trim());
      ref.invalidate(myGroupsProvider);
      ref.invalidate(discoverGroupsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (id.isNotEmpty) context.push('/groups/$id');
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not create the group.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SpSheetHeader(
          icon: Icons.groups_rounded,
          title: 'Create a group',
          subtitle: 'Start a new group to organise events and members.',
        ),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _desc,
          maxLines: 3,
          minLines: 2,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            alignLabelWithHint: true,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
        ],
        const SizedBox(height: 18),
        SpButton(
          label: _busy ? 'Creating…' : 'Create group',
          expand: true,
          onTap: _busy ? null : _submit,
        ),
      ],
    );
  }
}
