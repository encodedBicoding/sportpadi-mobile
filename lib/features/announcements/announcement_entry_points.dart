import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcement_models.dart';
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart';
import 'package:sportpadi_mobile/features/inbox/announcement_card.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Where announcements surface outside the Inbox: pinned ones at the top of
/// group and team pages, and the staff entry points (Announce, Sent, "Message
/// participants"). Staff-ness is the composer endpoint's answer — it 403s for
/// everyone else, so `valueOrNull == null` simply hides the buttons.

/// Pinned announcements for a group page ([teamId] null) or a team page.
/// [onOpen] replaces the default "push the announcement" (inside a sheet,
/// which has to close first). [max] caps how many show (null = all) — the
/// server sends urgent, then unread, then newest first.
class PinnedAnnouncements extends ConsumerWidget {
  const PinnedAnnouncements(
      {super.key,
      required this.groupId,
      this.teamId,
      this.onOpen,
      this.max});
  final String groupId;
  final String? teamId;
  final ValueChanged<AnnouncementItem>? onOpen;
  final int? max;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref
            .watch(
                pinnedAnnouncementsProvider((groupId: groupId, teamId: teamId)))
            .valueOrNull ??
        const <AnnouncementItem>[];
    if (all.isEmpty) return const SizedBox.shrink();
    final cap = max;
    final list = cap != null && all.length > cap ? all.take(cap).toList() : all;
    final open = onOpen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          PinnedAnnouncementTile(
            item: list[i],
            onTap: open != null
                ? () => open(list[i])
                : () => context.push('/inbox/announcements/${list[i].id}'),
          ),
        ],
      ],
    );
  }
}

/// Group page: its own "Pinned" section (top of the page, above the
/// overview tiles) with the group's pinned announcements — or, with
/// [teamId], the team page's with the team's. Members and followers alike —
/// the server decides what each viewer gets — and nothing at all when there
/// are none. Only the top [_shown] appear; more sit behind "See all", in a
/// sheet, so a busy group's pins never flood the page.
class GroupPinnedAnnouncementsSection extends ConsumerWidget {
  const GroupPinnedAnnouncementsSection(
      {super.key,
      required this.groupId,
      this.teamId,
      this.padding = const EdgeInsets.only(top: 18)});
  final String groupId;
  final String? teamId;
  final EdgeInsets padding;

  static const _shown = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final list = ref
            .watch(
                pinnedAnnouncementsProvider((groupId: groupId, teamId: teamId)))
            .valueOrNull ??
        const <AnnouncementItem>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final more = list.length > _shown;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSectionTitle(
            'Pinned',
            count: list.length > 1 ? list.length : null,
            trailing: more
                ? TextButton(
                    onPressed: () => _showAll(context),
                    style: TextButton.styleFrom(
                        foregroundColor: p.greenText,
                        visualDensity: VisualDensity.compact),
                    child: const Text('See all'),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          PinnedAnnouncements(groupId: groupId, teamId: teamId, max: _shown),
        ],
      ),
    );
  }

  void _showAll(BuildContext context) {
    // The page's context, for opening one after the sheet closes.
    final router = GoRouter.of(context);
    showSpSheet<void>(
      context,
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SpSheetHeader(
            icon: Icons.push_pin_outlined,
            title: 'Pinned',
            subtitle: 'Urgent and unread first',
          ),
          PinnedAnnouncements(
            groupId: groupId,
            teamId: teamId,
            onOpen: (a) {
              Navigator.of(sheet).pop();
              router.push('/inbox/announcements/${a.id}');
            },
          ),
        ],
      ),
    );
  }
}

/// Event page (organisers and group admins): "Message participants".
class EventAnnounceCard extends ConsumerWidget {
  const EventAnnounceCard(
      {super.key, required this.groupId, required this.eventId});
  final String groupId;
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final composer =
        ref.watch(announcementComposerProvider(groupId)).valueOrNull;
    if (composer == null || !composer.canAddressEvent(eventId)) {
      return const SizedBox.shrink();
    }
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        onTap: () =>
            context.push('/groups/$groupId/announcements/new?event=$eventId'),
        child: Row(children: [
          SpIconTile(Icons.campaign_outlined,
              bg: p.accentTint, fg: p.greenText, size: 40, iconSize: 20),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Message participants',
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              Text("An announcement to who's going or checked in",
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ]),
      ),
    );
  }
}

