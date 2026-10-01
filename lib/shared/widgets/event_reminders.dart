import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';

/// Event reminder slots, farthest from the event first — mirrors the
/// server's `reminders/schedule.ts` (REMINDER_SLOTS / DEFAULT_REMINDERS).
const kReminderSlots = <String, String>{
  'd5': '5 days',
  'd3': '3 days',
  'd2': '2 days',
  'd1': '1 day',
  'h2': '2 hours',
};

/// What a new event gets when the organizer doesn't change anything.
const kDefaultReminderSlots = <String>['d2', 'h2'];

const kRemindersHelp =
    'People going get these; everyone else the event is for gets one '
    '“Are you coming?” nudge. Day reminders arrive at 9am their time.';

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
          Text('Reminders',
              style: TextStyle(
                  color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
          Text(' · before the event',
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
            label: 'No reminders',
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
