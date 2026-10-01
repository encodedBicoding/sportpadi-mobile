import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/games/game_models.dart';
import 'package:sportpadi_mobile/features/games/basketball_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Volleyball on the game screen — web twin: components/games/volleyball.tsx.
/// A player-first pad where every rally is credited to someone (kill, ace,
/// block — or the error that gave the other side the point), set scores, the
/// next-set / end-match prompts, the stat sheet and the format picker.

String _jn(int? j) => j != null ? '#$j ' : '';

Color _teamColor(String? hex) {
  if (hex == null || hex.isEmpty) return const Color(0xFF888888);
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFF888888);
}

bool isVolleyballSport(String? name, String? emoji) =>
    RegExp('volley', caseSensitive: false).hasMatch(name ?? '') || emoji == '🏐';

/// "Set 2" from a stamped phase ("S2").
String setStamp(String? phase) {
  final m = RegExp(r'^S(\d)$').firstMatch(phase ?? '');
  return m != null ? 'Set ${m[1]}' : '';
}

/// The current set's points while the match is live (the big numbers).
Map<String, int>? currentSetPoints(GameDetail g) {
  final vb = g.volleyball;
  if (vb == null || !g.isLive) return null;
  return vb.current?.points ?? const {};
}

// ── Score pad ────────────────────────────────────────────────────────────────

const _vbActs = [
  PadAct('kill', 'Kill', PadTone.score, assist: true),
  PadAct('ace', 'Ace', PadTone.score),
  PadAct('block', 'Block', PadTone.score),
  PadAct('dig', 'Dig', PadTone.stat),
  PadAct('point', 'Point (other)', PadTone.stat),
  PadAct('attack_error', 'Attack error', PadTone.foul),
  PadAct('service_error', 'Serve error', PadTone.foul),
  PadAct('reception_error', 'Reception error', PadTone.foul),
  PadAct('fault', 'Fault', PadTone.foul),
];

class VolleyballScorePad extends StatelessWidget {
  const VolleyballScorePad({
    super.key,
    required this.game,
    required this.onRecord,
    this.busy = false,
    this.amend = false,
    this.onSub,
  });
  final GameDetail game;
  final PadRecord onRecord;
  final bool busy;
  final bool amend;
  final VoidCallback? onSub;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final box = {for (final l in game.volleyball?.boxPlayers ?? const <VbLine>[]) l.playerId: l};
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PlayerScorePad(
        game: game,
        onRecord: onRecord,
        acts: _vbActs,
        busy: busy,
        amend: amend,
        onSub: onSub,
        assistWord: 'Set by?',
        icon: Icons.sports_volleyball_rounded,
        statLine: (pl) {
          final l = box[pl.playerId];
          return '${l?.pts ?? 0} pts · ${l?.kills ?? 0} K · ${l?.digs ?? 0} D';
        },
      ),
      Text(
        'Red actions are errors: they’re logged on the player who made them and the point goes to the other team.',
        style: TextStyle(color: p.muted, fontSize: 11),
      ),
    ]);
  }
}

// ── Set scores ───────────────────────────────────────────────────────────────

/// One chip per set ("25–21"), in the scoreboard's team order.
class SetScoresStrip extends StatelessWidget {
  const SetScoresStrip({super.key, required this.game, required this.order, this.dark = true});
  final GameDetail game;
  final List<String> order;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final vb = game.volleyball;
    if (vb == null || order.length != 2 || vb.sets.isEmpty) return const SizedBox.shrink();
    final a = order[0], b = order[1];
    final muted = dark ? p.heroMuted : p.muted;
    final ink = dark ? p.onHero : p.ink;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? p.onHero.withAlpha(15) : p.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
        for (final s in vb.sets)
          Builder(builder: (context) {
            final live = s.n == vb.currentSet && s.winnerTeamId == null && game.isLive;
            TextStyle digit(String id) => TextStyle(
                  color: live ? const Color(0xFFFFB57D) : ink,
                  fontSize: 12.5,
                  fontWeight: s.winnerTeamId == id ? FontWeight.w900 : FontWeight.w600,
                  decoration: s.winnerTeamId == id ? TextDecoration.underline : null,
                  decorationColor: _teamColor(game.teams.where((t) => t.teamId == id).firstOrNull?.color),
                  decorationThickness: 2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                );
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: live ? const Color(0x33FFB57D) : (dark ? p.onHero.withAlpha(25) : p.surface),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: 'S${s.n} ', style: TextStyle(color: muted, fontSize: 10, fontWeight: FontWeight.w800)),
                TextSpan(text: '${s.points[a] ?? 0}', style: digit(a)),
                TextSpan(text: '–', style: TextStyle(color: ink, fontSize: 12.5)),
                TextSpan(text: '${s.points[b] ?? 0}', style: digit(b)),
              ])),
            );
          }),
      ]),
    );
  }
}

