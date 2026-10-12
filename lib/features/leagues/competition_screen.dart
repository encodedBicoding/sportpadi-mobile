import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_tab_track.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// A competition across its seasons (web `/competitions/[slug]`): seasons and
/// divisions with how they finished, honours, the all-time table, records and
/// all-time leaders, promotion & relegation as it happened.
class CompetitionScreen extends ConsumerWidget {
  const CompetitionScreen({super.key, required this.slug});
  final String slug;

  static const _status = {'draft': 'Draft', 'published': 'Starting', 'in_progress': 'In play', 'completed': 'Finished'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(competitionProvider(slug));
    final d = q.valueOrNull;
    return SpSubPage(
      title: d?.o('competition')?.str('name', 'Competition') ?? 'Competition',
      subtitle: d?.o('group')?.s('name'),
      body: AsyncView(
        value: q,
        onRetry: () => ref.invalidate(competitionProvider(slug)),
        data: (d) => DefaultTabController(
          length: 4,
          child: Builder(builder: (context) {
            final p = context.palette;
            return NestedScrollView(
              headerSliverBuilder: (_, __) => [
                SliverToBoxAdapter(child: _hero(d, p)),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: SpTabTrack(labels: ['Seasons', 'Honours', 'All-time table', 'Records']),
                  ),
                ),
              ],
              body: TabBarView(children: [
                _seasons(context, d, p),
                _honours(d, p),
                _allTime(d, p),
                _records(context, d, p),
              ]),
            );
          }),
        ),
      ),
    );
  }

  Widget _hero(J d, AppPalette p) {
    final seasons = d.list('seasons');
    final finished = seasons.expand((s) => s.list('divisions')).where((x) => x.s('status') == 'completed').length;
    final top = d.list('titles').firstOrNull;
    Widget stat(int v, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withAlpha(26), borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              Text('$v', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              Text(label, style: TextStyle(color: p.heroMuted, fontSize: 11)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: p.hero, borderRadius: BorderRadius.circular(26)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d.o('category')?.str('emoji', '🏆') ?? '🏆', style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 8),
          Text(d.o('competition')?.str('name') ?? '',
              style: TextStyle(color: p.onHero, fontSize: 22, fontWeight: FontWeight.w800, height: 1.15)),
          if (d.o('competition')?.s('description') != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(d.o('competition')!.str('description'), style: TextStyle(color: p.heroMuted, fontSize: 12.5)),
            ),
          const SizedBox(height: 14),
          Row(children: [
            stat(seasons.length, 'Seasons'),
            const SizedBox(width: 8),
            stat(d.list('allTime').length, 'Teams'),
            const SizedBox(width: 8),
            stat(finished, 'Finished'),
          ]),
          if (top?.o('team') != null) ...[
            const SizedBox(height: 12),
            Text('Most titles: ${top!.o('team')!.str('name')} (${top.i('titles')})',
                style: TextStyle(color: p.heroMuted, fontSize: 12.5)),
          ],
        ]),
      ),
    );
  }

  Widget _seasons(BuildContext context, J d, AppPalette p) {
    final seasons = d.list('seasons');
    final moves = d.list('movements');
    if (seasons.isEmpty) return const SpEmpty(icon: Icons.emoji_events_rounded, text: 'No seasons yet.');
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
      for (final s in seasons) ...[
        Padding(padding: const EdgeInsets.fromLTRB(2, 8, 2, 8), child: SpSectionTitle(s.str('season'))),
        for (final dv in s.list('divisions')) ...[
          GlassCard(
            padding: const EdgeInsets.all(14),
            onTap: () => context.push('/leagues/${dv.str('slug')}'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Text(dv.s('division') ?? d.o('competition')?.str('name') ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
                ),
                SpBadge(_status[dv.s('status')] ?? dv.str('status'),
                    tone: dv.s('status') == 'completed' ? null : dv.s('status') == 'draft' ? p.orangeInk : p.greenText),
              ]),
              Text('${dv.i('teams')} teams · ${dv.str('format')}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 12)),
              if (dv.o('champion') != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: p.accentTint, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    Crest(
                        logoUrl: dv.o('champion')!.s('logoUrl'),
                        label: dv.o('champion')!.s('name'),
                        kitPrimary: dv.o('champion')!.s('kitPrimary'),
                        size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('CHAMPIONS',
                            style: TextStyle(color: p.greenText, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                        Text(dv.o('champion')!.str('name'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
                        if (dv.o('runnerUp') != null)
                          Text('Runners-up: ${dv.o('runnerUp')!.str('name')}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted, fontSize: 11.5)),
                      ]),
                    ),
                  ]),
                ),
              ],
              for (final a in dv.list('awards'))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                      '${a.str('label')} — ${[a.o('player')?.s('name'), a.o('team')?.s('name'), if (a.d('value') != null) '${a.d('value')!.round()}'].whereType<String>().join(' · ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink, fontSize: 12.5)),
                ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
      ],
      if (moves.isNotEmpty) ...[
        const Padding(padding: EdgeInsets.fromLTRB(2, 8, 2, 8), child: SpSectionTitle('Promotion & relegation')),
        for (final m in moves) ...[
          GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${m.str('from')} → ${m.str('to')}',
                  style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final (list, up) in [(m.list('up'), true), (m.list('down'), false)])
                for (final u in list)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 15, color: up ? p.greenText : p.danger),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('${u.o('team')?.str('name') ?? 'Team'}  ${u.s('from') ?? '?'} → ${u.s('to') ?? '?'}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.ink, fontSize: 13)),
                      ),
                    ]),
                  ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
      ],
    ]);
  }

  Widget _honours(J d, AppPalette p) {
    final titles = d.list('titles');
    if (titles.isEmpty) {
      return const SpEmpty(icon: Icons.emoji_events_rounded, text: 'No champions yet — honours appear once a season is closed.');
    }
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
      const Padding(padding: EdgeInsets.fromLTRB(2, 8, 2, 8), child: SpSectionTitle('Titles')),
      SpListCard(children: [
        for (final t in titles)
          ListTile(
            leading: Crest(logoUrl: t.o('team')?.s('logoUrl'), label: t.o('team')?.s('name'), kitPrimary: t.o('team')?.s('kitPrimary'), size: 32),
            title: Text(t.o('team')?.str('name') ?? 'Team', style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
            subtitle: Text(t.strs('seasons').join(', ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.emoji_events_rounded, size: 17, color: p.greenText),
              const SizedBox(width: 4),
              Text('${t.i('titles')}', style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
            ]),
          ),
      ]),
      const Padding(padding: EdgeInsets.fromLTRB(2, 16, 2, 8), child: SpSectionTitle('Roll of honour')),
      SpListCard(children: [
        for (final s in d.list('seasons'))
          for (final dv in s.list('divisions').where((x) => x.o('champion') != null))
            ListTile(
              leading: SizedBox(
                width: 84,
                child: Text(s.str('season'), maxLines: 2, style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              title: Text(dv.o('champion')!.str('name'), style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
              subtitle: Text([dv.s('division'), if (dv.o('runnerUp') != null) 'runners-up ${dv.o('runnerUp')!.str('name')}']
                  .whereType<String>()
                  .join(' · ')),
            ),
      ]),
    ]);
  }

  Widget _allTime(J d, AppPalette p) {
    final rows = d.list('allTime');
    if (rows.isEmpty) return const SpEmpty(icon: Icons.leaderboard_rounded, text: 'No matches played yet.');
    TextStyle head() => TextStyle(color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8);
    Widget n(String v, {bool bold = false, double w = 28}) => SizedBox(
        width: w,
        child: Text(v,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.ink, fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w500)));
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
        child: Text('Every match in every season and division: 3 points a win, 1 a draw (shoot-outs count as draws).',
            style: TextStyle(color: p.muted, fontSize: 12)),
      ),
      GlassCard(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 12, 6),
            child: Row(children: [
              SizedBox(width: 24, child: Text('#', style: head())),
              Expanded(child: Text('TEAM', style: head())),
              for (final h in ['P', 'W', 'D', 'L', 'GD']) SizedBox(width: 28, child: Text(h, textAlign: TextAlign.center, style: head())),
              SizedBox(width: 34, child: Text('PTS', textAlign: TextAlign.center, style: head())),
            ]),
          ),
          for (final r in rows)
            Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: p.surface2))),
              padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
              child: Row(children: [
                SizedBox(width: 24, child: Text('${r.i('position')}', style: TextStyle(color: p.ink, fontWeight: FontWeight.w800))),
                Crest(logoUrl: r.o('team')?.s('logoUrl'), label: r.o('team')?.s('name'), kitPrimary: r.o('team')?.s('kitPrimary'), size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      '${r.o('team')?.str('name') ?? 'Team'}${r.i('titles') > 0 ? '  🏆${r.i('titles')}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                n('${r.i('played')}'),
                n('${r.i('won')}'),
                n('${r.i('drawn')}'),
                n('${r.i('lost')}'),
                n(r.i('gd') > 0 ? '+${r.i('gd')}' : '${r.i('gd')}'),
                n('${r.i('points')}', bold: true, w: 34),
              ]),
            ),
        ]),
      ),
    ]);
  }

  Widget _records(BuildContext context, J d, AppPalette p) {
    final rec = d.o('records');
    Widget card(String title, IconData icon, J r) => GlassCard(
          padding: const EdgeInsets.all(14),
          onTap: r.s('gameId') == null ? null : () => context.push('/games/${r.str('gameId')}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SpIconTile(icon, size: 28, iconSize: 15, bg: p.orangeTint, fg: p.orangeInk),
              const SizedBox(width: 8),
              Text(title.toUpperCase(), style: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ]),
            const SizedBox(height: 8),
            Text('${r.o('home')?.str('name') ?? 'Home'} ${r.i('homeScore')}–${r.i('awayScore')} ${r.o('away')?.str('name') ?? 'Away'}',
                style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
            Text([r.s('season'), r.s('label')].whereType<String>().join(' · '), style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
      const Padding(padding: EdgeInsets.fromLTRB(2, 8, 2, 8), child: SpSectionTitle('Match records')),
      if (rec?.o('biggestWin') == null && rec?.o('mostGoals') == null)
        Text('No matches played yet.', style: TextStyle(color: p.muted, fontSize: 12.5)),
      if (rec?.o('biggestWin') != null) ...[card('Biggest win', Icons.gps_fixed_rounded, rec!.o('biggestWin')!), const SizedBox(height: 10)],
      if (rec?.o('mostGoals') != null) card('Most goals in a match', Icons.local_fire_department_rounded, rec!.o('mostGoals')!),
      for (final l in d.list('leaders')) ...[
        Padding(padding: const EdgeInsets.fromLTRB(2, 16, 2, 8), child: SpSectionTitle('All-time ${l.str('label').toLowerCase()}')),
        if (l.list('entries').isEmpty)
          Text('Nobody yet.', style: TextStyle(color: p.muted, fontSize: 12.5))
        else
          SpListCard(children: [
            for (final (i, e) in l.list('entries').indexed)
              ListTile(
                onTap: () => context.push('/players/${e.str('playerId')}'),
                leading: SizedBox(width: 22, child: Text('${i + 1}', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700))),
                title: Text(e.str('name', 'Player'), style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
                subtitle: Text(e.o('team')?.str('name') ?? ''),
                trailing: Text('${e.d('value')?.round() ?? 0}', style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
              ),
          ]),
      ],
    ]);
  }
}
