import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/group_models.dart';
import 'package:sportpadi_mobile/data/messages/message_models.dart';
import 'package:sportpadi_mobile/data/messages/messages_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/inbox/message_widgets.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Starting a conversation (docs B4/B5). Every conversation has staff on one
/// side, so the choices are only ever:
///   • members / guardians: "Contact the admins" (one shared thread per
///     member per group) or "Message coach" (a coach of their own team);
///   • staff: a member they manage — a ward's thread goes to the guardians.
/// There is no member directory for members.

/// Who a new conversation goes to.
class MessageTarget {
  const MessageTarget._({
    required this.kind,
    required this.groupId,
    required this.toLabel,
    this.memberId,
    this.coachId,
    this.aboutWardId,
    this.aboutWardName,
    this.note,
  });

  /// Staff → a member (a ward: their guardians).
  factory MessageTarget.member({
    required String groupId,
    required String memberId,
    required String name,
    bool isWard = false,
  }) =>
      MessageTarget._(
        kind: 'staff',
        groupId: groupId,
        memberId: memberId,
        toLabel: isWard ? "$name's guardians" : name,
        aboutWardName: isWard ? name : null,
        note: isWard
            ? "$name is a ward: this goes to their guardians."
            : null,
      );

  /// Me (or a ward of mine) → the group's admins.
  factory MessageTarget.admins({
    required String groupId,
    required String groupName,
    String? aboutWardId,
    String? aboutWardName,
  }) =>
      MessageTarget._(
        kind: 'admins',
        groupId: groupId,
        toLabel: '$groupName admins',
        aboutWardId: aboutWardId,
        aboutWardName: aboutWardName,
        note: 'Every admin of the group sees this and can answer.',
      );

  /// Me (or a ward of mine) → a coach of our team.
  factory MessageTarget.coach({
    required String groupId,
    required String coachId,
    required String coachName,
    String? aboutWardId,
    String? aboutWardName,
  }) =>
      MessageTarget._(
        kind: 'coach',
        groupId: groupId,
        coachId: coachId,
        toLabel: coachName,
        aboutWardId: aboutWardId,
        aboutWardName: aboutWardName,
      );

  /// Not a recipient: "let me pick a member" (staff).
  const MessageTarget._pick(String groupId)
      : this._(kind: 'pick', groupId: groupId, toLabel: '');

  /// `staff` · `admins` · `coach` · `pick`.
  final String kind;
  final String groupId;
  final String toLabel;
  final String? memberId;
  final String? coachId;
  final String? aboutWardId;

  /// Shown as "About Tobi".
  final String? aboutWardName;
  final String? note;
}

/// Inbox → New message: pick one of my groups, then what to start there.
Future<void> startNewMessage(BuildContext context) async {
  final groupId = await showSpSheet<String>(
    context,
    scrollable: false,
    padding: EdgeInsets.zero,
    builder: (_) => const _GroupPickerSheet(),
  );
  if (groupId == null || !context.mounted) return;
  await showMessageStartSheet(context, groupId: groupId);
}

/// What I can start in [groupId]: Contact the admins, my coaches and — for
/// staff — "Message a member". [wardId] narrows it to one ward's options
/// ("About Tobi", from the ward's page); [teamId] to one team's coaches.
Future<void> showMessageStartSheet(
  BuildContext context, {
  required String groupId,
  String? wardId,
  String? teamId,
}) async {
  final target = await showSpSheet<MessageTarget>(
    context,
    builder: (_) => _StartOptionsSheet(
        groupId: groupId, wardId: wardId, teamId: teamId),
  );
  if (target == null || !context.mounted) return;
  if (target.kind == 'pick') {
    await pickMemberToMessage(context, groupId: groupId);
  } else {
    await composeFirstMessage(context, target);
  }
}

/// Staff: search the members I can message, then write to one.
Future<void> pickMemberToMessage(BuildContext context,
    {required String groupId}) async {
  final person = await showSpSheet<ReachablePerson>(
    context,
    scrollable: false,
    padding: EdgeInsets.zero,
    builder: (_) => _ReachablePickerSheet(groupId: groupId),
  );
  if (person == null || !context.mounted) return;
  await composeFirstMessage(
    context,
    MessageTarget.member(
      groupId: groupId,
      memberId: person.userId,
      name: person.name,
      isWard: person.isWard,
    ),
  );
}

