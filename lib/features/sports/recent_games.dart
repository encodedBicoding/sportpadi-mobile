import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Recent games, each row in the sport's own style (design §5, §8): a match
/// report for soccer, a box-score line for basketball, a linescore for
/// baseball, chess notation, a golf scorecard line …
class RecentGames extends StatefulWidget {
  const RecentGames({
    super.key,
    required this.family,
    required this.games,
    required this.fields,
    required this.playerId,
    this.initial = 5,
  });
  final SportFamily family;

  /// Newest first.
  final List<Map<String, dynamic>> games;
  final List<SportStat> fields;

  /// Whose record — rows open THEIR event / tournament record.
  final String playerId;
  final int initial;

  @override
  State<RecentGames> createState() => _RecentGamesState();
}

class _RecentGamesState extends State<RecentGames> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final games = widget.games;
    final shown = _all ? games : games.take(widget.initial).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RecordSectionTitle('Recent games', count: games.length),
      const SizedBox(height: 10),
      RecordList(children: [
        for (final g in shown)
          RecentGameRow(
            game: g,
            family: widget.family,
            fields: widget.fields,
            playerId: widget.playerId,
          ),
        if (games.length > shown.length)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => setState(() => _all = true),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Center(
                child: Text('Show all ${games.length}',
                    style: TextStyle(
                        color: p.greenText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
      ]),
    ]);
  }
}

/// One finished game from the player's side.
class RecentGameRow extends StatelessWidget {
  const RecentGameRow({
    super.key,
    required this.game,
    required this.family,
    required this.fields,
    required this.playerId,
  });
  final Map<String, dynamic> game;
  final SportFamily family;
  final List<SportStat> fields;
  final String playerId;

