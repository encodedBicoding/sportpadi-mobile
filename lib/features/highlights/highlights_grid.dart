import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/highlights/highlight_models.dart';
import 'package:sportpadi_mobile/data/highlights/highlights_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Bumped by a profile's pull-to-refresh ([reloadHighlightGrids]).
final _gridsReload = ValueNotifier<int>(0);

/// Re-read every highlights grid on screen. A grid pages with its own
/// state, so the profile it sits on can't refresh it through a provider.
void reloadHighlightGrids() => _gridsReload.value++;

/// A player's highlights as a grid of thumbnails (posts ABOUT them), on the
/// public profile and on your own. A tile opens the post as this PLAYER'S
/// reel (`?from=player:<id>`, the web's `playerReelHref`; workspace
/// `docs/wiki/highlights.md`, "Where a highlight was opened from"):
/// scrolling on shows the rest of this grid, and the end pops back here,
/// handing back the tile it was opened from.
///
/// It sits inside the profile's own scroll view, so it doesn't scroll
/// itself: more are fetched with "Show more".
class HighlightsGrid extends ConsumerStatefulWidget {
  const HighlightsGrid({super.key, required this.userId, this.mine = false});
  final String userId;

  /// Your own profile: the empty state invites you to post.
  final bool mine;

  @override
  ConsumerState<HighlightsGrid> createState() => _HighlightsGridState();
}

class _HighlightsGridState extends ConsumerState<HighlightsGrid> {
  final List<HighlightItem> _items = [];
  String? _cursor;
  bool _end = false;
  bool _loading = false;
  String? _error;
  // Bumped by each reset, so a page still in flight from before is dropped.
  int _gen = 0;

