import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';

/// All · Local · Tournaments, each with its game count. A scope with no games
/// is shown but can't be picked ("All" always can).
class SportScopeSwitch extends StatelessWidget {
  const SportScopeSwitch({
    super.key,
    required this.value,
    required this.counts,
    required this.onChanged,
  });
  final RecordScope value;
  final Map<RecordScope, int> counts;
  final ValueChanged<RecordScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: dark ? p.surface2 : const Color(0xFFE6EBE8),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(children: [
        for (final s in RecordScope.values)
          Expanded(child: _segment(context, p, dark, s)),
      ]),
    );
  }

  Widget _segment(
      BuildContext context, AppPalette p, bool dark, RecordScope s) {
    final n = counts[s] ?? 0;
    final enabled = s == RecordScope.all || n > 0;
    final selected = s == value;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '${s.label}, ${plural(n, 'game')}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled && !selected ? () => onChanged(s) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? p.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: selected && !dark
                ? const [
                    BoxShadow(
                        color: Color(0x140E1411),
                        blurRadius: 2,
                        offset: Offset(0, 1))
                  ]
                : null,
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(s.label,
                      style: TextStyle(
                          color: selected ? p.ink : p.muted,
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600)),
                  const SizedBox(width: 5),
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected
                          ? p.accentTint
                          : p.surface.withAlpha(dark ? 40 : 150),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text('$n',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: selected ? p.greenText : p.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            fontFeatures: tabularFigures)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
