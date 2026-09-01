import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_app_bar.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

class GroupsListScreen extends ConsumerStatefulWidget {
  const GroupsListScreen({super.key});

  @override
  ConsumerState<GroupsListScreen> createState() => _GroupsListScreenState();
}

class _GroupsListScreenState extends ConsumerState<GroupsListScreen> {
  String _query = '';

  bool _match(GroupSummary g) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return g.name.toLowerCase().contains(q) ||
        (g.description ?? '').toLowerCase().contains(q);
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref.refresh(myGroupsProvider.future),
      ref.refresh(discoverGroupsProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(myGroupsProvider);
    final discover = ref.watch(discoverGroupsProvider);
    final p = context.palette;

    return Scaffold(
      appBar: const SpAppBar(),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: AsyncView(
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Groups',
                            style: TextStyle(
                              color: p.ink,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Find a community near you — or start your own.',
                            style: TextStyle(color: p.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SpButton(
                      label: 'New',
                      icon: Icons.add_rounded,
                      onTap: () => _openCreate(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search groups',
                    prefixIcon: Icon(Icons.search_rounded, color: p.muted),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 18),
                const _SectionLabel('My groups'),
                const SizedBox(height: 10),
                if (myFiltered.isEmpty)
                  _EmptyBox(
                    icon: Icons.groups_outlined,
                    text: _query.isEmpty
                        ? "You're not in any groups yet. Create one or join from Discover below."
                        : 'No groups of yours match that search.',
                  )
                else
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    children: [
                      for (final g in myFiltered)
                        _GroupTile(
                          group: g,
                          onTap: () => context.push('/groups/${g.id}'),
                        ),
                    ],
                  ),
                const SizedBox(height: 18),
                const _SectionLabel('Discover'),
                const SizedBox(height: 10),
                if (discover.hasError)
                  const _EmptyBox(
                      icon: Icons.error_outline_rounded,
                      text: 'Could not load groups.')
                else if (discoverList.isEmpty)
                  _EmptyBox(
                    icon: Icons.search_rounded,
                    text: _query.isEmpty
                        ? 'No other groups to discover yet.'
                        : 'No groups match that search.',
                  )
                else
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    children: [
                      for (final g in discoverList)
                        _GroupTile(
                          group: g,
                          onTap: () => context.push('/groups/${g.id}'),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openCreate(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateGroupSheet(),
    );
  }
}

/// Square group tile (Browse-grid style): cover or wash, dark gradient,
/// crest + name + member count, verification tick, Member badge.
class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, this.onTap});
  final GroupSummary group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = group;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (g.coverImageUrl != null)
              CachedNetworkImage(
                imageUrl: g.coverImageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _wash(),
                errorWidget: (_, __, ___) => _wash(),
              )
            else
              _wash(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color.fromRGBO(0, 0, 0, 0.72),
                    Color.fromRGBO(0, 0, 0, 0.05),
                  ],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
            if (g.isMember)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF17A65E),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('MEMBER',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4)),
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Row(children: [
                ClipOval(
                  child:
                      Crest(logoUrl: g.logoUrl, label: g.name, size: 30),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(g.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                          if (g.verificationBadge != null &&
                              g.verificationBadge != 'none') ...[
                            const SizedBox(width: 3),
                            const Icon(Icons.verified_rounded,
                                size: 12, color: Color(0xFF38BDF8)),
                          ],
                        ]),
                        if (g.memberCount != null)
                          Text(
                              '${g.memberCount} member${g.memberCount == 1 ? '' : 's'}',
                              style: const TextStyle(
                                  color: Color.fromRGBO(
                                      255, 255, 255, 0.75),
                                  fontSize: 10)),
                      ]),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wash() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.fromRGBO(23, 166, 94, 0.30),
              Color.fromRGBO(14, 165, 233, 0.22),
            ],
          ),
        ),
        alignment: Alignment.center,
        child: const Text('👥', style: TextStyle(fontSize: 30)),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.palette.muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      );
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: p.muted),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13),
          ),
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
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.groups_rounded, color: p.accent),
                const SizedBox(width: 8),
                Text(
                  'Create a group',
                  style: TextStyle(
                      color: p.ink, fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Start a new group to organise events and members.',
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
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
        ),
      ),
    );
  }
}
