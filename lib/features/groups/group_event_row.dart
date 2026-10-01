import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/event_audience.dart';

/// One event as a row in a group's event lists (web `GroupEventRow`): a
/// weekday/day tile (ink when live, orange for tournaments, quiet otherwise),
/// emoji + title, time · venue, the teams it's for, then LIVE or a chevron.
/// Drop several inside an `SpListCard`.
class GroupEventRow extends StatelessWidget {
  const GroupEventRow({super.key, required this.event});
  final EventSummary event;

  static const _wd = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    final d = e.eventDate?.toUtc();
    final live = e.isLive || e.status == 'kicked_off';
    final clock = formatClock(e.startTime);
    final sub = [
      if (clock != null) clock,
      if (e.locationName != null && e.locationName!.isNotEmpty)
        e.locationName!,
    ].join(' · ');
    // Transparent material so the ripple shows on the card's white.
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => e.isTournament
          ? context.push('/tournaments/${e.id}')
          : context.push('/events/${e.slug.isNotEmpty ? e.slug : e.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(children: [
          Container(
            width: 46,
            height: 50,
            decoration: BoxDecoration(
              color: live
                  ? p.hero
                  : e.isTournament
                      ? p.orangeTint
                      : p.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(d != null ? _wd[d.weekday - 1] : '—',
                  style: TextStyle(
                      color: live
                          ? p.heroMuted
                          : e.isTournament
                              ? p.orangeInk
                              : p.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
              Text(d != null ? '${d.day}' : '—',
                  style: TextStyle(
                      color: live
                          ? p.onHero
                          : e.isTournament
                              ? p.orangeInk
                              : p.ink,
                      fontSize: 19,
                      height: 1.05,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e.categoryEmoji != null ? '${e.categoryEmoji} ' : ''}${e.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              if (sub.isNotEmpty)
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12)),
              if (e.audienceTeams.isNotEmpty) ...[
                const SizedBox(height: 4),
                AudienceBadge(e.audienceTeams),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          if (live)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: p.danger, borderRadius: BorderRadius.circular(999)),
              child: const Text('LIVE',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            )
          else
            Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
        ]),
      ),
      ),
    );
  }
}
