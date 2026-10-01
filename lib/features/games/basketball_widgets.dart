import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/games/game_models.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Basketball on the game screen — web twin: components/games/basketball.tsx.
/// A player-first score pad, the team-fouls / bonus strip, the first-to-N
/// "someone has won" card, the line score + box score, and the format picker
/// used when a game or tournament match is created.

String _jn(int? j) => j != null ? '#$j ' : '';

Color _teamColor(String? hex) {
  if (hex == null || hex.isEmpty) return const Color(0xFF888888);
  var h = hex.replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFF888888);
}

/// "7:05" from seconds.
String mmss(int sec) {
  final s = sec < 0 ? 0 : sec;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Short period name for a phase key: Q1…Q4, OT, OT2.
String? periodShort(String? phase) {
  if (phase == null) return null;
  if (RegExp(r'^Q[1-4]$').hasMatch(phase)) return phase;
  final ot = RegExp(r'^OT(\d+)$').firstMatch(phase);
  if (ot != null) return ot[1] == '1' ? 'OT' : 'OT${ot[1]}';
  return null;
}

/// Timeline stamp for a basketball activity: "Q2 4:48" (or the minute).
String bbStamp(GameActivity a) {
  final p = periodShort(a.phase);
  if (p != null && a.clockLeft != null) return '$p ${mmss(a.clockLeft!)}';
  if (p != null) return p;
  return a.minute != null ? "${a.minute}'" : '';
}

// ── Score pad ────────────────────────────────────────────────────────────────

enum PadTone { score, miss, stat, foul }

/// One button on the pad. [assist] asks which teammate set it up.
class PadAct {
  const PadAct(this.type, this.label, this.tone, {this.assist = false});
  final String type;
  final String label;
  final PadTone tone;
  final bool assist;
}

const _acts = [
  PadAct('two_points', '+2', PadTone.score, assist: true),
  PadAct('three_points', '+3', PadTone.score, assist: true),
  PadAct('free_throw', '+1 FT', PadTone.score),
  PadAct('two_miss', 'Miss 2', PadTone.miss),
  PadAct('three_miss', 'Miss 3', PadTone.miss),
  PadAct('ft_miss', 'Miss FT', PadTone.miss),
  PadAct('off_rebound', 'Off. reb', PadTone.stat),
  PadAct('def_rebound', 'Def. reb', PadTone.stat),
  PadAct('steal', 'Steal', PadTone.stat),
  PadAct('block', 'Block', PadTone.stat),
  PadAct('turnover', 'Turnover', PadTone.stat),
  PadAct('foul', 'Foul', PadTone.foul),
];

typedef PadRecord = Future<void> Function({
  required String teamId,
  required String type,
  required String playerId,
  String? relatedPlayerId,
});
typedef BbRecord = PadRecord;

/// Player-first scoring: tap a player on the court, then what they did.
/// Actions flagged `assist` ask for the teammate who set it up (one tap to
/// skip). [amend] lists everyone who took part (post-match corrections), not
/// only those on court. Basketball and volleyball both use it.
class PlayerScorePad extends StatelessWidget {
  const PlayerScorePad({
    super.key,
    required this.game,
    required this.onRecord,
    required this.acts,
    required this.statLine,
    this.warn,
    this.onRecorded,
    this.busy = false,
    this.amend = false,
    this.onSub,
    this.assistWord = 'Assisted by?',
    this.icon = Icons.sports_rounded,
  });
  final GameDetail game;
  final PadRecord onRecord;
  final List<PadAct> acts;

  /// Small line under each player's name ("12 pts · 3 PF").
  final String Function(GamePlayer p) statLine;

  /// Highlight a player's line (e.g. one foul from fouling out).
  final bool Function(GamePlayer p)? warn;
  final void Function(String type)? onRecorded;
  final bool busy;
  final bool amend;
  final VoidCallback? onSub;
  final String assistWord;
  final IconData icon;

  Future<void> _open(BuildContext context, GamePlayer player) async {
    final known = {for (final d in game.schema) d.type};
    final available = [
      for (final a in acts)
        if (known.contains(a.type)) a
    ];
    final mates = [
      for (final x in game.participants)
        if (x.teamId == player.teamId &&
            x.playerId != player.playerId &&
            x.onField &&
            !x.sentOff)
          x
    ];
    final pick = await showSpSheet<({String type, String? related})>(
      context,
      builder: (ctx) => _ActionSheet(
        player: player,
        acts: available,
        mates: mates,
        assistWord: assistWord,
        icon: icon,
      ),
    );
    if (pick == null) return;
    await onRecord(
      teamId: player.teamId,
      type: pick.type,
      playerId: player.playerId,
      relatedPlayerId: pick.related,
    );
    onRecorded?.call(pick.type);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final t in game.teams) ...[
        Container(
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
              color: p.surface2, borderRadius: BorderRadius.circular(16)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: _teamColor(t.color), shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(t.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6)),
              ),
            ]),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, c) {
              final players = [
                for (final x in game.participants)
                  if (x.teamId == t.teamId &&
                      (amend || (x.onField && !x.sentOff)))
                    x
              ];
              if (players.isEmpty) {
                return Text('No one on court.',
                    style: TextStyle(color: p.muted, fontSize: 12));
              }
              final w = (c.maxWidth - 6) / 2;
              return Wrap(spacing: 6, runSpacing: 6, children: [
                for (final pl in players)
                  SizedBox(
                    width: w,
                    child: Material(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: busy || pl.sentOff
                            ? null
                            : () => _open(context, pl),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${_jn(pl.jersey)}${pl.displayName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: pl.sentOff ? p.muted : p.ink,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      decoration: pl.sentOff
                                          ? TextDecoration.lineThrough
                                          : null,
                                    )),
                                Text(
                                  statLine(pl),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: (warn?.call(pl) ?? false)
                                      ? TextStyle(
                                          color: p.danger,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800)
                                      : TextStyle(color: p.muted, fontSize: 11),
                                ),
                              ]),
                        ),
                      ),
                    ),
                  ),
              ]);
            }),
          ]),
        ),
      ],
      if (onSub != null && !amend)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy ? null : onSub,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('Substitution'),
          ),
        ),
    ]);
  }
}

