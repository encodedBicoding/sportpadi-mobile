import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';

/// Instagram-style square event tile (web EventTile): cover or emoji-gradient,
/// dark wash, title + date, LIVE badge. Used on profile + group event grids.
class EventTileSquare extends StatelessWidget {
  const EventTileSquare({super.key, required this.event, this.onTap});
  final EventSummary event;

  /// Where the tile goes. Defaults to the event itself; a player's own grids
  /// pass their per-event record instead, because for a finished event the
  /// event page is a scoresheet — "what happened", not "how did I do".
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    final live = e.status == 'kicked_off' || e.isLive;
    final tournament = e.isTournament;
    return InkWell(
      onTap: onTap ??
          () => e.isTournament
              ? context.push('/tournaments/${e.id}')
              : context.push('/events/${e.slug.isNotEmpty ? e.slug : e.id}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: tournament
                  ? const Color.fromRGBO(245, 158, 11, 0.55)
                  : p.line),
          // Tournaments glow (web: amber ring + soft shadow).
          boxShadow: tournament
              ? const [
                  BoxShadow(
                    color: Color.fromRGBO(245, 158, 11, 0.35),
                    blurRadius: 14,
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (e.coverImage != null)
              Image.network(e.coverImage!,
                  fit: BoxFit.cover, errorBuilder: (_, __, ___) => _wash(e))
            else
              _wash(e),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color.fromRGBO(0, 0, 0, 0.72),
                    Color.fromRGBO(0, 0, 0, 0.05),
                  ],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
            if (tournament)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('🏆 TOURNAMENT',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4)),
                ),
              ),
            if (live)
              Positioned(
                left: tournament ? null : 6,
                right: tournament ? 6 : null,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('LIVE',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Team event: "For U12 Lions".
                  if (audienceLabel(e.audienceTeams) case final String who)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(children: [
                        const Icon(Icons.shield_outlined,
                            size: 10, color: Colors.white),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ]),
                    ),
                  Text(e.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.2)),
                  if (e.groupName != null)
                    Text(e.groupName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color.fromRGBO(255, 255, 255, 0.85),
                            fontSize: 10,
                            fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(formatDay(e.eventDate),
                      style: const TextStyle(
                          color: Color.fromRGBO(255, 255, 255, 0.75),
                          fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wash(EventSummary e) => Container(
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.fromRGBO(23, 166, 94, 0.25),
              Color.fromRGBO(245, 167, 10, 0.20),
            ],
          ),
        ),
        child: Text(e.isTournament ? '🏆' : (e.categoryEmoji ?? '🏅'),
            style: const TextStyle(fontSize: 34)),
      );
}
