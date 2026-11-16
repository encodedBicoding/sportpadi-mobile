import 'dart:math' as math;

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

/// The 2026 bottom navigation: a floating ink pill. The active tab grows into
/// a light pill with its icon + label; the others are icons only. Sits on
/// the page canvas with a soft drop shadow, 16 in from the edges.
class SpDock extends StatelessWidget {
  const SpDock({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
  });

  /// The pill, and the air above and below it — the three numbers [build]
  /// lays out. Named, so the room a page has to leave for the dock is
  /// derived from the dock itself instead of being a literal in every tab.
  static const double _pill = 64;
  static const double _gapAbove = 6;
  static const double _gapBelow = 4;

  /// What the dock takes at the bottom of the screen, before what the shell
  /// keeps of the system's own inset under it ([insetBelow]).
  static const double height = _pill + _gapAbove + _gapBelow;

  /// How far the dock sinks into the system's bottom inset. The strip a home
  /// indicator or a gesture handle lives in is mostly air; keeping all of it
  /// and a gap of our own on top left the pill riding 44 above the bottom of
  /// an iPhone.
  static const double _sink = 10;

  /// An inset at least this tall is a bar of BUTTONS (Android's back / home /
  /// recents, 48), not a gesture strip (an iPhone's 34 is the tallest of
  /// those). The system paints a button bar over the app — a scrim, or a
  /// solid colour — so the dock stays above ALL of it: sunk in, the pill's
  /// bottom edge would be cut off by it.
  static const double _buttonBar = 40;

  /// The spacer the shells put UNDER the dock: what is kept of the system's
  /// bottom inset. The pill's bottom edge therefore sits [_gapBelow] + this
  /// above the bottom of the screen — 28 over a 34pt home indicator, 18 over
  /// a 24dp gesture bar, 4 where there is no inset, and 4 clear of a button
  /// bar.
  ///
  /// Ask from the BAR (or above the shell's Scaffold), where
  /// `MediaQuery.padding.bottom` is the system inset. Inside a tab that
  /// number is the whole bar — see [spaceBelow] — and this is meaningless.
  static double insetBelow(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    if (inset >= _buttonBar) return inset;
    return math.max(0.0, inset - _sink);
  }

  /// The whole bar the shells lay out — the dock and the spacer under it —
  /// for something drawn over the app from OUTSIDE the shell (the update
  /// card, core/update/app_update.dart). Same rule as [insetBelow] about
  /// where to ask from; a tab asks [spaceBelow], which is this same number
  /// as its Scaffold measured it.
  static double barHeight(BuildContext context) =>
      height + insetBelow(context);

  /// Room a scrollable has to leave below its last row so nothing ends up
  /// hidden under the floating dock: the dock, plus what the shell keeps of
  /// the system inset (home indicator / gesture bar) beneath it.
  ///
  /// The shell runs its body BEHIND the dock (`extendBody: true`), and a
  /// Scaffold that does that hands the body the WHOLE bottom bar's height —
  /// dock and inset together — as its `MediaQuery.padding.bottom`
  /// (`_BodyBuilder`, in the framework's `scaffold.dart`). So inside a tab
  /// that padding already IS this number, measured off the bar as it was
  /// really laid out; adding [height] to it would count the dock twice.
  ///
  /// [height] is the floor only once a bar has been measured. A 0 there
  /// means nothing of ours is over the body at all — either the keyboard is
  /// up, which is the one case the Scaffold STOPS extending the body for (it
  /// ends above the keyboard and the bar hides behind it:
  /// `_ScaffoldLayout.performLayout`, `extendBody && minInsets.bottom <=
  /// bottomWidgetsHeight`), or this is not a Scaffold that extends its body
  /// — and in both the room to leave is none, not the dock. The keyboard
  /// cannot be asked about from in here: a Scaffold takes `viewInsets` out of
  /// its body's MediaQuery (`removeBottomInset`), so `viewInsetsOf(context)
  /// .bottom` is always 0 inside a tab.
  static double spaceBelow(BuildContext context) {
    final bar = MediaQuery.paddingOf(context).bottom;
    if (bar <= 0) return 0;
    return math.max(height, bar);
  }

  /// The air a tab's LAST ROW keeps above the pill, on top of the clearance.
  /// The pill is opaque, so a card never scrolls *under* it: without this a
  /// list's last row stops [_gapAbove] (6) above the pill and reads as
  /// jammed against it. 28 is the smallest of the bottom paddings the tabs
  /// carried before the dock floated (28–36), so no tab's last row ends up
  /// tighter than it was.
  static const double _air = 28;

  /// Room for the dock AND that air: what a tab's padded scrollable leaves
  /// at the bottom. The Highlights tab takes the bare [spaceBelow] instead:
  /// that is where its video stops, with nothing of it behind the pill.
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