/// Basketball's pad. After an offensive rebound it offers the timekeeper the
/// short shot-clock reset ([onShotShort]).
class BasketballScorePad extends StatefulWidget {
  const BasketballScorePad({
    super.key,
    required this.game,
    required this.onRecord,
    this.busy = false,
    this.amend = false,
    this.onSub,
    this.onShotShort,
  });
  final GameDetail game;
  final PadRecord onRecord;
  final bool busy;
  final bool amend;
  final VoidCallback? onSub;
  final VoidCallback? onShotShort;

  @override
  State<BasketballScorePad> createState() => _BasketballScorePadState();
}

class _BasketballScorePadState extends State<BasketballScorePad> {
  bool _offer = false;
  int _offerSeq = 0;

  void _showOffer() {
    if (!mounted) return;
    final seq = ++_offerSeq;
    setState(() => _offer = true);
    Future.delayed(const Duration(seconds: 8), () {
      if (mounted && seq == _offerSeq) setState(() => _offer = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bb = widget.game.basketball;
    final pts = {
      for (final l in bb?.boxPlayers ?? const <BoxLine>[]) l.playerId: l.pts
    };
    final fouls = bb?.playerFouls ?? const {};
    final limit = bb?.rules.foulLimit ?? 5;
    final short = bb?.rules.shotClockShort ?? 14;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_offer && widget.onShotShort != null)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: p.orangeTint, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Expanded(
              child: Text('Offensive rebound',
                  style: TextStyle(
                      color: p.orangeInk,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
            SpButton(
              label: 'Shot clock to $short',
              onTap: () {
                widget.onShotShort!();
                setState(() => _offer = false);
              },
            ),
            TextButton(
                onPressed: () => setState(() => _offer = false),
                child: const Text('Skip')),
          ]),
        ),
      PlayerScorePad(
        game: widget.game,
        onRecord: widget.onRecord,
        acts: _acts,
        busy: widget.busy,
        amend: widget.amend,
        onSub: widget.onSub,
        icon: Icons.sports_basketball_rounded,
        onRecorded: (type) {
          if (type == 'off_rebound' &&
              widget.onShotShort != null &&
              !widget.amend) {
            _showOffer();
          }
        },
        warn: (pl) => (fouls[pl.playerId] ?? 0) >= limit - 1,
        statLine: (pl) =>
            '${pts[pl.playerId] ?? 0} pts · ${fouls[pl.playerId] ?? 0} PF',
      ),
    ]);
  }
}

