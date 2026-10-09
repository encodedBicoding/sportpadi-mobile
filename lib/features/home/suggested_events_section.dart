import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/location/location_provider.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart'
    show homeTabIndexProvider;
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// "Suggested for you" — the discovery shelf on Home (2026 design).
///
/// The calendar above answers "what's on in my groups". This answers "what
/// else is out there", so everything here comes from a group the player isn't
/// in yet. Each card states WHY it was picked: a suggestion that explains
/// itself can be trusted or dismissed at a glance, while an unexplained one
/// just reads as an advert.
class SuggestedEventsSection extends ConsumerWidget {
  const SuggestedEventsSection(
      {super.key, this.categoryId, this.guest = false});

  /// The Home sport chip, so the shelf follows the filter.
  final String? categoryId;

  /// Signed-out Home. There the shelf is the main event rather than a
  /// footnote under a calendar, so it shows its loading and empty states
  /// instead of quietly disappearing.
  final bool guest;

  static const double _cardW = 228;
  static const double _shelfH = 196;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    // Use a location fix if the session already has one (Discover, or the
    // guest Home, asks for it), but never prompt from here — a permission
    // dialog from a shelf is a nasty surprise, and the ranking works without.
    final locState = ref.watch(locationProvider);
    final loc = locState.location;
    // Without a fix the shelf asks for one instead of showing games from
    // somewhere else: a visitor who hasn't said where they are gets no
    // "near you" list at all. With one, ONLY events within the radius,
    // nearest first (radiusMiles → the server filters + sorts).
    final gated = loc == null;
    final async = loc == null
        ? const AsyncValue<List<EventSummary>>.data(<EventSummary>[])
        : ref.watch(suggestedEventsProvider((
            lat: loc.lat,
            lng: loc.lng,
            radiusMiles: locState.radiusMiles,
            categoryId: categoryId,
          )));
    final rows = async.valueOrNull;

    // The section is ALWAYS on Home, whoever the person is and whatever
    // they came for: no fix → ask for one; nothing nearby → say so and
    // point at Browse. (It used to vanish in both cases, which read as
    // "the shelf is missing" rather than "nothing to show".)
    void browse() => ref.read(homeTabIndexProvider.notifier).state = 1;
    void signUp() => context.push('/sign-in');

    final Widget shelf;
    if (gated) {
      // Ask for the fix. A permanent refusal can only be undone in the OS
      // settings, so the button goes there instead of to a prompt that
      // won't appear.
      final denied = locState.denied;
      shelf = GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: p.accentTint, borderRadius: BorderRadius.circular(18)),
            child: Icon(
                denied
                    ? Icons.location_off_rounded
                    : Icons.location_searching_rounded,
                color: p.greenText,
                size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            'Games near you show up here',
            style: TextStyle(
                color: p.ink, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            denied
                ? 'Location is off for SportPadi. Turn it on in Settings and '
                    "we'll list the upcoming games closest to you first."
                : locState.error ??
                    "Allow SportPadi to read your location and we'll list the "
                        'upcoming games closest to you first.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 14),
          SpButton(
            label: locState.loading
                ? 'Finding you…'
                : denied
                    ? 'Open Settings'
                    : 'Allow location',
            icon: denied ? Icons.settings_outlined : Icons.my_location_rounded,
            tone: SpButtonTone.brand,
            onTap: locState.loading
                ? null
                : denied
                    ? () => Geolocator.openAppSettings()
                    : () => ref.read(locationProvider.notifier).request(),
          ),
        ]),
      );
    } else if (rows == null) {
      shelf = async.hasError
          ? GlassCard(
              child: Center(
                child: Text('Couldn\'t load suggestions right now.',
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
              ),
            )
          : SizedBox(
              height: _shelfH,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: 2,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, __) => Container(
                  width: _cardW,
                  decoration: BoxDecoration(
                    color: p.surface2,
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
              ),
            );
    } else if (rows.isEmpty) {
      shelf = GlassCard(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: p.accentTint, borderRadius: BorderRadius.circular(18)),
            child: Icon(Icons.travel_explore_rounded,
                color: p.greenText, size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            'No upcoming games within ${locState.radiusMiles} miles yet',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            guest
                ? 'Be the first — sign up (or sign in) and create an event; '
                    'players nearby will see it here. Or browse further afield.'
                : 'Nothing public from groups you\'re not in yet. Widen the '
                    'radius on Browse, or create an event and players nearby '
                    'will see it here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (guest)
                SpButton(
                  label: 'Sign up to create one',
                  icon: Icons.add_circle_outline_rounded,
                  tone: SpButtonTone.brand,
                  onTap: signUp,
                ),
              SpButton(
                label: guest ? 'Browse' : 'Browse all events',
                icon: Icons.explore_outlined,
                tone: guest ? SpButtonTone.ink : SpButtonTone.brand,
                onTap: browse,
              ),
            ],
          ),
        ]),
      );
    } else {
      // A horizontal shelf: a row you swipe reads as optional in a way a
      // full-width list doesn't, which is right for suggestions.
      shelf = SizedBox(
        height: _shelfH,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          // Let the cards' soft shadows breathe past the list bounds.
          clipBehavior: Clip.none,
          padding: EdgeInsets.zero,
          itemCount: rows.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => i == rows.length
              ? _BrowseAllCard(onTap: browse)
              : _SuggestionCard(event: rows[i], width: _cardW),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Suggested for you',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2)),
                const SizedBox(height: 2),
                Text(
                    loc == null
                        ? 'Upcoming games closest to you.'
                        : guest
                            ? 'Within ${locState.radiusMiles} miles, nearest first.'
                            : 'Within ${locState.radiusMiles} miles, outside your groups.',
                    style: TextStyle(color: p.muted, fontSize: 12)),
              ]),
        ),
        // Browse is a bottom tab, not a pushed route — switch to it rather
        // than stacking a second copy of it on top of Home.
        InkWell(
          onTap: browse,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text('See all',
                style: TextStyle(
                    color: p.greenText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      shelf,
    ]);
  }
}

