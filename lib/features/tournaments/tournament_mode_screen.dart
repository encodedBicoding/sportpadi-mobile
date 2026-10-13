import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/data/tournaments/tournament_models.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/groups/plan_gate.dart';
import 'package:sportpadi_mobile/features/leagues/group_team_leagues_tab.dart';
import 'package:sportpadi_mobile/features/tournaments/tournament_modes.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// One tournament mode for a group (web `/groups/[id]/tournaments/mode/[mode]`):
/// 1v1 friendlies, multi-team tournaments or leagues — search, filter by
/// status / side / sport, and (admins) start a new one in this mode.
class TournamentModeScreen extends ConsumerStatefulWidget {
  const TournamentModeScreen({super.key, required this.groupId, required this.mode});
  final String groupId;
  final String mode;

  @override
  ConsumerState<TournamentModeScreen> createState() => _TournamentModeScreenState();
}

class _TournamentModeScreenState extends ConsumerState<TournamentModeScreen> {
  final _search = TextEditingController();
  String _status = 'all';
  String _side = 'all';
  String _sport = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final m = TMode.fromSlug(widget.mode);
    if (m == null) {
      return const SpSubPage(title: 'Tournaments', body: Center(child: Text("That tournament mode doesn't exist.")));
    }
    final group = ref.watch(groupProvider(widget.groupId)).valueOrNull;
    final canManage = group?.canManage ?? false;
    final isLeague = m == TMode.league;
    // Same plan rule as the Tournaments tab's New card. Unknown (still
    // loading) counts as allowed — the server enforces it anyway.
    final ov = canManage ? ref.watch(groupOverviewProvider(widget.groupId)).valueOrNull : null;
    final leagueSetup = canManage && isLeague ? ref.watch(leagueSetupProvider(widget.groupId)).valueOrNull : null;
    final allowed = isLeague ? (leagueSetup == null || leagueSetup.b('enabled')) : (ov?.canCreateTournaments ?? true);
    final tq = ref.watch(groupTournamentsProvider(widget.groupId));
    final lq = ref.watch(groupLeaguesProvider(widget.groupId));
    // Leagues the group's teams play in (or are invited to) — the old Leagues tab.
    final tlq = isLeague ? ref.watch(groupTeamLeaguesProvider(widget.groupId)) : null;
    final entries = [for (final t in tlq?.valueOrNull?.list('teams') ?? const <J>[]) ...t.list('entries')];
    final loading = isLeague
        ? (lq.isLoading && lq.valueOrNull == null) || (tlq!.isLoading && tlq.valueOrNull == null)
        : tq.isLoading && tq.valueOrNull == null;
    final needle = _search.text.trim().toLowerCase();
    bool hit(Iterable<String?> xs) => needle.isEmpty || xs.any((x) => x?.toLowerCase().contains(needle) ?? false);

    final all = sortTournaments((tq.valueOrNull ?? const <TournamentSummary>[]).where((t) => m == TMode.friendly ? !t.isMulti : t.isMulti));
    final sports = <String>{for (final t in all) if (t.categoryName != null) '${t.categoryEmoji ?? ''} ${t.categoryName}'.trim()}.toList();
    final leagues = [...(lq.valueOrNull ?? const <J>[])]..sort((a, b) => leaguePhase(a).index - leaguePhase(b).index);

    final shownT = all.where((t) {
      if (_status != 'all' && tournamentPhase(t).name != _status) return false;
      if (_side == 'host' && !t.isHost) return false;
      if (_side == 'away' && t.isHost) return false;
      if (_sport != 'all' && '${t.categoryEmoji ?? ''} ${t.categoryName}'.trim() != _sport) return false;
      return hit([t.title, t.hostTeamName, t.guestTeamName, t.categoryName]);
    }).toList();
    // Organised leagues on the same chips: running / starting soon (draft) / finished.
    String orgStatus(J l) => switch (leaguePhase(l)) { LPhase.running => 'running', LPhase.draft => 'upcoming', LPhase.past => 'past' };
    final shownL = leagues.where((l) {
      if (_status != 'all' && orgStatus(l) != _status) return false;
      return hit([l.s('competitionName'), l.s('season'), l.s('division'), l.s('format')]);
    }).toList();
    // Team entries: running = active, starting soon = accepted, invitations, finished.
    final Set<String>? entryPhases = switch (_status) {
      'all' => null,
      'running' => {'active'},
      'upcoming' => {'upcoming'},
      'invited' => {'invited'},
      'past' => {'past'},
      _ => <String>{},
    };
    final entryMatches = entries.where((e) => GroupTeamLeaguesTab.keep(e, entryPhases, _search.text)).length;
    final invites = entries.where((e) => e.s('phase') == 'invited').length;

    final total = isLeague ? leagues.length + entries.where((e) => e.s('phase') != 'invited').length : all.length;
    final live = isLeague
        ? leagues.where((l) => leaguePhase(l) == LPhase.running).length + entries.where((e) => e.s('phase') == 'active').length
        : all.where((t) => tournamentPhase(t) == TPhase.live).length;
    final soon = isLeague
        ? leagues.where((l) => leaguePhase(l) == LPhase.draft).length + entries.where((e) => e.s('phase') == 'upcoming').length
        : all.where((t) => tournamentPhase(t) == TPhase.upcoming).length;

    final (Color bg, Color fg, Color sub) = switch (m) {
      TMode.friendly => (p.accentTint, p.ink, p.greenText),
      TMode.multi => (p.orangeTint, p.ink, p.orangeInk),
      TMode.league => (p.hero, p.onHero, const Color(0xFF6EDC9E)),
    };
    final statuses = isLeague
        ? [
            ('all', 'All'),
            ('running', 'Running'),
            ('upcoming', 'Starting soon'),
            if (invites > 0) ('invited', 'Invitations · $invites'),
            ('past', 'Finished'),
          ]
        : [('all', 'All'), ('upcoming', 'Upcoming'), ('live', 'Live'), ('past', 'Past')];

