import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/links/deep_links.dart';
import 'package:sportpadi_mobile/core/router/app_router.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcement_models.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart'
    show homeTabIndexProvider;
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';

/// Announcement building blocks shared by the Inbox, the detail page and the
/// pinned strips on group / team pages.

/// Red "Urgent" pill.
class UrgentPill extends StatelessWidget {
  const UrgentPill({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: p.liveTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.priority_high_rounded, size: 12, color: p.danger),
        const SizedBox(width: 2),
        Text('Urgent',
            style: TextStyle(
                color: p.danger,
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

/// Violet "For Tobi, Zara" chip on a guardian's copy.
class WardsForChip extends StatelessWidget {
  const WardsForChip(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: p.wardTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.child_care_rounded, size: 12, color: p.wardInk),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.wardInk,
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

/// A card with a danger-coloured rail down its left edge when [urgent].
class RailCard extends StatelessWidget {
  const RailCard({
    super.key,
    required this.child,
    this.urgent = false,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 14, 14),
    this.radius = 22,
  });
  final Widget child;
  final bool urgent;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: cardShadow(context),
      ),
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: shape,
          side: dark ? BorderSide(color: p.line) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(children: [
            Padding(padding: padding, child: child),
            if (urgent)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 4, color: p.danger),
              ),
          ]),
        ),
      ),
    );
  }
}

/// One announcement in the Inbox: group, sender and role, audience, time,
/// title and a two-line preview; ward chip, unread dot, pin, urgent styling.
class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({super.key, required this.item, this.onTap});
  final AnnouncementItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = item;
    final unread = a.isUnread;
    final who = [
      '${a.senderName} · ${a.roleLabel}',
      if (a.audienceLabel.isNotEmpty) 'to ${a.audienceLabel}',
    ].join(' · ');
    final wards = a.wardsLabel;
    final preview = a.body.trim().replaceAll(RegExp(r'\s*\n\s*'), ' ');
    return RailCard(
      urgent: a.isUrgent,
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Crest(logoUrl: a.groupImageUrl, label: a.groupName, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.groupName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700)),
              Text(who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ),
          const SizedBox(width: 8),
          if (a.isPinned) ...[
            Icon(Icons.push_pin_rounded, size: 15, color: p.muted),
            const SizedBox(width: 6),
          ],
          Text(fmtRelative(a.createdAt),
              style: TextStyle(color: p.muted, fontSize: 11.5)),
          if (unread) ...[
            const SizedBox(width: 6),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: a.isUrgent ? p.danger : p.orange,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        if (a.isUrgent) ...[
          const UrgentPill(),
          const SizedBox(height: 6),
        ],
        Text(a.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: p.ink,
                fontSize: 15,
                height: 1.3,
                fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.45)),
        ],
        if (wards != null || a.attachments.isNotEmpty || a.isAcked) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (wards != null) WardsForChip(wards),
              if (a.attachments.isNotEmpty)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.attach_file_rounded, size: 14, color: p.muted),
                  Text('${a.attachments.length}',
                      style: TextStyle(color: p.muted, fontSize: 11.5)),
                ]),
              if (a.isAcked)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_rounded,
                      size: 14, color: p.greenText),
                  const SizedBox(width: 3),
                  Text('Got it',
                      style: TextStyle(
                          color: p.greenText,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ]),
            ],
          ),
        ],
      ]),
    );
  }
}

/// A compact pinned announcement for the top of a group or team page.
class PinnedAnnouncementTile extends StatelessWidget {
  const PinnedAnnouncementTile({super.key, required this.item, this.onTap});
  final AnnouncementItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final a = item;
    return RailCard(
      urgent: a.isUrgent,
      onTap: onTap,
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
      child: Row(children: [
        Icon(Icons.push_pin_rounded,
            size: 17, color: a.isUrgent ? p.danger : p.greenText),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
            Text(
                [
                  if (a.isUrgent) 'Urgent',
                  a.senderName,
                  fmtRelative(a.createdAt),
                ].where((s) => s.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 11.5)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, size: 18, color: p.muted),
      ]),
    );
  }
}

/// Open a link found in an announcement: our own pages go through the same
/// resolver as deep links and pushes (a screen, a tab, or an in-app browser
/// for web-only pages); anything else opens in the browser.
Future<void> openAnnouncementUrl(WidgetRef ref, String raw) async {
  final base = Uri.parse(ref.read(appConfigProvider).apiBaseUrl);
  final text = raw.trim();
  final Uri? uri = text.startsWith('/')
      ? Uri.tryParse('${base.scheme}://${base.authority}$text')
      : Uri.tryParse(text.contains('://') ? text : 'https://$text');
  if (uri == null) return;
  final host = uri.host.toLowerCase();
  final ours = host == base.host.toLowerCase() ||
      host == 'sportpadi.com' ||
      host.endsWith('.sportpadi.com');
  if (ours) {
    final router = ref.read(routerProvider);
    final handled = await handleDeepLink(
      uri,
      push: (route) => router.push(route),
      switchTab: (tab) {
        router.go('/home');
        ref.read(homeTabIndexProvider.notifier).state = tab;
      },
    );
    if (handled) return;
  }
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    if (kDebugMode) debugPrint('[announcements] could not open $uri: $e');
  }
}