/// One suggestion: sport pill, title, when + how far, then the reason it
/// was picked (or how many are going).
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.event, required this.width});
  final EventSummary event;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final e = event;
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
      if (e.distanceMiles != null) '${e.distanceMiles} mi',
    ].join(' · ');

    // Tournaments wear the orange; everything else the brand green.
    final pillBg = e.isTournament ? p.orangeTint : p.accentTint;
    final pillFg = e.isTournament ? p.orangeInk : p.greenText;
    final pillLabel =
        e.isTournament ? 'Tournament' : (e.categoryName ?? 'Event');

    final going = e.interestCount ?? 0;

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => e.isTournament
              ? context.push('/tournaments/${e.id}')
              : context.push('/events/${e.slug.isNotEmpty ? e.slug : e.id}'),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(22),
              border: dark ? Border.all(color: p.line) : null,
              boxShadow: cardShadow(context),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: pillBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${e.categoryEmoji != null && !e.isTournament ? '${e.categoryEmoji} ' : ''}$pillLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: pillFg,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const Spacer(),
                Icon(Icons.north_east_rounded, size: 16, color: p.muted),
              ]),
              const SizedBox(height: 10),
              Text(
                e.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink,
                    fontSize: 15,
                    height: 1.3,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              if (when.isNotEmpty)
                Text(when,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12)),
              if (e.groupName != null || e.locationName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    e.groupName ?? e.locationName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12),
                  ),
                ),
              const Spacer(),
              // The why. Without it this shelf is indistinguishable
              // from promoted content.
              if (e.reasons.isNotEmpty)
                Text(
                  e.reasons.first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: e.isTournament ? p.orangeInk : p.greenText,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                )
              else if (going > 0)
                Text('$going going',
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The shelf's tail: a dark card that hands over to Browse.
class _BrowseAllCard extends StatelessWidget {
  const _BrowseAllCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      width: 150,
      child: Material(
        color: p.hero,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.onHero.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 20, color: p.onHero),
              ),
              const Spacer(),
              Text('Browse\neverything',
                  style: TextStyle(
                      color: p.onHero,
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Public games on SportPadi',
                  style: TextStyle(color: p.heroMuted, fontSize: 11.5)),
            ]),
          ),
        ),
      ),
    );
  }
}