    Future<void> refresh() async {
      ref.invalidate(isLeague ? groupLeaguesProvider(widget.groupId) : groupTournamentsProvider(widget.groupId));
      if (isLeague) ref.invalidate(groupTeamLeaguesProvider(widget.groupId));
    }

    return SpSubPage(
      title: m.plural,
      subtitle: group?.name,
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // Hero: the mode at a glance
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(28)),
              child: Stack(children: [
                Positioned(right: -6, top: 0, child: Opacity(opacity: 0.9, child: ModeArt(m, width: 140))),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('TOURNAMENT MODE', style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                  const SizedBox(height: 4),
                  Text(m.title, style: TextStyle(color: fg, fontSize: 24, fontWeight: FontWeight.w800, height: 1.1)),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 90),
                    child: Text(m.blurb,
                        style: TextStyle(color: isLeague ? p.heroMuted : p.muted, fontSize: 12.5, height: 1.35)),
                  ),
                  const SizedBox(height: 14),
                  // Three counts share the width (no fixed gaps, so a phone never overflows).
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    for (final (n, label) in [
                      (total, isLeague ? 'Seasons' : 'Total'),
                      (live, isLeague ? 'Running' : 'Live'),
                      isLeague && invites > 0 ? (invites, 'Invitations') : (soon, isLeague ? 'Starting soon' : 'Upcoming'),
                    ])
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(loading ? '–' : '$n',
                              style: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w800, height: 1)),
                          const SizedBox(height: 4),
                          Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: sub, fontSize: 11, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ]),
                  // New … on its own line under the counts.
                  if (canManage) ...[
                    const SizedBox(height: 14),
                    SpPill(
                      label: allowed ? m.newLabel : '${isLeague ? 'Leagues' : 'Tournaments'} are a plan feature',
                      icon: allowed ? Icons.add_rounded : Icons.lock_outline_rounded,
                      height: 36,
                      expand: true,
                      tone: isLeague ? SpPillTone.soft : SpPillTone.ink,
                      onTap: !allowed
                          ? () => showPlanLockedDialog(context, ref, widget.groupId,
                              title: isLeague ? "Leagues aren't enabled for this group" : "Tournaments aren't enabled for this group",
                              body: isLeague
                                  ? "Running leagues — seasons, fixtures, tables and promotion — isn't switched on for this group yet."
                                  : 'Tournament events — brackets, friendlies and inviting teams from '
                                      "other groups — aren't switched on for this group yet.",
                              topic: 'tournaments')
                          : () => context.push(isLeague
                              ? '/groups/${widget.groupId}/new-league'
                              : '/groups/${widget.groupId}/new-tournament?mode=${m == TMode.multi ? 'multi_team' : 'friendly'}'),
                    ),
                  ],
                ]),
              ]),
            ),
            const SizedBox(height: 14),

            // Search + filters
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: isLeague ? 'Search competition, season or division' : 'Search title, team or sport',
                prefixIcon: Icon(Icons.search_rounded, color: p.muted),
                filled: true,
                fillColor: p.surface,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: p.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(99), borderSide: BorderSide(color: p.line)),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (v, label) in statuses) _Chip(label, _status == v, () => setState(() => _status = v)),
                if (!isLeague) ...[
                  const _Divider(),
                  for (final (v, label) in const [('all', 'Any side'), ('host', 'Hosting'), ('away', 'Away')])
                    _Chip(label, _side == v, () => setState(() => _side = v)),
                ],
                if (!isLeague && sports.length > 1) ...[
                  const _Divider(),
                  _Chip('All sports', _sport == 'all', () => setState(() => _sport = 'all')),
                  for (final s in sports) _Chip(s, _sport == s, () => setState(() => _sport = s)),
                ],
              ]),
            ),
            const SizedBox(height: 12),

            // The list
            if (loading)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if ((isLeague ? shownL.length + entryMatches : shownT.length) == 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
                child: Column(children: [
                  const Center(child: SpIconTile(Icons.emoji_events_outlined, size: 56, iconSize: 26)),
                  const SizedBox(height: 12),
                  Text(
                      total > 0
                          ? 'Nothing matches — try another search or filter.'
                          : 'No ${m.plural.toLowerCase()} yet${canManage ? ' — start one with “${m.newLabel}”.' : '.'}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted, fontSize: 13.5)),
                ]),
              )
            else if (isLeague) ...[
              if (shownL.isNotEmpty && entryMatches > 0) ...[
                SpSectionTitle('Organised by this group', count: shownL.length),
                const SizedBox(height: 8),
              ],
              for (final l in shownL)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LeagueSummaryCard(l: l, groupId: widget.groupId, canManage: canManage),
                ),
              if (entryMatches > 0) ...[
                const SizedBox(height: 8),
                SpSectionTitle('Your teams play in', count: entryMatches),
                const SizedBox(height: 8),
                GroupTeamLeaguesTab(groupId: widget.groupId, phases: entryPhases, search: _search.text, embedded: true),
              ],
            ]
            else
              for (final t in shownT)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: TournamentSummaryCard(t: t)),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.active, this.onTap);
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: active ? p.ink : p.surface,
        shape: StadiumBorder(side: BorderSide(color: active ? p.ink : p.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(label,
                style: TextStyle(color: active ? p.bg : p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.only(left: 2, right: 8),
        color: context.palette.line,
      );
}
