import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/ads/admob.dart';
import 'package:sportpadi_mobile/core/location/location_provider.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/ads/ad_display.dart';
import 'package:sportpadi_mobile/features/home/suggested_events_section.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart'
    show homeTabIndexProvider;
import 'package:sportpadi_mobile/shared/widgets/app_logo.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Home for someone who hasn't signed in.
///
/// Laid out like the member dashboard so the app doesn't change shape the
/// moment they make an account — but where a member's calendar sits there is
/// a "Browse events" panel, the quick actions that need an account (scan,
/// new group) are gone, and the one thing a visitor CAN give us — where they
/// are — drives the "Events for you" shelf. Location is asked for on the
/// first visit because, with no account, it's the only signal that makes the
/// shelf personal; a refusal is respected and the shelf still renders from
/// whatever's popular.
class GuestHomeScreen extends ConsumerStatefulWidget {
  const GuestHomeScreen({super.key});
  @override
  ConsumerState<GuestHomeScreen> createState() => _GuestHomeScreenState();
}

class _GuestHomeScreenState extends ConsumerState<GuestHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askLocationOnce());
  }

  /// One ask per session. The controller keeps its state for the whole
  /// session, so a fix, a refusal or an error from earlier all mean "don't
  /// ask again" — the card below offers a manual retry instead.
  void _askLocationOnce() {
    if (!mounted) return;
    final st = ref.read(locationProvider);
    if (st.location != null || st.loading || st.error != null) return;
    // ignore: discarded_futures
    ref.read(locationProvider.notifier).request();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final loc = ref.watch(locationProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const AppLogo(height: 34),
        actions: [
          TextButton(
            onPressed: () => context.push('/sign-in'),
            child: Text('Sign in',
                style: TextStyle(
                    color: p.accent,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Re-read the fix (it may have been granted in Settings since) and
          // let the shelf refetch off the new key.
          if (loc.location == null) {
            await ref.read(locationProvider.notifier).request();
          }
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text('Welcome to SportPadi 👋',
                style: TextStyle(
                    color: p.ink, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              'Pick-up games, groups and tournaments near you. '
              'Have a look around — sign in when you want to join in.',
              style: TextStyle(color: p.muted, fontSize: 13),
            ),

            const SizedBox(height: 12),
            const AdDisplay(slots: ['mobile_home'], carousel: true),

            // Quick actions — the member row has New group + Scan QR; neither
            // means anything without an account, so it's Browse + Sign in.
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: _quickAction(p, Icons.explore_outlined, 'Browse events',
                    () => ref.read(homeTabIndexProvider.notifier).state = 1),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _quickAction(p, Icons.login_rounded, 'Sign in',
                    () => context.push('/sign-in')),
              ),
            ]),

            // Where the member calendar sits.
            const SizedBox(height: 12),
            _calendarStandIn(context, p),

            // AdMob native (Android). Takes no space until it fills.
            const AdMobNativeCard(padding: EdgeInsets.only(top: 12)),

            // Location — the one signal a visitor can give us.
            const SizedBox(height: 12),
            _LocationCard(state: loc),

            const SizedBox(height: 18),
            const SuggestedEventsSection(guest: true),

            const SizedBox(height: 10),
            const AdDisplay(slots: ['home_ads'], carousel: true),

            // The ask, once, at the bottom — after they've seen what's here.
            const SizedBox(height: 18),
            GlassCard(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ready to play?',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'An account lets you join games, follow groups, buy tickets '
                  'and keep your record across every sport you play.',
                  style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                SpButton(
                  label: 'Sign in or create an account',
                  icon: Icons.login_rounded,
                  expand: true,
                  onTap: () => context.push('/sign-in'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  /// The folder-tab calendar, reduced to its single honest state for a
  /// visitor: one tab, and the panel says where to go instead.
  Widget _calendarStandIn(BuildContext context, AppPalette p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                top: BorderSide(color: p.line),
                left: BorderSide(color: p.line),
                right: BorderSide(color: p.line),
              ),
            ),
            child: Text('Browse events',
                style: TextStyle(
                    color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border.all(color: p.line),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Column(children: [
          const Text('🗓️', style: TextStyle(fontSize: 28)),
          const SizedBox(height: 8),
          Text('Your calendar will live here',
              style: TextStyle(
                  color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            "Once you're signed in, every game from the groups you belong to "
            'and follow shows up on this page. Until then, see what\'s on.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          SpButton(
            label: 'Browse events',
            icon: Icons.explore_outlined,
            onTap: () => ref.read(homeTabIndexProvider.notifier).state = 1,
          ),
        ]),
      ),
    ]);
  }

  Widget _quickAction(
          AppPalette p, IconData icon, String label, VoidCallback onTap) =>
      Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: p.line),
            ),
            child: Column(children: [
              Icon(icon, size: 20, color: p.accent),
              const SizedBox(height: 5),
              Text(label,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

/// Where we think they are, and what to do when we don't know.
///
/// Four states, each with its own honest line: still finding; found (with no
/// coordinates shown — nobody wants to read a lat/lng); refused, with the
/// route to Settings when the OS won't ask again; and a plain error with a
/// retry. It never nags: a visitor who said no sees one quiet line and a
/// button they can ignore.
class _LocationCard extends ConsumerWidget {
  const _LocationCard({required this.state});
  final LocationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final s = state;

    final IconData icon;
    final String title;
    final String body;
    Widget? action;

    if (s.loading) {
      icon = Icons.my_location_rounded;
      title = 'Finding events near you…';
      body = 'Reading your location so the picks below are ones you can actually get to.';
    } else if (s.location != null) {
      icon = Icons.location_on_rounded;
      title = 'Showing events near you';
      body = 'Within about ${s.radiusMiles} miles of where you are. '
          'Browse to change the distance or search another area.';
    } else if (s.denied) {
      icon = Icons.location_off_rounded;
      title = 'Location is off';
      body = 'Turn it on in Settings to see games near you. '
          'Everything still works without it.';
      action = TextButton(
        onPressed: () => Geolocator.openAppSettings(),
        child: const Text('Open Settings'),
      );
    } else {
      icon = Icons.location_searching_rounded;
      title = 'See what\'s on near you';
      body = s.error ??
          'Share your location once and the picks below become local.';
      action = TextButton(
        onPressed: () => ref.read(locationProvider.notifier).request(),
        child: const Text('Use my location'),
      );
    }

    return GlassCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: s.location != null ? p.accent : p.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(body,
                style: TextStyle(color: p.muted, fontSize: 12, height: 1.35)),
            if (action != null)
              Align(alignment: Alignment.centerLeft, child: action),
          ]),
        ),
        if (s.loading)
          const Padding(
            padding: EdgeInsets.only(left: 8, top: 2),
            child: SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      ]),
    );
  }
}
