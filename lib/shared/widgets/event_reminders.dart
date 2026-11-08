import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Event reminder slots, farthest from the event first — mirrors the
/// server's `reminders/schedule.ts` (REMINDER_SLOTS / DEFAULT_REMINDERS).
/// Keys are the server's slot ids; values are labels in the current language.
Map<String, String> get kReminderSlots => <String, String>{
      'd5': l10n.common_reminderDays(5),
      'd3': l10n.common_reminderDays(3),
      'd2': l10n.common_reminderDays(2),
      'd1': l10n.common_reminderDays(1),
      'h2': l10n.common_reminderHours(2),
    };

/// What a new event gets when the organizer doesn't change anything.
const kDefaultReminderSlots = <String>['d2', 'h2'];

String get kRemindersHelp => l10n.common_remindersHelp;

/// The slots in server order (farthest first), unknown values dropped.
List<String> orderReminderSlots(Iterable<String> slots) => [
      for (final k in kReminderSlots.keys)
        if (slots.contains(k)) k
    ];

/// Same order + same members (order-insensitive compare for "changed?").
bool sameReminderSlots(Iterable<String> a, Iterable<String> b) =>
    orderReminderSlots(a).join(',') == orderReminderSlots(b).join(',');

/// "Reminders" field for the create / edit event forms: toggle chips for
/// each slot plus "No reminders" (selected when nothing is), and the helper
/// line. Purely controlled — the parent owns [selected].
class EventRemindersPicker extends StatelessWidget {
  const EventRemindersPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.alarm_rounded, size: 15, color: p.muted),
          const SizedBox(width: 6),
          Text(context.l10n.common_reminders,
              style: TextStyle(
                  color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
          Text(context.l10n.common_beforeTheEvent,
              style: TextStyle(color: p.muted, fontSize: 11.5)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final entry in kReminderSlots.entries)
            _ReminderChip(
              label: entry.value,
              on: selected.contains(entry.key),
              onTap: enabled
                  ? () {
                      final next = {...selected};
                      if (!next.remove(entry.key)) next.add(entry.key);
                      onChanged(next);
                    }
                  : null,
            ),
          _ReminderChip(
            label: context.l10n.common_noReminders,
            on: selected.isEmpty,
            onTap: enabled && selected.isNotEmpty
                ? () => onChanged(<String>{})
                : null,
          ),
        ]),
        const SizedBox(height: 6),
        Text(kRemindersHelp,
            style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.4)),
      ],
    );
  }
}

class _ReminderChip extends StatelessWidget {
  const _ReminderChip(
      {required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: on ? p.accentDeep : p.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: on ? p.accentDeep : p.line),
          ),
          child: Text(label,
              style: TextStyle(
                color: on ? Colors.white : p.ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
        ),
      ),
    );
  }
}
