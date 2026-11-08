import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

class CategoryDropdown extends ConsumerWidget {
  const CategoryDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.disabledIds = const {},
    this.disabledNote = 'has a team',
  });
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Sports that can't be picked (e.g. already have a team on a
  /// one-team-per-sport plan) — listed, greyed, with [disabledNote].
  final Set<String> disabledIds;
  final String disabledNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider);
    return cats.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (_, __) => Text(context.l10n.common_couldNotLoadSports),
      data: (list) => InputDecorator(
        decoration: InputDecoration(labelText: context.l10n.common_sport),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            // A value that became unavailable reads as "none picked".
            value: value != null && disabledIds.contains(value) ? null : value,
            isExpanded: true,
            isDense: true,
            hint: Text(context.l10n.common_chooseSport),
            items: [
              for (final c in list)
                DropdownMenuItem(
                  value: c.id,
                  enabled: !disabledIds.contains(c.id),
                  child: Text(
                    disabledIds.contains(c.id)
                        ? '${c.emoji ?? ''} ${c.name} · $disabledNote'
                        : '${c.emoji ?? ''} ${c.name}',
                    style: disabledIds.contains(c.id)
                        ? TextStyle(color: Theme.of(context).disabledColor)
                        : null,
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
