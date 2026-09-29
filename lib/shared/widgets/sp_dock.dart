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

  final List<SpDockItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Container(
        height: 64,
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
      Icon(selected ? item.selectedIcon : item.icon, size: 22, color: iconColor),
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
              border: Border.all(color: selected ? p.onHero : p.hero, width: 1.5),
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