/// Between rallies: change ends in the deciding set, start the next set once
/// this one is won, end the match once it's decided.
class VolleyballSetCard extends StatelessWidget {
  const VolleyballSetCard({
    super.key,
    required this.game,
    this.busy = false,
    this.onStartNext,
    this.onSwitched,
    this.onEnd,
  });
  final GameDetail game;
  final bool busy;
  final VoidCallback? onStartNext;
  final VoidCallback? onSwitched;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final vb = game.volleyball;
    if (vb == null || !game.isLive) return const SizedBox.shrink();
    String name(String? id) => game.teams.where((t) => t.teamId == id).firstOrNull?.name ?? 'A team';

    Widget card(IconData icon, Color bg, Color fg, String title, String body, String? cta, VoidCallback? onTap) =>
        GlassCard(
          child: Row(children: [
            SpIconTile(icon, bg: bg, fg: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w800)),
                Text(body, style: TextStyle(color: p.muted, fontSize: 12)),
              ]),
            ),
            if (cta != null && onTap != null) ...[
              const SizedBox(width: 8),
              SpButton(label: cta, onTap: busy ? null : onTap),
            ],
          ]),
        );

    final wid = vb.matchWinnerTeamId;
    if (wid != null) {
      final won = vb.setsWon[wid] ?? 0;
      var lost = 0;
      for (final e in vb.setsWon.entries) {
        if (e.key != wid && e.value > lost) lost = e.value;
      }
      return card(Icons.emoji_events_rounded, p.accentTint, p.accentDeep, '${name(wid)} won the match $won–$lost',
          'End the match to lock in the result. You can still correct stats afterwards.', 'End match', onEnd);
    }
    final cur = vb.current;
    if (vb.currentSetDecided && cur != null && cur.winnerTeamId != null) {
      final w = cur.winnerTeamId!;
      final l = cur.points.keys.where((k) => k != w).firstOrNull ?? w;
      return card(
          Icons.flag_rounded,
          p.orangeTint,
          p.orangeInk,
          'Set ${cur.n} to ${name(w)}, ${cur.points[w] ?? 0}–${cur.points[l] ?? 0}',
          'Sets ${vb.setsWon.values.join('–')}. Switch ends, then start set ${cur.n + 1}.',
          'Start set ${cur.n + 1}',
          onStartNext);
    }
    if (vb.switchSidesDue) {
      return card(Icons.swap_horiz_rounded, p.orangeTint, p.orangeInk, 'Change ends',
          'A team has reached ${vb.rules.switchAt} in the deciding set — the teams switch sides.', 'Done', onSwitched);
    }
    return const SizedBox.shrink();
  }
}

// ── Summary ─────────────────────────────────────────────────────────────────

/// Result + set-by-set table + leaders + the stat sheet.
class VolleyballSummary extends StatelessWidget {
  const VolleyballSummary({super.key, required this.game});
  final GameDetail game;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final vb = game.volleyball;
    if (vb == null) return const SizedBox.shrink();
    final done = game.status == 'completed';
    final winner = game.teams.where((t) => t.result == 'win').firstOrNull;
    final names = {for (final x in game.participants) x.playerId: x};
    final played = [for (final s in vb.sets) if (s.points.values.any((n) => n > 0)) s];

