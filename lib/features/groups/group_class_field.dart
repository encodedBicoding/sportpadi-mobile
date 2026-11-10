import 'package:flutter/material.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/data/groups/group_class.dart';

/// Optional group-type picker for the "create a group" sheets — "Not set" plus
/// the seven classes (docs/design/group-classes.md; web twin:
/// components/groups/GroupClassPicker.tsx). Edit group keeps its own copy
/// because it also shows the locked "Confirmed by SportPadi" state.
class GroupClassField extends StatelessWidget {
  const GroupClassField({
    super.key,
    required this.onChanged,
    this.initial,
    this.enabled = true,
    this.decoration,
  });

  final ValueChanged<String?> onChanged;
  final String? initial;
  final bool enabled;

  /// Base decoration to match the sheet's other fields; the label and helper
  /// text are filled in here.
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return DropdownButtonFormField<String?>(
      initialValue: initial,
      isExpanded: true,
      decoration: (decoration ?? const InputDecoration()).copyWith(
        labelText: t.group_classOptional,
        helperText: t.group_classPrompt,
        helperMaxLines: 3,
      ),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(t.group_classNotSet)),
        for (final c in groupClasses)
          DropdownMenuItem<String?>(
            value: c,
            child: Text('${groupClassEmoji[c] ?? ''} ${groupClassName(t, c)}',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: enabled ? onChanged : null,
    );
  }
}