class _ActionSheet extends StatefulWidget {
  const _ActionSheet({
    required this.player,
    required this.acts,
    required this.mates,
    required this.assistWord,
    required this.icon,
  });
  final GamePlayer player;
  final List<PadAct> acts;
  final List<GamePlayer> mates;
  final String assistWord;
  final IconData icon;
  @override
  State<_ActionSheet> createState() => _ActionSheetState();
}

class _ActionSheetState extends State<_ActionSheet> {
  String? _assistFor;

  void _done(String type, [String? related]) =>
      Navigator.of(context).pop((type: type, related: related));

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pl = widget.player;
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(
            icon: widget.icon,
            title: '${_jn(pl.jersey)}${pl.displayName}',
            subtitle: _assistFor == null ? 'What happened?' : widget.assistWord,
          ),
          if (_assistFor == null)
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.9,
              children: [
                for (final a in widget.acts)
                  Material(
                    color: switch (a.tone) {
                      PadTone.score => p.accentDeep,
                      PadTone.foul => p.liveTint,
                      _ => p.surface2,
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => a.assist && widget.mates.isNotEmpty
                          ? setState(() => _assistFor = a.type)
                          : _done(a.type),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(a.label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              style: TextStyle(
                                color: switch (a.tone) {
                                  PadTone.score => Colors.white,
                                  PadTone.foul => p.danger,
                                  PadTone.miss => p.muted,
                                  PadTone.stat => p.ink,
                                },
                                fontSize: a.label.length > 10 ? 12.5 : 15,
                                fontWeight: FontWeight.w800,
                                height: 1.1,
                              )),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          else ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in widget.mates)
                ActionChip(
                  label: Text('${_jn(m.jersey)}${m.displayName}'),
                  onPressed: () => _done(_assistFor!, m.playerId),
                ),
            ]),
            const SizedBox(height: 12),
            SpButton(
                label: 'No assist',
                expand: true,
                onTap: () => _done(_assistFor!)),
          ],
        ]);
  }
}

// ── Team fouls / bonus strip ─────────────────────────────────────────────────

/// Team fouls this quarter and who is in the penalty — under the scoreboard.
class TeamFoulsStrip extends StatelessWidget {
  const TeamFoulsStrip({super.key, required this.game, this.dark = true});
  final GameDetail game;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bb = game.basketball;
    if (bb == null || bb.rules.bonusAt <= 0 || game.teams.length != 2) {
      return const SizedBox.shrink();
    }
    final muted = dark ? p.heroMuted : p.muted;
    final ink = dark ? p.onHero : p.ink;
    Widget side(GameTeam t, GameTeam opp, {bool end = false}) {
      final n = bb.teamFouls[t.teamId] ?? 0;
      final pen = bb.inPenalty[t.teamId] == true;
      final oneAway = !pen && n == bb.rules.bonusAt - 1;
      return Row(
        mainAxisAlignment:
            end ? MainAxisAlignment.end : MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Fouls ', style: TextStyle(color: muted, fontSize: 12)),
          Text('$n',
              style: TextStyle(
                  color: ink, fontSize: 13, fontWeight: FontWeight.w800)),
          if (pen) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(0x33FFB57D),
                    borderRadius: BorderRadius.circular(999)),
                child: Text('BONUS ${opp.name.split(' ').first.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFFFB57D),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],
          if (oneAway) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text('1 to bonus',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: muted, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      );
    }

    final a = game.teams[0], b = game.teams[1];
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: dark ? p.onHero.withAlpha(15) : p.surface2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Expanded(child: side(a, b)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text((bb.foulPeriod ?? 'Team fouls').toUpperCase(),
              style: TextStyle(
                  color: muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8)),
        ),
        Expanded(child: side(b, a, end: true)),
      ]),
    );
  }
}

// ── First to N: someone has won ─────────────────────────────────────────────

