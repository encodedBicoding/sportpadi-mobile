import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcement_models.dart';
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Settings → Notifications: one card with a switch per activity category —
/// messages, discussions, new events and event reminders — instead of
/// separate sections.
/// Each is `notification_preferences(category).push`, default on (same store
/// as the web's NotificationPrefs). Announcements keep their own card: they
/// have push + email and a separate urgent tier.
class ActivityNotificationsCard extends ConsumerStatefulWidget {
  const ActivityNotificationsCard({super.key});

  @override
  ConsumerState<ActivityNotificationsCard> createState() =>
      _ActivityNotificationsCardState();
}

class _Row {
  const _Row(this.category, this.icon, this.title, this.subtitle);
  final String category;
  final IconData icon;
  final String title;
  final String subtitle;
}

const _rows = <_Row>[
  _Row('messages', Icons.chat_bubble_outline_rounded, 'Messages',
      'When an admin, coach or member writes to you or your wards. Mute one conversation from its menu.'),
  _Row('discussions', Icons.forum_outlined, 'Discussions',
      'Comments on discussions you started and replies to your comments.'),
  _Row('events', Icons.event_available_outlined, 'New events',
      'When your groups or teams create an event, or a group you follow posts a public one.'),
  _Row('reminders', Icons.alarm_rounded, 'Event reminders',
      "Before events you're going to, and one “Are you coming?” for ones you haven't answered."),
];

class _ActivityNotificationsCardState
    extends ConsumerState<ActivityNotificationsCard> {
  final Map<String, bool> _pending = {};

  Future<void> _set(String category, bool v) async {
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _pending[category] = v);
    try {
      await ref
          .read(announcementsRepositoryProvider)
          .setPreference(category, push: v);
      container.invalidate(notificationPreferencesProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pending.remove(category));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final list = ref.watch(notificationPreferencesProvider).valueOrNull;
    bool saved(String c) =>
        _pending[c] ??
        list
            ?.firstWhere((x) => x.category == c,
                orElse: () => NotificationPreference(category: c))
            .push ??
        true;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.surface2),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              secondary: Icon(_rows[i].icon, size: 20, color: p.muted),
              title: Text(_rows[i].title,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              subtitle: Text(_rows[i].subtitle,
                  style: TextStyle(color: p.muted, fontSize: 12)),
              value: saved(_rows[i].category),
              onChanged: list == null
                  ? null
                  : (v) => _set(_rows[i].category, v),
            ),
          ],
        ],
      ),
    );
  }
}
