import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/features/teams/balance_setup_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// "Set your position for ⚽ Soccer" — one card per sport the viewer plays
/// in whose team balancing is missing their role (web twin:
/// components/home/BalanceGapsCard). Opens the same sheet the event page
/// uses; gone once saved.
class BalanceGapsCard extends ConsumerWidget {
  const BalanceGapsCard({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final gaps = ref.watch(balanceGapsProvider).valueOrNull ?? const [];
    if (gaps.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Column(children: [
        for (final g in gaps) ...[
          _card(context, ref, p, g),
          const SizedBox(height: 10),
        ],
      ]),
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, AppPalette p, Map<String, dynamic> g) {
    final field = g['field'] is Map ? Map<String, dynamic>.from(g['field'] as Map) : const <String, dynamic>{};
    final label = ((field['label'] as String?) ?? 'position').toLowerCase();
    final name = (g['categoryName'] as String?) ?? 'this sport';
    final categoryId = g['categoryId'] as String?;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        SpIconTile(Icons.shield_outlined, bg: p.orangeTint, fg: p.orangeInk),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Set your $label for $name',
                style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
            Text('Teams are balanced by $label — without yours, you can land anywhere.',
                style: TextStyle(color: p.muted, fontSize: 12, height: 1.35)),
          ]),
        ),
        const SizedBox(width: 8),
        Material(
          color: p.hero,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: categoryId == null
                ? null
                : () => showBalanceSetupIfNeeded(context, ref, categoryId: categoryId, dismissible: true),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Text('Set it',
                  style: TextStyle(color: p.onHero, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ]),
    );
  }
}
