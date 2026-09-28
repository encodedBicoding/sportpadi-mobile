import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/location/location_provider.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart'
    show homeTabIndexProvider;
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// "Events for you" — the discovery shelf on Home.
///
/// The calendar above answers "what's on in my groups". This answers "what
/// else is out there", so everything here comes from a group the player isn't
/// in yet. Each card states WHY it was picked: a suggestion that explains
/// itself can be trusted or dismissed at a glance, while an unexplained one
/// just reads as an advert.
class SuggestedEventsSection extends ConsumerWidget {
  const SuggestedEventsSection({super.key, this.categoryId, this.guest = false});

  /// The Home sport chip, so the shelf follows the filter.
  final String? categoryId;

  /// Signed-out Home. There the shelf is the main event rather than a
  /// footnote under a calendar, so it shows its loading and empty states
  /// instead of quietly disappearing.
  final bool guest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    // Use a location fix if the session already has one (Discover, or the
    // guest Home, asks for it), but never prompt from here — a permission
    // dialog from a shelf is a nasty surprise, and the ranking works without.
    final loc = ref.watch(locationProvider).location;
    final async = ref.watch(suggestedEventsProvider((
      lat: loc?.lat,
      lng: loc?.lng,
      categoryId: categoryId,
    )));
    final rows = async.valueOrNull;

    // Nothing to suggest is a real answer. A "we found nothing" card on a
    // member's Home is just clutter, so stay silent — unless this is the
    // guest Home, where an empty shelf with no explanation looks broken.
    if (!guest && (rows == null || rows.isEmpty)) return const SizedBox.shrink();

    final Widget shelf;
    if (rows == null) {
      shelf = SizedBox(
        height: 120,
        child: Center(
          child: async.hasError
              ? Text('Couldn\'t load suggestions right now.',
                  style: TextStyle(color: p.muted, fontSize: 12.5))
              : const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    } else if (rows.isEmpty) {
      shelf = GlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          const Text('🔭', style: TextStyle(fontSize: 26)),
          const SizedBox(height: 8),
          Text(
            loc == null ? 'Nothing to show yet' : 'Nothing near you just yet',
            style: TextStyle(
                color: p.ink, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            loc == null
                ? 'Share your location above, or browse everything that\'s on.'
                : 'No public games within reach in the next two months. '
                    'Browse further afield, or check back soon.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          SpButton(
            label: 'Browse all events',
            icon: Icons.explore_outlined,
            onTap: () => ref.read(homeTabIndexProvider.notifier).state = 1,
          ),
        ]),
      );
    } else {
      shelf = SizedBox(
        height: 236,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: rows.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => i == rows.length
              ? _BrowseAllCard(
                  onTap: () =>
                      ref.read(homeTabIndexProvider.notifier).state = 1)
              : _SuggestionCard(event: rows[i]),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('✨', style: TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('EVENTS FOR YOU',
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
                Text(
                    guest
                        ? (loc == null
                            ? 'What\'s on around SportPadi.'
                            : 'Happening near you.')
                        : 'Happening near you, outside your groups.',
                    style: TextStyle(color: p.muted, fontSize: 11.5)),
              ]),
        ),
        InkWell(
          // Browse is a bottom tab, not a pushed route — switch to it rather
          // than stacking a second copy of it on top of Home.
          onTap: () => ref.read(homeTabIndexProvider.notifier).state = 1,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('Browse all',
                style: TextStyle(
                    color: p.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      // A horizontal shelf: a row you swipe reads as optional in a way a
      // full-width list doesn't, which is right for suggestions.
      shelf,
    ]);
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.event});
  final EventSummary event;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    final d = e.eventDate?.toUtc();
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return SizedBox(
      width: 220,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => e.isTournament
              ? context.push('/tournaments/${e.id}')
              : context.push('/events/${e.slug.isNotEmpty ? e.slug : e.id}'),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.line),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14)),
                    child: SizedBox(
                      height: 88,
                      width: double.infinity,
                      child: e.coverImage != null
                          ? Stack(fit: StackFit.expand, children: [
                              CachedNetworkImage(
                                imageUrl: e.coverImage!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    _placeholder(p, e),
                              ),
                              if (e.isTournament)
                                Positioned(
                                  left: 6,
                                  top: 6,
                                  child: SpBadge('Tournament', tone: p.accent),
                                ),
                            ])
                          : _placeholder(p, e),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                if (d != null)
                                  '${wd[d.weekday - 1]} ${d.day}/${d.month}',
                                if (formatClock(e.startTime) != null)
                                  formatClock(e.startTime)!,
                              ].join(' · '),
                              style: TextStyle(
                                  color: p.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${e.categoryEmoji != null ? '${e.categoryEmoji} ' : ''}${e.title}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 13,
                                  height: 1.25,
                                  fontWeight: FontWeight.w800),
                            ),
                            if (e.groupName != null) ...[
                              const SizedBox(height: 2),
                              Text(e.groupName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: p.muted, fontSize: 11)),
                            ],
                            if (e.locationName != null) ...[
                              const SizedBox(height: 1),
                              Row(children: [
                                Icon(Icons.place_outlined,
                                    size: 11, color: p.muted),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Text(e.locationName!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: p.muted, fontSize: 11)),
                                ),
                              ]),
                            ],
                            const Spacer(),
                            // The why. Without it this shelf is
                            // indistinguishable from promoted content.
                            if (e.reasons.isNotEmpty)
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  for (final r in e.reasons)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: p.accent.withAlpha(26),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(r,
                                          style: TextStyle(
                                              color: p.accent,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800)),
                                    ),
                                ],
                              ),
                          ]),
                    ),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(AppPalette p, EventSummary e) => Container(
        color: p.accent.withAlpha(26),
        alignment: Alignment.center,
        child: Text(e.categoryEmoji ?? '🏟️',
            style: const TextStyle(fontSize: 30)),
      );
}

class _BrowseAllCard extends StatelessWidget {
  const _BrowseAllCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: 130,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.line),
            ),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.explore_outlined, size: 26, color: p.accent),
                  const SizedBox(height: 8),
                  Text('Browse\neverything',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w700)),
                ]),
          ),
        ),
      ),
    );
  }
}
