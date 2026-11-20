import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/data/highlights/highlight_models.dart';
import 'package:sportpadi_mobile/data/highlights/highlights_repository.dart';
import 'package:sportpadi_mobile/features/highlights/highlight_viewer.dart';
import 'package:sportpadi_mobile/features/highlights/highlight_visitor.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';

/// Where a feed was when its tab was last on screen.
class HighlightFeedSnapshot {
  HighlightFeedSnapshot({
    required this.items,
    required this.cursor,
    required this.end,
    required this.index,
    required this.at,
  });
  final List<HighlightItem> items;
  final String? cursor;
  final bool end;
  final int index;

  /// When its first page was fetched.
  final DateTime at;
}

/// The dock doesn't keep a tab alive: leaving Highlights throws the screen
/// away. This remembers each feed (and which one was showing) so a quick
/// look at another tab doesn't lose the viewer's place.
class HighlightFeedMemory {
  /// 0 = Following, 1 = Discover. Discover is where a fresh open lands
  /// (owner, 2026-11-18: like TikTok's "For you", it is where players are
  /// found — each with a Follow button); a tab picked since is kept for as
  /// long as this memory lives (the app session, for this account).
  int tab = 1;
  final Map<String, HighlightFeedSnapshot> feeds = {};

  /// Videos just posted from this phone, by post id → when. The server
  /// publishes an app video at once and checks the file afterwards: within
  /// about a minute it may take the post down, or move the file to a new
  /// address (docs/wiki/highlights.md). Each is therefore read again a
  /// little later — twice (`_HighlightFeedState._settle`). Kept here so the
  /// reads still happen when the person looked at another tab meanwhile.
  final Map<String, DateTime> unsettled = {};

  /// The posts in [unsettled] that have had the first of those two reads.
  final Set<String> settledOnce = {};

  /// How many times each feed was forgotten from OUTSIDE the Highlights tab
  /// ([forgetFromOutside]). A feed remembers the count it was built under
  /// and saves nothing once it has moved on: were the tab ever kept alive
  /// offstage, its old list would otherwise be written straight back over
  /// the forgetting (review three-fixes LOW-5). The screen keys its feed by
  /// it too, so its next build starts that feed afresh. (Not for a change
  /// made ON the tab — a follow there — where the feed on screen keeps
  /// saving itself and is never reloaded under the viewer's thumb.)
  final Map<String, int> _forgotten = {};
  int forgotten(String tab) => _forgotten[tab] ?? 0;
  void forgetFromOutside(String tab) {
    feeds.remove(tab);
    _forgotten[tab] = forgotten(tab) + 1;
  }

  /// Put a newer copy of a post into every remembered feed.
  void patch(HighlightItem item) {
    for (final snap in feeds.values) {
      final i = snap.items.indexWhere((x) => x.id == item.id);
      if (i >= 0) snap.items[i] = item;
    }
  }

  /// Take a post that is gone out of every remembered feed.
  void drop(String id) {
    for (final snap in feeds.values) {
      snap.items.removeWhere((x) => x.id == id);
    }
  }
}

/// Bumped to put an already-built Highlights tab on DISCOVER ("Keep watching"
/// at the end of a reel; review context-reels-app.md nit): `memory.tab` alone
/// only decides the tab a NEW screen opens on.
final highlightShowDiscover = ValueNotifier<int>(0);

final highlightFeedMemoryProvider = Provider<HighlightFeedMemory>((ref) {
  // A different account must never be shown the last one's feed — nor a
  // visitor one read with a token, or the other way round (the id alone is
  // null for both an unchecked session and a visitor: review L1).
  watchHighlightsAudience(ref);
  return HighlightFeedMemory();
});

