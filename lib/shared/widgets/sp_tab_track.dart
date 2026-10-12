import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';

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