/// The group page's announcements button (members): mute the group's
/// announcements, and — for staff — compose or see what was sent.
class GroupAnnouncementsButton extends ConsumerWidget {
  const GroupAnnouncementsButton(
      {super.key, required this.groupId, required this.groupName});
  final String groupId;
  final String groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = ref
            .watch(mutedAnnouncementGroupsProvider)
            .valueOrNull
            ?.contains(groupId) ??
        false;
    return SpRoundButton(
      icon: muted ? Icons.notifications_off_outlined : Icons.campaign_outlined,
      tooltip: 'Announcements',
      onTap: () => showGroupAnnouncementsSheet(context,
          groupId: groupId, groupName: groupName),
    );
  }
}

/// A group's announcements sheet: "Mute announcements" and, for staff,
/// compose / sent. [withInbox] puts "Open Inbox" on top (the group page's
/// Talk section — pinned announcements have their own section on the page);
/// [canMute] false leaves the mute switch out (the viewer isn't a member).
/// With [teamId] it's the team page's: the staff part is "Announce to team"
/// and Sent, for the group's admins and the team's coaches ([groupName] is
/// then the team's name, the sheet's subtitle).
Future<void> showGroupAnnouncementsSheet(
  BuildContext context, {
  required String groupId,
  required String groupName,
  bool withInbox = false,
  bool canMute = true,
  String? teamId,
}) =>
    showSpSheet<void>(
      context,
      builder: (_) => _GroupAnnouncementsSheet(
        groupId: groupId,
        groupName: groupName,
        withInbox: withInbox,
        canMute: canMute,
        teamId: teamId,
      ),
    );

class _GroupAnnouncementsSheet extends ConsumerStatefulWidget {
  const _GroupAnnouncementsSheet({
    required this.groupId,
    required this.groupName,
    required this.withInbox,
    required this.canMute,
    this.teamId,
  });
  final String groupId;
  final String groupName;
  final bool withInbox;
  final bool canMute;
  final String? teamId;

  @override
  ConsumerState<_GroupAnnouncementsSheet> createState() =>
      _GroupAnnouncementsSheetState();
}

class _GroupAnnouncementsSheetState
    extends ConsumerState<_GroupAnnouncementsSheet> {
  bool? _muted; // optimistic value while saving
  bool _busy = false;

  Future<void> _toggle(bool v) async {
    // The sheet may be closed before the save lands; the container outlives
    // it, so the group page's button still picks up the change.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _muted = v;
      _busy = true;
    });
    try {
      await ref
          .read(announcementsRepositoryProvider)
          .setMuted(widget.groupId, v);
      container.invalidate(mutedAnnouncementGroupsProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _muted = !v);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _go(String path) {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.push(path);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final mutedAsync = ref.watch(mutedAnnouncementGroupsProvider);
    final muted =
        _muted ?? mutedAsync.valueOrNull?.contains(widget.groupId) ?? false;
    final composer =
        ref.watch(announcementComposerProvider(widget.groupId)).valueOrNull;
    final teamId = widget.teamId;
    // Staff tools: the group's staff here; a team's admins and coaches there.
    final canCompose =
        composer != null && (teamId == null || composer.canAddressTeam(teamId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.campaign_outlined,
          title: 'Announcements',
          subtitle: widget.groupName,
        ),
        if (widget.withInbox) ...[
          SpListCard(children: [
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Open Inbox'),
              subtitle: Text('All your announcements, from every group',
                  style: TextStyle(color: p.muted, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _go('/inbox'),
            ),
          ]),
        ],
        if (widget.canMute) ...[
          if (widget.withInbox) const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mute announcements'),
              subtitle: Text('Urgent ones still come through',
                  style: TextStyle(color: p.muted, fontSize: 12)),
              value: muted,
              onChanged:
                  _busy || !mutedAsync.hasValue ? null : (v) => _toggle(v),
            ),
          ),
        ],
        if (canCompose) ...[
          if (widget.withInbox || widget.canMute) const SizedBox(height: 12),
          SpListCard(children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(
                  teamId == null ? 'New announcement' : 'Announce to team'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _go(teamId == null
                  ? '/groups/${widget.groupId}/announcements/new'
                  : '/groups/${widget.groupId}/announcements/new?team=$teamId'),
            ),
            ListTile(
              leading: const Icon(Icons.outbox_outlined),
              title: const Text('Sent announcements'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _go('/groups/${widget.groupId}/announcements'),
            ),
          ]),
        ],
      ],
    );
  }
}

