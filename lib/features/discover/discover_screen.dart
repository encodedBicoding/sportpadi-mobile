import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:geolocator/geolocator.dart';

import 'package:sportpadi_mobile/core/location/location_provider.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/event_feed_card.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_app_bar.dart';

/// Currently-selected category filter (null = All). Client-side; the chips are
/// derived from whatever the discover feed returns.
final _discoverFilterProvider = StateProvider.autoDispose<String?>((_) => null);

/// Nearby events for the active location + radius (null location = no query).
final _nearbyProvider =
    FutureProvider.autoDispose<List<EventSummary>?>((ref) async {
  final loc = ref.watch(locationProvider);
  final l = loc.location;
  if (l == null) return null;
  return ref.read(eventsRepositoryProvider).near(
        lat: l.lat,
        lng: l.lng,
        radiusMiles: loc.radiusMiles,
      );
});

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  @override
  void initState() {
    super.initState();
    // Location-based recommendations are the default experience — ask on
    // first open (quietly no-ops if already granted or previously denied).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final st = ref.read(locationProvider);
      if (st.location == null && !st.loading && st.error == null) {
        ref.read(locationProvider.notifier).request();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final events = ref.watch(discoverProvider);
    final filter = ref.watch(_discoverFilterProvider);
    final loc = ref.watch(locationProvider);
    final nearby = ref.watch(_nearbyProvider).valueOrNull;
    final p = context.palette;

    return Scaffold(
      appBar: const SpAppBar(),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(discoverProvider.future),
        child: AsyncView(
          value: events,
          onRetry: () => ref.invalidate(discoverProvider),
          data: (list) {
            // Distinct category names present in the feed, for the filter row.
            final cats = <String, String>{}; // name -> emoji
            for (final e in list) {
              if (e.categoryName != null) {
                cats[e.categoryName!] = e.categoryEmoji ?? '';
              }
            }
            var filtered = filter == null
                ? list
                : list.where((e) => e.categoryName == filter).toList();
            // With a location fixed, the distance-sorted nearby feed replaces
            // the generic list (web NearMe behaviour, incl. category filter).
            final usingNearby = loc.location != null && nearby != null;
            if (usingNearby) {
              filtered = filter == null
                  ? nearby
                  : nearby.where((e) => e.categoryName == filter).toList();
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Text(
                  'Sports events near you',
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Browse upcoming games, show interest, and join teams.',
                  style: TextStyle(color: p.muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                _NearMeCard(state: loc),
                if (cats.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 34,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _FilterChip(
                          label: 'All',
                          selected: filter == null,
                          onTap: () => ref
                              .read(_discoverFilterProvider.notifier)
                              .state = null,
                        ),
                        for (final entry in cats.entries)
                          _FilterChip(
                            label: '${entry.value} ${entry.key}'.trim(),
                            selected: filter == entry.key,
                            onTap: () => ref
                                .read(_discoverFilterProvider.notifier)
                                .state = entry.key,
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 80),
                    child: Center(
                      child: Text(
                        usingNearby
                            ? 'No events within ${loc.radiusMiles} miles yet — widen the radius.'
                            : 'Nothing coming up yet.',
                        style: TextStyle(color: p.muted),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  for (final e in filtered)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: EventFeedCard(
                        event: e,
                        onTap: () => _open(context, e),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _open(BuildContext context, EventSummary e) {
    if (e.isTournament) {
      context.push('/tournaments/${e.id}');
    } else {
      context.push('/events/${e.slug}');
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? p.accent : p.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? p.accent : p.line),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : p.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The web NearMe card: request GPS, show the fixed location + radius slider,
/// clear to fall back to the generic feed.
class _NearMeCard extends ConsumerWidget {
  const _NearMeCard({required this.state});
  final LocationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final active = state.location != null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.place_rounded, size: 16, color: p.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                active
                    ? 'Near ${state.location!.label}'
                    : 'Find events near you',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700),
              ),
            ),
            if (active)
              InkWell(
                onTap: () => ref.read(locationProvider.notifier).clear(),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('Clear',
                      style:
                          TextStyle(color: p.muted, fontSize: 12)),
                ),
              ),
          ]),
          if (!active) ...[
            const SizedBox(height: 10),
            Material(
              color: p.accent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: state.loading
                    ? null
                    : () => ref.read(locationProvider.notifier).request(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  alignment: Alignment.center,
                  child: state.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.navigation_rounded,
                                size: 16, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Use my location',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                ),
              ),
            ),
            if (state.error != null) ...[
              const SizedBox(height: 8),
              Text(state.error!,
                  style: TextStyle(color: p.danger, fontSize: 11.5)),
              if (state.denied)
                InkWell(
                  onTap: Geolocator.openAppSettings,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Open settings to enable location',
                        style: TextStyle(
                            color: p.accent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ] else ...[
            const SizedBox(height: 6),
            Row(children: [
              Text('Radius',
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
              Expanded(
                child: Slider(
                  value: state.radiusMiles.toDouble(),
                  min: 5,
                  max: 100,
                  divisions: 19,
                  onChanged: (v) => ref
                      .read(locationProvider.notifier)
                      .setRadius(v.round()),
                ),
              ),
              Text('${state.radiusMiles} mi',
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ]),
          ],
        ],
      ),
    );
  }
}
