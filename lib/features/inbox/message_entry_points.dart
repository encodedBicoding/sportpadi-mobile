import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/announcements/announcement_models.dart';
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart';
import 'package:sportpadi_mobile/data/messages/message_models.dart';
import 'package:sportpadi_mobile/data/messages/messages_repository.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/features/inbox/message_start.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Where messages start outside the Inbox (docs B4/B5): the group page
/// ("Contact the admins", "Message coach", and for admins "Conversations"),
/// the team page ("Message coach", and for its staff "Message a player"),
/// member rows for staff, the ward page, and Settings.
/// Everything reads `start-options`, so a button only shows when the server
/// would accept what it starts.

/// Group page (its Talk section's Messages sheet): members' "Contact the
/// admins" / "Message coach", staff's "Message a member" and admins'
/// "Conversations". Inside a sheet, pass [launch] so the sheet closes before
/// anything opens.
class GroupMessagesSection extends ConsumerWidget {
  const GroupMessagesSection({
    super.key,
    required this.groupId,
    this.launch,
    this.padding = const EdgeInsets.only(bottom: 14),
  });
  final String groupId;
  final SheetLaunch? launch;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(messageStartOptionsProvider(groupId)).valueOrNull;
    if (o == null) return const SizedBox.shrink();
    final admins = o.adminContacts;
    final hasCoaches = o.coaches.isNotEmpty;
    final staff = o.asStaff;
    // A supervised player (Wards 3) has no direct line to staff: the note
    // takes the place of the member-side buttons.
    final blocked = o.selfBlockedReason;
    if (admins.isEmpty && !hasCoaches && staff == null && blocked == null) {
      return const SizedBox.shrink();
    }
    void run(void Function(BuildContext context) action) =>
        runFromSheet(context, launch, action);
    final memberButtons = <Widget>[
      if (blocked == null && admins.isNotEmpty)
        _QuietButton(
          label: 'Contact the admins',
          icon: Icons.admin_panel_settings_outlined,
          onTap: () => run((c) => contactGroupAdmins(c, o)),
        ),
      if (blocked == null && hasCoaches)
        _QuietButton(
          label: 'Message coach',
          icon: Icons.sports_rounded,
          onTap: () =>
              run((c) => showMessageStartSheet(c, groupId: groupId)),
        ),
    ];
    final staffButtons = <Widget>[
      if (staff != null)
        _QuietButton(
          label: 'Message a member',
          icon: Icons.chat_bubble_outline_rounded,
          onTap: () => run((c) => pickMemberToMessage(c, groupId: groupId)),
        ),
      if (staff != null && staff.isAdmin)
        _QuietButton(
          label: 'Conversations',
          icon: Icons.forum_outlined,
          onTap: () => run((c) => c.push('/groups/$groupId/messages')),
        ),
    ];
    Widget row(List<Widget> buttons) => Row(children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: buttons[i]),
          ],
        ]);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (blocked != null)
            SelfBlockedNote(blocked)
          else if (memberButtons.isNotEmpty)
            row(memberButtons),
          if ((blocked != null || memberButtons.isNotEmpty) &&
              staffButtons.isNotEmpty)
            const SizedBox(height: 8),
          if (staffButtons.isNotEmpty) row(staffButtons),
        ],
      ),
    );
  }
}

/// "Contact the admins": straight to the message when there's one thread to
/// open (me, or my only ward), otherwise ask who it's about first.
Future<void> contactGroupAdmins(BuildContext context, StartOptions o,
    {String? wardId}) async {
  final entries = [
    for (final c in o.adminContacts)
      if (wardId == null || c.wardId == wardId) c
  ];
  if (entries.isEmpty) return;
  StartFor? who = entries.length == 1 ? entries.first : null;
  who ??= await showSpSheet<StartFor>(
    context,
    builder: (ctx) {
      final p = ctx.palette;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SpSheetHeader(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Contact the admins',
            subtitle: 'Who is it about?',
          ),
          SpListCard(children: [
            for (final c in entries)
              ListTile(
                leading: Icon(
                    c.isMe ? Icons.person_outline_rounded
                        : Icons.child_care_rounded,
                    color: c.isMe ? p.ink : p.wardInk),
                title: Text(c.isMe ? 'Me' : 'About ${c.name}'),
                trailing:
                    Icon(Icons.chevron_right_rounded, color: p.muted),
                onTap: () => Navigator.of(ctx).pop(c),
              ),
          ]),
        ],
      );
    },
  );
  if (who == null || !context.mounted) return;
  await composeFirstMessage(
    context,
    MessageTarget.admins(
      groupId: o.group.id,
      groupName: o.group.name,
      aboutWardId: who.wardId,
      aboutWardName: who.isMe ? null : who.name,
    ),
  );
}

