import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';

/// One destination in the [SpDock].
class SpDockItem {
  const SpDockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.dot = false,
  });
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Small orange "something's happening" dot (never a number).
  final bool dot;
}

/// The 2026 bottom navigation: an ink pill. The active tab grows into a
/// light pill with its icon + label; the others are icons only. Sits on a
/// band of the page canvas (the shells paint it `p.bg`) with a soft drop
/// shadow, 16 in from the edges, 6 above it and 10 below.
class SpDock extends StatelessWidget {
  const SpDock({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
  });

  /// The pill, and the air above and below it — the three numbers [build]
  /// lays out. Named, so the room the dock takes is derived from the dock
  /// itself instead of being a literal wherever it is needed.
  static const double _pill = 64;
  static const double _gapAbove = 6;
  static const double _gapBelow = 10;

  /// What the dock takes at the bottom of the screen, before the system's
  /// own inset, which the shells keep IN FULL under it.
  static const double height = _pill + _gapAbove + _gapBelow;

  /// The whole bar the shells lay out — the dock and the system inset under
  /// it — for something drawn over the app from OUTSIDE the shell (the update
  /// card, core/update/app_update.dart). Ask from there (or from the bar),
  /// where `MediaQuery.padding.bottom` is the system inset.
  static double barHeight(BuildContext context) =>
      height + MediaQuery.paddingOf(context).bottom;

  /// Room a tab's scrollable leaves at its bottom for anything of the
  /// shell's laid OVER its body. The dock is not: it sits on its own band of
  /// page colour (`p.bg`) BELOW the body — the shells do not extend their
  /// body behind it — and a Scaffold with a `bottomNavigationBar` zeroes its
  /// body's `MediaQuery.padding.bottom`, so inside a tab this is 0. It is
  /// read off that padding rather than written as 0 so that it stays true if
  /// a shell's layout ever changes (from 2026-11-15 to 11-16 the dock
  /// floated over the tabs, and every tab leaned on this number).
  static double spaceBelow(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom;

  /// The air a tab's LAST ROW keeps above the dock's band: 28, the smallest
  /// of the bottom paddings the tabs carried before the dock ever floated
  /// (28–36).
  static const double _air = 28;

  /// What a tab's padded scrollable leaves at its bottom: [spaceBelow] (0
  /// inside a tab) plus that air.
  static double spaceBelowList(BuildContext context) =>
      spaceBelow(context) + _air;

  final List<SpDockItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, _gapAbove, 16, _gapBelow),
      child: Container(
        height: _pill,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: p.hero,
          borderRadius: BorderRadius.circular(32),
          // Night: no shadow to lift it, so a hairline does.
          border: dark ? Border.all(color: p.onHero.withAlpha(20)) : null,
          boxShadow: dark
              ? const []
              : const [
                  BoxShadow(
                    color: Color(0x660E1411),
                    blurRadius: 36,
                    spreadRadius: -14,
                    offset: Offset(0, 16),
                  ),
                ],
        ),
        child: LayoutBuilder(builder: (context, c) {
          // Room left for the active tab's label on this screen width, so a
          // long one ("Tournaments") fades instead of overflowing on 360dp.
          final labelMax = (c.maxWidth - (items.length - 1) * 44 - 22 - 7 - 32)
              .clamp(0.0, 120.0);
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < items.length; i++)
                _DockButton(
                  item: items[i],
                  selected: i == index,
                  labelMax: labelMax,
                  onTap: () {
                    if (i != index) HapticFeedback.selectionClick();
                    onSelect(i);
                  },
                ),
            ],
          );
        }),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.item,
    required this.selected,
    required this.onTap,
    required this.labelMax,
  });
  final SpDockItem item;
  final bool selected;
  final VoidCallback onTap;
  final double labelMax;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final iconColor = selected ? p.accent : p.onHero.withAlpha(185);
    final icon = Stack(clipBehavior: Clip.none, children: [
      Icon(selected ? item.selectedIcon : item.icon,
          size: 22, color: iconColor),
      if (item.dot)
        Positioned(
          top: -1,
          right: -2,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: p.orange,
              shape: BoxShape.circle,
              border:
                  Border.all(color: selected ? p.onHero : p.hero, width: 1.5),
            ),
          ),
        ),
    ]);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 11),
          decoration: ShapeDecoration(
            color: selected ? p.onHero : Colors.transparent,
            shape: const StadiumBorder(),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            icon,
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: labelMax),
                        child: Text(
                          item.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: TextStyle(
                            color: p.hero,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ]),
        ),
      ),
    );
  }
}
