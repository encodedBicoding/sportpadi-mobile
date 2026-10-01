import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';

/// The web events-feed card: cover image with overlaid badges + title, then a
/// detail block (date/time, venue, host group, interest count, action button).
/// Mirrors apps/web `EventCard` on the /events page.
class EventFeedCard extends StatelessWidget {
  const EventFeedCard({super.key, required this.event, this.onTap});

  final EventSummary event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    final live = e.status == 'kicked_off';
    final when = [
      formatDay(e.eventDate),
      formatClock(e.startTime),
    ].where((s) => s != null && s.isNotEmpty).join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: e.isTournament ? p.amber : p.line,
          width: e.isTournament ? 1.4 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(15, 30, 22, 0.06),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cover(context, e, live),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _metaRow(context, e, when),
                    if (e.groupName != null) ...[
                      const SizedBox(height: 6),
                      _iconLine(context, Icons.groups_outlined, e.groupName!,
                          muted: true),
                    ],
                    if (e.description != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        e.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.muted, fontSize: 12.5, height: 1.35),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _footer(context, e),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, EventSummary e, bool live) {
    final p = context.palette;
    return SizedBox(
      height: 156,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (e.coverImage != null)
            CachedNetworkImage(
              imageUrl: e.coverImage!,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: p.surface2),
              errorWidget: (_, __, ___) => _placeholder(context, e),
            )
          else
            _placeholder(context, e),
          // Dark wash so overlaid text reads over any image.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color.fromRGBO(0, 0, 0, 0.72),
                  Color.fromRGBO(0, 0, 0, 0.08),
                  Color.fromRGBO(0, 0, 0, 0.0),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 10,
            right: 10,
            child: Row(
              children: [
                if (e.categoryName != null)
                  _chip(context,
                      '${e.categoryEmoji ?? ''} ${e.categoryName}'.trim(),
                      tone: p.accent),
                if (e.isPrivate) ...[
                  const SizedBox(width: 6),
                  _chip(context, 'Private',
                      icon: Icons.lock_outline, tone: p.amber),
                ],
                const Spacer(),
                if (e.isTournament)
                  _chip(context, 'Tournament',
                      icon: Icons.emoji_events_outlined, tone: p.amber)
                else if (live)
                  _chip(context, 'Live',
                      icon: Icons.bolt_rounded, tone: p.danger),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Text(
              e.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.15,
                shadows: [
                  Shadow(color: Color.fromRGBO(0, 0, 0, 0.5), blurRadius: 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder(BuildContext context, EventSummary e) {
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromRGBO(23, 166, 94, 0.22),
            Color.fromRGBO(245, 167, 10, 0.20),
          ],
        ),
      ),
      child: Text(
        e.isTournament ? '🏆' : (e.categoryEmoji ?? '🎟️'),
        style: const TextStyle(fontSize: 46),
      ),
    );
  }

  Widget _chip(BuildContext context, String label,
      {IconData? icon, required Color tone}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: tone),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
                color: tone, fontSize: 10.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(BuildContext context, EventSummary e, String when) {
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (when.isNotEmpty)
          _iconLine(context, Icons.calendar_today_outlined, when),
        if (e.locationName != null)
          _iconLine(context, Icons.place_outlined, e.locationName!),
        if (e.distanceMiles != null)
          _iconLine(
              context, Icons.near_me_outlined, _distance(e.distanceMiles!)),
      ],
    );
  }

  String _distance(double mi) {
    if (mi < 0.15) return 'here';
    if (mi < 10) return '${mi.toStringAsFixed(1)} mi away';
    return '${mi.round()} mi away';
  }

  Widget _iconLine(BuildContext context, IconData icon, String text,
      {bool muted = false}) {
    final p = context.palette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: muted ? p.muted : p.accent),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 230),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.muted, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _footer(BuildContext context, EventSummary e) {
    final p = context.palette;
    return Row(
      children: [
        Icon(Icons.favorite_border_rounded, size: 15, color: p.danger),
        const SizedBox(width: 5),
        Text(
          '${e.interestCount ?? 0}',
          style: TextStyle(
              color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        Text(' RSVPs', style: TextStyle(color: p.muted, fontSize: 12.5)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.isTournament ? 'Spectate' : 'View',
                style: TextStyle(
                    color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              Icon(Icons.chevron_right_rounded, size: 16, color: p.ink),
            ],
          ),
        ),
      ],
    );
  }
}
