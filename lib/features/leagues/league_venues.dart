import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/leagues/leagues_repository.dart';
import 'package:sportpadi_mobile/features/venues/venues.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// The season's venues (web league console → Venues): add / edit / archive,
/// place fixtures without a venue, and each team's home venue.
class LeagueVenuesSection extends ConsumerWidget {
  const LeagueVenuesSection({super.key, required this.leagueId, required this.onChanged});
  final String leagueId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final q = ref.watch(leagueVenuesProvider(leagueId));
    final repo = ref.read(leaguesRepositoryProvider);
    void refresh() {
      ref.invalidate(leagueVenuesProvider(leagueId));
      onChanged();
    }

    Future<String?> run(String op, Map<String, dynamic> body, String Function(Map<String, dynamic> r) msg) async {
      final r = await repo.mutate(op, body);
      refresh();
      return msg(r is Map ? Map<String, dynamic>.from(r) : const {});
    }

    int n(Map<String, dynamic> r, String k) => r[k] is num ? (r[k] as num).toInt() : 0;

    return AsyncView(
      value: q,
      onRetry: () => ref.invalidate(leagueVenuesProvider(leagueId)),
      data: (j) {
        final data = VenuesData.fromJson(j.raw);
        if (!data.ready) {
          return SpEmpty(icon: Icons.place_rounded, text: context.l10n.league_venuesNeedTheLatestDatabase);
        }
        final teams = j.list('teams');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          VenuesPanel(
            data: data,
            noun: 'fixture',
            intro: context.l10n.league_fixturesArePlayedAtThe,
            actions: VenueActions(
              add: (b) => run('addVenue', {'leagueId': leagueId, ...b}, (r) {
                final placed = n(r, 'placed');
                return placed > 0 ? l10n.league_venueAddedFixturesPlacedThere(placed) : l10n.league_venueAdded;
              }),
              update: (id, b) => run('updateVenue', {'venueId': id, ...b}, (r) {
                final u = n(r, 'updated');
                return u > 0 ? l10n.league_savedFixturesUpdatedEveryoneTold(u) : l10n.league_saved;
              }),
              archive: (id, to) => run('archiveVenue', {'venueId': id, 'moveToVenueId': to}, (r) {
                final m = n(r, 'moved');
                return m > 0 ? l10n.league_movedFixturesAndArchivedTheVenue(m) : l10n.league_venueArchived;
              }),
              restore: (id) => run('restoreVenue', {'venueId': id}, (_) => l10n.league_venueRestored),
              placeUnplaced: (venueId) => run('placeFixtures', {'leagueId': leagueId, 'fixtureIds': data.unplacedIds, 'venueId': venueId}, (r) {
                final c = n(r, 'placed');
                return l10n.league_fixturesPlacedCount(c);
              }),
            ),
          ),
          if (data.active.length > 1 && teams.isNotEmpty) ...[
            const SizedBox(height: 20),
            SpSectionTitle(context.l10n.league_homeVenues),
            const SizedBox(height: 4),
            Text(context.l10n.league_aTeamsHomeFixturesWithout, style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 8),
            for (final t in teams) ...[
              Text(t.str('name', context.l10n.league_team), style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              VenueDropdown(
                venues: data.active,
                value: t.s('homeVenueId'),
                none: context.l10n.league_noHomeVenue,
                onChanged: (v) async {
                  final ok = await runVenueAction(
                      context,
                      () => run('setHomeVenue', {'leagueId': leagueId, 'teamId': t.str('teamId'), 'venueId': v}, (r) {
                            final c = n(r, 'placed');
                            return c > 0 ? l10n.league_homeVenueSetFixturesPlacedThere(c) : l10n.league_homeVenueSet;
                          }));
                  if (!ok || v == null || !context.mounted) return;
                  final move = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text(l10n.league_moveTheirHomeFixturesToo2),
                      content: Text(l10n.league_sUnpublishedHomeFixturesMove(t.str('name'))),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l10n.league_notNow)),
                        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(l10n.league_moveThem)),
                      ],
                    ),
                  );
                  if (move != true || !context.mounted) return;
                  await runVenueAction(
                      context,
                      () => run('setHomeVenue', {'leagueId': leagueId, 'teamId': t.str('teamId'), 'venueId': v, 'moveHomeFixtures': true}, (r) {
                            final c = n(r, 'placed');
                            return l10n.league_fixturesMovedCount(c);
                          }));
                },
              ),
              const SizedBox(height: 12),
            ],
          ],
        ]);
      },
    );
  }
}

/// The orange bar on the Fixtures tab when fixtures still need a venue.
class LeagueVenueNudge extends ConsumerWidget {
  const LeagueVenueNudge({super.key, required this.leagueId, required this.onOpen});
  final String leagueId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final j = ref.watch(leagueVenuesProvider(leagueId)).valueOrNull;
    if (j == null) return const SizedBox.shrink();
    final data = VenuesData.fromJson(j.raw);
    if (!data.ready) return const SizedBox.shrink();
    final none = data.active.isEmpty;
    final n = data.unplacedIds.length;
    if (!none && n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: p.orangeTint,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Expanded(
                child: Text(
                    none
                        ? context.l10n.league_noVenuesYetAddThe
                        : context.l10n.league_withoutAVenuePlaceThem2(n, pluralNoun('fixture', n)),
                    style: TextStyle(color: p.orangeInk, fontSize: 12.5)),
              ),
              Text(context.l10n.league_venues, style: TextStyle(color: p.orangeInk, fontWeight: FontWeight.w800, fontSize: 12.5)),
            ]),
          ),
        ),
      ),
    );
  }
}
