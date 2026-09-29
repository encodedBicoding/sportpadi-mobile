import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// "Past events" on Home (2026 design): one card of compact rows — date
/// tile, title, group — each leading to the player's own record for that
/// event rather than the event's scoresheet. Shows the four most recent and
/// expands in place.
class PastEventsSection extends StatefulWidget {
  const PastEventsSection({super.key, required this.events, this.userId});

  /// Already filtered to the last two months (and the sport chip).
  final List<EventSummary> events;

  /// The signed-in player; rows open `/players/<id>/events/<event>`.
  final String? userId;

  @override
  State<PastEventsSection> createState() => _PastEventsSectionState();
}

class _PastEventsSectionState extends State<PastEventsSection> {
  static const _collapsed = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final all = widget.events;
    final shown =
        _expanded || all.length <= _collapsed ? all : all.sublist(0, _collapsed);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Past events',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2)),
                const SizedBox(height: 2),
                Text('Last two months · tap for your stats',
                    style: TextStyle(color: p.muted, fontSize: 12)),
              ]),
        ),
        if (all.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('${all.length}',
                style: TextStyle(
                    color: p.ink, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
      ]),
      const SizedBox(height: 12),
      if (all.isEmpty)
        GlassCard(
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: p.surface2, borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.history_rounded, color: p.muted, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('No past events in the last two months.',
                  style: TextStyle(color: p.muted, fontSize: 13)),
            ),
          ]),
        )
      else
        GlassCard(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 1,
                    thickness: 1,
                    indent: 10,
                    endIndent: 10,
                    color: p.surface2),
              _PastRow(event: shown[i], userId: widget.userId),
            ],
            if (all.length > _collapsed) ...[
              Divider(
                  height: 1,
                  thickness: 1,
                  indent: 10,
                  endIndent: 10,
                  color: p.surface2),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                            _expanded
                                ? 'Show less'
                                : 'Show all ${all.length}',
                            style: TextStyle(
                                color: p.greenText,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 4),
                        Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: p.greenText),
                      ]),
                ),
              ),
            ],
          ]),
        ),
    ]);
  }
}

class _PastRow extends StatelessWidget {
  const _PastRow({required this.event, this.userId});
  final EventSummary event;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    final d = e.eventDate?.toUtc();
    const mo = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];
    final t = e.isTournament;

    void open() {
      // Your record there, not the event's scoresheet; the event is one
      // deliberate tap further in.
      if (userId != null) {
        context.push(t
            ? '/players/$userId/tournaments/${e.id}'
            : '/players/$userId/events/${e.id}');
      } else {
        context.push(t
            ? '/tournaments/${e.id}'
            : '/events/${e.slug.isNotEmpty ? e.slug : e.id}');
      }
    }

    final sub = [
      if (e.groupName != null) e.groupName!,
      if (t) 'Tournament' else if (e.categoryName != null) e.categoryName!,
    ].join(' · ');

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: open,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(children: [
          Container(
            width: 46,
            height: 50,
            decoration: BoxDecoration(
              color: t ? p.orangeTint : p.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(d != null ? mo[d.month - 1] : '—',
                  style: TextStyle(
                      color: t ? p.orangeInk : p.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
              Text(d != null ? '${d.day}' : '—',
                  style: TextStyle(
                      color: t ? p.orangeInk : p.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      height: 1.05)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.categoryEmoji != null ? '${e.categoryEmoji} ' : ''}${e.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700),
                  ),
                  if (sub.isNotEmpty)
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                ]),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: p.accentTint,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('Your stats',
                style: TextStyle(
                    color: p.greenText,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}
