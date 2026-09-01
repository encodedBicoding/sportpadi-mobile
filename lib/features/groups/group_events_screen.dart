import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/event_tile_square.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Per-group events page — upcoming / past toggle over a square-tile grid
/// with paging (the web /groups/[id]/events page).
class GroupEventsScreen extends ConsumerStatefulWidget {
  const GroupEventsScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupEventsScreen> createState() => _GroupEventsScreenState();
}

class _GroupEventsScreenState extends ConsumerState<GroupEventsScreen> {
  String _scope = 'upcoming';
  final List<EventSummary> _items = [];
  int? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _items.clear();
        _nextCursor = null;
      });
    }
    try {
      final page = await ref.read(eventsRepositoryProvider).forGroupPaged(
            widget.groupId,
            scope: _scope,
            cursor: reset ? null : _nextCursor,
          );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _nextCursor = page.nextCursor;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final group = ref.watch(groupProvider(widget.groupId)).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Events',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (group != null)
              Text(group.name,
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
          ],
        ),
        actions: [
          if (group?.canManage == true)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: SpButton(
                  label: 'New',
                  icon: Icons.add_rounded,
                  onTap: () =>
                      context.push('/groups/${widget.groupId}/new-event'),
                ),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Scope toggle (web's pill switcher).
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                for (final k in const ['upcoming', 'past'])
                  Expanded(
                    child: Material(
                      color:
                          _scope == k ? p.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        onTap: () {
                          if (_scope == k) return;
                          setState(() => _scope = k);
                          _load(reset: true);
                        },
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            k == 'upcoming' ? 'Upcoming' : 'Past',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _scope == k ? p.ink : p.muted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_error != null)
              GlassCard(
                child: Text(_error!,
                    style: TextStyle(color: p.danger, fontSize: 13)),
              )
            else if (_items.isEmpty)
              GlassCard(
                child: Center(
                  child: Text(
                    'No $_scope events${_scope == 'upcoming' ? ' yet' : ''}.',
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                ),
              )
            else ...[
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final e in _items) EventTileSquare(event: e),
                ],
              ),
              if (_nextCursor != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: _loadingMore
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                              CircularProgressIndicator(strokeWidth: 2))
                      : InkWell(
                          onTap: () {
                            setState(() => _loadingMore = true);
                            _load();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text('Load more',
                                style: TextStyle(
                                    color: p.accent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