    VbLine? leader(int Function(VbLine) f) {
      VbLine? best;
      for (final l in vb.boxPlayers) {
        if (f(l) > 0 && (best == null || f(l) > f(best))) best = l;
      }
      return best;
    }

    final leaders = [
      ('Points', leader((l) => l.pts), (VbLine l) => l.pts),
      ('Kills', leader((l) => l.kills), (VbLine l) => l.kills),
      ('Blocks', leader((l) => l.blocks), (VbLine l) => l.blocks),
      ('Digs', leader((l) => l.digs), (VbLine l) => l.digs),
    ].where((x) => x.$2 != null).toList();

    TextStyle cell({bool bold = false, Color? color}) => TextStyle(
          color: color ?? p.ink,
          fontSize: 12.5,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    Widget c(String v, {double w = 40, bool bold = false, Color? color, TextAlign align = TextAlign.right}) =>
        SizedBox(width: w, child: Text(v, textAlign: align, style: cell(bold: bold, color: color)));

    final scores = [for (final t in game.teams) t.score]..sort((x, y) => y - x);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (done) ...[
        GlassCard(
          child: Row(children: [
            SpIconTile(Icons.emoji_events_rounded,
                bg: winner != null ? p.orangeTint : p.surface2, fg: winner != null ? p.orangeInk : p.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Final${vb.rules.bestOf > 1 ? ' · best of ${vb.rules.bestOf}' : ''}',
                    style: TextStyle(color: p.muted, fontSize: 12)),
                Text(winner != null ? '${winner.name} won ${scores.join('–')}' : 'Match summary',
                    style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      if (played.isNotEmpty && game.teams.length == 2) ...[
        GlassCard(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                c('TEAM', w: 120, color: p.muted, align: TextAlign.left),
                for (final s in played) c('S${s.n}', color: p.muted),
                c('SETS', w: 48, color: p.muted),
              ]),
              for (final t in game.teams) ...[
                const Divider(height: 12),
                Row(children: [
                  SizedBox(
                    width: 120,
                    child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: cell(bold: true)),
                  ),
                  for (final s in played)
                    c('${s.points[t.teamId] ?? 0}',
                        bold: s.winnerTeamId == t.teamId, color: s.winnerTeamId == t.teamId ? null : p.muted),
                  c('${vb.setsWon[t.teamId] ?? 0}', w: 48, bold: true),
                ]),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (leaders.isNotEmpty) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final x in leaders)
            SizedBox(
              width: (MediaQuery.sizeOf(context).width - 48) / 2,
              child: GlassCard(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(x.$1.toUpperCase(), style: TextStyle(color: p.muted, fontSize: 10, fontWeight: FontWeight.w800)),
                  Text('${x.$3(x.$2!)}', style: TextStyle(color: p.ink, fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(
                    names[x.$2!.playerId] != null
                        ? '${_jn(names[x.$2!.playerId]!.jersey)}${names[x.$2!.playerId]!.displayName}'
                        : 'Player',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 11.5),
                  ),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 10),
      ],
      for (final t in game.teams) ...[
        Builder(builder: (context) {
          final rows = [for (final l in vb.boxPlayers) if (l.teamId == t.teamId) l]
            ..sort((x, y) => y.pts != x.pts ? y.pts - x.pts : y.kills - x.kills);
          if (rows.isEmpty) return const SizedBox.shrink();
          final tot = vb.boxTeams[t.teamId];
          const heads = ['PTS', 'K', 'AE', 'ACE', 'SE', 'BLK', 'DIG', 'AST', 'RE', 'F'];
          const errCols = {2, 4, 8, 9};
          List<int> vals(VbLine l) => [
                l.pts, l.kills, l.attackErrors, l.aces, l.serviceErrors,
                l.blocks, l.digs, l.assists, l.receptionErrors, l.faults,
              ];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: _teamColor(t.color), borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(t.name, style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                  Text('Stat sheet', style: TextStyle(color: p.muted, fontSize: 11)),
                ]),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      c('PLAYER', w: 130, color: p.muted, align: TextAlign.left),
                      for (final h in heads) c(h, color: p.muted),
                    ]),
                    for (final l in rows) ...[
                      const Divider(height: 10),
                      Row(children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            names[l.playerId] != null
                                ? '${_jn(names[l.playerId]!.jersey)}${names[l.playerId]!.displayName}'
                                : 'Player',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: cell(bold: true),
                          ),
                        ),
                        for (var i = 0; i < heads.length; i++)
                          c('${vals(l)[i]}',
                              bold: i == 0,
                              color: errCols.contains(i) && vals(l)[i] > 0 ? p.danger : null),
                      ]),
                    ],
                    if (tot != null) ...[
                      const Divider(height: 12, thickness: 1.5),
                      Row(children: [
                        c('Team', w: 130, bold: true, align: TextAlign.left),
                        for (var i = 0; i < heads.length; i++) c('${vals(tot)[i]}', bold: true),
                      ]),
                    ],
                  ]),
                ),
                if (tot != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Points won ${tot.kills + tot.aces + tot.blocks} (kills, aces, blocks) · '
                    'errors given away ${tot.errors}',
                    style: TextStyle(color: p.muted, fontSize: 11),
                  ),
                ],
              ]),
            ),
          );
        }),
      ],
    ]);
  }
}

