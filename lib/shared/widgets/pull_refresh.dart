import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Pull-to-refresh helpers — every RefreshIndicator in the app follows the
/// same rule: a pull refetches EVERYTHING the page shows (not just its first
/// provider), and the spinner stays until that data is back.
///
/// Usage:
///   onRefresh: () {
///     ref.invalidate(a(id));
///     ref.invalidate(b(id));
///     return settleAll([ref.read(a(id).future), ref.read(b(id).future)]);
///   },

/// Waits for every future; a failure doesn't throw (the page shows its own
/// error state) — it just lets the spinner stop.
Future<void> settleAll(Iterable<Future<Object?>> futures) async {
  await Future.wait<void>([
    for (final f in futures) f.then<void>((_) {}, onError: (Object _) {}),
  ]);
}

/// Makes a non-scrolling state (a loader, an error, an empty message) still
/// pullable when it's the RefreshIndicator's child: wraps it in an
/// always-scrollable list that fills the viewport.
class PullableState extends StatelessWidget {
  const PullableState(
      {super.key, required this.child, this.bottomPadding = 0});
  final Widget child;

  /// Room to keep free at the bottom, for something laid OVER the body
  /// there: the state stays centred in what can actually be seen. The tabs
  /// pass `SpDock.spaceBelow`, which is 0 since the dock went back onto its
  /// own band below the body (2026-11-16) — kept so it stays right if a
  /// shell ever runs its body under the dock again.
  ///
  /// It is SUBTRACTED from the viewport and never added to the list: this
  /// `ListView` is given no `padding:` of its own, so
  /// `BoxScrollView.buildSlivers` already pads it by
  /// `MediaQuery.padding.bottom`, and a trailing box of ours would reserve
  /// the room a second time — scrollable slack a loader or an empty state
  /// can be dragged up into (and stays in, on Android). Left at 0 the list
  /// is exactly what it always was.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: math.max(0.0, box.maxHeight - bottomPadding)),
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}