class TargetReachedCard extends StatelessWidget {
  const TargetReachedCard({super.key, required this.game, this.onEnd});
  final GameDetail game;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bb = game.basketball;
    final wid = bb?.targetWinnerTeamId;
    if (bb == null || wid == null || !game.isLive) {
      return const SizedBox.shrink();
    }
    final w = game.teams.where((t) => t.teamId == wid).firstOrNull;
    if (w == null) return const SizedBox.shrink();
    final other = game.teams.where((t) => t.teamId != wid).firstOrNull;
    return GlassCard(
      child: Row(children: [
        SpIconTile(Icons.emoji_events_rounded,
            bg: p.accentTint, fg: p.greenText),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${w.name} reached ${bb.rules.targetScore}'
                '${other != null ? ' — ${w.score}–${other.score}' : ''}',
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w800)),
            Text(
                'First to ${bb.rules.targetScore}${bb.rules.winBy > 1 ? ', win by ${bb.rules.winBy}' : ''}. '
                'End the game to lock in the result.',
                style: TextStyle(color: p.muted, fontSize: 12)),
          ]),
        ),
        if (onEnd != null) ...[
          const SizedBox(width: 8),
          SpButton(label: 'End game', onTap: onEnd),
        ],
      ]),
    );
  }
}

// ── Line score + box score ───────────────────────────────────────────────────

String _pct(int m, int a) => a > 0 ? '${(m * 100 / a).round()}%' : '–';

class BasketballSummary extends StatelessWidget {
  const BasketballSummary({super.key, required this.game});
  final GameDetail game;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bb = game.basketball;
    if (bb == null) return const SizedBox.shrink();
    final done = game.status == 'completed';
    final winner = game.teams.where((t) => t.result == 'win').firstOrNull;
    final wentOT = game.activities.any((a) => (a.phase ?? '').startsWith('OT'));
    final names = {for (final x in game.participants) x.playerId: x};

    // Line score: points per team per period.
    final points = {
      for (final d in game.schema)
        if (d.scorePoints != null) d.type: d.scorePoints!
    };
    final byTeam = <String, Map<String, int>>{
      for (final t in game.teams) t.teamId: {}
    };
    final seen = <String>{};
    for (final a in game.activities) {
      final pts = points[a.type];
      final per = periodShort(a.phase);
      if (pts == null || per == null) continue;
      seen.add(per);
      final m = byTeam[a.teamId];
      if (m != null) m[per] = (m[per] ?? 0) + pts;
    }
    final ots = seen.where((x) => x.startsWith('OT')).toList()..sort();
    final periods = [
      for (final q in const ['Q1', 'Q2', 'Q3', 'Q4'])
        if (seen.contains(q) || done) q,
      ...ots,
    ];

    BoxLine? leader(int Function(BoxLine) f) {
      BoxLine? best;
      for (final l in bb.boxPlayers) {
        if (f(l) > 0 && (best == null || f(l) > f(best))) best = l;
      }
      return best;
    }

    final leaders = [
      ('Points', leader((l) => l.pts), (BoxLine l) => l.pts),
      ('Rebounds', leader((l) => l.reb), (BoxLine l) => l.reb),
      ('Assists', leader((l) => l.ast), (BoxLine l) => l.ast),
    ].where((x) => x.$2 != null).toList();

