import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/features/ads/ad_anchor.dart';
import 'package:sportpadi_mobile/core/location/location_provider.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/ads/ads_repository.dart'
    show servedSlotsProvider;
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/features/ads/ad_display.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/event_tile.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Browse — the search bar (tapping it opens the search page,
/// browse_search_screen.dart: recent searches + network results), the
/// "find your event" location filter, and an infinite-scroll 2-column grid of
/// event tiles (2026 design): cover, sport, status, then title, when, group.
/// Web /discover twin.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key});
  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  final _scroll = ScrollController();

  // Grid state
  final List<EventSummary> _items = [];
  int? _nextCursor = 0;
  bool _loading = false;
  // Bumped by each reset, so a page still in flight from before it (a
  // scroll's loadMore, an older filter) is dropped instead of appended.
  int _gen = 0;
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
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore({bool reset = false}) async {
    // A reset (pull, filter change) always goes ahead and supersedes
    // whatever is loading.
    if (_loading && !reset) return;
    if (reset) {
      _nextCursor = 0;
    }
    final cursor = _nextCursor;
    if (cursor == null) return;
    final gen = reset ? ++_gen : _gen;
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
      if (!mounted || gen != _gen) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _nextCursor = page.nextCursor;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loading = false;
        if (reset) _error = '$e';
      });
    }
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
              Text(l10n.browse_findYourEvent,
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
                  child: Text(l10n.browse_clear,
                      style: TextStyle(color: p.danger, fontSize: 12.5)),
                ),
            ]),
            const SizedBox(height: 12),
            if (loc.location == null) ...[
              SpButton(
                label: loc.loading ? l10n.browse_locating : l10n.browse_useMyLocation,
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
                  child: Text(l10n.browse_eventsWithin,
                      style: TextStyle(color: p.muted, fontSize: 12.5)),
                ),
                Text(l10n.browse_miles2(loc.radiusMiles),
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
                label: l10n.browse_showEventsNearMe,
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
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Bottom-nav tab, not a pushed page: a big title, no back button.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Text(context.l10n.browse_browse,
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
          _filterChips(p),
          // Sponsored (zero-height when no ads). Must live in the Column,
          // not a Row: a Row gives it unbounded width and the frame can't
          // lay out.
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: AdDisplay(slots: ['home_ads'], carousel: true),
          ),
          Expanded(child: _list(p)),
        ]),
      ),
    );
  }

  /// Looks like a search field; tapping it opens the search page (its own
  /// screen with a back button and your recent searches — Instagram /
  /// TikTok style).
  Widget _searchField(AppPalette p) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hint = context.l10n.browse_searchGroupsPlayersEvents;
    return Semantics(
      button: true,
      label: hint,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => context.push('/search'),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: dark ? Border.all(color: p.line) : null,
              boxShadow: cardShadow(context),
            ),
            child: Row(children: [
              Icon(Icons.search_rounded, size: 21, color: p.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 14.5)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// One filter pill. Active = ink pill, like the rest of the app.
  Widget _chip(AppPalette p, String label, bool active, VoidCallback onTap,
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

  /// Near me (opens the finder), sport chips (All + active sports) and the
  /// Live / Tournaments toggles.
  Widget _filterChips(AppPalette p) {
    final sports = ref.watch(browseCategoriesProvider).valueOrNull ?? const [];
    final loc = ref.watch(locationProvider);

    Widget chip(String label, bool active, VoidCallback onTap,
            {IconData? icon, Color? iconColor}) =>
        _chip(p, label, active, onTap, icon: icon, iconColor: iconColor);

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
          chip(near ? context.l10n.browse_nearMeMi2(loc.radiusMiles) : context.l10n.browse_nearMe, near,
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
          chip(context.l10n.browse_live, _liveOnly, () => apply(() => _liveOnly = !_liveOnly),
              icon: Icons.circle, iconColor: const Color(0xFFE02424)),
          chip(context.l10n.browse_tournaments, _tournamentsOnly,
              () => apply(() => _tournamentsOnly = !_tournamentsOnly),
              icon: Icons.emoji_events_outlined,
              iconColor: _tournamentsOnly ? p.onHero : p.orange),
        ],
      ),
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
            if (body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(body,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: p.muted, fontSize: 12.5, height: 1.45)),
            ],
            if (action != null) ...[const SizedBox(height: 14), action],
          ]),
        ),
      );

  // ── Event list ────────────────────────────────────────────────────────────

  /// Pull to refresh: the grid from its first page, plus the sport chips
  /// and the sponsored strip above it.
  Future<void> _refresh() {
    ref.invalidate(browseCategoriesProvider);
    ref.invalidate(servedSlotsProvider('home_ads'));
    return settleAll([
      _loadMore(reset: true),
      ref.read(browseCategoriesProvider.future),
    ]);
  }

  /// Pullable in every state: error, first load, empty and the grid.
  Widget _list(AppPalette p) =>
      RefreshIndicator(onRefresh: _refresh, child: _listBody(p));

  Widget _listBody(AppPalette p) {
    if (_error != null && _items.isEmpty) {
      return PullableState(
          child: _emptyState(
              p, Icons.wifi_off_rounded, context.l10n.browse_couldntLoadEvents, _error!,
              action: SpButton(
                  label: context.l10n.browse_retry, onTap: () => _loadMore(reset: true))));
    }
    if (_items.isEmpty && _loading) {
      return const PullableState(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return PullableState(
          child: _emptyState(
        p,
        Icons.travel_explore_rounded,
        context.l10n.browse_noEventsHereYet,
        _locationFilter
            ? context.l10n.browse_nothingInThisAreaWiden
            : (_categoryId != null || _liveOnly || _tournamentsOnly)
                ? context.l10n.browse_noEventsMatchTheseFilters
                : context.l10n.browse_noUpcomingEventsRightNow,
      ));
    }

    // The grid is cut into runs of tiles with a full-width ad between runs,
    // where the owner console put one (anchor "discover.events": AdMob
    // native or a SportPadi slot, first after N tiles, every M, max K —
    // nothing at all unless it's set). Slivers rather than one
    // GridView.builder because a fixed-column grid can't host a cell that
    // spans both columns. Tile indexes are rounded to a row boundary so an
    // ad never splits a row of two.
    final ads = AdInterleave.of(ref, 'discover.events', _items.length,
        hasMore: _nextCursor != null,
        padding: const EdgeInsets.symmetric(vertical: 12));
    final cuts = <int>[0];
    for (var i = 0; i < _items.length; i++) {
      if (ads.after(i) != null) {
        final rowEnd = i.isOdd ? i + 1 : i + 2; // end of this row of two
        if (rowEnd < _items.length && rowEnd > cuts.last) cuts.add(rowEnd);
      }
    }
    cuts.add(_items.length);
    final slivers = <Widget>[];
    for (var c = 0; c + 1 < cuts.length; c++) {
      final start = cuts[c];
      final run = _items.sublist(start, cuts[c + 1]);
      if (start > 0) {
        // The ad for the gap before this run (position = run number - 1).
        final ad = ads.after(start - 1) ?? ads.after(start - 2);
        if (ad != null) slivers.add(SliverToBoxAdapter(child: ad));
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

    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          sliver: SliverMainAxisGroup(slivers: slivers),
        ),
      ],
    );
  }

  /// Tiles between native ads in the Browse grid.
}
