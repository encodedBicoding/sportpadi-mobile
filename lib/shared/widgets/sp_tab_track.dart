import 'package:flutter/gestures.dart' show Drag;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerPhase;

import 'package:sportpadi_mobile/core/theme/app_colors.dart';

/// A page that scrolls as ONE [CustomScrollView] — [header] slivers, then the
/// [track] (an [SpTabTrack]) on a band of page colour, then [body] slivers —
/// with the track pinned once it reaches the top, as the group page pins its
/// tabs. Used by the two profiles (`profile_screen.dart`,
/// `player_profile_screen.dart`).
///
/// Why not a pinned `SliverPersistentHeader`, as the group page has: a pinned
/// header sticks to the top of the SCROLL VIEW, and on the profiles that is
/// the top of the screen — their dark cover runs up under the status bar, so
/// there is no SafeArea to stop it — which would park the tabs under the
/// clock. Here the track stays in the flow, and once its top passes the
/// status bar's edge a second copy is shown over the page just below the
/// status bar, on a band of page colour that covers the status bar too. Both
/// copies drive the same [TabController], so the switch is one switch.
/// Pinned is decided from the scroll offset as it changes (the same frame),
/// against where the track was last measured; a vertical drag on the pinned
/// copy scrolls the page.
class SpPinnedTabsScrollView extends StatefulWidget {
  const SpPinnedTabsScrollView({
    super.key,
    required this.header,
    required this.track,
    required this.body,
  });

  final List<Widget> header;
  final Widget track;
  final List<Widget> body;

  @override
  State<SpPinnedTabsScrollView> createState() => _SpPinnedTabsScrollViewState();

  /// Scrolls the page [context] sits in (a header widget's own context) so
  /// the tab switch is at its pinned place under the status bar — the
  /// profiles' highlights count, after it selects the Highlights tab.
  /// Waits a frame, so the new tab's content (and the page's length) is in.
  static void revealTabs(BuildContext context) {
    final state = context.findAncestorStateOfType<_SpPinnedTabsScrollViewState>();
    state?._revealTabs();
  }
}

class _SpPinnedTabsScrollViewState extends State<SpPinnedTabsScrollView> {
  final _trackKey = GlobalKey();
  final _scroll = ScrollController();
  bool _pinned = false;
  bool _checkQueued = false;

  /// The status bar's height, as of the last build.
  double _inset = 0;

  /// Where the track's top sits in the scroll view's content (its top on
  /// screen + the scroll offset), from the last measure; null until then.
  double? _trackAt;

  /// A drag that started on the pinned copy, handed to the scroll view.
  ScrollHoldController? _hold;
  Drag? _drag;

