import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/data/manage/manage_repository.dart';

class CategoryDropdown extends ConsumerWidget {
  const CategoryDropdown({super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider);
    return cats.when(
      loading: () => const LinearProgressIndicator(minHeight: 2),
      error: (_, __) => const Text('Could not load sports.'),
      data: (list) => InputDecorator(
        decoration: const InputDecoration(labelText: 'Sport'),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            isDense: true,
            hint: const Text('Choose sport'),
            items: [
              for (final c in list)
                DropdownMenuItem(
                  value: c.id,
                  child: Text('${c.emoji ?? ''} ${c.name}'),
                ),
            ],
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}
