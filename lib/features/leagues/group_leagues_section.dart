import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/features/leagues/league_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The leagues a group RUNS, inside its Tournaments tab (a league is a
/// tournament format). Leagues its TEAMS play in — and their invitations —
/// have their own Leagues tab (group_team_leagues_tab.dart).
class GroupLeaguesSection extends ConsumerWidget {
  const GroupLeaguesSection({super.key, required this.groupId, required this.canManage});
  final String groupId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final leagues = ref.watch(groupLeaguesProvider(groupId)).valueOrNull ?? const <J>[];
    if (leagues.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final l in leagues) ...[
          GlassCard(
            padding: const EdgeInsets.all(12),
            onTap: () => context.push(canManage ? '/groups/$groupId/leagues/${l.str('id')}' : '/leagues/${l.str('slug')}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SpBadge('League', icon: Icons.format_list_numbered_rounded, tone: p.ink),
                Text(l.str('season'), style: TextStyle(color: p.muted, fontSize: 11)),
                if (l.s('division') != null) SpBadge(l.str('division')),
                SpBadge(leagueStatusLabel[l.s('status')] ?? l.str('status'),
                    tone: l.s('status') == 'draft' ? p.orangeInk : p.greenText),
              ]),
              const SizedBox(height: 6),
              Text(l.str('competitionName'), style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.groups_rounded, size: 16, color: p.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      '${l.i('teamsIn')} team${l.i('teamsIn') == 1 ? '' : 's'}'
                      '${l.i('teamsInvited') > 0 ? ' · ${l.i('teamsInvited')} invited' : ''}'
                      '${l.i('fixtures') > 0 ? ' · ${l.i('played')}/${l.i('fixtures')} played' : ''}',
                      style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                Icon(Icons.chevron_right_rounded, color: p.muted),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
        ],
      ]),
    );
  }
}
