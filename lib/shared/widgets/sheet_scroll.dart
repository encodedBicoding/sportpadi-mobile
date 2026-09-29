import 'package:flutter/material.dart';

/// Scrollable body for a modal bottom sheet that still closes on a pull-down.
///
/// A scroll view inside `showModalBottomSheet` wins every vertical drag, so the
/// sheet's own drag-to-dismiss never fires and pulling down does nothing. This
/// watches the scroll view instead: once it is at the top and the finger keeps
/// pulling down (an overscroll on Android, a bounce past zero on iOS), the
/// sheet is popped. Scrolling long content works exactly as before.
class SheetScrollView extends StatefulWidget {
  const SheetScrollView({
    super.key,
    required this.child,
    this.padding,
    this.dismissDistance = 64,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// How far past the top the user has to pull before the sheet closes.
  final double dismissDistance;

  @override
  State<SheetScrollView> createState() => _SheetScrollViewState();
}

class _SheetScrollViewState extends State<SheetScrollView> {
  double _pull = 0;
  bool _closing = false;

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  bool _onScroll(ScrollNotification n) {
    // Only this sheet's own scroll view — a list nested inside it (a search
    // result list) reaching its top must not close the sheet.
    if (n.depth != 0) return false;
    if (n is ScrollStartNotification) {
      _pull = 0;
    } else if (n is OverscrollNotification &&
        n.dragDetails != null &&
        n.overscroll < 0) {
      // Clamping physics (Android): the pull shows up as overscroll.
      _pull += -n.overscroll;
    } else if (n is ScrollUpdateNotification && n.dragDetails != null) {
      final past = n.metrics.minScrollExtent - n.metrics.pixels;
      // Bouncing physics (iOS): the view itself goes past the top.
      _pull = past > 0 ? past : 0;
    }
    if (_pull > widget.dismissDistance) _close();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: SingleChildScrollView(
        // Always scrollable, so a short ticket still reports the pull.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.padding,
        child: widget.child,
      ),
    );
  }
}
