import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/manage/manage_models.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart';
import 'package:sportpadi_mobile/data/teams/teams_repository.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/groups/members_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Team page — mirrors the web team page: header + record, then scrollable
/// tabs: Players (starters/subs, invite, add), Formation, Coaches, Games.
class TeamDetailScreen extends ConsumerStatefulWidget {
  const TeamDetailScreen({super.key, required this.teamId});
  final String teamId;

  @override
  ConsumerState<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends ConsumerState<TeamDetailScreen> {
  int _tab = 0; // 0 players, 1 formation, 2 coaches, 3 games

  String get teamId => widget.teamId;

  void _refetch() {
    ref.invalidate(teamDetailProvider(teamId));
    ref.invalidate(teamStatsProvider(teamId));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final team = ref.watch(teamDetailProvider(teamId));
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: Text(team.valueOrNull?.name ?? 'Team',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: AsyncView(
        value: team,
        onRetry: _refetch,
        data: (t) {
          final tabs = <(String, int)>[
            ('Players', 0),
            if (t.formation.needsFormation) ('Formation', 1),
            ('Coaches', 2),
            ('Games', 3),
          ];
          return RefreshIndicator(
            onRefresh: () async =>
                ref.refresh(teamDetailProvider(teamId).future),
            child: CustomScrollView(slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverList(
                    delegate: SliverChildListDelegate([
                  _Header(team: t),
                  const SizedBox(height: 10),
                  _RecordStrip(teamId: teamId),
                  const SizedBox(height: 12),
                ])),
              ),
              // Tab bar pins while the header scrolls away.
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedTeamTabs(
                  child: Container(
                    color: p.bg,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    // Scrollable tab bar.
                    child: Container(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: p.line)),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final (label, i) in tabs)
                        InkWell(
                          onTap: () => setState(() => _tab = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: _tab == i
                                      ? p.accent
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              label.toUpperCase(),
                              style: TextStyle(
                                color: _tab == i ? p.accent : p.muted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                sliver: SliverList(
                    delegate: SliverChildListDelegate([
                  if (_tab == 0)
                    _PlayersTab(team: t, onChanged: _refetch)
                  else if (_tab == 1)
                    _FormationTab(team: t)
                  else if (_tab == 2)
                    _CoachesTab(team: t)
                  else
                    _GamesTab(teamId: teamId),
                ])),
              ),
            ]),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header + record strip
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.team});
  final TeamDetail team;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = team;
    return GlassCard(
      child: Row(children: [
        Crest(
            logoUrl: t.logoUrl,
            kitPrimary: t.kitPrimary,
            kitSecondary: t.kitSecondary,
            label: t.name,
            size: 60),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              if (t.username != null)
                Text('@${t.username}',
                    style: TextStyle(color: p.muted, fontSize: 12)),
              const SizedBox(height: 5),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (t.categoryName != null) SpBadge(t.categoryName!),
                SpBadge('${t.members.length} players'),
                if (t.homeVenue != null)
                  SpBadge(t.homeVenue!, icon: Icons.place_outlined),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}

class _RecordStrip extends ConsumerWidget {
  const _RecordStrip({required this.teamId});
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final stats = ref.watch(teamStatsProvider(teamId)).valueOrNull;
    if (stats == null || stats.played == 0) return const SizedBox.shrink();
    Widget cell(String label, String value, [Color? tone]) => Expanded(
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    color: tone ?? p.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
            Text(label,
                style: TextStyle(color: p.muted, fontSize: 10)),
          ]),
        );
    final gd = stats.goalsFor - stats.goalsAgainst;
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(children: [
        cell('Played', '${stats.played}'),
        cell('Won', '${stats.won}', p.accent),
        cell('Drawn', '${stats.drawn}'),
        cell('Lost', '${stats.lost}', p.danger),
        cell('GF', '${stats.goalsFor}'),
        cell('GA', '${stats.goalsAgainst}'),
        cell('GD', '${gd > 0 ? '+' : ''}$gd'),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Players tab — starters / subs, invite link + add player (admin), tap a
// player for stats (and admin edits: jersey, positions, starter, captain).
// ---------------------------------------------------------------------------

class _PlayersTab extends ConsumerWidget {
  const _PlayersTab({required this.team, required this.onChanged});
  final TeamDetail team;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final starters = team.members.where((m) => m.isStarter).toList();
    final subs = team.members.where((m) => !m.isStarter).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (team.canManage) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip(context, 'Invite link', Icons.link_rounded, () {
              final base = ref.read(appConfigProvider).apiBaseUrl;
              Clipboard.setData(
                  ClipboardData(text: '$base/join-team/${team.id}'));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content:
                      Text('Join link copied — share it to invite players')));
            }),
            _chip(context, 'Add player', Icons.person_add_alt_rounded,
                () => _addPlayer(context, ref)),
          ]),
          const SizedBox(height: 12),
        ],
        if (team.members.isEmpty)
          GlassCard(
            child: Center(
              child: Text(
                'No players yet${team.canManage ? ' — add from your group members.' : '.'}',
                style: TextStyle(color: p.muted, fontSize: 13),
              ),
            ),
          )
        else ...[
          const Eyebrow('Starters'),
          const SizedBox(height: 6),
          if (starters.isEmpty)
            Text('No starters set.',
                style: TextStyle(color: p.muted, fontSize: 12.5))
          else
            for (final m in starters) _memberRow(context, ref, m),
          if (subs.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Eyebrow('Substitutes'),
            const SizedBox(height: 6),
            for (final m in subs) _memberRow(context, ref, m),
          ],
        ],
      ],
    );
  }

