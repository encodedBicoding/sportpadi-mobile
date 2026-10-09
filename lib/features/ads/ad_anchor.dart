import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/ads/admob.dart';
import 'package:sportpadi_mobile/data/ads/placements.dart';
import 'package:sportpadi_mobile/features/ads/ad_display.dart';

/// Ad anchors (web twin: components/ads/placements.tsx). A screen ships the
/// anchor; the owner console says what fills it, if anything:
///
///   AdAnchor(anchor: 'event.detail_bottom')          — a single spot
///   final ads = AdInterleave.of(ref, 'leaderboard.rows', rows.length);
///   for (final (i, r) in rows.indexed) ...[row(r), ...ads.afterRow(i)]
///
/// Both fills already collapse to nothing when there is nothing to show:
/// [AdDisplay] when the engine has no ad for this viewer, [AdMobNativeCard]
/// until a native ad has actually loaded. So an unfilled anchor costs the
/// screen no space, and a network no-fill never leaves a hole.
class AdAnchor extends ConsumerWidget {
  const AdAnchor({
    super.key,
    required this.anchor,
    this.hasContent = true,
    this.padding = EdgeInsets.zero,
  });

  final String anchor;

  /// False while the screen is empty/loading, so a unit never shows on a
  /// screen without content.
  final bool hasContent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!hasContent) return const SizedBox.shrink();
    final p = ref.watch(placementProvider(anchor));
    if (p == null) return const SizedBox.shrink();
    return _fill(p, anchor, 0, padding);
  }
}

Widget _fill(AdPlacement p, String anchor, int position, EdgeInsets padding) {
  Widget w;
  String label;
  if (p.isFirstParty) {
    label = 'slot "${p.slotKey}"';
    w = Padding(
      // Each position gets its own key so a list never recycles one serve
      // into another slot.
      key: ValueKey('ad:$anchor:$position:${p.slotKey}'),
      padding: padding,
      child: AdDisplay(slots: [p.slotKey!]),
    );
  } else if (p.isAdMobNative) {
    label = 'AdMob native';
    // One native ad request per position; the key keeps a disposed ad from
    // being reused when the list rebuilds.
    w = AdMobNativeCard(
      key: ValueKey('admob:$anchor:$position'),
      padding: padding,
    );
  } else {
    return const SizedBox.shrink();
  }
  // Debug builds outline every resolved anchor and say what it holds, so
  // "the console says X but nothing shows" is visible at a glance (an
  // empty frame here = the fill itself had nothing: no matching ad, or no
  // AdMob fill yet). Release builds get the bare widget.
  if (!kDebugMode) return w;
  return _DebugFrame(label: '$anchor #$position · $label', child: w);
}

class _DebugFrame extends StatelessWidget {
  const _DebugFrame({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.deepOrange.withAlpha(140)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Text('ad anchor · $label',
                style: const TextStyle(
                    color: Colors.deepOrange,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ),
          child,
        ]),
      );
}

/// Row interleaving for a list anchor. Build once per build() with the row
/// count, then ask [after] for each row index — it answers with the ad
/// widget for that gap, or null.
class AdInterleave {
  AdInterleave._(this._p, this._anchor, this._rows, this.padding);

  /// Watches the anchor's placement — call during build().
  static AdInterleave of(
    WidgetRef ref,
    String anchor,
    int count, {
    bool hasMore = false,
    EdgeInsets padding = const EdgeInsets.only(bottom: 6),
  }) =>
      from(ref.watch(placementProvider(anchor)), anchor, count,
          hasMore: hasMore, padding: padding);

  /// From a placement already watched higher up (for builders that run
  /// outside the widget's own build, e.g. AsyncView's `data:`).
  /// [hasMore]: the list paginates — keep the last row ad-free.
  static AdInterleave from(
    AdPlacement? p,
    String anchor,
    int count, {
    bool hasMore = false,
    EdgeInsets padding = const EdgeInsets.only(bottom: 6),
  }) =>
      AdInterleave._(p, anchor,
          p?.adRows(count, hasMore: hasMore) ?? const [], padding);

  final AdPlacement? _p;
  final String _anchor;
  final List<int> _rows;
  final EdgeInsets padding;

  bool get any => _rows.isNotEmpty;

  Widget? after(int index) {
    final p = _p;
    if (p == null) return null;
    final pos = _rows.indexOf(index);
    if (pos < 0) return null;
    return _fill(p, _anchor, pos, padding);
  }

  /// [after] as a spreadable list (one widget or none) for collection-for
  /// bodies: `...ads.afterRow(i)`.
  List<Widget> afterRow(int index) {
    final w = after(index);
    return w == null ? const [] : [w];
  }
}