  /// One key per tile, so a reel coming back can find the tile it opened.
  final _tileKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    highlightsChanged.addListener(_onChanged);
    _gridsReload.addListener(_onChanged);
    _load(reset: true);
  }

  @override
  void didUpdateWidget(HighlightsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      // After this build: loading starts with a setState.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(reset: true);
      });
    }
  }

  @override
  void dispose() {
    highlightsChanged.removeListener(_onChanged);
    _gridsReload.removeListener(_onChanged);
    super.dispose();
  }

  // A post was made, deleted or re-linked somewhere in the app — or the
  // profile around this grid was pulled to refresh.
  void _onChanged() {
    if (mounted) _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (widget.userId.isEmpty) {
      // No one to show (a profile without an id): simply empty.
      _end = true;
      return;
    }
    if (_loading && !reset) return;
    if (!reset && _end) return;
    final gen = reset ? ++_gen : _gen;
    setState(() {
      _loading = true;
      _error = null;
    });
    var cursor = reset ? null : _cursor;
    final fresh = <HighlightItem>[];
    var end = false;
    String? error;
    try {
      // A short or empty page isn't the end while there is a cursor.
      for (var hops = 0; hops < 5; hops++) {
        final page = await ref
            .read(highlightsRepositoryProvider)
            .byPlayer(widget.userId, cursor: cursor);
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
        _load(reset: true);
        return;
      }
      error = '$e';
    }
    final failed = error;
    final nextCursor = cursor;
    final reachedEnd = end;
    setState(() {
      if (failed == null) {
        if (reset) _items.clear();
        final seen = {for (final i in _items) i.id};
        for (final item in fresh) {
          if (item.id.isNotEmpty && seen.add(item.id)) _items.add(item);
        }
        _cursor = nextCursor;
        _end = reachedEnd;
      }
      _error = failed;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l = context.l10n;
    final error = _error;

    if (_items.isEmpty) {
      if (_loading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return GlassCard(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(children: [
          SpIconTile(Icons.movie_filter_outlined,
              bg: p.surface2, fg: p.muted, size: 52, iconSize: 24),
          const SizedBox(height: 6),
          Text(
            error ??
                (!_end
                    ? l.highlights_noneFoundSoFar
                    : widget.mine
                        ? l.highlights_gridEmptyMine
                        : l.profile_noHighlightsYet),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
          ),
          if (error != null)
            TextButton(
                onPressed: () => _load(reset: true),
                child: Text(l.common_retry))
          else if (!_end)
            TextButton(
                onPressed: _load, child: Text(l.highlights_keepLooking)),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 3 / 4,
          children: [for (final item in _items) _tile(p, item)],
        ),
        if (!_end)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: _load,
                      child: Text(error ?? l.profile_showMore)),
            ),
          ),
      ],
    );
  }

  /// Open a tile as this player's reel, and come back to it. The pop hands
  /// back the tile's id; an exit that doesn't go through the reel's own way
  /// out (the iOS swipe, predictive back) hands back nothing, and the tile is
  /// then the one opened — never unknown, as on the match timeline.
  Future<void> _open(HighlightItem item) async {
    final back = await context.push<String>(Uri(
        path: '/highlights/${item.id}',
        queryParameters: {'from': 'player:${widget.userId}'}).toString());
    if (!mounted) return;
    _bringIntoViewWhenBack(back ?? item.id, 0);
  }

  /// The push's future completes INSIDE the pop, before the profile is laid
  /// out again (review context-reels-app.md LOW-1): measured then, the tile's
  /// place is the one from before the reel. So wait for frames until this
  /// route is the current one again and one more has laid it out (a grid
  /// that re-read itself meanwhile has rebuilt by then too), then bring it
  /// into view.
  void _bringIntoViewWhenBack(String id, int frames) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ModalRoute.of(context)?.isCurrent ?? true;
      if (!current || frames < 1) {
        // Out of frames with the profile still not on top (something else was
        // pushed over it): give up rather than scroll a page nobody sees
        // (review context-reels-app.md MED-R1).
        if (frames >= 60) return;
        WidgetsBinding.instance.scheduleFrame();
        _bringIntoViewWhenBack(id, frames + 1);
        return;
      }
      _bringIntoView(id);
    });
  }

  /// Where the profile's pinned tab band ends, from the top of the SCREEN: the
  /// status bar plus `SpPinnedTabsScrollView`'s copy of the track (about 58).
  double get _pinnedBand => MediaQuery.paddingOf(context).top + 64;

  /// The profile kept its offset across the reel, so the tile is usually
  /// still on screen and nothing moves; a grid that re-read itself meanwhile
  /// (a post deleted or posted in the reel) can have moved it — then only as
  /// far as needed to show it whole, BELOW the pinned tab band, or above the
  /// bottom of the profile's scroll view. Cheap: a tile not loaded is not
  /// paged in.
  ///
  /// The scroll view moved is the PROFILE's — the nearest one above this
  /// grid, looked up from this State's own context, which sits OUTSIDE the
  /// grid's own (shrink-wrapped, never-scrolling) `GridView`; looking it up
  /// from the tile found that one, whose extent is 0..0, and moved nothing
  /// (MED-R1). Measured in screen coordinates.
  void _bringIntoView(String id) {
    final tile = _tileKeys[id]?.currentContext;
    if (tile == null) return;
    final box = tile.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    if (box is! RenderBox || !box.hasSize || scrollable == null) return;
    final view = scrollable.context.findRenderObject();
    if (view is! RenderBox || !view.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final viewBottom = view.localToGlobal(Offset.zero).dy + view.size.height;
    final position = scrollable.position;
    double delta = 0;
    if (top < _pinnedBand) {
      delta = top - (_pinnedBand + 8);
    } else if (bottom > viewBottom) {
      delta = bottom - viewBottom + 8;
    }
    if (delta == 0) return;
    final to = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    position.animateTo(to,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Widget _tile(AppPalette p, HighlightItem item) {
    var url = item.thumbnailUrl;
    if (url != null && url.startsWith('/')) {
      url = '${ref.read(appConfigProvider).apiBaseUrl}$url';
    }
    final photos = item.isVideo ? 0 : item.media.length;
    return ClipRRect(
      key: _tileKeys.putIfAbsent(item.id, GlobalKey.new),
      borderRadius: BorderRadius.circular(14),
      child: Material(
        color: p.surface2,
        child: InkWell(
          onTap: () => _open(item),
          child: Stack(fit: StackFit.expand, children: [
            if (url != null)
              CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            // What kind of post it is: a clip, or several photos.
            if (item.isVideo || photos > 1)
              Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  item.isVideo
                      ? Icons.play_arrow_rounded
                      : Icons.collections_rounded,
                  size: item.isVideo ? 20 : 16,
                  color: Colors.white,
                  shadows: const [
                    Shadow(color: Color(0x99000000), blurRadius: 6)
                  ],
                ),
              ),
            // Linked to a stat: its emoji, bottom-left.
            if (item.stat?.icon != null)
              Positioned(
                left: 6,
                bottom: 5,
                child: Text(item.stat!.icon!,
                    style: const TextStyle(fontSize: 14)),
              ),
          ]),
        ),
      ),
    );
  }
}