/// The coaches of [teamId] I (or a ward of mine on it) can message — what
/// start-options offers for this team.
List<CoachOption> teamCoachOptions(StartOptions? o, String teamId) => [
      for (final c in o?.coaches ?? const <CoachOption>[])
        if (c.coachesTeam(teamId)) c
    ];

/// Whether I can message this team's players: the group's admins and the
/// team's coaches.
bool canMessageTeamPlayers(StartOptions? o, String teamId) {
  final staff = o?.asStaff;
  return staff != null && (staff.isAdmin || staff.coaches(teamId));
}

/// Team page (its Talk section's Messages sheet): "Message coach" for the
/// team's players and their guardians (the coaches of THIS team), and
/// "Message a player" for its coaches and the group's admins. Inside a
/// sheet, pass [launch] so the sheet closes before anything opens.
class TeamMessagesSection extends ConsumerWidget {
  const TeamMessagesSection({
    super.key,
    required this.groupId,
    required this.teamId,
    this.launch,
    this.padding = EdgeInsets.zero,
  });
  final String groupId;
  final String teamId;
  final SheetLaunch? launch;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(messageStartOptionsProvider(groupId)).valueOrNull;
    // A supervised player (Wards 3): no "Message coach" — say why instead.
    final blocked = o?.selfBlockedReason;
    final coaches =
        blocked == null ? teamCoachOptions(o, teamId) : const <CoachOption>[];
    final toPlayers = canMessageTeamPlayers(o, teamId);
    if (coaches.isEmpty && !toPlayers && blocked == null) {
      return const SizedBox.shrink();
    }
    void run(void Function(BuildContext context) action) =>
        runFromSheet(context, launch, action);
    final buttons = <Widget>[
      if (blocked != null) SelfBlockedNote(blocked),
      if (coaches.isNotEmpty)
        _QuietButton(
          label: coaches.length == 1
              ? 'Message ${coaches.first.name}'
              : 'Message coach',
          icon: Icons.sports_rounded,
          onTap: () => run((c) => _messageTeamCoach(c, coaches)),
        ),
      if (toPlayers)
        _QuietButton(
          label: 'Message a player',
          icon: Icons.chat_bubble_outline_rounded,
          onTap: () => run((c) =>
              pickTeamPlayerToMessage(c, groupId: groupId, teamId: teamId)),
        ),
    ];
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            buttons[i],
          ],
        ],
      ),
    );
  }

  /// Straight to the message when there's one coach and one thread (me, or
  /// my only ward); otherwise the start sheet, narrowed to this team.
  void _messageTeamCoach(BuildContext context, List<CoachOption> coaches) {
    final only = coaches.length == 1 && coaches.first.forWho.length == 1
        ? coaches.first
        : null;
    if (only == null) {
      showMessageStartSheet(context, groupId: groupId, teamId: teamId);
      return;
    }
    final f = only.forWho.first;
    composeFirstMessage(
      context,
      MessageTarget.coach(
        groupId: groupId,
        coachId: only.userId,
        coachName: only.name,
        aboutWardId: f.wardId,
        aboutWardName: f.isMe ? null : f.name,
      ),
    );
  }
}

/// Staff: pick one of the team's players I can message (a ward's thread
/// goes to their guardians), then write to them.
Future<void> pickTeamPlayerToMessage(BuildContext context,
    {required String groupId, required String teamId}) async {
  final player = await showSpSheet<TeamMember>(
    context,
    builder: (_) => _TeamPlayerPickerSheet(groupId: groupId, teamId: teamId),
  );
  if (player == null || !context.mounted) return;
  await composeFirstMessage(
    context,
    MessageTarget.member(
      groupId: groupId,
      memberId: player.playerId,
      name: player.displayName,
      isWard: player.isWard,
    ),
  );
}

/// The team's roster, narrowed to who I can reach.
class _TeamPlayerPickerSheet extends ConsumerWidget {
  const _TeamPlayerPickerSheet({required this.groupId, required this.teamId});
  final String groupId;
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final team = ref.watch(teamDetailProvider(teamId));
    final reachable = ref.watch(messageReachableIdsProvider(groupId));
    final t = team.valueOrNull;
    final roster = t?.members;
    final ids = reachable.valueOrNull;
    final failed = team.hasError || reachable.hasError;
    final players = roster == null || ids == null
        ? null
        : [
            for (final m in roster)
              if (ids.contains(m.playerId)) m
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.person_search_outlined,
          title: 'Message a player',
          subtitle: t == null
              ? "Wards' messages go to their guardians."
              : "${t.name} · wards' messages go to their guardians.",
        ),
        if (players == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: failed
                  ? Text("Couldn't load the players.",
                      style: TextStyle(color: p.muted))
                  : const CircularProgressIndicator(),
            ),
          )
        else if (players.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No players you can message on this team yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted)),
          )
        else
          SpListCard(children: [
            for (final m in players)
              ListTile(
                leading: WardAvatar(
                    name: m.displayName, url: m.avatarUrl, size: 36),
                title: Row(children: [
                  Flexible(
                    child: Text(m.displayName,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (m.isWard) ...[
                    const SizedBox(width: 6),
                    const WardBadge(),
                  ],
                ]),
                subtitle: m.isWard
                    ? Text('Goes to their guardians',
                        style: TextStyle(color: p.wardInk, fontSize: 11.5))
                    : null,
                trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
                onTap: () => Navigator.of(context).pop(m),
              ),
          ]),
      ],
    );
  }
}

