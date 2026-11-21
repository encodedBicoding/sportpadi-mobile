import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/sports/sport_artwork.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// A sport's match rating as a card shows it (the profiles' Records tab;
/// `ratingsByCategory` from the honours read, `players/honours.ts`): the
/// average over their last 10 completed games there that could be rated
/// (null: none could — "–") and the games they have played in it.
class SportRatingCorner {
  const SportRatingCorner({this.avg, this.games}) : loading = false;

  /// The ratings are still on their way: a placeholder, not a "–".
  const SportRatingCorner.loading()
      : avg = null,
        games = null,
        loading = true;

  /// The entry for [categoryId] in `ratingsByCategory` (none: "–").
  factory SportRatingCorner.of(List<Map<String, dynamic>> ratings, String? categoryId) {
    for (final r in ratings) {
      if (parseStr(r['categoryId']) == categoryId) {
        return SportRatingCorner(avg: parseDouble(r['avg']), games: parseInt(r['games']));
      }
    }
    return const SportRatingCorner();
  }

  final double? avg;
  final int? games;
  final bool loading;

  /// Nothing to rate, no corner (review LOW-4): a hike / run counted in
  /// check-ins, or any sport with no games and no rating entry, would read
  /// "★ – / 0 games" beside its own record line. [cardGames]: the card's.
  bool rateable(int cardGames) => loading ? cardGames > 0 : (games ?? cardGames) > 0;
}

/// A sport card (design §6): the sport's artwork, its name, the record line
/// and the three headline numbers. Used by My records and the public
/// profile's Records section — where it also carries the sport's match
/// rating in its top corner ([rating]; owner, 2026-11-20: one card per
/// sport, the separate rating tile is gone):
///
///   ⚽ Football                    ★ 7.4  ›
///   P 12 · W 7 · D 2 · L 3        12 games
///   12        9          4
///   GOALS     ASSISTS    MOTM
class SportRecordCard extends StatelessWidget {
  const SportRecordCard({
    super.key,
    required this.category,
    required this.onTap,
    this.rating,
  });
  final Map<String, dynamic> category;
  final VoidCallback onTap;

  /// Null: no rating corner (My records).
  final SportRatingCorner? rating;

  @override
  Widget build(BuildContext context) {
    final family = familyOf(category);
    final t = sportTheme(family);
    final emoji = parseStr(category['emoji']) ?? t.emoji;
    final name = parseStr(category['name']) ?? context.l10n.profile_sport;
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
      label: context.l10n.profile_record2(name),
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
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(emoji,
                                        style: const TextStyle(fontSize: 20)),
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
                                ]),
                          ),
                          if (rating != null && rating!.rateable(games)) ...[
                            const SizedBox(width: 8),
                            _RatingCorner(rating: rating!, games: games),
                          ],
                          const Icon(Icons.chevron_right_rounded,
                              size: 22, color: sportHeroMuted),
                        ]),
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
                                  ? context.l10n.profile_noGamesYet2
                                  : context.l10n.profile_nothingOnRecordYet,
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

/// The card's rating corner — what the rating tile showed: "★ 7.4" ("–"
/// before any game could be rated) over "12 games". Read aloud as "Avg
/// rating 7.4, 12 games".
class _RatingCorner extends StatelessWidget {
  const _RatingCorner({required this.rating, required this.games});
  final SportRatingCorner rating;

  /// The card's own games, when the rating entry has none.
  final int games;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (rating.loading) {
      return Container(
        width: 44,
        height: 32,
        decoration: BoxDecoration(
            color: const Color(0x26FFFFFF),
            borderRadius: BorderRadius.circular(8)),
      );
    }
    final avg = rating.avg;
    final value = avg == null ? '–' : avg.toStringAsFixed(1);
    final played = l.profile_ratingTileGames(rating.games ?? games);
    return Semantics(
      label:
          '${l.profile_avgRating} ${avg == null ? l.profile_ratingTileNotRated : value}, $played',
      child: ExcludeSemantics(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('★',
                    style: TextStyle(color: sportHeroMuted, fontSize: 12)),
                const SizedBox(width: 2),
                Text(value,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                        color: avg == null ? sportHeroMuted : sportHeroInk,
                        fontSize: 18,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        fontFeatures: tabularFigures)),
              ]),
              const SizedBox(height: 3),
              Text(played,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(
                      color: sportHeroMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600)),
            ]),
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
            child: Text(parseStr(category['name']) ?? context.l10n.profile_sport,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Text(context.l10n.profile_notPlayedYet,
              style: TextStyle(color: p.muted, fontSize: 12)),
          Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
        ]),
      ),
    );
  }
}

/// The profiles' Records section: ONE sport card per sport they've played
/// or have a match rating in, each with that sport's rating in its corner
/// and opening that sport's record (owner, 2026-11-20 — the rating tiles
/// that sat above the cards are merged into them).
class PlayerRecordsSection extends StatelessWidget {
  const PlayerRecordsSection({
    super.key,
    required this.userId,
    required this.categories,
    required this.loaded,
    this.mine = false,
    this.trailing,
    this.ratings,
  });
  final String userId;
  final List<Map<String, dynamic>> categories;

  /// False while the stats are still on their way.
  final bool loaded;

  /// Your own profile: cards open /profile/records/<sport>, copy says "your".
  final bool mine;

  /// e.g. an "All records" pill on your own profile.
  final Widget? trailing;

  /// `ratingsByCategory` from the honours read; null while it is on its way
  /// (each card's corner a placeholder); empty when that read failed (each
  /// corner "–", review LOW-3).
  final List<Map<String, dynamic>>? ratings;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final rated = {
      for (final r in ratings ?? const <Map<String, dynamic>>[])
        if ((parseInt(r['games']) ?? 0) > 0) parseStr(r['categoryId']),
    };
    final played = [
      for (final c in categories)
        if ((hasPlayed(c) || rated.contains(parseStr(c['categoryId']))) &&
            parseStr(c['categoryId']) != null)
          c
    ];
    final list = ratings;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Counted once the ratings are in too (a rating-only sport is a card):
      // no N → N+1 jump.
      SpSectionTitle(context.l10n.profile_records,
          count: played.isEmpty || ratings == null ? null : played.length,
          trailing: trailing),
      const SizedBox(height: 10),
      if (!loaded)
        GlassCard(
          child: Text(mine ? context.l10n.profile_loadingYourRecord : context.l10n.profile_loadingTheirRecord,
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
                    Text(context.l10n.profile_noGamesOnRecordYet2,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        mine
                            ? context.l10n.profile_playAGameThatFinishes
                            : context.l10n.profile_theirSportsAppearHereOnce,
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
            rating: list == null
                ? const SportRatingCorner.loading()
                : SportRatingCorner.of(list, parseStr(played[i]['categoryId'])),
            onTap: () => context.push(mine
                ? '/profile/records/${parseStr(played[i]['categoryId'])}'
                : '/players/$userId/records/${parseStr(played[i]['categoryId'])}'),
          ),
        ],
    ]);
  }
}