  /// Room above and below the track on its band, and either side of it —
  /// the group page's band (`EdgeInsets.fromLTRB(20, 6, 20, 6)` around the
  /// 46 track).
  static const double _pad = 6;
  static const double _side = 20;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScrolled);
  }

  @override
  void dispose() {
    // The scroll view's position (and with it any drag on it) is disposed
    // with the scroll view itself.
    _hold = null;
    _drag = null;
    _scroll.dispose();
    super.dispose();
  }

  /// Pinned or not, straight from the offset — the listener runs when the
  /// offset changes, before that frame is laid out, so the copy shows in the
  /// same frame the track reaches the status bar (no frame of it under the
  /// clock on a fling).
  void _onScrolled() {
    final at = _trackAt;
    if (at == null || !_scroll.hasClients) return;
    final pinned = _scroll.offset > at - _inset;
    if (pinned == _pinned) return;
    // Never a setState from inside a build or layout; measure after it.
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      _queueCheck();
      return;
    }
    setState(() => _pinned = pinned);
  }

  /// Measures once the frame is laid out — for changes the offset doesn't
  /// show: a card above the track that loads or goes away, a rebuild.
  /// Asks for that frame too: a re-measure queued from a post-frame
  /// notification would otherwise wait for an unrelated one, with both
  /// copies on screen meanwhile.
  void _queueCheck() {
    if (_checkQueued) return;
    _checkQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      _check();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _revealTabs() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _check();
      final at = _trackAt;
      if (at == null) return;
      final pos = _scroll.position;
      final target = (at - _inset)
          .clamp(pos.minScrollExtent, pos.maxScrollExtent)
          .toDouble();
      // Less motion when the viewer asked for it.
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(target);
      } else {
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _check() {
    if (!mounted) return;
    final track = _trackKey.currentContext?.findRenderObject();
    final page = context.findRenderObject();
    if (track is! RenderBox || page is! RenderBox) return;
    if (!track.attached || !track.hasSize || !page.hasSize) return;
    final top = track.localToGlobal(Offset.zero, ancestor: page).dy;
    if (_scroll.hasClients) _trackAt = _scroll.offset + top;
    final pinned = top < MediaQuery.paddingOf(context).top;
    if (pinned != _pinned) setState(() => _pinned = pinned);
  }

  bool _onNotification(Notification n) {
    // A change in the scroll extent is a card above the track that loaded
    // or went away: it moves the track without moving the offset.
    if (n is ScrollMetricsNotification) _queueCheck();
    return false;
  }

  // The pinned copy sits ABOVE the scroll view and takes the touches that
  // land on it; a vertical drag there is handed to the scroll view, the way
  // Scrollable drives its own position (hold on down, then drag), so the
  // page scrolls and flings from the band as it does from anywhere else.
  // Taps and the track's own sideways scroll win their own arenas.
  void _onDragDown(DragDownDetails d) {
    if (!_scroll.hasClients) return;
    _hold = _scroll.position.hold(() => _hold = null);
  }

  void _onDragStart(DragStartDetails d) {
    if (!_scroll.hasClients) return;
    _drag = _scroll.position.drag(d, () => _drag = null);
  }

  void _onDragUpdate(DragUpdateDetails d) => _drag?.update(d);

  void _onDragEnd(DragEndDetails d) => _drag?.end(d);

  void _onDragCancel() {
    _hold?.cancel();
    _drag?.cancel();
  }

  Widget _band(BuildContext context, double top) => ColoredBox(
        color: context.palette.bg,
        child: Padding(
          padding: EdgeInsets.fromLTRB(_side, top, _side, _pad),
          child: widget.track,
        ),
      );

  @override
  Widget build(BuildContext context) {
    _inset = MediaQuery.paddingOf(context).top;
    _queueCheck();
    return Stack(children: [
      NotificationListener<Notification>(
        onNotification: _onNotification,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            ...widget.header,
            SliverToBoxAdapter(
              child: KeyedSubtree(key: _trackKey, child: _band(context, _pad)),
            ),
            ...widget.body,
          ],
        ),
      ),
      // Always mounted, hidden (no paint, no hit testing) while unpinned:
      // a drag that began on it keeps getting its pointer events when it
      // unpins under the finger, instead of being left half-done.
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: GestureDetector(
          onVerticalDragDown: _onDragDown,
          onVerticalDragStart: _onDragStart,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          onVerticalDragCancel: _onDragCancel,
          child: Offstage(
            offstage: !_pinned,
            child: _band(context, _inset + _pad),
          ),
        ),
      ),
    ]);
  }
}

/// The 2026 pill tab track (quiet track, active tab on a white thumb) for a
/// [DefaultTabController] / [controller].
///
/// When the labels fit, the tabs share the width evenly (as before). When
/// they don't — a fourth tab on a narrow phone — the track scrolls sideways
/// instead of shrinking or truncating the labels; the body below stays put
/// and follows the selected tab, and the selected tab scrolls into view.
class SpTabTrack extends StatelessWidget {
  const SpTabTrack({super.key, required this.labels, this.controller});

  final List<String> labels;
  final TabController? controller;

  static const double labelPadding = 16;
  static const double trackPadding = 4;
  static const TextStyle labelStyle =
      TextStyle(fontWeight: FontWeight.w700, fontSize: 13);
  static const TextStyle unselectedLabelStyle =
      TextStyle(fontWeight: FontWeight.w600, fontSize: 13);

  /// Whether [labels] fit side by side in [width] (the track's inner width):
  /// each label at the selected (bolder) weight plus its padding either side.
  static bool fits(BuildContext context, List<String> labels, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    // The tab labels inherit the app font from the ambient text style, so
    // measure with the same merge TabBar does.
    final style = DefaultTextStyle.of(context).style.merge(labelStyle);
    var need = 0.0;
    for (final l in labels) {
      final tp = TextPainter(
        text: TextSpan(text: l, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      need += tp.width + labelPadding * 2;
      tp.dispose();
    }
    return need <= width;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(trackPadding),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? p.surface2 : const Color(0xFFE6EBE8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final scroll = !fits(context, labels, box.maxWidth);
        return TabBar(
          controller: controller,
          isScrollable: scroll,
          // Scrolling: start-aligned with no leading inset (Material 3's
          // default `startOffset` would add a gap); fitting: equal shares.
          tabAlignment: scroll ? TabAlignment.start : TabAlignment.fill,
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.symmetric(horizontal: labelPadding),
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(999),
            boxShadow: dark
                ? null
                : const [
                    BoxShadow(
                        color: Color(0x140E1411),
                        blurRadius: 2,
                        offset: Offset(0, 1))
                  ],
          ),
          labelColor: p.ink,
          unselectedLabelColor: p.muted,
          labelStyle: labelStyle,
          unselectedLabelStyle: unselectedLabelStyle,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          tabs: [for (final l in labels) Tab(height: 38, text: l)],
        );
      }),
    );
  }
}
