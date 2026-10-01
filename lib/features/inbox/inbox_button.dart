import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart';
import 'package:sportpadi_mobile/data/messages/messages_repository.dart';

/// "Inbox, 2 unread announcements, 1 unread conversation".
String _inboxLabel(int announcements, int messages) {
  final parts = [
    if (announcements > 0)
      '$announcements unread announcement${announcements == 1 ? '' : 's'}',
    if (messages > 0)
      '$messages unread conversation${messages == 1 ? '' : 's'}',
  ];
  return parts.isEmpty ? 'Inbox' : 'Inbox, ${parts.join(', ')}';
}

/// The Inbox entry next to the notifications bell: a megaphone with its own
/// badge — an orange dot for unread announcements, a green count for unread
/// messages, a red count when an announcement is urgent. Refreshes like the
/// bell (polled while shown, and on push, resume and tab switches — see
/// HomeShell). Opens on Messages when only messages are unread.
class InboxHeaderButton extends ConsumerWidget {
  const InboxHeaderButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final unread = ref.watch(announcementsUnreadProvider).valueOrNull;
    final announcements = unread?.announcements ?? 0;
    final messages = ref.watch(messagesUnreadProvider).valueOrNull ?? 0;
    final count = announcements + messages;
    final urgent = unread?.urgent ?? 0;
    return Semantics(
      button: true,
      label: _inboxLabel(announcements, messages),
      child: Material(
        color: p.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => context.push(announcements == 0 && messages > 0
              ? '/inbox?tab=messages'
              : '/inbox'),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                shape: BoxShape.circle, boxShadow: cardShadow(context)),
            child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(Icons.campaign_outlined, size: 23, color: p.ink),
                  if (urgent > 0 || messages > 0)
                    Positioned(
                      top: 5,
                      right: 3,
                      child: _CountBubble(
                          count: count,
                          color: urgent > 0 ? p.danger : p.accentDeep,
                          border: p.surface),
                    )
                  else if (count > 0)
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: p.orange,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.surface, width: 2),
                        ),
                      ),
                    ),
                ]),
          ),
        ),
      ),
    );
  }
}

/// The megaphone for an AppBar action slot, with the same badge rules
/// (announcements + messages).
class InboxIcon extends ConsumerWidget {
  const InboxIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final unread = ref.watch(announcementsUnreadProvider).valueOrNull;
    final announcements = unread?.announcements ?? 0;
    final messages = ref.watch(messagesUnreadProvider).valueOrNull ?? 0;
    final count = announcements + messages;
    final urgent = unread?.urgent ?? 0;
    const icon = Icon(Icons.campaign_outlined);
    if (count <= 0) return icon;
    return Semantics(
      label: _inboxLabel(announcements, messages),
      child: Stack(clipBehavior: Clip.none, children: [
        icon,
        Positioned(
          right: -4,
          top: -3,
          child: _CountBubble(
              count: count,
              color: urgent > 0
                  ? p.danger
                  : messages > 0
                      ? p.accentDeep
                      : p.orange),
        ),
      ]),
    );
  }
}

class _CountBubble extends StatelessWidget {
  const _CountBubble({required this.count, required this.color, this.border});
  final int count;
  final Color color;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      constraints: const BoxConstraints(minWidth: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: border != null ? Border.all(color: border!, width: 1.5) : null,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
            color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
      ),
    );
  }
}
