import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/sports/sport_artwork.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// A sport card (design §6): the sport's artwork, its name, the record line
/// and the three headline numbers. Used by My records and the public
/// profile's Records section.
class SportRecordCard extends StatelessWidget {
  const SportRecordCard({
    super.key,
    required this.category,
    required this.onTap,
  });
  final Map<String, dynamic> category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final family = familyOf(category);
    final t = sportTheme(family);
    final emoji = parseStr(category['emoji']) ?? t.emoji;
    final name = parseStr(category['name']) ?? 'Sport';
    final tally = mapOf(category['overall']);
    final games = gamesOf(tally);
    final att = attendanceOf(category);
    final checkIns = statInt(att['checkIns']);
    final fields = statFields(category['fields'], family);
    final setup = [
      for (final f in listOf(category['setup']))
        if (parseStr(f['value']) != null) parseStr(f['value'])!
    ];
    final heads = headlineFor(family, tally, fields, attendance: att);
    // Hikes and runs lead with check-ins; every other sport with games.
    final showNumbers =
        isAttendanceDesign(family) ? games > 0 || checkIns > 0 : games > 0;

    return Semantics(
      button: true,
      label: '$name record',
      child: SizedBox(
        height: 132,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(children: [
            Positioned.fill(
              child: SportArtworkBox(family: family, emoji: emoji, dense: true),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0x47000000), Color(0x00000000)],
                    stops: [0, 0.75],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 10, 14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(emoji, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: sportHeroInk,
                                fontSize: 17,
                                fontWeight: FontWeight.w800)),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          size: 22, color: sportHeroMuted),
                    ]),
                    const SizedBox(height: 2),
                    Text(cardLineFor(family, category),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: sportHeroMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            fontFeatures: tabularFigures)),
                    const Spacer(),
                    if (showNumbers)
                      Row(children: [
                        for (var i = 0; i < heads.length; i++)
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(heads[i].$1,
                                        maxLines: 1,
                                        style: TextStyle(
                                            color: i == 0
                                                ? t.accent
                                                : sportHeroInk,
                                            fontSize: 21,
                                            height: 1.05,
                                            fontWeight: FontWeight.w800,
                                            fontFeatures: tabularFigures)),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(heads[i].$2.toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: sportHeroMuted,
                                          fontSize: 9.5,
                                          letterSpacing: 1,
                                          fontWeight: FontWeight.w700)),
                                ]),
                          ),
                      ])
                    else
                      Text(
                          setup.isNotEmpty
                              ? setup.join(' · ')
                              : checkIns > 0
                                  ? 'No games yet'
                                  : 'Nothing on record yet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: sportHeroInk,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                  ]),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A compact row for a sport they haven't played ("Other sports").
class OtherSportRow extends StatelessWidget {
  const OtherSportRow({super.key, required this.category, required this.onTap});
  final Map<String, dynamic> category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final family = familyOf(category);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: p.surface2, borderRadius: BorderRadius.circular(12)),
            child: Text(parseStr(category['emoji']) ?? sportTheme(family).emoji,
                style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(parseStr(category['name']) ?? 'Sport',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Text('Not played yet',
              style: TextStyle(color: p.muted, fontSize: 12)),
          Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
        ]),
      ),
    );
  }
}

/// The public profile's Records section: one sport card per sport they've
/// played, each opening that sport's record.
class PlayerRecordsSection extends StatelessWidget {
  const PlayerRecordsSection({
    super.key,
    required this.userId,
    required this.categories,
    required this.loaded,
  });
  final String userId;
  final List<Map<String, dynamic>> categories;

  /// False while the stats are still on their way.
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final played = [
      for (final c in categories)
        if (hasPlayed(c) && parseStr(c['categoryId']) != null) c
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SpSectionTitle('Records', count: played.isEmpty ? null : played.length),
      const SizedBox(height: 10),
      if (!loaded)
        GlassCard(
          child: Text('Loading their record…',
              style: TextStyle(color: p.muted, fontSize: 13)),
        )
      else if (played.isEmpty)
        GlassCard(
          child: Row(children: [
            SpIconTile(Icons.emoji_events_outlined,
                bg: p.surface2, fg: p.muted, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('No games on record yet',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        "Their sports appear here once they've finished a game.",
                        style: TextStyle(
                            color: p.muted, fontSize: 12.5, height: 1.35)),
                  ]),
            ),
          ]),
        )
      else
        for (var i = 0; i < played.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          SportRecordCard(
            category: played[i],
            onTap: () => context.push(
                '/players/$userId/records/${parseStr(played[i]['categoryId'])}'),
          ),
        ],
    ]);
  }
}
