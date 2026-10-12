import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/features/leagues/league_polls.dart';
import 'package:sportpadi_mobile/features/leagues/league_sheets.dart';
import 'package:sportpadi_mobile/features/leagues/league_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Public league page (web `/leagues/[slug]`): season awards, table or
/// groups, the knockout bracket, fixtures & results, player rankings.
class LeagueScreen extends ConsumerStatefulWidget {
  const LeagueScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<LeagueScreen> createState() => _LeagueScreenState();
}

class _LeagueScreenState extends ConsumerState<LeagueScreen> {
  String _tab = 'table';
  bool _results = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final q = ref.watch(leaguePublicProvider(widget.slug));
    final d = q.valueOrNull;
    final l = d?.o('league');
    return SpSubPage(
      title: l?.str('competitionName', 'League') ?? 'League',
      subtitle: l == null ? null : [l.s('season'), l.s('division')].whereType<String>().join(' · '),
      actions: [
        if (l != null && l.s('status') != 'draft')
          SpRoundButton(
            icon: Icons.ios_share_rounded,
            tooltip: 'Share & embed',
            onTap: () => showShareLeagueSheet(context,
                base: ref.read(appConfigProvider).apiBaseUrl, slug: l.str('slug'), title: l.str('title')),
          ),
        if (d?.b('isOrganiser') == true && l != null)
          SpRoundButton(
            icon: Icons.tune_rounded,
            tooltip: 'Manage',
            onTap: () => context.push('/groups/${l.str('groupId')}/leagues/${l.str('id')}'),
          ),
      ],
      body: AsyncView(
        value: q,
        onRetry: () => ref.invalidate(leaguePublicProvider(widget.slug)),
        data: (d) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(leaguePublicProvider(widget.slug));
            ref.invalidate(mvpPollsProvider(widget.slug));
          },
          child: _body(d, p),
        ),
      ),
    );
  }

  Widget _body(J d, AppPalette p) {
    final l = d.o('league')!;
    final stages = d.list('stages');
    final knockoutIds = stages.where((s) => s.s('kind') == 'knockout').map((s) => s.s('id')).toSet();
    final fixtures = d.list('fixtures');
    final ko = fixtures.where((f) => knockoutIds.contains(f.s('stageId'))).toList();
    final standings = d.list('standings');
    final awards = d.list('awards');
    final champion = awards.where((a) => a.s('kind') == 'champion').firstOrNull;
    final champTeam = champion?.o('team');
    final others = awards.where((a) => a.s('kind') != 'champion').toList();
    final tabs = <(String, String, IconData)>[
      if (standings.isNotEmpty)
        ('table', stages.any((s) => s.s('kind') == 'groups')
                ? 'Groups'
                : stages.any((s) => s.s('kind') == 'split')
                    ? 'Tables'
                    : 'Table', Icons.leaderboard_rounded),
      if (ko.isNotEmpty) ('bracket', 'Bracket', Icons.account_tree_rounded),
      ('fixtures', 'Fixtures', Icons.calendar_month_rounded),
      ('players', 'Players', Icons.people_alt_rounded),
    ];
    final tab = tabs.any((t) => t.$1 == _tab) ? _tab : tabs.first.$1;
    final divisions = d.list('divisions');
    final titleSponsor = d.list('sponsors').where((x) => x.s('tier') == 'title').firstOrNull;
    final partners = d.list('sponsors').where((x) => x.s('tier') == 'partner').toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // Hero
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: p.hero, borderRadius: BorderRadius.circular(26)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(d.o('category')?.str('emoji', '🏆') ?? '🏆', style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withAlpha(26), borderRadius: BorderRadius.circular(99)),
                child: Text(
                    l.s('status') == 'completed'
                        ? 'FINAL TABLE'
                        : l.s('status') == 'draft'
                            ? 'DRAFT — ONLY YOU SEE THIS'
                            : 'SEASON LIVE',
                    style: TextStyle(color: p.accent, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
            ]),
            const SizedBox(height: 10),
            Text(l.str('title'),
                style: TextStyle(color: p.onHero, fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
            const SizedBox(height: 4),
            Text(
                [if (d.o('group')?.s('name') != null) 'Run by ${d.o('group')!.str('name')}', l.str('format')].join(' · '),
                style: TextStyle(color: p.heroMuted, fontSize: 12.5)),
            if (titleSponsor != null) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: titleSponsor.s('url') == null
                    ? null
                    : () => launchUrl(Uri.parse(titleSponsor.str('url')), mode: LaunchMode.externalApplication),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: Colors.white.withAlpha(26), borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (titleSponsor.s('logoUrl') != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(2),
                          child: Image.network(titleSponsor.str('logoUrl'), width: 24, height: 24, fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const SizedBox(width: 24, height: 24)),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text('Presented by ', style: TextStyle(color: p.heroMuted, fontSize: 12)),
                    Text(titleSponsor.str('name'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => context.push('/competitions/${l.str('competitionSlug')}'),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.military_tech_rounded, size: 15, color: p.accent),
                const SizedBox(width: 4),
                Text('All seasons, honours & records',
                    style: TextStyle(color: p.accent, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ]),
            ),
            if (divisions.length > 1) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final dv in divisions)
                  GestureDetector(
                    onTap: dv.b('current') ? null : () => context.pushReplacement('/leagues/${dv.str('slug')}'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: dv.b('current') ? Colors.white : Colors.white.withAlpha(26),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(dv.str('division', 'Main'),
                          style: TextStyle(
                              color: dv.b('current') ? const Color(0xFF0E1411) : Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ],
          ]),
        ),

        if (partners.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final x in partners)
              GestureDetector(
                onTap: x.s('url') == null ? null : () => launchUrl(Uri.parse(x.str('url')), mode: LaunchMode.externalApplication),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.line)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (x.s('logoUrl') != null) ...[
                      Image.network(x.str('logoUrl'), width: 22, height: 22, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox(width: 22, height: 22)),
                      const SizedBox(width: 6),
                    ],
                    Text(x.str('name'), style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
          ]),
        ],
        if (champion != null || others.isNotEmpty) ...[
          const SizedBox(height: 14),
          GlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SpSectionTitle('Season awards'),
              if (champTeam != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: p.accentTint, borderRadius: BorderRadius.circular(18)),
                  child: Row(children: [
                    Crest(
                        logoUrl: champTeam.s('logoUrl'),
                        label: champTeam.s('name'),
                        kitPrimary: champTeam.s('kitPrimary'),
                        size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('CHAMPIONS',
                            style: TextStyle(color: p.greenText, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
                        Text(champTeam.str('name'),
                            style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    Icon(Icons.emoji_events_rounded, color: p.greenText, size: 28),
                  ]),
                ),
              ],
              for (final a in others)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    SpIconTile(Icons.military_tech_rounded, size: 32, iconSize: 17, bg: p.orangeTint, fg: p.orangeInk),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.str('label'), style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w700)),
                        Text(
                            [a.o('player')?.s('name'), a.o('team')?.s('name')].whereType<String>().join(' · '),
                            style: TextStyle(color: p.muted, fontSize: 12)),
                      ]),
                    ),
                    if (a.s('kind') == 'stat' && a.d('value') != null)
                      Text('${a.d('value')!.round()}',
                          style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w800)),
                  ]),
                ),
            ]),
          ),
        ],

        if (d.o('league')?.s('status') != 'draft') MvpPollsSection(slug: widget.slug),

        const SizedBox(height: 14),
        SpSegmented(
          options: [for (final t in tabs) t.$2],
          icons: [for (final t in tabs) t.$3],
          index: tabs.indexWhere((t) => t.$1 == tab),
          onChanged: (i) => setState(() => _tab = tabs[i].$1),
        ),
        const SizedBox(height: 12),

        if (tab == 'table')
          for (final t in standings) ...[
            if (standings.length > 1)
              Padding(padding: const EdgeInsets.fromLTRB(2, 6, 2, 8), child: SpSectionTitle(t.str('name'))),
            StandingsTableView(rows: t.list('rows')),
            const SizedBox(height: 8),
          ],
        if (tab == 'bracket')
          BracketView(fixtures: ko, padding: EdgeInsets.zero),
        if (tab == 'fixtures') ..._fixtures(fixtures),
        if (tab == 'players') ..._players(d, p),

        if (tab == 'table' && d.list('sanctions').isNotEmpty) ...[
          const SizedBox(height: 10),
          const SpSectionTitle('Forfeits'),
          const SizedBox(height: 8),
          SpListCard(children: [
            for (final s in d.list('sanctions'))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text('${s.str('teamName', 'A team')} forfeited a match — ${s.str('publicReason')}',
                    style: TextStyle(color: p.ink, fontSize: 13)),
              ),
          ]),
        ],
      ],
    );
  }

  List<Widget> _fixtures(List<J> fixtures) {
    final upcoming = fixtures.where((f) => f.s('status') != 'completed' && f.s('status') != 'cancelled').toList();
    final played = fixtures.where((f) => f.s('status') == 'completed').toList().reversed.toList();
    final list = _results ? played : upcoming;
    return [
      Row(children: [
        SpPill(
            label: 'Upcoming (${upcoming.length})',
            tone: _results ? SpPillTone.soft : SpPillTone.ink,
            onTap: () => setState(() => _results = false)),
        const SizedBox(width: 8),
        SpPill(
            label: 'Results (${played.length})',
            tone: _results ? SpPillTone.ink : SpPillTone.soft,
            onTap: () => setState(() => _results = true)),
      ]),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SpEmpty(icon: Icons.calendar_month_rounded, text: _results ? 'No results yet.' : 'No upcoming matches.'),
        )
      else
        RoundsView(fixtures: list),
    ];
  }

  List<Widget> _players(J d, AppPalette p) {
    final rankings = d.list('rankings').where((r) => r.list('entries').isNotEmpty).toList();
    final mvps = d.list('mvps');
    if (rankings.isEmpty && mvps.isEmpty) {
      return [const SpEmpty(icon: Icons.people_alt_rounded, text: 'Player rankings appear after the first results.')];
    }
    return [
      for (final r in rankings) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 8),
          child: SpSectionTitle(r.str('label'),
              trailing: r.list('entries').length >= 5
                  ? GestureDetector(
                      onTap: () => _showFullRanking(r),
                      child: Text('See all', style: TextStyle(color: p.greenText, fontSize: 13, fontWeight: FontWeight.w700)),
                    )
                  : null),
        ),
        SpListCard(children: [
          for (final e in r.list('entries').take(5)) _rankRow(e, r, p),
        ]),
        const SizedBox(height: 8),
      ],
      if (mvps.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.fromLTRB(2, 6, 2, 8), child: SpSectionTitle('Match MVPs')),
        SpListCard(children: [
          for (final m in mvps)
            ListTile(
              dense: true,
              leading: SpIconTile(Icons.military_tech_rounded, size: 32, iconSize: 17, bg: p.orangeTint, fg: p.orangeInk),
              title: Text(m.str('name'), style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
              subtitle: Text([m.s('teamName'), m.s('note')].whereType<String>().join(' · ')),
              onTap: () => context.push('/players/${m.str('playerId')}'),
            ),
        ]),
      ],
    ];
  }

  Widget _rankRow(J e, J r, AppPalette p) => InkWell(
        onTap: () => context.push('/players/${e.str('playerId')}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(children: [
            SizedBox(width: 22, child: Text('${e.i('rank')}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700))),
            PersonAvatar(url: e.s('avatarUrl'), name: e.str('name', '?'), size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.str('name'), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text('${e.o('team')?.str('name') ?? ''} · ${e.i('appearances')} apps',
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
              ]),
            ),
            if (e.i('rank') == 1 && r.s('award') != null) ...[
              SpBadge(r.str('award'), tone: p.orangeInk),
              const SizedBox(width: 8),
            ],
            Text('${e.d('value')?.round() ?? 0}', style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
          ]),
        ),
      );

  void _showFullRanking(J r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final p = ctx.palette;
        final q = ref.watch(leagueRankingProvider('${widget.slug}|${r.str('key')}'));
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          builder: (_, ctl) => AsyncView(
            value: q,
            data: (full) => ListView(controller: ctl, padding: const EdgeInsets.all(20), children: [
              SpSectionTitle(r.str('label')),
              const SizedBox(height: 10),
              SpListCard(children: [for (final e in full.list('entries')) _rankRow(e, r, p)]),
            ]),
          ),
        );
      }),
    );
  }
}
