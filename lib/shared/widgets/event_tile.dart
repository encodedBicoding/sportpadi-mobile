import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';

/// The 2026 event tile (web: components/EventTile.tsx) — Browse, and the
/// group page's Events tab and events page: a cover (photo, or a pitch drawn
/// in the sport's colour) carrying the sport and LIVE / members-only, then
/// the title, when, the group ([showGroup]), the teams a team event is for,
/// and "distance · n going" (not for past events). Each line takes room only
/// when it's shown, so a card is exactly as tall as what it says. Lay several
/// out with [EventTileGrid] (or [EventTileRow] per pair in a sliver list).
class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, this.showGroup = true});
  final EventSummary event;

  /// Off on a group's own pages (every event is that group's).
  final bool showGroup;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final e = event;
    final live = e.isLive || e.status == 'kicked_off';
    final t = e.isTournament;
    final d = e.eventDate?.toUtc();
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final when = [
      if (d != null) '${wd[d.weekday - 1]} ${d.day} ${mo[d.month - 1]}',
      if (formatClock(e.startTime) != null) formatClock(e.startTime)!,
    ].join(' · ');
    // "n going" only means something before it happens: hidden once the
    // event is over (completed, or its day has passed).
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final past = e.status == 'completed' ||
        (d != null && DateTime.utc(d.year, d.month, d.day).isBefore(today));
    final going = past ? 0 : (e.interestCount ?? 0);
    final foot = [
      if (e.distanceMiles != null) '${e.distanceMiles} mi',
      if (going > 0) '$going going',
    ].join(' · ');

    void open() => t
        ? context.push('/tournaments/${e.id}')
        : context.push('/events/${e.slug.isNotEmpty ? e.slug : e.id}');

    Widget pill(String label, Color bg, Color fg, {Widget? lead}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (lead != null) ...[lead, const SizedBox(width: 4)],
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ]),
        );

    final pitch = t ? const Color(0xFF7A3E12) : const Color(0xFF1E6B45);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: open,
        child: Ink(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(22),
            border: dark
                ? Border.all(color: p.line)
                : t
                    ? Border.all(color: p.orange.withAlpha(90))
                    : null,
            boxShadow: cardShadow(context),
          ),
          // Sized by its content: every line below the cover takes room only
          // when it's shown — no reserved footer, no blank band.
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            // Cover, inset so the card's white frames it.
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: SizedBox(
                  height: 112,
                  child: Stack(fit: StackFit.expand, children: [
                    if (e.coverImage != null)
                      CachedNetworkImage(
                        imageUrl: e.coverImage!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            CustomPaint(painter: _CoverPitch(pitch)),
                      )
                    else
                      CustomPaint(painter: _CoverPitch(pitch)),
                    if (e.coverImage == null)
                      Center(
                        child: t
                            ? const Icon(Icons.emoji_events_outlined,
                                size: 30, color: Color(0xCCFFFFFF))
                            : Text(e.categoryEmoji ?? '',
                                style: const TextStyle(fontSize: 28)),
                      ),
                    Positioned(
                      left: 8,
                      top: 8,
                      right: live ? 56 : 8,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: pill(
                          t ? 'Tournament' : (e.categoryName ?? 'Event'),
                          const Color(0xEBFFFFFF),
                          t ? const Color(0xFF9A4308) : const Color(0xFF0F7A45),
                        ),
                      ),
                    ),
                    if (live)
                      Positioned(
                        right: 8,
                        top: 8,
                        child: pill(
                            'LIVE', const Color(0xFFE02424), Colors.white,
                            lead: Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle))),
                      )
                    else if (e.isPrivate)
                      const Positioned(
                        right: 8,
                        top: 8,
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: Color(0xEBFFFFFF),
                          child: Icon(Icons.lock_outline_rounded,
                              size: 12, color: Color(0xFF3E4A45)),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
            Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13.5,
                              height: 1.25,
                              fontWeight: FontWeight.w700)),
                      if (when.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(when,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: live ? p.danger : p.muted,
                                fontSize: 11.5,
                                fontWeight:
                                    live ? FontWeight.w700 : FontWeight.w500)),
                      ],
                      if (showGroup && e.groupName != null)
                        Text(e.groupName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.muted, fontSize: 11.5)),
                      // Team events: "For U12 Lions" — one compact line.
                      if (audienceLabel(e.audienceTeams) case final aud?)
                        Row(children: [
                          Icon(Icons.shield_outlined,
                              size: 11, color: p.greenText),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(aud,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: p.greenText,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      if (foot.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(foot,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: t ? p.orangeInk : p.greenText,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      ],
                    ]),
              ),
          ]),
        ),
      ),
    );
  }
}

/// A plain pitch in the card's colour — the cover when an event has no photo.
class _CoverPitch extends CustomPainter {
  _CoverPitch(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final line = Paint()
      ..color = const Color(0x24FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final r = Rect.fromLTWH(16, 14, size.width - 32, size.height - 28);
    canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(6)), line);
    canvas.drawLine(
        Offset(size.width / 2, r.top), Offset(size.width / 2, r.bottom), line);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 26, line);
  }

  @override
  bool shouldRepaint(covariant _CoverPitch old) => old.color != color;
}

/// Two tiles side by side, each as tall as its own content (the second may
/// be null for an odd count).
class EventTileRow extends StatelessWidget {
  const EventTileRow(
      {super.key, required this.left, this.right, this.showGroup = true});
  final EventSummary left;
  final EventSummary? right;
  final bool showGroup;

  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: EventTile(event: left, showGroup: showGroup)),
        const SizedBox(width: 12),
        Expanded(
          child: right == null
              ? const SizedBox.shrink()
              : EventTile(event: right!, showGroup: showGroup),
        ),
      ]);
}

/// A 2-column grid of [EventTile]s for a non-lazy list (a group's events).
class EventTileGrid extends StatelessWidget {
  const EventTileGrid({super.key, required this.events, this.showGroup = true});
  final List<EventSummary> events;
  final bool showGroup;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < events.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 12),
          EventTileRow(
            left: events[i],
            right: i + 1 < events.length ? events[i + 1] : null,
            showGroup: showGroup,
          ),
        ],
      ]);
}