/// Staff: a small "Message" button on a member / roster row. Shows only for
/// people the viewer can reach (admins: anyone; coaches: their players).
class MessageMemberButton extends ConsumerWidget {
  const MessageMemberButton({
    super.key,
    required this.groupId,
    required this.memberId,
    required this.name,
    this.isWard = false,
  });
  final String groupId;
  final String memberId;
  final String name;
  final bool isWard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reachable =
        ref.watch(messageReachableIdsProvider(groupId)).valueOrNull;
    if (reachable == null || !reachable.contains(memberId)) {
      return const SizedBox.shrink();
    }
    final p = context.palette;
    return IconButton(
      tooltip: isWard ? "Message $name's guardians" : 'Message $name',
      visualDensity: VisualDensity.compact,
      icon: Icon(Icons.chat_bubble_outline_rounded,
          size: 19, color: p.greenText),
      onPressed: () => composeFirstMessage(
        context,
        MessageTarget.member(
          groupId: groupId,
          memberId: memberId,
          name: name,
          isWard: isWard,
        ),
      ),
    );
  }
}

/// Ward page, per group: "Message coach" / "Contact the admins" about the
/// ward. Hidden when there's nothing to start for them there.
class WardGroupMessageButton extends ConsumerWidget {
  const WardGroupMessageButton({
    super.key,
    required this.groupId,
    required this.wardId,
    required this.wardName,
  });
  final String groupId;
  final String wardId;
  final String wardName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(messageStartOptionsProvider(groupId)).valueOrNull;
    if (o == null) return const SizedBox.shrink();
    final admins = o.adminContacts.any((c) => c.wardId == wardId);
    final coaches =
        o.coaches.any((c) => c.forWho.any((f) => f.wardId == wardId));
    if (!admins && !coaches) return const SizedBox.shrink();
    final p = context.palette;
    Widget chip(IconData icon, String label, VoidCallback onTap) => ActionChip(
          avatar: Icon(icon, size: 16, color: p.wardInk),
          label: Text(label),
          labelStyle: TextStyle(
              color: p.wardInk, fontSize: 12, fontWeight: FontWeight.w700),
          backgroundColor: p.wardTint,
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
        );
    return Semantics(
      container: true,
      label: 'Messages about $wardName',
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        if (coaches)
          chip(
              Icons.sports_rounded,
              'Message coach',
              () => showMessageStartSheet(context,
                  groupId: groupId, wardId: wardId)),
        if (admins)
          chip(Icons.admin_panel_settings_outlined, 'Contact the admins',
              () => contactGroupAdmins(context, o, wardId: wardId)),
      ]),
    );
  }
}

/// Settings → Messages: push on/off for new messages (category `messages`).
/// Per-conversation mute lives in each thread's menu.
class MessageNotificationsCard extends ConsumerStatefulWidget {
  const MessageNotificationsCard({super.key});

  @override
  ConsumerState<MessageNotificationsCard> createState() =>
      _MessageNotificationsCardState();
}

class _MessageNotificationsCardState
    extends ConsumerState<MessageNotificationsCard> {
  bool? _pending;

  Future<void> _set(bool v) async {
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _pending = v);
    try {
      await ref
          .read(announcementsRepositoryProvider)
          .setPreference('messages', push: v);
      container.invalidate(notificationPreferencesProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _pending = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final list = ref.watch(notificationPreferencesProvider).valueOrNull;
    final saved = list
            ?.firstWhere((x) => x.category == 'messages',
                orElse: () =>
                    const NotificationPreference(category: 'messages'))
            .push ??
        true;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Push notifications',
            style: TextStyle(
                color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
        subtitle: Text(
            'New messages from your admins and coaches (and, for staff, '
            'from members). Mute a single conversation from its menu.',
            style: TextStyle(color: p.muted, fontSize: 12)),
        value: _pending ?? saved,
        onChanged: list == null ? null : _set,
      ),
    );
  }
}

/// A quiet outlined pill button (matches the announcements entry points).
class _QuietButton extends StatelessWidget {
  const _QuietButton(
      {required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface,
      shape: StadiumBorder(side: BorderSide(color: p.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 17, color: p.ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}
