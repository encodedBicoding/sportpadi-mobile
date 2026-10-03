import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/ads/admob.dart';
import 'package:sportpadi_mobile/core/location/location_provider.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/features/ads/ad_display.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/event_tile.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// Browse — universal network search (events, groups, players, teams), the
/// "find your event" location filter, and an infinite-scroll 2-column grid of
/// event tiles (2026 design): cover, sport, status, then title, when, group.
/// Web /discover twin.
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
    await showSpSheet<void>(
      context,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final p = ctx.palette;
        final loc = ref.watch(locationProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: p.accentTint,
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.place_outlined, size: 20, color: p.greenText),
              ),
              const SizedBox(width: 12),
              Text('Find your event',
                  style: TextStyle(
                      color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
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
                onChanged: (v) =>
                    ref.read(locationProvider.notifier).setRadius(v.round()),
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
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final showResults = _search.text.trim().length >= 2;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Bottom-nav tab, not a pushed page: a big title, no back button.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Text('Browse',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _searchField(p),
          ),
          if (!showResults) _filterChips(p),
          // Sponsored (zero-height when no ads). Must live in the Column,
          // not a Row: a Row gives it unbounded width and the frame can't
          // lay out.
          if (!showResults)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: AdDisplay(slots: ['home_ads'], carousel: true),
            ),
          Expanded(
            child: showResults ? _resultsList(p) : _list(p),
          ),
        ]),
      ),
    );
  }

  Widget _searchField(AppPalette p) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        border: dark ? Border.all(color: p.line) : null,
        boxShadow: cardShadow(context),
      ),
      alignment: Alignment.center,
      child: TextField(
        controller: _search,
        onChanged: (v) {
          setState(() {});
          _onSearch(v);
        },
        textInputAction: TextInputAction.search,
        style: TextStyle(color: p.ink, fontSize: 14.5),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search groups, players, events…',
          hintStyle: TextStyle(color: p.muted, fontSize: 14.5),
          prefixIcon: Icon(Icons.search_rounded, size: 21, color: p.muted),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(15),
                  child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : _search.text.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() => _results = null);
                      },
                      icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
                    )
                  : null,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }

  /// Near me (opens the finder), sport chips (All + active sports) and the
  /// Live / Tournaments toggles. Active = ink pill, like the rest of the app.
  Widget _filterChips(AppPalette p) {
    final sports = ref.watch(browseCategoriesProvider).valueOrNull ?? const [];
    final loc = ref.watch(locationProvider);

    Widget chip(String label, bool active, VoidCallback onTap,
            {IconData? icon, Color? iconColor}) =>
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: active ? p.hero : p.surface,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: onTap,
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: active ? null : Border.all(color: p.line),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[
                    Icon(icon,
                        size: icon == Icons.circle ? 9 : 15,
                        color: iconColor ?? (active ? p.onHero : p.muted)),
                    const SizedBox(width: 6),
                  ],
                  Text(label,
                      style: TextStyle(
                          color: active ? p.onHero : p.ink,
                          fontSize: 12.5,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w600)),
                ]),
              ),
            ),
          ),
        );

    void apply(VoidCallback change) {
      setState(change);
      _loadMore(reset: true);
    }

    final near = _locationFilter && loc.location != null;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
        children: [
          chip(near ? 'Near me · ${loc.radiusMiles} mi' : 'Near me', near,
              _openFinder,
              icon: Icons.place_outlined,
              iconColor: near ? const Color(0xFF6EDC9E) : null),
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
            margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
            color: p.line,
          ),
          chip('Live', _liveOnly, () => apply(() => _liveOnly = !_liveOnly),
              icon: Icons.circle, iconColor: const Color(0xFFE02424)),
          chip('Tournaments', _tournamentsOnly,
              () => apply(() => _tournamentsOnly = !_tournamentsOnly),
              icon: Icons.emoji_events_outlined,
              iconColor: _tournamentsOnly ? p.onHero : p.orange),
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
      return _emptyState(
          p,
          Icons.search_off_rounded,
          'Nothing on the network matches that.',
          'Try a shorter name or a username.');
    }

    Widget header(String label, int n) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
          child: Row(children: [
            Text(label,
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: p.surface2, borderRadius: BorderRadius.circular(999)),
              child: Text('$n',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        );

    Widget group(List<Widget> rows) => GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    thickness: 1,
                    indent: 12,
                    endIndent: 12,
                    color: p.surface2),
              rows[i],
            ],
          ]),
        );

    Widget row(Widget lead, String title, String? sub, VoidCallback onTap) =>
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(children: [
              lead,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700)),
                      if (sub != null && sub.isNotEmpty)
                        Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.muted, fontSize: 12)),
                    ]),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
            ]),
          ),
        );

    Widget tile(String text, {bool tournament = false}) => Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tournament ? p.orangeTint : p.accentTint,
            borderRadius: BorderRadius.circular(14),
          ),
          child: tournament
              ? Icon(Icons.emoji_events_outlined, size: 20, color: p.orangeInk)
              : Text(text, style: const TextStyle(fontSize: 19)),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        if (events.isNotEmpty) ...[
          header('Events', events.length),
          group([
            for (final e in events)
              row(
                tile(
                    (e['category'] is Map
                            ? parseStr((e['category'] as Map)['emoji'])
                            : null) ??
                        '🏅',
                    tournament: e['isTournament'] == true),
                parseStr(e['title']) ?? 'Event',
                [
                  formatDay(e['eventDate']),
                  if (e['isTournament'] == true) 'Tournament',
                ].join(' · '),
                () {
                  final id = parseStr(e['id']);
                  if (e['isTournament'] == true && id != null) {
                    context.push('/tournaments/$id');
                  } else {
                    context.push('/events/${parseStr(e['slug']) ?? id}');
                  }
                },
              ),
          ]),
        ],
        if (groups.isNotEmpty) ...[
          header('Groups', groups.length),
          group([
            for (final g in groups)
              row(
                Crest(
                    logoUrl: parseStr(g['imageUrl']),
                    label: parseStr(g['name']) ?? 'G',
                    size: 42),
                parseStr(g['name']) ?? 'Group',
                null,
                () => context.push('/groups/${parseStr(g['id'])}'),
              ),
          ]),
        ],
        if (teams.isNotEmpty) ...[
          header('Teams', teams.length),
          group([
            for (final t in teams)
              row(
                Crest(
                    logoUrl: parseStr(t['logoUrl']),
                    kitPrimary: parseStr(t['kitPrimary']),
                    kitSecondary: parseStr(t['kitSecondary']),
                    label: parseStr(t['name']) ?? 'T',
                    size: 42),
                parseStr(t['name']) ?? 'Team',
                [
                  if (parseStr(t['username']) != null)
                    '@${parseStr(t['username'])}',
                  if (parseStr(t['groupName']) != null)
                    parseStr(t['groupName'])!,
                ].join(' · '),
                () => context.push('/teams/${parseStr(t['id'])}'),
              ),
          ]),
        ],
        if (players.isNotEmpty) ...[
          header('Players', players.length),
          group([
            for (final u in players)
              row(
                ClipOval(
                  child: Crest(
                      logoUrl: parseStr(u['avatarUrl']),
                      label: parseStr(u['displayName']) ?? 'P',
                      size: 42),
                ),
                parseStr(u['displayName']) ?? 'Player',
                parseStr(u['username']) != null
                    ? '@${parseStr(u['username'])}'
                    : null,
                () => context.push('/players/${parseStr(u['userId'])}'),
              ),
          ]),
        ],
      ],
    );
  }

  Widget _emptyState(AppPalette p, IconData icon, String title, String body,
          {Widget? action}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: p.surface2, borderRadius: BorderRadius.circular(20)),
              child: Icon(icon, color: p.muted, size: 26),
            ),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: p.ink, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.45)),
            if (action != null) ...[const SizedBox(height: 14), action],
          ]),
        ),
      );

  // ── Event list ────────────────────────────────────────────────────────────

  Widget _list(AppPalette p) {
    if (_error != null && _items.isEmpty) {
      return _emptyState(
          p, Icons.wifi_off_rounded, 'Couldn\'t load events', _error!,
          action:
              SpButton(label: 'Retry', onTap: () => _loadMore(reset: true)));
    }
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return _emptyState(
        p,
        Icons.travel_explore_rounded,
        'No events here yet',
        _locationFilter
            ? 'Nothing in this area — widen the radius or clear the location filter.'
            : (_categoryId != null || _liveOnly || _tournamentsOnly)
                ? 'No events match these filters right now.'
                : 'No upcoming events right now.',
      );
    }

    // The grid is cut into runs of [_adEvery] tiles with a full-width AdMob
    // native card between runs (Android only; on iOS the card is empty and
    // the runs simply abut). Slivers rather than one GridView.builder because
    // a fixed-column grid can't host a cell that spans both columns.
    final slivers = <Widget>[];
    for (var start = 0; start < _items.length; start += _adEvery) {
      final run =
          _items.sublist(start, (start + _adEvery).clamp(0, _items.length));
      if (start > 0) {
        slivers.add(SliverToBoxAdapter(
          child: AdMobNativeCard(
            // Keyed by position so a longer list doesn't hand a recycled
            // (disposed) ad to a new slot.
            key: ValueKey('browse-ad-$start'),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ));
      }
      // Rows of two; each card is as tall as its own content.
      slivers.add(SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, r) => Padding(
            padding: EdgeInsets.only(top: r == 0 ? 0 : 12),
            child: EventTileRow(
              left: run[r * 2],
              right: r * 2 + 1 < run.length ? run[r * 2 + 1] : null,
            ),
          ),
          childCount: (run.length + 1) ~/ 2,
        ),
      ));
    }
    if (_nextCursor != null) {
      slivers.add(const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      ));
    }

    return RefreshIndicator(
      onRefresh: () => _loadMore(reset: true),
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            sliver: SliverMainAxisGroup(slivers: slivers),
          ),
        ],
      ),
    );
  }

  /// Tiles between native ads in the Browse grid.
  static const _adEvery = 8;
}
