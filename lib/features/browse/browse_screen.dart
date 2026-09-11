import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/location/location_provider.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/features/ads/ad_display.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/event_tile_square.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Browse — universal network search (events, groups, players, teams), the
/// "find your event" location filter, and an infinite-scroll event grid where
/// tournaments glow and live events carry the LIVE badge. Web /discover twin.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});
  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  // Universal search state
  Map<String, dynamic>? _results;
  bool _searching = false;

  // Grid state
  final List<EventSummary> _items = [];
  int? _nextCursor = 0;
  bool _loading = false;
  bool _locationFilter = false;
  String? _error;

  // Filters: sport (null = All) + quick toggles.
  String? _categoryId;
  bool _liveOnly = false;
  bool _tournamentsOnly = false;

  @override
  void initState() {
    super.initState();
    _loadMore(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_loading) return;
    if (reset) {
      _nextCursor = 0;
    }
    final cursor = _nextCursor;
    if (cursor == null) return;
    setState(() {
      _loading = true;
      if (reset) _error = null;
    });
    final loc = ref.read(locationProvider);
    try {
      final page = await ref.read(eventsRepositoryProvider).browse(
            cursor: cursor,
            categoryId: _categoryId,
            liveOnly: _liveOnly,
            tournamentsOnly: _tournamentsOnly,
            lat: _locationFilter ? loc.location?.lat : null,
            lng: _locationFilter ? loc.location?.lng : null,
            radiusMiles: _locationFilter && loc.location != null
                ? loc.radiusMiles
                : null,
          );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (reset) _error = '$e';
      });
    }
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final query = q.trim();
      if (query.length < 2) {
        if (mounted) setState(() => _results = null);
        return;
      }
      setState(() => _searching = true);
      try {
        final r = await ref.read(eventsRepositoryProvider).searchAll(query);
        if (mounted) setState(() => _results = r);
      } catch (_) {
        if (mounted) setState(() => _results = const {});
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _openFinder() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final p = ctx.palette;
        final loc = ref.watch(locationProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.place_outlined, size: 18, color: p.accent),
                  const SizedBox(width: 6),
                  Text('Find your event',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  if (loc.location != null && _locationFilter)
                    InkWell(
                      onTap: () {
                        setState(() => _locationFilter = false);
                        Navigator.pop(ctx);
                        _loadMore(reset: true);
                      },
                      child: Text('Clear',
                          style: TextStyle(color: p.danger, fontSize: 12.5)),
                    ),
                ]),
                const SizedBox(height: 12),
                if (loc.location == null) ...[
                  SpButton(
                    label: loc.loading ? 'Locating…' : 'Use my location',
                    icon: Icons.my_location_rounded,
                    expand: true,
                    onTap: loc.loading
                        ? null
                        : () async {
                            await ref.read(locationProvider.notifier).request();
                            final st = ref.read(locationProvider);
                            if (st.location != null) {
                              setState(() => _locationFilter = true);
                              if (ctx.mounted) Navigator.pop(ctx);
                              _loadMore(reset: true);
                            }
                          },
                  ),
                  if (loc.error != null) ...[
                    const SizedBox(height: 8),
                    Text(loc.error!,
                        style: TextStyle(color: p.danger, fontSize: 12)),
                  ],
                ] else ...[
                  Row(children: [
                    Expanded(
                      child: Text('Events within',
                          style: TextStyle(color: p.muted, fontSize: 12.5)),
                    ),
                    Text('${loc.radiusMiles} miles',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ]),
                  Slider(
                    value: loc.radiusMiles.toDouble().clamp(5, 100),
                    min: 5,
                    max: 100,
                    divisions: 19,
                    onChanged: (v) => ref
                        .read(locationProvider.notifier)
                        .setRadius(v.round()),
                  ),
                  const SizedBox(height: 4),
                  SpButton(
                    label: 'Show events near me',
                    icon: Icons.travel_explore_rounded,
                    expand: true,
                    onTap: () {
                      setState(() => _locationFilter = true);
                      Navigator.pop(ctx);
                      _loadMore(reset: true);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final showResults = _search.text.trim().length >= 2;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Browse',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        // Search bar + find-your-event
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(children: [
            const AdDisplay(slots: ['home_ads'], carousel: true),
            const SizedBox(height: 10),
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (v) {
                  setState(() {});
                  _onSearch(v);
                },
                style: TextStyle(color: p.ink, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search groups, players, events…',
                  hintStyle: TextStyle(color: p.muted, fontSize: 13.5),
                  prefixIcon:
                      Icon(Icons.search_rounded, size: 20, color: p.muted),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : _search.text.isNotEmpty
                          ? InkWell(
                              onTap: () {
                                _search.clear();
                                setState(() => _results = null);
                              },
                              child: Icon(Icons.close_rounded,
                                  size: 18, color: p.muted),
                            )
                          : null,
                  filled: true,
                  fillColor: p.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: p.line)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: p.line)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: _locationFilter ? p.accent : p.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _openFinder,
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: _locationFilter ? p.accent : p.line),
                  ),
                  child: Icon(Icons.place_outlined,
                      size: 21,
                      color: _locationFilter ? Colors.white : p.muted),
                ),
              ),
            ),
          ]),
        ),
        if (!showResults) _filterChips(p),
        Expanded(
          child: showResults ? _resultsList(p) : _grid(p),
        ),
      ]),
    );
  }

  /// Sport chips (All + active sports) and the Live / Tournaments toggles.
  Widget _filterChips(AppPalette p) {
    final sports = ref.watch(browseCategoriesProvider).valueOrNull ?? const [];

    Widget chip(String label, bool active, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: active ? p.accent : p.surface,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: active ? p.accent : p.line),
                ),
                child: Text(label,
                    style: TextStyle(
                        color: active ? Colors.white : p.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        );

    void apply(VoidCallback change) {
      setState(change);
      _loadMore(reset: true);
    }

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
        children: [
          chip('All', _categoryId == null,
              () => apply(() => _categoryId = null)),
          for (final c in sports)
            chip(
              '${parseStr(c['emoji']) ?? ''} ${parseStr(c['name']) ?? ''}'
                  .trim(),
              _categoryId == parseStr(c['id']),
              () => apply(() => _categoryId =
                  _categoryId == parseStr(c['id']) ? null : parseStr(c['id'])),
            ),
          Container(
            width: 1,
            margin: const EdgeInsets.only(right: 8, top: 4, bottom: 12),
            color: p.line,
          ),
          chip('🔴 Live', _liveOnly, () => apply(() => _liveOnly = !_liveOnly)),
          chip('🏆 Tournaments', _tournamentsOnly,
              () => apply(() => _tournamentsOnly = !_tournamentsOnly)),
        ],
      ),
    );
  }

  // ── Universal search results ──────────────────────────────────────────────

  Widget _resultsList(AppPalette p) {
    final r = _results;
    if (r == null) {
      return Center(
        child:
            Text('Searching…', style: TextStyle(color: p.muted, fontSize: 13)),
      );
    }
    List<Map<String, dynamic>> section(String key) => r[key] is List
        ? [
            for (final e in r[key] as List)
              if (e is Map) Map<String, dynamic>.from(e)
          ]
        : const [];
    final events = section('events');
    final groups = section('groups');
    final teams = section('teams');
    final players = section('players');
    if (events.isEmpty && groups.isEmpty && teams.isEmpty && players.isEmpty) {
      return Center(
        child: Text('Nothing on the network matches that.',
            style: TextStyle(color: p.muted, fontSize: 13)),
      );
    }

    Widget header(IconData icon, String label) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(children: [
            Icon(icon, size: 13, color: p.muted),
            const SizedBox(width: 5),
            Text(label.toUpperCase(),
                style: TextStyle(
                    color: p.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
          ]),
        );

    return ListView(children: [
      if (events.isNotEmpty) ...[
        header(Icons.calendar_today_outlined, 'Events'),
        for (final e in events)
          ListTile(
            dense: true,
            leading: Text(
                (e['category'] is Map
                        ? parseStr((e['category'] as Map)['emoji'])
                        : null) ??
                    '🏅',
                style: const TextStyle(fontSize: 18)),
            title: Text(parseStr(e['title']) ?? 'Event',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink, fontSize: 14)),
            trailing: Text(formatDay(e['eventDate']),
                style: TextStyle(color: p.muted, fontSize: 11.5)),
            onTap: () {
              final id = parseStr(e['id']);
              if (e['isTournament'] == true && id != null) {
                context.push('/tournaments/$id');
              } else {
                context.push('/events/${parseStr(e['slug']) ?? id}');
              }
            },
          ),
      ],
      if (groups.isNotEmpty) ...[
        header(Icons.groups_outlined, 'Groups'),
        for (final g in groups)
          ListTile(
            dense: true,
            leading: ClipOval(
              child: Crest(
                  logoUrl: parseStr(g['imageUrl']),
                  label: parseStr(g['name']) ?? 'G',
                  size: 32),
            ),
            title: Text(parseStr(g['name']) ?? 'Group',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink, fontSize: 14)),
            onTap: () => context.push('/groups/${parseStr(g['id'])}'),
          ),
      ],
      if (teams.isNotEmpty) ...[
        header(Icons.shield_outlined, 'Teams'),
        for (final t in teams)
          ListTile(
            dense: true,
            leading: Crest(
                logoUrl: parseStr(t['logoUrl']),
                kitPrimary: parseStr(t['kitPrimary']),
                kitSecondary: parseStr(t['kitSecondary']),
                label: parseStr(t['name']) ?? 'T',
                size: 32),
            title: Text(parseStr(t['name']) ?? 'Team',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink, fontSize: 14)),
            subtitle: Text(
                '@${parseStr(t['username']) ?? ''} · ${parseStr(t['groupName']) ?? ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 11.5)),
            onTap: () => context.push('/teams/${parseStr(t['id'])}'),
          ),
      ],
      if (players.isNotEmpty) ...[
        header(Icons.person_outline_rounded, 'Players'),
        for (final u in players)
          ListTile(
            dense: true,
            leading: ClipOval(
              child: Crest(
                  logoUrl: parseStr(u['avatarUrl']),
                  label: parseStr(u['displayName']) ?? 'P',
                  size: 32),
            ),
            title: Text(parseStr(u['displayName']) ?? 'Player',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink, fontSize: 14)),
            subtitle: parseStr(u['username']) != null
                ? Text('@${parseStr(u['username'])}',
                    style: TextStyle(color: p.muted, fontSize: 11.5))
                : null,
            onTap: () => context.push('/players/${parseStr(u['userId'])}'),
          ),
      ],
      const SizedBox(height: 24),
    ]);
  }

  // ── Event grid ────────────────────────────────────────────────────────────

  Widget _grid(AppPalette p) {
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 10),
            SpButton(label: 'Retry', onTap: () => _loadMore(reset: true)),
          ]),
        ),
      );
    }
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _locationFilter
                ? 'No events in this area — widen the radius or clear the location filter.'
                : (_categoryId != null || _liveOnly || _tournamentsOnly)
                    ? 'No events match these filters right now.'
                    : 'No upcoming events right now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadMore(reset: true),
      child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.88,
        ),
        itemCount: _items.length + (_nextCursor != null ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final e = _items[i];
          return Column(children: [
            Expanded(child: EventTileSquare(event: e)),
            if (e.distanceMiles != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${e.distanceMiles} mi away',
                    style: TextStyle(color: p.muted, fontSize: 9.5)),
              ),
          ]);
        },
      ),
    );
  }
}
