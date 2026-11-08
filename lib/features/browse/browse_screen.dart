import 'dart:async';

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
import 'package:sportpadi_mobile/data/groups/group_class.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/features/ads/ad_display.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/event_tile.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/verified_badge.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

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
  // Bumped by each reset, so a page still in flight from before it (a
  // scroll's loadMore, an older filter) is dropped instead of appended.
  int _gen = 0;
  bool _locationFilter = false;
  String? _error;

  // Filters: sport (null = All) + quick toggles.
  String? _categoryId;
  bool _liveOnly = false;
  bool _tournamentsOnly = false;

  // Browse groups by type: the picked class (null = the normal Browse) and
  // its groups, paged like the grid and narrowed by the search text.
  String? _groupClass;
  final _classScroll = ScrollController();
  final List<GroupSummary> _classItems = [];
  int? _classCursor = 0;
  bool _classLoading = false;
  bool _classRefreshing = false;
  int _classGen = 0;
  String? _classError;

  @override
  void initState() {
    super.initState();
    _loadMore(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    _classScroll.addListener(() {
      if (_classScroll.position.pixels >
          _classScroll.position.maxScrollExtent - 600) {
        _loadClass();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    _classScroll.dispose();
    super.dispose();
  }

  /// The next page of the picked type's groups (or the first, on [reset]:
  /// a new type, new search text, a pull). Same generation guard as the grid.
  Future<void> _loadClass({bool reset = false}) async {
    final cls = _groupClass;
    if (cls == null) return;
    if (_classLoading && !reset) return;
    if (reset) _classCursor = 0;
    final cursor = _classCursor;
    if (cursor == null) return;
    final gen = reset ? ++_classGen : _classGen;
    setState(() {
      _classLoading = true;
      if (reset) {
        _classRefreshing = true;
        _classError = null;
      }
    });
    final q = _search.text.trim();
    try {
      final page = await ref.read(groupsRepositoryProvider).classifiedGroups(
            classification: cls,
            q: q.isEmpty ? null : q,
            cursor: cursor,
          );
      if (!mounted || gen != _classGen) return;
      setState(() {
        if (reset) _classItems.clear();
        _classItems.addAll(page.items);
        _classCursor = page.nextCursor;
        _classLoading = false;
        _classRefreshing = false;
      });
    } catch (e) {
      if (!mounted || gen != _classGen) return;
      setState(() {
        _classLoading = false;
        _classRefreshing = false;
        if (reset) _classError = '$e';
      });
    }
  }

  /// Pick a type chip; the same one again (or All, [c] null) goes back to
  /// the normal Browse.
  void _pickClass(String? c) {
    final next = c == null || c == _groupClass ? null : c;
    if (next == _groupClass) return;
    setState(() {
      _groupClass = next;
      _classItems.clear();
      _classCursor = 0;
      _classError = null;
      _classLoading = false;
      _classRefreshing = false;
    });
    if (_classScroll.hasClients) _classScroll.jumpTo(0);
    if (next != null) {
      _loadClass(reset: true);
    } else {
      _classGen++; // drop a page still in flight
      // Back to the normal Browse: bring its search results up to date with
      // the text typed while a type was picked.
      if (_search.text.trim().isNotEmpty) _onSearch(_search.text);
    }
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

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      // A type is picked: the text narrows that type's groups instead.
      if (_groupClass != null) {
        if (mounted) _loadClass(reset: true);
        return;
      }
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
    final classMode = _groupClass != null;
    final showResults = !classMode && _search.text.trim().length >= 2;
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
          _classChips(p),
          if (!showResults && !classMode) _filterChips(p),
          // Sponsored (zero-height when no ads). Must live in the Column,
          // not a Row: a Row gives it unbounded width and the frame can't
          // lay out.
          if (!showResults && !classMode)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: AdDisplay(slots: ['home_ads'], carousel: true),
            ),
          Expanded(
            child: classMode
                ? _classList(p)
                : showResults
                    ? _resultsList(p)
                    : _list(p),
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
          hintText: context.l10n.browse_searchGroupsPlayersEvents,
          hintStyle: TextStyle(color: p.muted, fontSize: 14.5),
          prefixIcon: Icon(Icons.search_rounded, size: 21, color: p.muted),
          suffixIcon: _searching || _classRefreshing
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
                        _debounce?.cancel();
                        _search.clear();
                        setState(() => _results = null);
                        if (_groupClass != null) _loadClass(reset: true);
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

  /// "Browse groups by type": All + one chip per type (emoji + plural name).
  /// A picked type swaps the page for that type's groups ([_classList]).
  Widget _classChips(AppPalette p) {
    final t = context.l10n;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 20, 6),
        child: Text(t.group_classBrowseLabel,
            style: TextStyle(
                color: p.muted, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
          children: [
            _chip(p, t.group_classAll, _groupClass == null,
                () => _pickClass(null)),
            for (final c in groupClasses)
              _chip(
                p,
                '${groupClassEmoji[c] ?? ''} ${groupClassChipLabel(t, c)}'
                    .trim(),
                _groupClass == c,
                () => _pickClass(c),
              ),
          ],
        ),
      ),
    ]);
  }

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

  // ── Universal search results ──────────────────────────────────────────────

  Widget _resultsList(AppPalette p) {
    final r = _results;
    if (r == null) {
      return Center(
        child:
            Text(context.l10n.browse_searching, style: TextStyle(color: p.muted, fontSize: 13)),
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
          context.l10n.browse_nothingOnTheNetworkMatches,
          context.l10n.browse_tryAShorterNameOr);
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
          header(context.l10n.browse_events, events.length),
          group([
            for (final e in events)
              row(
                tile(
                    (e['category'] is Map
                            ? parseStr((e['category'] as Map)['emoji'])
                            : null) ??
                        '🏅',
                    tournament: e['isTournament'] == true),
                parseStr(e['title']) ?? context.l10n.browse_event,
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
          header(context.l10n.browse_groups, groups.length),
          group([
            for (final g in groups)
              row(
                Crest(
                    logoUrl: parseStr(g['imageUrl']),
                    label: parseStr(g['name']) ?? 'G',
                    size: 42),
                parseStr(g['name']) ?? context.l10n.browse_group,
                _classLine(parseGroupClass(g['classification'])),
                () => context.push('/groups/${parseStr(g['id'])}'),
              ),
          ]),
        ],
        if (teams.isNotEmpty) ...[
          header(context.l10n.browse_teams, teams.length),
          group([
            for (final t in teams)
              row(
                Crest(
                    logoUrl: parseStr(t['logoUrl']),
                    kitPrimary: parseStr(t['kitPrimary']),
                    kitSecondary: parseStr(t['kitSecondary']),
                    label: parseStr(t['name']) ?? 'T',
                    size: 42),
                parseStr(t['name']) ?? context.l10n.browse_team,
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
          header(context.l10n.browse_players, players.length),
          group([
            for (final u in players)
              row(
                ClipOval(
                  child: Crest(
                      logoUrl: parseStr(u['avatarUrl']),
                      label: parseStr(u['displayName']) ?? 'P',
                      size: 42),
                ),
                parseStr(u['displayName']) ?? context.l10n.browse_player,
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

  // ── Groups by type ────────────────────────────────────────────────────────

  /// "🏫 School" for a group row, or null when the type isn't set.
  String? _classLine(String? code) => code == null
      ? null
      : '${groupClassEmoji[code] ?? ''} ${groupClassName(context.l10n, code)}'
          .trim();

  /// The picked type's groups, biggest first, paged on scroll; each row
  /// opens the group. Pullable in every state.
  Widget _classList(AppPalette p) => RefreshIndicator(
      onRefresh: () => _loadClass(reset: true), child: _classListBody(p));

  Widget _classListBody(AppPalette p) {
    if (_classError != null && _classItems.isEmpty) {
      return PullableState(
          child: _emptyState(p, Icons.wifi_off_rounded, _classError!, '',
              action: SpButton(
                  label: context.l10n.browse_retry,
                  onTap: () => _loadClass(reset: true))));
    }
    if (_classItems.isEmpty && (_classLoading || _classCursor == 0)) {
      return const PullableState(child: CircularProgressIndicator());
    }
    if (_classItems.isEmpty) {
      return PullableState(
          child: _emptyState(p, Icons.groups_outlined,
              context.l10n.group_classEmpty, ''));
    }
    final t = context.l10n;
    return ListView(
      controller: _classScroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(children: [
            for (var i = 0; i < _classItems.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    thickness: 1,
                    indent: 12,
                    endIndent: 12,
                    color: p.surface2),
              _classRow(p, t, _classItems[i]),
            ],
          ]),
        ),
        if (_classCursor != null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
      ],
    );
  }

  Widget _classRow(AppPalette p, AppLocalizations t, GroupSummary g) =>
      InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: g.id.isEmpty ? null : () => context.push('/groups/${g.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(children: [
            Crest(logoUrl: g.logoUrl, label: g.name, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(g.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                      ),
                      if (g.isVerified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 15),
                      ],
                    ]),
                    Text(t.group_classMembers(g.memberCount ?? 0),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ]),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
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