  void _open(BuildContext context) {
    final eventId = parseStr(game['eventId']);
    final gameId = parseStr(game['gameId']);
    if (eventId != null) {
      context.push(parseStr(game['scope']) == 'tournament'
          ? '/players/$playerId/tournaments/$eventId'
          : '/players/$playerId/events/$eventId');
    } else if (gameId != null) {
      context.push('/games/$gameId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final result = parseStr(game['result']);
    final us = mapOf(game['us']);
    final them = game['them'] is Map ? mapOf(game['them']) : null;
    final counts = mapOf(game['counts']);
    final usName = parseStr(us['name']) ?? 'Us';
    final themName = parseStr(them?['name']);
    final usScore = statInt(us['score']);
    final themScore = statInt(them?['score']);
    final venue = parseStr(game['eventTitle']) ?? parseStr(game['groupName']);
    final tournament = parseStr(game['scope']) == 'tournament';
    final golf = family == SportFamily.golf;
    final chess = family == SportFamily.chess;

    final (badgeBg, badgeFg, letter) = switch (result) {
      'win' => (p.accentTint, p.greenText, chess ? '1' : 'W'),
      'loss' => (p.liveTint, p.danger, chess ? '0' : 'L'),
      'draw' => (p.surface2, p.muted, chess ? '½' : 'D'),
      _ => (p.surface2, p.muted, '–'),
    };

    final headStyle = TextStyle(
        color: p.ink,
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        fontFeatures: tabularFigures);
    final score = them == null ? '$usScore' : '$usScore–$themScore';
    final vs = them == null ? null : 'vs ${themName ?? 'Opponent'}';

    // Under the headline: the day and the event — for golf the headline has
    // those, so the score against the field goes here instead.
    final meta = [
      if (golf) ...[
        if (vs != null) '$score $vs',
      ] else ...[
        plainDay(game['date']),
        venue,
      ],
      if (tournament) 'Tournament',
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    // The headline: a match report for soccer ("Lions 3 – 1 Eagles", my team
    // bold); chess notation ("1–0 vs Ana"); a scorecard line for golf ("Rd ·
    // Oct 12 · Pinewood"); the pair for padel ("6–4 · Lions"); a scoreline +
    // opponent everywhere else ("54–48 vs Eagles").
    final InlineSpan head = switch (family) {
      SportFamily.chess => TextSpan(children: [
          TextSpan(
              text: chessResult(result),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(
              text: '  ${vs ?? usName}',
              style: TextStyle(
                  color: vs == null ? p.ink : p.muted,
                  fontWeight: FontWeight.w600)),
        ]),
      SportFamily.golf => TextSpan(children: [
          const TextSpan(
              text: 'Rd', style: TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(
              text: [shortDay(game['date']), venue ?? '']
                  .where((s) => s.isNotEmpty)
                  .map((s) => ' · $s')
                  .join(),
              style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
        ]),
      SportFamily.padel => TextSpan(children: [
          TextSpan(
              text: score, style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(
              text: ' · $usName',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (vs != null)
            TextSpan(
                text: '  $vs',
                style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
        ]),
      SportFamily.soccer => TextSpan(children: [
          TextSpan(
              text: usName,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(
              text: them == null ? '  $usScore' : '  $usScore – $themScore  ',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          if (them != null)
            TextSpan(
                text: themName ?? 'Opponent',
                style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
        ]),
      _ => TextSpan(children: [
          TextSpan(
              text: score, style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(
              text: '  ${vs ?? usName}',
              style: TextStyle(
                  color: vs == null ? p.ink : p.muted,
                  fontWeight: FontWeight.w600)),
        ]),
    };

    final line = _statLine(p, counts);

    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: badgeBg, borderRadius: BorderRadius.circular(12)),
            child: Text(letter,
                style: TextStyle(
                    color: badgeFg, fontSize: 14, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(head,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: headStyle),
                  if (line != null) ...[
                    const SizedBox(height: 4),
                    line,
                  ],
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                  ],
                ]),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
        ]),
      ),
    );
  }

  /// The player's own numbers in this game, in the sport's style.
  Widget? _statLine(AppPalette p, Map<String, dynamic> counts) {
    int n(String k) => countOf(counts, k);
    // Every field the design doesn't spell out, as "icon n" chips.
    List<String> rest(Set<String> placed) => [
          for (final f in fields)
            if (!placed.contains(f.key) && n(f.key) > 0)
              '${f.icon ?? f.label} ${n(f.key)}',
        ];
    switch (family) {
      case SportFamily.soccer:
        return _chips(p, [
          if (n('goals') > 0) '⚽ ${n('goals')}',
          if (n('assists') > 0) '🅰️ ${n('assists')}',
          if (n('yellows') > 0) n('yellows') > 1 ? '🟨 ${n('yellows')}' : '🟨',
          if (n('reds') > 0) '🟥',
          if (n('ownGoals') > 0) '🥅 ${n('ownGoals')} OG',
          ...rest(const {'goals', 'assists', 'yellows', 'reds', 'ownGoals'}),
        ]);
      case SportFamily.tennis:
        return _chips(p, [
          if (n('aces') > 0) '🎯 ${plural(n('aces'), 'ace')}',
          ...rest(const {'aces'}),
        ]);
      case SportFamily.padel:
      case SportFamily.tableTennis:
      case SportFamily.chess:
      case SportFamily.ultimate:
      case SportFamily.golf:
      case SportFamily.hiking:
      case SportFamily.running:
      case SportFamily.paintball:
      case SportFamily.generic:
        return _chips(p, rest(const {}));
      case SportFamily.basketball:
        return _boxLine(p, [
          (n('points'), 'PTS'),
          if (hasStat('assists', fields, counts)) (n('assists'), 'AST'),
          if (n('reb') > 0) (n('reb'), 'REB'),
          if (hasStat('fouls', fields, counts)) (n('fouls'), 'PF'),
        ]);
      case SportFamily.volleyball:
        return _boxLine(p, [
          (n('points'), n('points') == 1 ? 'pt' : 'pts'),
          if (n('aces') > 0) (n('aces'), n('aces') == 1 ? 'ace' : 'aces'),
          if (n('blocks') > 0)
            (n('blocks'), n('blocks') == 1 ? 'block' : 'blocks'),
        ]);
      case SportFamily.baseball:
        return _boxLine(p, [
          (n('runs'), 'R'),
          (n('hits'), 'H'),
          if (n('homeRuns') > 0) (n('homeRuns'), 'HR'),
        ]);
    }
  }

  /// The player's numbers as small pills ("⚽ 2", "🎯 3 aces"); null when
  /// there are none.
  Widget? _chips(AppPalette p, List<String> chips) {
    if (chips.isEmpty) return null;
    return Wrap(spacing: 5, runSpacing: 4, children: [
      for (final c in chips)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(c,
              style: TextStyle(
                  color: p.ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures)),
        ),
    ]);
  }

  /// "18 PTS · 4 AST · 2 PF" — numbers bold, units muted, tabular.
  Widget _boxLine(AppPalette p, List<(int, String)> parts) => Text.rich(
        TextSpan(children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0)
              TextSpan(
                  text: '  ·  ',
                  style: TextStyle(color: p.muted.withAlpha(120))),
            TextSpan(
                text: '${parts[i].$1}',
                style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
            TextSpan(
                text: ' ${parts[i].$2}',
                style: TextStyle(color: p.muted, fontWeight: FontWeight.w600)),
          ],
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 12.5,
            letterSpacing: 0.2,
            fontFeatures: [FontFeature.tabularFigures()]),
      );
}
