import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/event_tile.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// A group's events (2026, the web /groups/[id]/events page): the round-back
/// header with "Group · N events" and a New pill, an Upcoming / Past switch,
/// then the 2026 event tiles in two columns, paged as you scroll.
class GroupEventsScreen extends ConsumerStatefulWidget {
  const GroupEventsScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupEventsScreen> createState() => _GroupEventsScreenState();
}

class _GroupEventsScreenState extends ConsumerState<GroupEventsScreen> {
  static const _scopes = ['upcoming', 'past'];
  String _scope = 'upcoming';
  final _scroll = ScrollController();
  final List<EventSummary> _items = [];
  int? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

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
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter < 600) _loadMore();
  }

  Future<void> _reload() async {
    final gen = ++_gen;
    setState(() {
      _loading = true;
      _loadingMore = false; // an older page still in flight is dropped
      _error = null;
      _nextCursor = null; // a failed reload must not page on with the old cursor
    });
    try {
      final page = await ref
          .read(eventsRepositoryProvider)
          .forGroupPaged(widget.groupId, scope: _scope);
      if (!mounted || gen != _gen) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _nextCursor = page.nextCursor;
        _loading = false;
      });
      // A short first page may not fill the screen — keep going.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScroll();
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _loading || _loadingMore) return;
    final gen = _gen;
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(eventsRepositoryProvider)
          .forGroupPaged(widget.groupId, scope: _scope, cursor: cursor);
      if (!mounted || gen != _gen) return;
      setState(() {
        final have = {for (final e in _items) e.id};
        _items.addAll(page.items.where((e) => !have.contains(e.id)));
        _nextCursor = page.nextCursor;
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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final group = ref.watch(groupProvider(widget.groupId)).valueOrNull;
    // Admins, and coaches for the teams they coach.
    final canCreate = group?.canManage == true ||
        (group?.isMember == true &&
            (ref
                    .watch(eventAudiencesProvider(widget.groupId))
                    .valueOrNull
                    ?.canCreate ??
                false));
    final name = group?.name ?? 'Group';
    final count = group?.eventsCount;

    Widget content;
    // A refresh keeps the rows on screen (the pull indicator shows instead).
    if (_loading && _items.isEmpty) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (_error != null) {
      content = GlassCard(
        child: Column(children: [
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.danger, fontSize: 13)),
          TextButton(onPressed: _reload, child: const Text('Try again')),
        ]),
      );
    } else if (_items.isEmpty) {
      content = SpEmpty(
        icon: Icons.calendar_today_outlined,
        text: 'No $_scope events${_scope == 'upcoming' ? ' yet' : ''}.',
      );
    } else {
      // The 2026 event tiles in two columns (as on Browse / the web).
      content = Column(children: [
        EventTileGrid(events: _items, showGroup: false),
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
      ]);
    }

    return SpSubPage(
      title: 'Events',
      subtitle: count != null
          ? '$name · $count event${count == 1 ? '' : 's'}'
          : name,
      actions: [
        if (canCreate)
          SpPill(
            label: 'New',
            icon: Icons.add_rounded,
            onTap: () => context.push('/groups/${widget.groupId}/new-event'),
          ),
      ],
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
              20, 12, 20, 32 + MediaQuery.of(context).padding.bottom),
          children: [
            // Web's compact switcher (not full width).
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 220,
                child: SpSegmented(
                  options: const ['Upcoming', 'Past'],
                  index: _scopes.indexOf(_scope),
                  onChanged: (i) {
                    if (_scopes[i] == _scope) return;
                    setState(() {
                      _scope = _scopes[i];
                      _items.clear(); // the other list, not this one's rows
                    });
                    _reload();
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            content,
          ],
        ),
      ),
    );
  }
}