  Widget _chip(BuildContext context, String label, IconData icon,
      VoidCallback onTap) {
    final p = context.palette;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: p.accent),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: p.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _memberRow(BuildContext context, WidgetRef ref, TeamMember m) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        onTap: () => _openPlayer(context, ref, m),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          SizedBox(
            width: 30,
            child: Text(
              m.jerseyNumber != null ? '#${m.jerseyNumber}' : '—',
              style: TextStyle(
                  color: p.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w800),
            ),
          ),
          ClipOval(
            child: Crest(
                logoUrl: m.avatarUrl, label: m.displayName, size: 32),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(m.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600)),
                  ),
                  if (m.isCaptain) ...[
                    const SizedBox(width: 5),
                    SpBadge('C', tone: p.amber),
                  ],
                ]),
                if (m.positions.isNotEmpty)
                  Text(m.positions.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 11.5)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: p.muted),
        ]),
      ),
    );
  }

  void _openPlayer(BuildContext context, WidgetRef ref, TeamMember m) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PlayerSheet(team: team, member: m, onChanged: onChanged),
    );
  }

  Future<void> _addPlayer(BuildContext context, WidgetRef ref) async {
    final p = context.palette;
    List<SimpleUser> eligible;
    try {
      eligible =
          await ref.read(manageRepositoryProvider).eligibleMembers(team.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }
    if (!context.mounted) return;
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Every group member is already on the team.')));
      return;
    }
    final picked = await showModalBottomSheet<SimpleUser>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add player',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final u in eligible)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: ClipOval(
                        child: Crest(
                            logoUrl: u.avatarUrl,
                            label: u.displayName,
                            size: 32)),
                    title: Text(u.displayName,
                        style: TextStyle(color: p.ink, fontSize: 14)),
                    onTap: () => Navigator.pop(ctx, u),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    try {
      await ref
          .read(manageRepositoryProvider)
          .addMember(team.id, playerId: picked.userId);
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Player sheet — tournament stats for everyone; jersey/positions/starter/
// captain/remove for group admins.
// ---------------------------------------------------------------------------

class _PlayerSheet extends ConsumerStatefulWidget {
  const _PlayerSheet(
      {required this.team, required this.member, required this.onChanged});
  final TeamDetail team;
  final TeamMember member;
  final VoidCallback onChanged;

  @override
  ConsumerState<_PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends ConsumerState<_PlayerSheet> {
  late final TextEditingController _jersey = TextEditingController(
      text: widget.member.jerseyNumber?.toString() ?? '');
  late final List<String> _positions = List.of(widget.member.positions);
  late bool _starter = widget.member.isStarter;
  bool _busy = false;

  @override
  void dispose() {
    _jersey.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() op, {bool close = false}) async {
    setState(() => _busy = true);
    try {
      await op();
      widget.onChanged();
      if (close && mounted) {
        Navigator.of(context).pop();
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = widget.member;
    final card = ref
        .watch(playerCardProvider(
            (teamId: widget.team.id, playerId: m.playerId)))
        .valueOrNull;
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
        shrinkWrap: true,
        children: [
          Row(children: [
            ClipOval(
              child: Crest(
                  logoUrl: m.avatarUrl, label: m.displayName, size: 44),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.displayName,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  Text(
                    [
                      if (m.username != null) '@${m.username}',
                      m.isStarter ? 'Starter' : 'Substitute',
                      if (m.isCaptain) 'Captain',
                    ].join(' · '),
                    style: TextStyle(color: p.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          if (card == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else ...[
            if (card.setup.isNotEmpty) ...[
              Eyebrow(
                  '${card.categoryEmoji ?? ''} ${card.categoryName ?? 'Sport'} setup'
                      .trim()),
              const SizedBox(height: 6),
              GlassCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Column(children: [
                  for (final f in card.setup)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(
                          child: Text(f.label,
                              style: TextStyle(
                                  color: p.muted, fontSize: 12.5)),
                        ),
                        Flexible(
                          child: Text(f.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            const Eyebrow('Tournament stats'),
            const SizedBox(height: 6),
            if (card.appearances == 0 && card.tallies.isEmpty)
              Text('No games played with this team yet.',
                  style: TextStyle(color: p.muted, fontSize: 12.5))
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: p.surface2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${card.appearances} appearance${card.appearances == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                for (final t in card.tallies)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: p.line),
                    ),
                    child: Text(
                      '${t.icon != null ? '${t.icon} ' : ''}${t.count} ${t.label}',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ]),
          ],
          if (widget.team.canManage) ...[
            const SizedBox(height: 16),
            const Eyebrow('Manage'),
            const SizedBox(height: 8),
            TextField(
              controller: _jersey,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Jersey number'),
            ),
            if (widget.team.positionOptions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Positions (up to 3)',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final o in widget.team.positionOptions)
                  Material(
                    color: _positions.contains(o) ? p.accent : p.surface,
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => setState(() {
                        if (_positions.contains(o)) {
                          _positions.remove(o);
                        } else if (_positions.length < 3) {
                          _positions.add(o);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: _positions.contains(o)
                                  ? p.accent
                                  : p.line),
                        ),
                        child: Text(o,
                            style: TextStyle(
                              color: _positions.contains(o)
                                  ? Colors.white
                                  : p.ink,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ),
                  ),
              ]),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text('Starter',
                    style: TextStyle(color: p.ink, fontSize: 13.5)),
              ),
              Switch(
                value: _starter,
                onChanged: (v) => setState(() => _starter = v),
              ),
            ]),
            const SizedBox(height: 8),
            SpButton(
              label: _busy ? 'Saving…' : 'Save changes',
              expand: true,
              onTap: _busy
                  ? null
                  : () => _run(() async {
                        await ref
                            .read(manageRepositoryProvider)
                            .updateMember(
                              m.memberId,
                              jerseyNumber:
                                  int.tryParse(_jersey.text.trim()),
                              positions: _positions,
                              isStarter: _starter,
                            );
                      }, close: true),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: _busy
                      ? null
                      : () => _run(() async {
                            await ref
                                .read(manageRepositoryProvider)
                                .setCaptain(widget.team.id,
                                    m.isCaptain ? null : m.playerId);
                          }, close: true),
                  child: Center(
                    child: Text(
                      m.isCaptain ? 'Remove captaincy' : 'Make captain',
                      style: TextStyle(
                          color: p.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: _busy ? null : () => _confirmRemove(m),
                  child: Center(
                    child: Text('Remove from team',
                        style: TextStyle(
                            color: p.danger,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemove(TeamMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${m.displayName}?'),
        content: const Text('They come off the team roster.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      await _run(
          () => ref
              .read(manageRepositoryProvider)
              .removeMember(m.memberId),
          close: true);
    }
  }
}

// ---------------------------------------------------------------------------
// Formation tab — preview + open the interactive board.
// ---------------------------------------------------------------------------

class _FormationTab extends StatelessWidget {
  const _FormationTab({required this.team});
  final TeamDetail team;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final placed =
        team.members.where((m) => m.posX != null && m.posY != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.grid_view_rounded, size: 16, color: p.accent),
                const SizedBox(width: 6),
                Text(
                  team.formationName ?? 'No formation set',
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                '$placed of ${team.formation.maxStarters} placed on the pitch.',
                style: TextStyle(color: p.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SpButton(
          label: team.canManage ? 'Open formation board' : 'View formation',
          icon: Icons.sports_soccer_rounded,
          expand: true,
          onTap: () => context.push('/teams/${team.id}/formation'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Coaches tab — staff from group members, admin add/remove with role.
// ---------------------------------------------------------------------------

class _CoachesTab extends ConsumerWidget {
  const _CoachesTab({required this.team});
  final TeamDetail team;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final data = ref.watch(teamCoachesProvider(team.id));
    final coaches = data.valueOrNull?.coaches ?? const <TeamCoach>[];
    final roleOptions = data.valueOrNull?.roleOptions ??
        const ['Head coach', 'Assistant coach'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (coaches.isEmpty)
          GlassCard(
            child: Center(
              child: Text(
                'No coaching staff yet${team.canManage ? ' — add from your group members.' : '.'}',
                style: TextStyle(color: p.muted, fontSize: 13),
              ),
            ),
          )
        else
          for (final c in coaches)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(children: [
                  ClipOval(
                    child: Crest(
                        logoUrl: c.avatarUrl,
                        label: c.displayName,
                        size: 34),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600)),
                        Text(c.role,
                            style: TextStyle(
                                color: p.muted, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  if (team.canManage)
                    InkWell(
                      onTap: () async {
                        try {
                          await ref
                              .read(teamsRepositoryProvider)
                              .removeCoach(team.id, c.id);
                          ref.invalidate(teamCoachesProvider(team.id));
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$e')));
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.close_rounded,
                            size: 17, color: p.muted),
                      ),
                    ),
                ]),
              ),
            ),
        if (team.canManage && team.groupId != null) ...[
          const SizedBox(height: 6),
          SpButton(
            label: 'Add coach',
            icon: Icons.sports_rounded,
            expand: true,
            onTap: () =>
                _addCoach(context, ref, roleOptions, coaches),
          ),
        ],
      ],
    );
  }

  Future<void> _addCoach(BuildContext context, WidgetRef ref,
      List<String> roleOptions, List<TeamCoach> existing) async {
    final p = context.palette;
    List<GroupMemberItem> members;
    try {
      final page =
          await ref.read(groupMembersProvider(team.groupId!).future);
      members = page.items;
    } catch (_) {
      members = const [];
    }
    if (!context.mounted) return;
    final existingIds = existing.map((c) => c.userId).toSet();
    final candidates =
        members.where((m) => !existingIds.contains(m.userId)).toList();
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Every group member is already on the staff.')));
      return;
    }
    String role = roleOptions.isNotEmpty ? roleOptions.first : 'Coach';
    String? userId;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: ListView(shrinkWrap: true, children: [
            Text('Add a coach',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in roleOptions)
                Material(
                  color: role == r ? p.accent : p.surface,
                  borderRadius: BorderRadius.circular(999),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => setSheet(() => role = r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: role == r ? p.accent : p.line),
                      ),
                      child: Text(r,
                          style: TextStyle(
                            color:
                                role == r ? Colors.white : p.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 10),
            for (final m in candidates)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: ClipOval(
                    child: Crest(
                        logoUrl: m.avatarUrl,
                        label: m.displayName,
                        size: 32)),
                title: Text(m.displayName,
                    style: TextStyle(color: p.ink, fontSize: 14)),
                trailing: userId == m.userId
                    ? Icon(Icons.check_circle_rounded,
                        color: p.accent, size: 18)
                    : null,
                onTap: () => setSheet(() => userId = m.userId),
              ),
            const SizedBox(height: 8),
            SpButton(
              label: 'Add coach',
              expand: true,
              onTap: userId != null
                  ? () => Navigator.pop(ctx, true)
                  : null,
            ),
          ]),
        ),
      ),
    );
    if (ok != true || userId == null || !context.mounted) return;
    try {
      await ref
          .read(teamsRepositoryProvider)
          .addCoach(team.id, userId!, role);
      ref.invalidate(teamCoachesProvider(team.id));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Games tab — the team's matches over the last six months.
// ---------------------------------------------------------------------------

class _GamesTab extends ConsumerWidget {
  const _GamesTab({required this.teamId});
  final String teamId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final games = ref.watch(teamGamesProvider(teamId));
    final list = games.valueOrNull ?? const <TeamGame>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('Last 6 months'),
        const SizedBox(height: 8),
        if (games.isLoading)
          GlassCard(
              child: Text('Loading…',
                  style: TextStyle(color: p.muted, fontSize: 13)))
        else if (list.isEmpty)
          GlassCard(
            child: Center(
              child: Text('No games in the last 6 months.',
                  style: TextStyle(color: p.muted, fontSize: 13)),
            ),
          )
        else
          for (final g in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                onTap: () => context.push('/games/${g.id}'),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(children: [
                  Container(
                    width: 36,
                    padding:
                        const EdgeInsets.symmetric(vertical: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: g.status == 'live'
                          ? const Color.fromRGBO(245, 167, 10, 0.15)
                          : g.result == 'win'
                              ? const Color.fromRGBO(23, 166, 94, 0.15)
                              : g.result == 'loss'
                                  ? const Color.fromRGBO(
                                      222, 33, 33, 0.12)
                                  : p.surface2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      g.status == 'live'
                          ? 'LIVE'
                          : g.result == 'win'
                              ? 'W'
                              : g.result == 'loss'
                                  ? 'L'
                                  : g.result == 'draw'
                                      ? 'D'
                                      : '—',
                      style: TextStyle(
                        color: g.status == 'live'
                            ? p.amber
                            : g.result == 'win'
                                ? p.accent
                                : g.result == 'loss'
                                    ? p.danger
                                    : p.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('vs ${g.oppName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600)),
                        Text(
                          [
                            if (g.eventTitle != null) g.eventTitle!,
                            if (g.playedAt != null)
                              formatDay(g.playedAt),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.muted, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  Text('${g.myScore} – ${g.oppScore}',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
      ],
    );
  }
}


/// Pins the team tab bar to the top of the scroll view.
class _PinnedTeamTabs extends SliverPersistentHeaderDelegate {
  const _PinnedTeamTabs({required this.child});
  final Widget child;

  static const double _height = 43;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: _height, child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedTeamTabs oldDelegate) =>
      oldDelegate.child != child;
}
