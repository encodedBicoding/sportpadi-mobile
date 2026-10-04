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
  const PullableState({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}