// ── Format picker (create game / tournament match) ──────────────────────────

/// How a volleyball match is played: one set, best of 3 or best of 5.
class VolleyballFormatFields extends StatelessWidget {
  const VolleyballFormatFields({super.key, required this.value, required this.onChanged});
  final VolleyballRules value;
  final ValueChanged<VolleyballRules> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget field(String label, int v, int min, int max, ValueChanged<int> set, {String? hint}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Row(children: [
              _StepBtn(icon: Icons.remove_rounded, onTap: v > min ? () => set(v - 1) : null),
              Expanded(
                child: Text('$v',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              _StepBtn(icon: Icons.add_rounded, onTap: v < max ? () => set(v + 1) : null),
            ]),
            if (hint != null) Text(hint, style: TextStyle(color: p.muted, fontSize: 10.5)),
          ]),
        );
    const bests = [1, 3, 5];
    final multi = value.bestOf > 1;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('🏐 Match format', style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SpSegmented(
          options: const ['1 set', 'Best of 3', 'Best of 5'],
          index: bests.contains(value.bestOf) ? bests.indexOf(value.bestOf) : 2,
          onChanged: (i) => onChanged(value.copyWith(bestOf: bests[i])),
        ),
        const SizedBox(height: 12),
        Row(children: [
          field('Points per set', value.setPoints, 5, 50, (n) => onChanged(value.copyWith(setPoints: n)),
              hint: 'Indoor 25 · beach 21'),
          const SizedBox(width: 12),
          if (multi)
            field('Deciding set to', value.decidingSetPoints, 5, 50,
                (n) => onChanged(value.copyWith(decidingSetPoints: n)),
                hint: 'Set ${value.bestOf}')
          else
            field('Win by', value.winBy, 1, 5, (n) => onChanged(value.copyWith(winBy: n))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          if (multi) ...[
            field('Win by', value.winBy, 1, 5, (n) => onChanged(value.copyWith(winBy: n))),
            const SizedBox(width: 12),
          ],
          field('Timeouts per set', value.timeoutsPerSet, 0, 5, (n) => onChanged(value.copyWith(timeoutsPerSet: n)),
              hint: 'Per team · 30 s each'),
        ]),
        const SizedBox(height: 8),
        Text(
          multi
              ? 'Rally scoring: first to win ${value.setsToWin} sets. Sets go to ${value.setPoints} '
                  '(the deciding set to ${value.decidingSetPoints}), win by ${value.winBy}. '
                  'Teams change ends at ${value.switchAt} in the decider.'
              : 'Rally scoring: one set to ${value.setPoints}, win by ${value.winBy}.',
          style: TextStyle(color: p.muted, fontSize: 11, height: 1.35),
        ),
      ]),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: onTap == null ? p.line : p.ink),
        ),
      ),
    );
  }
}