/// The Highlights tab (docs/wiki/highlights.md): Following and Discover —
/// Discover selected when it opens, the order on screen kept Following |
/// Discover as on TikTok — one post per screen, and "+" to post. In both
/// shells: a signed-out visitor (the guest dock, 2026-11-19) gets Discover
/// alone — Following needs someone to follow from, and the server answers it
/// 401 — under the server's visitor rule, and "+" asks them to sign up
/// (`highlight_visitor.dart`).
class HighlightsScreen extends ConsumerStatefulWidget {
  const HighlightsScreen({super.key});

  @override
  ConsumerState<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends ConsumerState<HighlightsScreen> {
  static const _tabs = ['following', 'discover'];
  late int _tab;

  /// Bumped to rebuild the showing feed from its first page.
  int _reload = 0;

  @override
  void initState() {
    super.initState();
    final remembered = ref.read(highlightFeedMemoryProvider).tab;
    _tab = remembered == 0 && !ref.read(highlightVisitorProvider) ? 0 : 1;
    highlightShowDiscover.addListener(_showDiscover);
  }

  @override
  void dispose() {
    highlightShowDiscover.removeListener(_showDiscover);
    super.dispose();
  }

  void _showDiscover() {
    if (mounted) _select(1);
  }

  void _select(int tab) {
    if (tab == _tab) return;
    ref.read(highlightFeedMemoryProvider).tab = tab;
    setState(() => _tab = tab);
  }

  Future<void> _create() async {
    if (ref.read(highlightVisitorProvider)) {
      // Straight on to the composer once they are in.
      return showHighlightSignUpPrompt(context,
          action: HighlightVisitorAction.post, returnTo: '/highlights/new');
    }
    final created = await context.push<HighlightItem>('/highlights/new');
    if (created == null || !mounted) return;
    // My own posts are part of Following: show it from the top, where the
    // new one now is.
    final memory = ref.read(highlightFeedMemoryProvider);
    memory.feeds.remove(_tabs[0]);
    memory.tab = 0;
    // Its file is checked by the server after it went out: read it again
    // a minute later, and once more a few minutes on (_settle).
    if (created.isVideo && created.source == 'app') {
      memory.unsettled[created.id] = DateTime.now();
    }
    setState(() {
      _tab = 0;
      _reload++;
    });
  }

  Widget _tabLabel(int tab, String label, {required int current}) {
    // [current] is the tab SHOWN — a visitor's is Discover whatever [_tab]
    // says (review L1: a screen that became a visitor's on tab 0 lit nothing).
    final active = tab == current;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(tab),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  color: active ? Colors.white : const Color(0xB3FFFFFF),
                  fontSize: 15.5,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  shadows: const [
                    Shadow(color: Color(0x99000000), blurRadius: 6)
                  ])),
          const SizedBox(height: 4),
          Container(
            width: 22,
            height: 3,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final memory = ref.watch(highlightFeedMemoryProvider);
    final visitor = ref.watch(highlightVisitorProvider);
    // A visitor has no Following: Discover whatever was picked before.
    final tab = visitor ? 1 : _tab;
    final l = context.l10n;
    final top = MediaQuery.paddingOf(context).top;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The feed is dark whatever the theme: light status-bar icons. The
      // tab ends ABOVE the dock's band of page colour (the shell does not
      // extend its body behind the dock), so the Android navigation bar
      // keeps app.dart's colour, the band's own.
      value: SystemUiOverlayStyle.light,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(children: [
          // The video fills the tab, which already ends above the dock's
          // band: the pill never covers the picture, and there is nothing of
          // the dock to leave room for in here.
          Positioned.fill(
            child: HighlightFeed(
              key: ValueKey('${_tabs[tab]}-$_reload-${visitor ? 'v' : 'm'}'
                  '-${memory.forgotten(_tabs[tab])}'),
              tab: _tabs[tab],
              memory: memory,
              topInset: top + 52,
              onDiscover: tab == 0 ? () => _select(1) : null,
              onCreate: _create,
            ),
          ),
          Positioned(
            top: top + 4,
            left: 8,
            right: 8,
            child: SizedBox(
              height: 44,
              child: Row(children: [
                const SizedBox(width: 44),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!visitor) ...[
                        _tabLabel(0, l.profile_following, current: tab),
                        const SizedBox(width: 8),
                      ],
                      _tabLabel(1, l.menu_discover, current: tab),
                    ],
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Tooltip(
                    message: l.highlights_newPost,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _create,
                      child: const Center(
                        child: Icon(Icons.add_circle_outline_rounded,
                            color: Colors.white,
                            size: 30,
                            shadows: [
                              Shadow(color: Color(0x99000000), blurRadius: 6)
                            ]),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// One feed (`following` or `discover`): pages itself, and hands the posts
/// to the viewer.
class HighlightFeed extends ConsumerStatefulWidget {
  const HighlightFeed({
    super.key,
    required this.tab,
    required this.memory,
    required this.topInset,
    this.onDiscover,
    this.onCreate,
  });

  final String tab;
  final HighlightFeedMemory memory;

  /// Height of the tab bar drawn over the feed.
  final double topInset;

  /// Following only: "look in Discover" from its empty state.
  final VoidCallback? onDiscover;
  final VoidCallback? onCreate;

  @override
  ConsumerState<HighlightFeed> createState() => _HighlightFeedState();
}

class _HighlightFeedState extends ConsumerState<HighlightFeed> {
  /// How long a remembered feed is shown again before it is fetched afresh.
  static const _freshFor = Duration(minutes: 10);

  /// See [_settle].
  static const _settleAfter = Duration(seconds: 60);
  static const _settleAgainAfter = Duration(minutes: 3);
  static const _settleGiveUp = Duration(minutes: 5);
  static const _pollEvery = Duration(seconds: 15);

  final List<HighlightItem> _items = [];
  String? _cursor;
  bool _end = false;
  bool _loading = false;

  /// The server kept answering "nothing on this page, but there is more":
  /// stop asking by ourselves and offer a button.
  bool _stalled = false;
  String? _error;
  DateTime _loadedAt = DateTime.now();

  // Bumped by each reset, so a page still in flight from before is dropped.
  int _gen = 0;
  int _index = 0;

  /// Changes when the list starts over, so the viewer starts over with it.
  int _epoch = 0;

  Timer? _settleTimer;
  bool _settling = false;

  /// When each still-processing post was last read again.
  final Map<String, DateTime> _polled = {};

  /// [HighlightFeedMemory.forgotten] for this feed when it was built.
  late final int _forgottenAt;

  @override
  void initState() {
    super.initState();
    _forgottenAt = widget.memory.forgotten(widget.tab);
    _settleTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _settle());
    final snap = widget.memory.feeds[widget.tab];
    if (snap != null &&
        snap.items.isNotEmpty &&
        DateTime.now().difference(snap.at) < _freshFor) {
      _items.addAll(snap.items);
      _cursor = snap.cursor;
      _end = snap.end;
      _loadedAt = snap.at;
      final last = snap.items.length - 1;
      _index = snap.index < 0 ? 0 : (snap.index > last ? last : snap.index);
    } else {
      _load(reset: true);
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  /// Two kinds of post change by themselves after they were fetched — both
  /// only ever the viewer's own:
  ///
  ///  * a video posted from this phone is checked by the server after it is
  ///    published ([HighlightFeedMemory.unsettled]): it is read again
  ///    [_settleAfter] after posting — it may have failed (the reason is
  ///    then shown on it) or its file may have a new address — and, while
  ///    it still looks fine, once more [_settleAgainAfter] after posting:
  ///    the check shares its worker with web videos and can run late;
  ///  * a web upload stays `processing` until the server has converted it
  ///    (minutes, at worst hours): while this feed is open it is read again
  ///    every [_pollEvery].
  ///
  /// Runs every few seconds and usually finds nothing to do.
  Future<void> _settle() async {
    if (_settling || !mounted) return;
    final memory = widget.memory;
    final now = DateTime.now();
    final due = <String>[];
    for (final e in memory.unsettled.entries) {
      final age = now.difference(e.value);
      if (age >= _settleAgainAfter ||
          (age >= _settleAfter && !memory.settledOnce.contains(e.key))) {
        due.add(e.key);
      }
    }
    for (final item in _items) {
      if (item.status != 'processing' || due.contains(item.id)) continue;
      final last = _polled[item.id];
      if (last == null || now.difference(last) >= _pollEvery) due.add(item.id);
    }
    if (due.isEmpty) return;
    _settling = true;
    final repo = ref.read(highlightsRepositoryProvider);
    try {
      for (final id in due.take(3)) {
        _polled[id] = now;
        final posted = memory.unsettled[id];
        try {
          final fresh = await repo.get(id);
          if (posted == null ||
              !fresh.isReady ||
              now.difference(posted) >= _settleAgainAfter) {
            // The second read — or there is nothing left to wait for.
            memory.unsettled.remove(id);
            memory.settledOnce.remove(id);
          } else {
            memory.settledOnce.add(id);
          }
          memory.patch(fresh);
          if (!mounted) return;
          _replace(fresh);
        } on ApiException catch (e) {
          if (e.statusCode == 404) {
            // Gone: deleted from another device, or taken down.
            memory.unsettled.remove(id);
            memory.settledOnce.remove(id);
            memory.drop(id);
            if (!mounted) return;
            _gone(id);
          } else if (posted != null &&
              now.difference(posted) >= _settleGiveUp) {
            // No connection for minutes: a pull-to-refresh will do the rest.
            memory.unsettled.remove(id);
            memory.settledOnce.remove(id);
          }
        } catch (_) {/* the next round tries again */}
      }
    } finally {
      _settling = false;
    }
  }

  void _remember() {
    // Forgotten from elsewhere since this feed was built: its list is the
    // stale one, and must not be put back.
    if (widget.memory.forgotten(widget.tab) != _forgottenAt) return;
    widget.memory.feeds[widget.tab] = HighlightFeedSnapshot(
      items: List.of(_items),
      cursor: _cursor,
      end: _end,
      index: _index,
      at: _loadedAt,
    );
  }

  Future<void> _load({bool reset = false}) async {
    // A reset (pull to refresh) always goes ahead and supersedes whatever
    // is loading.
    if (_loading && !reset) return;
    if (!reset && _end) return;
    final gen = reset ? ++_gen : _gen;
    setState(() {
      _loading = true;
      _stalled = false;
      if (!reset) _error = null;
    });
    var cursor = reset ? null : _cursor;
    final fresh = <HighlightItem>[];
    var end = false;
    String? error;
    try {
      // The contract: a page may be short — even empty — and still not be
      // the last (posts this viewer may not see were skipped). Keep asking
      // until something arrives or the server says that's all.
      for (var hops = 0; hops < 6; hops++) {
        final page = await ref
            .read(highlightsRepositoryProvider)
            .feed(tab: widget.tab, cursor: cursor);
        if (!mounted || gen != _gen) return;
        fresh.addAll(page.items);
        cursor = page.nextCursor;
        if (cursor == null) {
          end = true;
          break;
        }
        if (fresh.isNotEmpty) break;
      }
    } catch (e) {
      if (!mounted || gen != _gen) return;
      // A cursor the server can no longer open ([isRefusedCursor]): start the
      // list again from the top rather than offer a Retry that sends it back.
      // A reset sends no cursor, so this cannot come round again by itself.
      if (!reset && isRefusedCursor(e, cursor)) {
        setState(() => _loading = false);
        unawaited(_load(reset: true));
        return;
      }
      error = '$e';
    }
    final failed = error;
    final nextCursor = cursor;
    final reachedEnd = end;
    setState(() {
      if (failed == null) {
        if (reset) {
          _items.clear();
          _index = 0;
          _epoch++;
          _loadedAt = DateTime.now();
        }
        final seen = {for (final i in _items) i.id};
        for (final item in fresh) {
          if (item.id.isNotEmpty && seen.add(item.id)) _items.add(item);
        }
        _cursor = nextCursor;
        _end = reachedEnd;
        _stalled = fresh.isEmpty && !reachedEnd;
      }
      _error = failed;
      _loading = false;
    });
    if (failed == null) _remember();
  }

  Future<void> _refresh() async {
    await _load(reset: true);
    if (!mounted) return;
    // With posts on screen a failed refresh would otherwise pass unseen.
    final error = _error;
    if (error != null && _items.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _replace(HighlightItem item) {
    final i = _items.indexWhere((x) => x.id == item.id);
    if (i < 0) return;
    setState(() => _items[i] = item);
    _remember();
  }

  void _remove(String id) {
    setState(() => _items.removeWhere((x) => x.id == id));
    _remember();
    // The viewer may now be sitting on the "loading more" page, and nothing
    // loads without a page change: ask here.
    if (!_end && _index >= _items.length - 3) unawaited(_load());
  }

  /// The post turned out to be gone — deleted from another device, taken
  /// down, or no longer this viewer's to see (the server doesn't say
  /// which). Unlike a delete made here, nobody asked for it: the feed would
  /// otherwise just slide on to the next post, so it says so.
  void _gone(String id) {
    // Before [_remove], which calls setState: a guard after it guards
    // nothing.
    if (!mounted || !_items.any((x) => x.id == id)) return;
    _remove(id);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.highlights_goneToast)));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final error = _error;
    final Widget body;
    if (_items.isEmpty) {
      final Widget state;
      if (_loading) {
        state = const HighlightMessage(busy: true);
      } else if (error != null) {
        state = HighlightMessage(
          icon: Icons.wifi_off_rounded,
          title: l.highlights_couldntLoad,
          body: error,
          actionLabel: l.common_retry,
          onAction: () => _load(reset: true),
        );
      } else if (!_end) {
        state = HighlightMessage(
          icon: Icons.travel_explore_rounded,
          title: l.highlights_noneFoundSoFar,
          actionLabel: l.highlights_keepLooking,
          onAction: _load,
        );
      } else if (widget.tab == 'following') {
        state = HighlightMessage(
          icon: Icons.movie_filter_outlined,
          title: l.highlights_followingEmptyTitle,
          body: l.highlights_followingEmptyBody,
          actionLabel: l.highlights_openDiscover,
          onAction: widget.onDiscover,
        );
      } else {
        state = HighlightMessage(
          icon: Icons.movie_filter_outlined,
          title: l.highlights_discoverEmptyTitle,
          body: l.highlights_discoverEmptyBody,
          actionLabel: l.highlights_newPost,
          onAction: widget.onCreate,
        );
      }
      // No `bottomPadding`, unlike the other tabs' states: this feed
      // already ends above the dock (HighlightsScreen.build).
      body = PullableState(child: state);
    } else {
      Widget? trailing;
      if (!_end) {
        trailing = error != null
            ? HighlightMessage(
                icon: Icons.wifi_off_rounded,
                title: l.highlights_couldntLoadMore,
                body: error,
                actionLabel: l.common_retry,
                onAction: _load,
              )
            : _stalled && !_loading
                ? HighlightMessage(
                    icon: Icons.travel_explore_rounded,
                    title: l.highlights_noneFoundSoFar,
                    actionLabel: l.highlights_keepLooking,
                    onAction: _load,
                  )
                : const HighlightMessage(busy: true);
      }
      body = HighlightPager(
        key: ValueKey(_epoch),
        items: _items,
        initialIndex: _index,
        trailing: trailing,
        onNearEnd: _load,
        onChanged: _replace,
        onRemoved: _remove,
        onGone: _gone,
        onIndexChanged: (i) {
          _index = i;
          _remember();
        },
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      // Below the tab bar drawn over the feed.
      edgeOffset: widget.topInset,
      child: body,
    );
  }
}
