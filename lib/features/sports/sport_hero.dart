import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/sports/sport_artwork.dart';
import 'package:sportpadi_mobile/features/sports/sport_theme.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';

/// The top of a sport record page (design §3.1): a dark card painted with the
/// sport's artwork — dark in light AND dark mode — with the sport, the player,
/// their setup, three headline numbers and the sport's record line.
class SportHero extends StatelessWidget {
  const SportHero({
    super.key,
    required this.category,
    required this.family,
    required this.tally,
    required this.recent,
    required this.playerName,
    this.avatarUrl,
    this.onPlayerTap,
    this.onViewAsOthers,
  });
  final Map<String, dynamic> category;
  final SportFamily family;

  /// The overall tally (the hero doesn't follow the scope switch).
  final Map<String, dynamic> tally;

  /// Every recent game, newest first — for the streak.
  final List<Map<String, dynamic>> recent;
  final String playerName;
  final String? avatarUrl;
  final VoidCallback? onPlayerTap;

  /// Own view only: open the public version of this page.
  final VoidCallback? onViewAsOthers;

  void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = sportTheme(family);
    final top = MediaQuery.of(context).padding.top;
    final emoji = parseStr(category['emoji']) ?? t.emoji;
    final name = parseStr(category['name']) ?? 'Sport';
    final fields = statFields(category['fields'], family);
    final setup = listOf(category['setup']);
    final games = gamesOf(tally);
    final att = attendanceOf(category);
    final checkIns = statInt(att['checkIns']);
    final heads = headlineFor(family, tally, fields, attendance: att);
    final line =
        recordLineFor(family, tally, streak: streakOf(recent), attendance: att);
    // Hikes and runs lead with check-ins; every other sport with games.
    final showNumbers =
        isAttendanceDesign(family) ? games > 0 || checkIns > 0 : games > 0;
    final canPop = context.canPop();

    Widget linePill(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0x38000000),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 7,
              height: 7,
              decoration:
                  BoxDecoration(color: t.accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: sportHeroInk,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabularFigures)),
            ),
          ]),
        );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Stack(children: [
        Positioned.fill(child: SportArtworkBox(family: family, emoji: emoji)),
        // A scrim top and bottom so the text always reads over the lines.
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Color(0x00000000),
                  Color(0x52000000)
                ],
                stops: [0, 0.4, 1],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(16, top + 8, 16, 22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _GlassButton(
                icon: canPop
                    ? Icons.arrow_back_ios_new_rounded
                    : Icons.home_outlined,
                tooltip: canPop ? 'Back' : 'Home',
                onTap: () => _back(context),
              ),
              if (onViewAsOthers != null) ...[
                const SizedBox(width: 12),
                // Flush right, and free to shrink (ellipsis) on narrow
                // screens.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _GlassPill(
                      icon: Icons.visibility_outlined,
                      label: 'View as others see it',
                      onTap: onViewAsOthers!,
                    ),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sportHeroPill,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0x1FFFFFFF)),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: sportHeroInk,
                              fontSize: 26,
                              height: 1.1,
                              letterSpacing: -0.4,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: onPlayerTap,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            padding: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: t.accent, width: 1.5),
                            ),
                            child: ClipOval(
                              child: Crest(
                                  logoUrl: avatarUrl,
                                  label: playerName,
                                  size: 22),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(playerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: sportHeroMuted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    ]),
              ),
            ]),
            if (setup.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in setup)
                  if (parseStr(f['value']) != null) _SetupPill(field: f),
              ]),
            ],
            const SizedBox(height: 22),
            if (showNumbers) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < heads.length; i++)
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
                      decoration: i == 0
                          ? null
                          : const BoxDecoration(
                              border: Border(
                                  left: BorderSide(color: Color(0x29FFFFFF)))),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(heads[i].$1,
                                  maxLines: 1,
                                  style: TextStyle(
                                      color: i == 0 ? t.accent : sportHeroInk,
                                      fontSize: 32,
                                      height: 1,
                                      letterSpacing: -0.8,
                                      fontWeight: FontWeight.w800,
                                      fontFeatures: tabularFigures)),
                            ),
                            const SizedBox(height: 7),
                            Text(heads[i].$2.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: sportHeroMuted,
                                    fontSize: 10.5,
                                    letterSpacing: 1.1,
                                    fontWeight: FontWeight.w700)),
                          ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              linePill(line),
            ] else ...[
              Text(
                  isAttendanceDesign(family)
                      ? 'No $name outings on record yet.'
                      : 'No $name games on record yet.',
                  style: const TextStyle(
                      color: sportHeroMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              // Check-ins but no games yet (a club night, a session).
              if (checkIns > 0) ...[
                const SizedBox(height: 12),
                linePill(attendanceSummary(family, att)),
              ],
            ],
          ]),
        ),
      ]),
    );
  }
}

/// "Positions  ST, CAM" as a translucent pill.
class _SetupPill extends StatelessWidget {
  const _SetupPill({required this.field});
  final Map<String, dynamic> field;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 32),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: sportHeroPill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
              text: '${parseStr(field['label']) ?? ''}  ',
              style: const TextStyle(
                  color: sportHeroMuted, fontWeight: FontWeight.w600)),
          TextSpan(
              text: parseStr(field['value']) ?? '',
              style: const TextStyle(
                  color: sportHeroInk, fontWeight: FontWeight.w700)),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

/// A round translucent button on the hero.
class _GlassButton extends StatelessWidget {
  const _GlassButton(
      {required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: sportHeroPill,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(icon, size: 18, color: sportHeroInk),
          ),
        ),
      ),
    );
  }
}

/// A translucent pill action on the hero.
class _GlassPill extends StatelessWidget {
  const _GlassPill(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: sportHeroPill,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: sportHeroInk),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: sportHeroInk,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}
