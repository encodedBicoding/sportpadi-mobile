import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/features/manage/add_team_player.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';

class _MemberEdit {
  const _MemberEdit(this.positions, this.jersey, this.starter);
  final List<String> positions;
  final int? jersey;
  final bool starter;
}

class ManageRosterScreen extends ConsumerWidget {
  const ManageRosterScreen({super.key, required this.teamId});
  final String teamId;

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// The web's Add player flow, shared with the team page.
  Future<void> _add(BuildContext context, WidgetRef ref, TeamDetail team) =>
      addTeamPlayer(context, ref, team);

  Future<void> _edit(BuildContext context, WidgetRef ref, TeamDetail team,
      TeamMember m) async {
    final edit = await showSpSheet<_MemberEdit>(
      context,
      builder: (_) => _MemberSheet(
        title: m.displayName,
        options: team.positionOptions,
        initialPositions: m.positions,
        initialJersey: m.jerseyNumber,
        initialStarter: m.isStarter,
      ),
    );
    if (edit == null) return;
    try {
      await ref.read(manageRepositoryProvider).updateMember(
            m.memberId,
            positions: edit.positions,
            jerseyNumber: edit.jersey,
            isStarter: edit.starter,
          );
      ref.invalidate(teamDetailProvider(teamId));
    } on ApiException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  Future<void> _cancelInvite(
      BuildContext context, WidgetRef ref, TeamWardInvite i) async {
    try {
      await ref
          .read(manageRepositoryProvider)
          .cancelWardInvite(teamId, i.inviteId);
      ref.invalidate(teamWardInvitesProvider(teamId));
      ref.invalidate(eligibleMembersProvider(teamId));
      if (context.mounted) _snack(context, 'Invitation cancelled.');
    } on ApiException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  Future<void> _captain(
      BuildContext context, WidgetRef ref, TeamMember m) async {
    try {
      await ref
          .read(manageRepositoryProvider)
          .setCaptain(teamId, m.isCaptain ? null : m.playerId);
      ref.invalidate(teamDetailProvider(teamId));
    } on ApiException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  Future<void> _remove(
      BuildContext context, WidgetRef ref, TeamMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove player?'),
        content: Text('Remove ${m.displayName} from the team?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(manageRepositoryProvider).removeMember(m.memberId);
      ref.invalidate(teamDetailProvider(teamId));
    } on ApiException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(teamDetailProvider(teamId));
    // Wards invited onto the team, waiting for a guardian (admin only; a
    // failure just hides the section).
    final waiting =
        ref.watch(teamWardInvitesProvider(teamId)).valueOrNull ?? const [];
    final p = context.palette;
    return Scaffold(
      appBar:
          AppBar(leading: const SpLeading(), title: const Text('Manage squad')),
      floatingActionButton: team.maybeWhen(
        data: (t) => FloatingActionButton.extended(
          onPressed: () => _add(context, ref, t),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('Add'),
        ),
        orElse: () => null,
      ),
      body: AsyncView(
        value: team,
        onRetry: () => ref.invalidate(teamDetailProvider(teamId)),
        data: (t) {
          if (t.members.isEmpty && waiting.isEmpty) {
            return const Center(child: Text('No players yet. Add your squad.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              if (waiting.isNotEmpty) ...[
                SpSectionTitle('Waiting for a guardian', count: waiting.length),
                const SizedBox(height: 4),
                Text(
                  'Wards join once one of their guardians accepts.',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                SpListCard(children: [
                  for (final i in waiting)
                    _WaitingRow(
                      invite: i,
                      onCancel: () => _cancelInvite(context, ref, i),
                    ),
                ]),
                const SizedBox(height: 20),
                if (t.members.isNotEmpty) ...[
                  SpSectionTitle('Squad', count: t.members.length),
                  const SizedBox(height: 10),
                ],
              ],
              for (var i = 0; i < t.members.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _memberCard(context, ref, t, t.members[i]),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _memberCard(
      BuildContext context, WidgetRef ref, TeamDetail t, TeamMember m) {
    final p = context.palette;
    return GlassCard(
      padding: const EdgeInsets.all(10),
      onTap: () => openPlayerProfile(context, ref, m.playerId),
      child: Row(children: [
        Crest(logoUrl: m.avatarUrl, label: m.displayName, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(m.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              if (m.isCaptain) ...[
                const SizedBox(width: 6),
                Icon(Icons.star_rounded, size: 15, color: p.amber),
              ],
              if (m.isWard) ...[
                const SizedBox(width: 6),
                const WardBadge(),
              ],
            ]),
            Text(
                [
                  m.isStarter ? 'Starter' : 'Sub',
                  if (m.positions.isNotEmpty) m.positions.join(' · '),
                  if (m.jerseyNumber != null) '#${m.jerseyNumber}',
                ].join('  ·  '),
                style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') _edit(context, ref, t, m);
            if (v == 'captain') _captain(context, ref, m);
            if (v == 'remove') _remove(context, ref, m);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(
                value: 'captain',
                child: Text(m.isCaptain ? 'Remove captain' : 'Make captain')),
            const PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
      ]),
    );
  }
}

/// A ward invited onto the team, waiting for a guardian — Cancel withdraws it.
class _WaitingRow extends StatelessWidget {
  const _WaitingRow({required this.invite, required this.onCancel});
  final TeamWardInvite invite;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sub = [
      if (invite.positions.isNotEmpty) invite.positions.join(' · '),
      if (invite.jerseyNumber != null) '#${invite.jerseyNumber}',
      'Invited — waiting for a guardian',
    ].join('  ·  ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: [
        ClipOval(
          child: Crest(
              logoUrl: invite.avatarUrl, label: invite.displayName, size: 38),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(invite.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              const WardBadge(),
            ]),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.orangeInk, fontSize: 12)),
          ]),
        ),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ]),
    );
  }
}

class _MemberSheet extends StatefulWidget {
  const _MemberSheet({
    required this.title,
    required this.options,
    this.initialPositions = const [],
    this.initialJersey,
    this.initialStarter = false,
  });
  final String title;
  final List<String> options;
  final List<String> initialPositions;
  final int? initialJersey;
  final bool initialStarter;
  @override
  State<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends State<_MemberSheet> {
  late final Set<String> _positions = {...widget.initialPositions};
  late final TextEditingController _jersey =
      TextEditingController(text: widget.initialJersey?.toString() ?? '');
  late bool _starter = widget.initialStarter;

  @override
  void dispose() {
    _jersey.dispose();
    super.dispose();
  }

  void _toggle(String pos) {
    setState(() {
      if (_positions.contains(pos)) {
        _positions.remove(pos);
      } else {
        if (_positions.length >= 3) return;
        _positions.add(pos);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SpSheetHeader(
          icon: Icons.badge_outlined,
          title: widget.title,
          subtitle: 'Position, shirt number and starting spot.',
        ),
        if (widget.options.isNotEmpty) ...[
          const Text('Positions (up to 3)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in widget.options)
                FilterChip(
                  label: Text(o),
                  selected: _positions.contains(o),
                  onSelected: (_) => _toggle(o),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _jersey,
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: 'Jersey number (optional)'),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Starter'),
          value: _starter,
          onChanged: (v) => setState(() => _starter = v),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _MemberEdit(
                _positions.toList(),
                int.tryParse(_jersey.text.trim()),
                _starter,
              ),
            ),
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}
