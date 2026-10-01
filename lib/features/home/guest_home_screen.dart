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
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

const _mint = Color(0xFF6EDC9E);
const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Home for someone who hasn't signed in.
///
/// Laid out like the member dashboard (2026) so the app doesn't change shape
/// the moment they make an account: the same greeting header, the same two
/// quick-action tiles (Browse + Join instead of Create group + Scan), and
/// where a member's calendar sits, a calendar card showing this week with the
/// agenda saying what signing in puts there. The one thing a visitor CAN give
/// us — where they are — drives the "Suggested for you" shelf. Location is
/// asked for on the first visit because, with no account, it's the only
/// signal that makes the shelf personal; a refusal is respected and the shelf
/// still renders from whatever's popular. The ask comes once, at the bottom,
/// as a dark card.
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

  void _browse() => ref.read(homeTabIndexProvider.notifier).state = 1;
  void _signIn() => context.push('/sign-in');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final loc = ref.watch(locationProvider);

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            // Re-read the fix (it may have been granted in Settings since)
            // and let the shelf refetch off the new key.
            if (loc.location == null) {
              await ref.read(locationProvider.notifier).request();
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _GuestHeader(onSignIn: _signIn),

              const SizedBox(height: 12),
              const AdDisplay(slots: ['mobile_home'], carousel: true),

              // Quick actions — the member row has Create group + Scan QR;
              // neither means anything without an account.
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: _quickAction(
                      p, Icons.explore_outlined, 'Browse events', _browse),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _quickAction(p, Icons.person_add_alt_1_rounded,
                      'Join SportPadi', _signIn,
                      dark: true),
                ),
              ]),

              // Where the member calendar sits.
              const SizedBox(height: 14),
              _CalendarStandIn(onBrowse: _browse, onSignIn: _signIn),

              // AdMob native (Android). Takes no space until it fills.
              const AdMobNativeCard(padding: EdgeInsets.only(top: 12)),

              // Location — the one signal a visitor can give us.
              const SizedBox(height: 14),
              _LocationCard(state: loc),

              const SizedBox(height: 22),
              const SuggestedEventsSection(guest: true),

              const SizedBox(height: 10),
              const AdDisplay(slots: ['home_ads'], carousel: true),

              // The ask, once, at the bottom — after they've seen what's here.
              const SizedBox(height: 18),
              _JoinCard(onSignIn: _signIn),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickAction(
          AppPalette p, IconData icon, String label, VoidCallback onTap,
          {bool dark = false}) =>
      Material(
        color: dark ? p.hero : p.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: dark ? null : cardShadow(context),
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: dark ? p.onHero.withAlpha(26) : p.accentTint,
                  borderRadius: BorderRadius.circular(13),
                ),
                child:
                    Icon(icon, size: 20, color: dark ? p.accent : p.accentDeep),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: dark ? p.onHero : p.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      );
}

/// The member header's twin: greeting + "Welcome", and where the member's
/// bell and avatar sit, a Sign in pill.
class _GuestHeader extends StatelessWidget {
  const _GuestHeader({required this.onSignIn});
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final h = DateTime.now().hour;
    final greeting = h < 12
        ? 'Good morning'
        : h < 17
            ? 'Good afternoon'
            : 'Good evening';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(greeting,
                style: TextStyle(
                    color: p.muted, fontSize: 13, fontWeight: FontWeight.w500)),
            Text('Welcome 👋',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.15)),
          ]),
        ),
        Material(
          color: p.ink,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onSignIn,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Sign in',
                    style: TextStyle(
                        color: p.bg,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward_rounded, size: 17, color: p.bg),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The member calendar, reduced to its one honest state for a visitor: this
/// week's strip (real dates, today marked) and an agenda that says what
/// signing in puts there.
class _CalendarStandIn extends StatelessWidget {
  const _CalendarStandIn({required this.onBrowse, required this.onSignIn});
  final VoidCallback onBrowse;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text('Your calendar',
                style: TextStyle(
                    color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: p.orangeTint,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_outline_rounded, size: 12, color: p.orangeInk),
              const SizedBox(width: 4),
              Text('After sign-in',
                  style: TextStyle(
                      color: p.orangeInk,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: _DayCell(day: today.add(Duration(days: i)), today: i == 0),
            ),
          ],
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(children: [
            SpIconTile(Icons.event_available_rounded,
                bg: p.accentTint, fg: p.greenText, size: 48, iconSize: 22),
            const SizedBox(height: 10),
            Text('Your games will land here',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              "Once you're signed in, every game from the groups you belong "
              "to and follow shows up on this calendar. Until then, see "
              "what's on.",
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: SpButton(
                  label: 'Browse events',
                  icon: Icons.explore_outlined,
                  expand: true,
                  onTap: onBrowse,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Material(
                  color: p.surface,
                  shape: StadiumBorder(side: BorderSide(color: p.line)),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: onSignIn,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text('Sign in',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.today});
  final DateTime day;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: today ? p.ink : p.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Text(_dayNames[day.weekday - 1],
            style: TextStyle(
                color: today ? p.bg.withAlpha(190) : p.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text('${day.day}',
            style: TextStyle(
                color: today ? p.bg : p.ink,
                fontSize: 16,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

/// The ask: dark card, what an account gets you, one white pill.
class _JoinCard extends StatelessWidget {
  const _JoinCard({required this.onSignIn});
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget perk(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: p.onHero.withAlpha(26),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 17, color: _mint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: p.onHero,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: p.hero,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('JOIN FREE',
            style: TextStyle(
                color: _mint,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4)),
        const SizedBox(height: 6),
        Text('Ready to play?',
            style: TextStyle(
                color: p.onHero,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3)),
        const SizedBox(height: 4),
        Text(
          'One account for every sport you play.',
          style: TextStyle(color: p.heroMuted, fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        perk(Icons.sports_soccer_rounded, 'Join games and check in with a QR'),
        perk(Icons.groups_rounded, 'Follow groups and see their calendar'),
        perk(
            Icons.confirmation_num_outlined, 'Buy tickets for you and friends'),
        perk(
            Icons.emoji_events_outlined, 'Keep your record, level and streaks'),
        const SizedBox(height: 6),
        Material(
          color: Colors.white,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onSignIn,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text('Sign in or create an account',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Color(0xFF0E1411),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800)),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded,
                      size: 18, color: Color(0xFF0E1411)),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Where we think they are, and what to do when we don't know.
///
/// Four states, each with its own honest line: still finding; found (with no
/// coordinates shown — nobody wants to read a lat/lng); refused, with the
/// route to Settings when the OS won't ask again; and a plain error with a
/// retry. It never nags: a visitor who said no sees one quiet line and a
/// pill they can ignore.
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
    String? actionLabel;
    VoidCallback? action;

    if (s.loading) {
      icon = Icons.my_location_rounded;
      title = 'Finding events near you…';
      body = 'Reading your location so the picks below are ones you can '
          'actually get to.';
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
      actionLabel = 'Open Settings';
      action = () => Geolocator.openAppSettings();
    } else {
      icon = Icons.location_searching_rounded;
      title = "See what's on near you";
      body = s.error ??
          'Share your location once and the picks below become local.';
      actionLabel = 'Use my location';
      action = () => ref.read(locationProvider.notifier).request();
    }
    final found = s.location != null;

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SpIconTile(icon,
            bg: found ? p.accentTint : p.surface2,
            fg: found ? p.greenText : p.muted,
            size: 44,
            iconSize: 21),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(body,
                style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: 10),
              Material(
                color: p.surface2,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: action,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Text(actionLabel,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
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
