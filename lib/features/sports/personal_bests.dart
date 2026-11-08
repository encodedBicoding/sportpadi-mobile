import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Keys that are never a "best" (nobody brags about their most fouls).
const _notABest = {
  'fouls', 'yellows', 'reds', 'greens', 'ownGoals', 'turnovers', //
  'strikeouts', 'faults', 'attackErrors', 'serviceErrors', //
  'receptionErrors', 'suspensions',
};

/// Personal bests — single-game highs for the sport's headline stats, only
/// the ones they've actually set.
class PersonalBests extends StatelessWidget {
  const PersonalBests({
    super.key,
    required this.family,
    required this.bests,
    required this.fields,
    this.top = 0,
  });
  final SportFamily family;

  /// Space above the section, only when there is one.
  final double top;

  /// `bests[scope]`: `{ key: { value, gameId, date } }`.
  final Map<String, dynamic> bests;
  final List<SportStat> fields;

  /// (key, label, unit) in the order the sport cares about.
  List<(String, String, String?)> _wanted() {
    // "Most aces in a match", "Most birdies in a round" — no stroke
    // semantics are known, so golf reads higher-is-better too (§8).
    String most(String key) {
      final stat = fieldFor(key, fields, family).label.toLowerCase();
      // Same families as gameNoun(): match / round / race / game.
      return switch (family) {
        SportFamily.tennis ||
        SportFamily.padel =>
          l10n.profile_mostStatInAMatch(stat),
        SportFamily.golf => l10n.profile_mostStatInARound(stat),
        SportFamily.running => l10n.profile_mostStatInARace(stat),
        _ => l10n.profile_mostStatInAGame(stat),
      };
    }

    switch (family) {
      case SportFamily.soccer:
        return [
          ('goals', l10n.profile_mostGoalsInAGame, null),
          ('assists', l10n.profile_mostAssistsInAGame, null),
        ];
      case SportFamily.basketball:
        return [
          ('points', l10n.profile_careerHigh, l10n.profile_p5StatPts),
          ('assists', l10n.profile_mostAssists, l10n.profile_p5StatAst),
          ('reb', l10n.profile_mostRebounds, l10n.profile_p5StatReb),
        ];
      case SportFamily.volleyball:
        return [
          ('points', l10n.profile_mostPointsInAGame, null),
          ('aces', l10n.profile_mostAcesInAGame, null),
          ('blocks', l10n.profile_mostBlocksInAGame, null),
        ];
      case SportFamily.baseball:
        return [
          ('runs', l10n.profile_mostRunsInAGame, null),
          ('hits', l10n.profile_mostHitsInAGame, null),
          ('homeRuns', l10n.profile_mostHomeRunsInAGame, null),
        ];
      case SportFamily.tennis:
      case SportFamily.padel:
      case SportFamily.tableTennis:
      case SportFamily.chess:
      case SportFamily.ultimate:
      case SportFamily.golf:
      case SportFamily.hiking:
      case SportFamily.running:
      case SportFamily.paintball:
      case SportFamily.generic:
        return [
          for (final f in fields)
            if (!_notABest.contains(f.key)) (f.key, most(f.key), null),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final entries = [
      for (final (key, label, unit) in _wanted())
        if (statInt(mapOf(bests[key])['value']) > 0)
          (key, label, unit, mapOf(bests[key])),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    // Same design as the web: label, big number (+ unit), date, the stat's
    // emoji as a faint watermark — and each tile opens the game it was set in.
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RecordSectionTitle(context.l10n.profile_personalBests),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth >= 560 ? 3 : 2;
          final tileW = (box.maxWidth - 10 * (cols - 1)) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (key, label, unit, best) in entries)
              SizedBox(
                width: tileW,
                child: _BestTile(
                  icon: fieldFor(key, fields, family).icon ?? '🏅',
                  label: label,
                  value: statInt(best['value']),
                  unit: unit,
                  date: plainDay(best['date']),
                  gameId: parseStr(best['gameId']),
                  palette: p,
                ),
              ),
          ]);
        }),
      ]),
    );
  }
}

class _BestTile extends StatelessWidget {
  const _BestTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.date,
    required this.gameId,
    required this.palette,
  });
  final String icon;
  final String label;
  final int value;
  final String? unit;
  final String date;
  final String? gameId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final id = gameId;
    return GlassCard(
      padding: EdgeInsets.zero,
      onTap: id == null || id.isEmpty ? null : () => context.push('/games/$id'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(children: [
          // Faint watermark of the stat's emoji, top-right.
          Positioned(
            right: -4,
            top: -8,
            child: Opacity(
              opacity: 0.09,
              child: Text(icon, style: const TextStyle(fontSize: 44)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('$value',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 30,
                            height: 1.0,
                            fontWeight: FontWeight.w900,
                            fontFeatures: tabularFigures)),
                    if (unit != null) ...[
                      const SizedBox(width: 6),
                      Text(unit!,
                          style: TextStyle(
                              color: p.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                    ],
                  ]),
              const SizedBox(height: 6),
              Text(date,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 11)),
            ]),
          ),
        ]),
      ),
    );
  }
}