/// Write the first message to [target]; on send, open the thread.
Future<void> composeFirstMessage(
    BuildContext context, MessageTarget target) async {
  final router = GoRouter.of(context);
  final id = await showSpSheet<String>(
    context,
    builder: (_) => _FirstMessageSheet(target: target),
  );
  if (id == null) return;
  router.push('/inbox/messages/$id');
}

// ── Group picker ─────────────────────────────────────────────────────────

class _GroupPickerSheet extends ConsumerWidget {
  const _GroupPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final groups = ref.watch(myGroupsProvider);
    Widget body;
    final list = groups.valueOrNull;
    if (list == null) {
      body = Center(
        child: groups.hasError
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${groups.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted)),
                  TextButton(
                    onPressed: () => ref.invalidate(myGroupsProvider),
                    child: const Text('Retry'),
                  ),
                ]),
              )
            : const CircularProgressIndicator(),
      );
    } else if (list.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
              "You're not in any groups yet. Messages are with a group's "
              'admins and coaches.',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13)),
        ),
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        itemCount: list.length,
        itemBuilder: (_, i) {
          final GroupSummary g = list[i];
          return ListTile(
            leading: Crest(logoUrl: g.logoUrl, label: g.name, size: 40),
            title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: g.role == 'admin'
                ? Text('Admin',
                    style: TextStyle(color: p.muted, fontSize: 12))
                : null,
            trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
            onTap: () => Navigator.of(context).pop(g.id),
          );
        },
      );
    }
    return Column(children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: SpSheetHeader(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'New message',
          subtitle: 'Which group is it about?',
        ),
      ),
      Expanded(child: body),
    ]);
  }
}

// ── Supervised players ───────────────────────────────────────────────────

/// A supervised player (claimed their account under 18, Wards 3) can't
/// message staff: the server's reason, as a quiet note where "Contact the
/// admins" / "Message coach" would be.
class SelfBlockedNote extends StatelessWidget {
  const SelfBlockedNote(this.reason, {super.key});
  final String reason;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lock_outline_rounded, size: 17, color: p.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(reason,
              style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
        ),
      ]),
    );
  }
}

// ── Start options ────────────────────────────────────────────────────────