    TextStyle cell({bool bold = false, Color? color}) => TextStyle(
          color: color ?? p.ink,
          fontSize: 12.5,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    Widget c(String v,
            {double w = 40,
            bool bold = false,
            Color? color,
            TextAlign align = TextAlign.right}) =>
        SizedBox(
            width: w,
            child: Text(v,
                textAlign: align, style: cell(bold: bold, color: color)));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (done) ...[
        GlassCard(
          child: Row(children: [
            SpIconTile(Icons.emoji_events_rounded,
                bg: winner != null ? p.orangeTint : p.surface2,
                fg: winner != null ? p.orangeInk : p.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(wentOT ? 'Final · after overtime' : 'Final',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                    Text(
                        winner != null
                            ? '${winner.name} won'
                            : game.teams.any((t) => t.result == 'draw')
                                ? 'Tied'
                                : 'Match summary',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                  ]),
            ),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      if (periods.isNotEmpty && game.teams.length == 2) ...[
        GlassCard(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                c('TEAM', w: 120, color: p.muted, align: TextAlign.left),
                for (final per in periods) c(per, color: p.muted),
                c('T', w: 44, color: p.muted),
              ]),
              for (final t in game.teams) ...[
                const Divider(height: 12),
                Row(children: [
                  SizedBox(
                    width: 120,
                    child: Text(t.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: cell(bold: true)),
                  ),
                  for (final per in periods)
                    c('${byTeam[t.teamId]?[per] ?? 0}'),
                  c('${t.score}', w: 44, bold: true),
                ]),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (leaders.isNotEmpty) ...[
        Row(children: [
          for (var i = 0; i < leaders.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: GlassCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(leaders[i].$1.toUpperCase(),
                          style: TextStyle(
                              color: p.muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                      Text('${leaders[i].$3(leaders[i].$2!)}',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                      Text(
                        names[leaders[i].$2!.playerId] != null
                            ? '${_jn(names[leaders[i].$2!.playerId]!.jersey)}${names[leaders[i].$2!.playerId]!.displayName}'
                            : 'Player',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 11.5),
                      ),
                    ]),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 10),
      ],
      for (final t in game.teams) ...[
        Builder(builder: (context) {
          final rows = [
            for (final l in bb.boxPlayers)
              if (l.teamId == t.teamId) l
          ]..sort((x, y) => y.pts != x.pts ? y.pts - x.pts : y.reb - x.reb);
          if (rows.isEmpty) return const SizedBox.shrink();
          final tot = bb.boxTeams[t.teamId];
          const heads = [
            'PTS',
            'REB',
            'AST',
            'STL',
            'BLK',
            'TO',
            'PF',
            'FG',
            '3PT',
            'FT',
            'FG%'
          ];
          List<String> vals(BoxLine l) => [
                '${l.pts}',
                '${l.reb}',
                '${l.ast}',
                '${l.stl}',
                '${l.blk}',
                '${l.tov}',
                '${l.pf}',
                '${l.fgm}-${l.fga}',
                '${l.tpm}-${l.tpa}',
                '${l.ftm}-${l.fta}',
                _pct(l.fgm, l.fga),
              ];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                            color: _teamColor(t.color),
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(t.name,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w800)),
                      ),
                      Text('Box score',
                          style: TextStyle(color: p.muted, fontSize: 11)),
                    ]),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              c('PLAYER',
                                  w: 130,
                                  color: p.muted,
                                  align: TextAlign.left),
                              for (final h in heads)
                                c(h,
                                    w: h.length > 3 || h == 'FG%' ? 52 : 40,
                                    color: p.muted),
                            ]),
                            for (final l in rows) ...[
                              const Divider(height: 10),
                              Row(children: [
                                SizedBox(
                                  width: 130,
                                  child: Text(
                                    names[l.playerId] != null
                                        ? '${_jn(names[l.playerId]!.jersey)}${names[l.playerId]!.displayName}'
                                            '${names[l.playerId]!.sentOff ? ' · out' : ''}'
                                        : 'Player',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: cell(bold: true),
                                  ),
                                ),
                                for (var i = 0; i < heads.length; i++)
                                  c(vals(l)[i],
                                      w: heads[i].length > 3 ||
                                              heads[i] == 'FG%'
                                          ? 52
                                          : 40,
                                      bold: i == 0,
                                      color:
                                          i == 6 && l.pf >= bb.rules.foulLimit
                                              ? p.danger
                                              : i == 10
                                                  ? p.muted
                                                  : null),
                              ]),
                            ],
                            if (tot != null) ...[
                              const Divider(height: 12, thickness: 1.5),
                              Row(children: [
                                c('Team',
                                    w: 130, bold: true, align: TextAlign.left),
                                for (var i = 0; i < heads.length; i++)
                                  c(vals(tot)[i],
                                      w: heads[i].length > 3 ||
                                              heads[i] == 'FG%'
                                          ? 52
                                          : 40,
                                      bold: true),
                              ]),
                            ],
                          ]),
                    ),
                    if (tot != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '3PT ${_pct(tot.tpm, tot.tpa)} · FT ${_pct(tot.ftm, tot.fta)} · '
                        'Off. reb ${tot.oreb} · Def. reb ${tot.dreb}',
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

bool isBasketballSport(String? name, String? emoji) =>
    RegExp('basket', caseSensitive: false).hasMatch(name ?? '') ||
    emoji == '🏀';

/// How a basketball game is played: 4 timed quarters (+ overtime) or first
/// to N — and the foul rules.
class BasketballFormatFields extends StatelessWidget {
  const BasketballFormatFields(
      {super.key, required this.value, required this.onChanged});
  final BasketballRules value;
  final ValueChanged<BasketballRules> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget field(String label, int v, int min, int max, ValueChanged<int> set,
            {String? hint}) =>
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    color: p.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Row(children: [
              _StepBtn(
                  icon: Icons.remove_rounded,
                  onTap: v > min ? () => set(v - 1) : null),
              Expanded(
                child: Text('$v',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ),
              _StepBtn(
                  icon: Icons.add_rounded,
                  onTap: v < max ? () => set(v + 1) : null),
            ]),
            if (hint != null)
              Text(hint, style: TextStyle(color: p.muted, fontSize: 10.5)),
          ]),
        );
    final timed = !value.isTarget;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: p.surface2, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('🏀 Game format',
            style: TextStyle(
                color: p.ink, fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SpSegmented(
          options: const ['4 quarters', 'First to N'],
          index: timed ? 0 : 1,
          onChanged: (i) =>
              onChanged(value.copyWith(format: i == 0 ? 'timed' : 'target')),
        ),
        const SizedBox(height: 12),
        if (timed)
          Row(children: [
            field('Minutes per quarter', value.quarterMinutes, 1, 30,
                (n) => onChanged(value.copyWith(quarterMinutes: n)),
                hint: 'FIBA 10 · NBA 12'),
            const SizedBox(width: 12),
            field('Overtime (min)', value.overtimeMinutes, 1, 15,
                (n) => onChanged(value.copyWith(overtimeMinutes: n)),
                hint: 'When tied after the 4th'),
          ])
        else
          Row(children: [
            field('Points to win', value.targetScore, 1, 200,
                (n) => onChanged(value.copyWith(targetScore: n))),
            const SizedBox(width: 12),
            field('Win by', value.winBy, 1, 5,
                (n) => onChanged(value.copyWith(winBy: n)),
                hint: '1 = next basket wins'),
          ]),
        const SizedBox(height: 10),
        Row(children: [
          field('Fouls to foul out', value.foulLimit, 1, 10,
              (n) => onChanged(value.copyWith(foulLimit: n)),
              hint: 'FIBA 5 · NBA 6'),
          const SizedBox(width: 12),
          field('Bonus from team foul', value.bonusAt, 0, 15,
              (n) => onChanged(value.copyWith(bonusAt: n)),
              hint: timed ? 'Per quarter · 0 = off' : 'Whole game · 0 = off'),
        ]),
        const SizedBox(height: 10),
        if (timed)
          Row(children: [
            field('Timeouts 1st half', value.timeoutsFirstHalf, 0, 10,
                (n) => onChanged(value.copyWith(timeoutsFirstHalf: n))),
            const SizedBox(width: 12),
            field('2nd half', value.timeoutsSecondHalf, 0, 10,
                (n) => onChanged(value.copyWith(timeoutsSecondHalf: n)),
                hint: 'Max 2 in the last 2 min'),
            const SizedBox(width: 12),
            field('Per OT', value.timeoutsPerOvertime, 0, 5,
                (n) => onChanged(value.copyWith(timeoutsPerOvertime: n))),
          ])
        else
          Row(children: [
            field('Timeouts per team', value.timeoutsPerGame, 0, 10,
                (n) => onChanged(value.copyWith(timeoutsPerGame: n)),
                hint: 'Whole game · 0 = none'),
          ]),
        if (timed) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: p.line),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Shot clock',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w800)),
                      Text('Runs with the game clock and buzzes at 0',
                          style: TextStyle(color: p.muted, fontSize: 11)),
                    ]),
              ),
              Switch.adaptive(
                value: value.shotClock > 0,
                onChanged: (on) =>
                    onChanged(value.copyWith(shotClock: on ? 24 : 0)),
              ),
            ]),
          ),
          if (value.shotClock > 0) ...[
            const SizedBox(height: 10),
            Row(children: [
              field('Shot clock (s)', value.shotClock, 10, 35,
                  (n) => onChanged(value.copyWith(shotClock: n)),
                  hint: 'FIBA / NBA 24'),
              const SizedBox(width: 12),
              field('After off. rebound', value.shotClockShort, 5, 35,
                  (n) => onChanged(value.copyWith(shotClockShort: n)),
                  hint: 'FIBA / NBA 14'),
            ]),
          ],
        ],
        const SizedBox(height: 8),
        Text(
          timed
              ? 'The clock counts down each quarter and stops on every whistle. Tied at the end? Overtime, as many as it takes.'
              : 'No clock to beat — the first team to ${value.targetScore}'
                  '${value.winBy > 1 ? ', ahead by ${value.winBy},' : ''} wins.',
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
