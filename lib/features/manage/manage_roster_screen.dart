import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_models.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

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

  Future<void> _add(BuildContext context, WidgetRef ref, TeamDetail team) async {
    final picked = await showModalBottomSheet<SimpleUser>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EligiblePicker(teamId: teamId),
    );
    if (picked == null || !context.mounted) return;
    final edit = await showModalBottomSheet<_MemberEdit>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MemberSheet(
        title: picked.displayName,
        options: team.positionOptions,
      ),
    );
    if (edit == null) return;
    try {
      await ref.read(manageRepositoryProvider).addMember(
            teamId,
            playerId: picked.userId,
            positions: edit.positions,
            jerseyNumber: edit.jersey,
            isStarter: edit.starter,
          );
      ref.invalidate(teamDetailProvider(teamId));
    } on ApiException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, TeamDetail team, TeamMember m) async {
    final edit = await showModalBottomSheet<_MemberEdit>(
      context: context,
      isScrollControlled: true,
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

  Future<void> _captain(BuildContext context, WidgetRef ref, TeamMember m) async {
    try {
      await ref.read(manageRepositoryProvider).setCaptain(teamId, m.isCaptain ? null : m.playerId);
      ref.invalidate(teamDetailProvider(teamId));
    } on ApiException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, TeamMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove player?'),
        content: Text('Remove ${m.displayName} from the team?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
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
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Manage squad')),
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
          if (t.members.isEmpty) {
            return const Center(child: Text('No players yet. Add your squad.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: t.members.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final m = t.members[i];
              return GlassCard(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Crest(logoUrl: m.avatarUrl, label: m.displayName, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text(m.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                        if (m.isCaptain) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.star_rounded, size: 15, color: p.amber),
                        ],
                      ]),
                      Text([
                        m.isStarter ? 'Starter' : 'Sub',
                        if (m.positions.isNotEmpty) m.positions.join(' · '),
                        if (m.jerseyNumber != null) '#${m.jerseyNumber}',
                      ].join('  ·  '), style: TextStyle(color: p.muted, fontSize: 12)),
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
            },
          );
        },
      ),
    );
  }
}

class _EligiblePicker extends ConsumerWidget {
  const _EligiblePicker({required this.teamId});
  final String teamId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eligible = ref.watch(eligibleMembersProvider(teamId));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (_, controller) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Add a group member',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          Expanded(
            child: AsyncView(
              value: eligible,
              onRetry: () => ref.invalidate(eligibleMembersProvider(teamId)),
              data: (list) => list.isEmpty
                  ? const Center(child: Text('Everyone in the group is already on the team.'))
                  : ListView.builder(
                      controller: controller,
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final u = list[i];
                        return ListTile(
                          leading: Crest(logoUrl: u.avatarUrl, label: u.displayName, size: 38),
                          title: Text(u.displayName),
                          subtitle: u.username != null ? Text('@${u.username}') : null,
                          onTap: () => Navigator.pop(context, u),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
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
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 16),
          if (widget.options.isNotEmpty) ...[
            const Text('Positions (up to 3)', style: TextStyle(fontWeight: FontWeight.w600)),
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
            decoration: const InputDecoration(labelText: 'Jersey number (optional)'),
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
      ),
    );
  }
}