class _StartOptionsSheet extends ConsumerWidget {
  const _StartOptionsSheet(
      {required this.groupId, this.wardId, this.teamId});
  final String groupId;
  final String? wardId;
  final String? teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final async = ref.watch(messageStartOptionsProvider(groupId));
    final o = async.valueOrNull;
    if (o == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: async.hasError
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${async.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted)),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(messageStartOptionsProvider(groupId)),
                    child: const Text('Retry'),
                  ),
                ])
              : const CircularProgressIndicator(),
        ),
      );
    }
    bool forThis(StartFor f) => wardId == null || f.wardId == wardId;
    final admins = [
      for (final c in o.adminContacts)
        if (forThis(c) && teamId == null) c
    ];
    final coaches = <({CoachOption coach, StartFor forWho})>[
      for (final c in o.coaches)
        if (teamId == null || c.coachesTeam(teamId!))
          for (final f in c.forWho)
            if (forThis(f)) (coach: c, forWho: f)
    ];
    final staff = o.asStaff;
    final showStaff = staff != null && wardId == null && teamId == null;
    void pop(MessageTarget t) => Navigator.of(context).pop(t);

    Widget option({
      required IconData icon,
      required String title,
      String? subtitle,
      String? about,
      Widget? leading,
      required VoidCallback onTap,
    }) =>
        ListTile(
          leading: leading ??
              SpIconTile(icon,
                  size: 40, iconSize: 20, bg: p.accentTint, fg: p.greenText),
          title: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
          subtitle: subtitle == null && about == null
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subtitle != null)
                      Text(subtitle,
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    if (about != null) ...[
                      const SizedBox(height: 4),
                      AboutWardChip(about),
                    ],
                  ]),
          trailing: Icon(Icons.chevron_right_rounded, color: p.muted),
          onTap: onTap,
        );

    // Supervised player: their own member-side options are closed (the
    // server leaves them out); say why. Not on a ward's page.
    final blocked = wardId == null ? o.selfBlockedReason : null;
    final empty = admins.isEmpty && coaches.isEmpty && !showStaff;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Message',
          subtitle: o.group.name,
        ),
        if (blocked != null) ...[
          SelfBlockedNote(blocked),
          if (!empty) const SizedBox(height: 12),
        ] else if (empty)
          GlassCard(
            child: Text(
              teamId != null
                  ? "This team has no coach you can message yet."
                  : "There's no one you can message in this group yet. "
                      "Messages are always with the group's admins or your "
                      'coaches.',
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
            ),
          ),
        if (admins.isNotEmpty || coaches.isNotEmpty)
          SpListCard(children: [
            for (final c in admins)
              option(
                icon: Icons.admin_panel_settings_outlined,
                title: 'Contact the admins',
                subtitle: 'Every admin of ${o.group.name} can answer',
                about: c.isMe ? null : c.name,
                onTap: () => pop(MessageTarget.admins(
                  groupId: groupId,
                  groupName: o.group.name,
                  aboutWardId: c.wardId,
                  aboutWardName: c.isMe ? null : c.name,
                )),
              ),
            for (final e in coaches)
              option(
                icon: Icons.sports_rounded,
                leading: WardAvatar(
                    name: e.coach.name, url: e.coach.avatarUrl, size: 40),
                title: 'Message ${e.coach.name}',
                subtitle: e.coach.teams.isEmpty
                    ? 'Coach'
                    : 'Coach · ${e.coach.teams.join(', ')}',
                about: e.forWho.isMe ? null : e.forWho.name,
                onTap: () => pop(MessageTarget.coach(
                  groupId: groupId,
                  coachId: e.coach.userId,
                  coachName: e.coach.name,
                  aboutWardId: e.forWho.wardId,
                  aboutWardName: e.forWho.isMe ? null : e.forWho.name,
                )),
              ),
          ]),
        if (showStaff) ...[
          if (admins.isNotEmpty || coaches.isNotEmpty)
            const SizedBox(height: 12),
          SpListCard(children: [
            option(
              icon: Icons.person_search_outlined,
              title: 'Message a member',
              subtitle: staff.isAdmin
                  ? 'Anyone in the group — wards through their guardians'
                  : 'Players on the teams you coach, or their guardians',
              onTap: () => pop(MessageTarget._pick(groupId)),
            ),
          ]),
        ],
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.visibility_outlined, size: 15, color: p.muted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
                "Visible to ${o.group.name}'s admins. Messages are for "
                'club information — members never message each other.',
                style: TextStyle(color: p.muted, fontSize: 12, height: 1.4)),
          ),
        ]),
      ],
    );
  }
}

// ── Staff: member picker ─────────────────────────────────────────────────

class _ReachablePickerSheet extends ConsumerStatefulWidget {
  const _ReachablePickerSheet({required this.groupId});
  final String groupId;

  @override
  ConsumerState<_ReachablePickerSheet> createState() =>
      _ReachablePickerSheetState();
}