/// Settings → Announcements: push and email for normal and urgent ones.
class AnnouncementPreferencesCard extends ConsumerStatefulWidget {
  const AnnouncementPreferencesCard({super.key});

  @override
  ConsumerState<AnnouncementPreferencesCard> createState() =>
      _AnnouncementPreferencesCardState();
}

class _AnnouncementPreferencesCardState
    extends ConsumerState<AnnouncementPreferencesCard> {
  static const _rows = [
    (
      category: 'announcements',
      title: 'Announcements',
      subtitle: 'News from your groups, teams and event organisers',
    ),
    (
      category: 'announcements_urgent',
      title: 'Urgent announcements',
      subtitle: 'Time-critical news — comes through even for muted groups',
    ),
  ];

  /// Values being saved, shown before the server confirms them.
  final Map<String, NotificationPreference> _pending = {};

  Future<void> _set(NotificationPreference cur,
      {bool? push, bool? email}) async {
    final container = ProviderScope.containerOf(context, listen: false);
    setState(
        () => _pending[cur.category] = cur.copyWith(push: push, email: email));
    try {
      await ref
          .read(announcementsRepositoryProvider)
          .setPreference(cur.category, push: push, email: email);
      container.invalidate(notificationPreferencesProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pending.remove(cur.category));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final prefs = ref.watch(notificationPreferencesProvider);
    final list = prefs.valueOrNull;
    if (list == null) {
      return GlassCard(
        child: prefs.hasError
            ? Row(children: [
                Expanded(
                  child: Text("Couldn't load these settings.",
                      style: TextStyle(color: p.muted, fontSize: 13)),
                ),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(notificationPreferencesProvider),
                  child: const Text('Retry'),
                ),
              ])
            : Text('Loading…', style: TextStyle(color: p.muted, fontSize: 13)),
      );
    }
    NotificationPreference prefFor(String c) =>
        _pending[c] ??
        list.firstWhere((x) => x.category == c,
            orElse: () => NotificationPreference(category: c));
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _rows.length; i++) ...[
            if (i > 0) Divider(height: 20, color: p.surface2),
            Text(_rows[i].title,
                style: TextStyle(
                    color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
            Text(_rows[i].subtitle,
                style: TextStyle(color: p.muted, fontSize: 12)),
            Builder(builder: (context) {
              final cur = prefFor(_rows[i].category);
              return Column(children: [
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Push notifications'),
                  value: cur.push,
                  onChanged: (v) => _set(cur, push: v),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Email'),
                  value: cur.email,
                  onChanged: (v) => _set(cur, email: v),
                ),
              ]);
            }),
          ],
        ],
      ),
    );
  }
}

/// Settings → Events: one on/off switch for "New event in <group>"
/// notifications (in-app + push). Off means none at all. Stored as the
/// `events` category's push flag; defaults on.
class EventNotificationsCard extends ConsumerStatefulWidget {
  const EventNotificationsCard({super.key});

  @override
  ConsumerState<EventNotificationsCard> createState() =>
      _EventNotificationsCardState();
}

class _EventNotificationsCardState
    extends ConsumerState<EventNotificationsCard> {
  bool? _pending;

  Future<void> _set(bool v) async {
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _pending = v);
    try {
      await ref
          .read(announcementsRepositoryProvider)
          .setPreference('events', push: v);
      container.invalidate(notificationPreferencesProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pending = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final list = ref.watch(notificationPreferencesProvider).valueOrNull;
    final saved = list
            ?.firstWhere((x) => x.category == 'events',
                orElse: () => const NotificationPreference(category: 'events'))
            .push ??
        true;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('New events',
            style: TextStyle(
                color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
        subtitle: Text(
            'When your groups or teams create an event, and when groups you '
            'follow post a public one. Includes events for your wards.',
            style: TextStyle(color: p.muted, fontSize: 12)),
        value: _pending ?? saved,
        onChanged: list == null ? null : _set,
      ),
    );
  }
}