class _ReachablePickerSheetState extends ConsumerState<_ReachablePickerSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ReachablePerson>? _results;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final seq = ++_seq;
    try {
      final r = await ref
          .read(messagesRepositoryProvider)
          .reachable(widget.groupId, q: q);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = r;
        _error = null;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _error = '$e');
    }
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(q));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final results = _results;
    return Column(children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: SpSheetHeader(
          icon: Icons.person_search_outlined,
          title: 'Message a member',
          subtitle: "Wards' messages go to their guardians.",
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: TextField(
          controller: _search,
          onChanged: _onSearch,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search by name',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
      ),
      Expanded(
        child: results == null
            ? Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.muted)),
                      )
                    : const CircularProgressIndicator(),
              )
            : results.isEmpty
                ? Center(
                    child: Text('Nobody matches.',
                        style: TextStyle(color: p.muted)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final u = results[i];
                      return ListTile(
                        leading:
                            WardAvatar(name: u.name, url: u.avatarUrl, size: 36),
                        title: Row(children: [
                          Flexible(
                            child: Text(u.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          if (u.isWard) ...[
                            const SizedBox(width: 6),
                            const WardBadge(),
                          ],
                        ]),
                        subtitle: u.isWard
                            ? Text('Goes to their guardians',
                                style: TextStyle(
                                    color: p.wardInk, fontSize: 11.5))
                            : null,
                        trailing:
                            Icon(Icons.chevron_right_rounded, color: p.muted),
                        onTap: () => Navigator.of(context).pop(u),
                      );
                    },
                  ),
      ),
    ]);
  }
}

// ── First message ────────────────────────────────────────────────────────

class _FirstMessageSheet extends ConsumerStatefulWidget {
  const _FirstMessageSheet({required this.target});
  final MessageTarget target;

  @override
  ConsumerState<_FirstMessageSheet> createState() => _FirstMessageSheetState();
}

class _FirstMessageSheetState extends ConsumerState<_FirstMessageSheet> {
  static const _maxImages = 4;
  final _body = TextEditingController();
  final List<MessageAttachment> _images = [];
  bool _uploading = false;
  bool _sending = false;
  String? _error;

  MessageTarget get t => widget.target;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending &&
      !_uploading &&
      (_body.text.trim().isNotEmpty || _images.isNotEmpty);

  Future<void> _addImage() async {
    if (_images.length >= _maxImages || _uploading) return;
    setState(() => _uploading = true);
    try {
      final a = await pickMessageImage(ref, t.groupId);
      if (a != null && mounted) setState(() => _images.add(a));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _send() async {
    if (!_canSend) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final repo = ref.read(messagesRepositoryProvider);
    final body = _body.text.trim();
    final images = List.of(_images);
    try {
      final String id;
      switch (t.kind) {
        case 'staff':
          id = await repo.startAsStaff(
              groupId: t.groupId,
              memberId: t.memberId ?? '',
              body: body,
              attachments: images);
        case 'coach':
          id = await repo.messageCoach(
              groupId: t.groupId,
              coachId: t.coachId ?? '',
              aboutWardId: t.aboutWardId,
              body: body,
              attachments: images);
        default:
          id = await repo.contactAdmins(
              groupId: t.groupId,
              aboutWardId: t.aboutWardId,
              body: body,
              attachments: images);
      }
      if (!mounted) return;
      ref.invalidate(messagesListProvider);
      ref.invalidate(messagesUnreadProvider);
      Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.edit_outlined,
          title: 'New message',
          subtitle: 'To ${t.toLabel}',
        ),
        if (t.aboutWardName != null || t.note != null) ...[
          Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (t.aboutWardName != null) AboutWardChip(t.aboutWardName!),
                if (t.note != null)
                  Text(t.note!,
                      style: TextStyle(color: p.muted, fontSize: 12)),
              ]),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _body,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          maxLength: 2000,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'Write your message'),
        ),
        if (_images.isNotEmpty) ...[
          const SizedBox(height: 6),
          PendingImagesStrip(
            images: _images,
            onRemove: (a) => setState(() => _images.remove(a)),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          SpRoundPhotoButton(
            busy: _uploading,
            onTap: _images.length >= _maxImages || _sending ? null : _addImage,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SpButton(
              label: _sending ? 'Sending…' : 'Send',
              icon: Icons.send_rounded,
              tone: SpButtonTone.brand,
              expand: true,
              onTap: _canSend ? _send : null,
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Text("Visible to the group's admins.",
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 11.5)),
      ],
    );
  }
}

/// A round "add photo" button (with a spinner while uploading).
class SpRoundPhotoButton extends StatelessWidget {
  const SpRoundPhotoButton({super.key, required this.onTap, this.busy = false});
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.add_photo_alternate_outlined,
                  size: 21, color: onTap == null ? p.muted : p.ink),
        ),
      ),
    );
  }
}
