import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/location/location_provider.dart'
    show locationProvider;
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/ads/ads_repository.dart'
    show servedSlotsProvider;
import 'package:sportpadi_mobile/data/announcements/announcements_repository.dart'
    show announcementsUnreadProvider;
import 'package:sportpadi_mobile/data/attention/attention_repository.dart'
    show attentionProvider;
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/data/messages/messages_repository.dart'
    show messagesUnreadProvider;
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/data/wards/wards_repository.dart'
    show myWardsProvider, wardTeamInvitesProvider;
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/event_audience.dart';
import 'package:sportpadi_mobile/features/home/suggested_events_section.dart';
import 'package:sportpadi_mobile/features/home/past_events_section.dart';
import 'package:sportpadi_mobile/features/inbox/inbox_button.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_app_bar.dart'
    show SideMenuAttentionCount, showSideMenu;
import 'package:sportpadi_mobile/data/notifications/notifications_repository.dart'
    show unreadCountProvider;
import 'package:sportpadi_mobile/data/progression/progression_repository.dart'
    show yourWeekProvider;
import 'package:sportpadi_mobile/features/shell/home_shell.dart'
    show homeTabIndexProvider;
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/ads/admob.dart';
import 'package:sportpadi_mobile/features/ads/ad_display.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/features/home/weather_card.dart';
import 'package:sportpadi_mobile/data/weather/weather_repository.dart';

/// Home — the user's personal dashboard: their upcoming events across every
/// group they belong to (live events beep on the tab), a Kids tab (future),
/// a sport filter, their past events, and quick actions (new group, scan…).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _range = 'today'; // live | today | upcoming | all
  String? _sport; // category name filter, null = All
  // A day picked on the calendar's week strip ("yyyy-mm-dd"); overrides
  // [_range] until a range chip is tapped again.
  String? _day;
  // The agenda shows a handful of rows, then expands in place.
  bool _agendaOpen = false;

  static bool _live(EventSummary e) => e.isLive || e.status == 'kicked_off';

  /// "Today" follows the user's own clock/timezone (local date); event dates
  /// are UTC wall-clock faces — compare the face to the local day.
  static String _todayKey() {
    final t = DateTime.now();
    return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  static String? _eventKey(EventSummary e) {
    final d = e.eventDate?.toUtc();
    if (d == null) return null;
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static bool _isToday(EventSummary e) => _eventKey(e) == _todayKey();

  /// Upcoming is strictly futuristic — after today.
  static bool _isUpcoming(EventSummary e) {
    if (_live(e)) return false;
    final k = _eventKey(e);
    if (k == null) return true;
    return k.compareTo(_todayKey()) > 0;
  }

  /// "Ward · Tobi, Zara" — which of my wards an event is on my feed for.
  static String? _wardChip(EventSummary e) => e.forWards.isEmpty
      ? null
      : 'Ward · ${e.forWards.map((w) => w.name).join(', ')}';

  /// Pull to refresh: everything on Home — the feed, the header (me, your
  /// week, the bell, the inbox, the menu dot), the suggestions shelf (for
  /// the sport chip in [categoryId]) and the sponsored strips.
  Future<void> _refresh(String? categoryId) {
    final locState = ref.read(locationProvider);
    final loc = locState.location;
    final shelf = suggestedEventsProvider((
      lat: loc?.lat,
      lng: loc?.lng,
      radiusMiles: loc == null ? null : locState.radiusMiles,
      categoryId: categoryId,
    ));
    ref.invalidate(myFeedProvider);
    ref.invalidate(meProvider);
    ref.invalidate(yourWeekProvider);
    ref.invalidate(weatherProvider);
    ref.invalidate(unreadCountProvider);
    ref.invalidate(announcementsUnreadProvider);
    ref.invalidate(messagesUnreadProvider);
    ref.invalidate(attentionProvider);
    ref.invalidate(myWardsProvider);
    ref.invalidate(wardTeamInvitesProvider);
    ref.invalidate(shelf);
    ref.invalidate(servedSlotsProvider('home_top,mobile_home'));
    ref.invalidate(servedSlotsProvider('home_ads'));
    return settleAll([
      ref.read(myFeedProvider.future),
      ref.read(meProvider.future),
      ref.read(yourWeekProvider.future),
      ref.read(unreadCountProvider.future),
      ref.read(announcementsUnreadProvider.future),
      ref.read(messagesUnreadProvider.future),
      ref.read(attentionProvider.future),
      ref.read(myWardsProvider.future),
      ref.read(shelf.future),
    ]);
  }

  /// First load / error: only the feed (and me) is on screen, and the
  /// AsyncView's loader / error need wrapping to be pullable.
  Widget _pullable(AsyncValue<Object?> value, Widget child) => value.maybeWhen(
        data: (_) => child,
        orElse: () => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(myFeedProvider);
            ref.invalidate(meProvider);
            return settleAll([
              ref.read(myFeedProvider.future),
              ref.read(meProvider.future),
            ]);
          },
          child: PullableState(child: child),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final feed = ref.watch(myFeedProvider);
    final me = ref.watch(meProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _pullable(feed, AsyncView(
          value: feed,
          onRetry: () => ref.invalidate(myFeedProvider),
          data: (f) {
            // Sport chips from everything in the feed.
            final cats = <String, String>{}; // name -> emoji
            for (final e in [...f.upcoming, ...f.past]) {
              if (e.categoryName != null) {
                cats[e.categoryName!] = e.categoryEmoji ?? '';
              }
            }
            List<EventSummary> bySport(List<EventSummary> list) =>
                _sport == null
                    ? list
                    : [
                        for (final e in list)
                          if (e.categoryName == _sport) e
                      ];
            final all = bySport(f.upcoming);
            final liveList = all.where(_live).toList();
            final todayList = all.where(_isToday).toList();
            final upcomingList = all.where(_isUpcoming).toList();
            // Past events: only the last two months.
            final cutoff =
                DateTime.now().toUtc().subtract(const Duration(days: 61));
            final past = [
              for (final e in bySport(f.past))
                if (e.eventDate == null || e.eventDate!.isAfter(cutoff)) e
            ];
            // The sport chips filter by name; suggestions are queried by
            // category id, so resolve one to the other off the same feed.
            final sportCategoryId = _sport == null
                ? null
                : [...f.upcoming, ...f.past]
                    .firstWhere((e) => e.categoryName == _sport,
                        orElse: () =>
                            const EventSummary(id: '', title: '', slug: ''))
                    .categoryId;
            final panelList = _day != null
                ? [
                    for (final e in all)
                      if (_eventKey(e) == _day) e
                  ]
                : _range == 'live'
                    ? liveList
                    : _range == 'today'
                        ? todayList
                        : _range == 'upcoming'
                            ? upcomingList
                            : all;

            return RefreshIndicator(
              onRefresh: () => _refresh(sportCategoryId),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  const _HomeHeader(),

                  // Local ads — invisible until the owner activates mobile
                  // slots with this key; location-targeted server-side. Also
                  // "home_top": SportPadi messages at the top of Home (a slot
                  // set to Top bar or Card in the console), drawn first.
                  const SizedBox(height: 12),
                  const AdDisplay(
                      slots: ['home_top', 'mobile_home'], carousel: true),

                  // Quick actions
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: _quickAction(p, Icons.group_add_outlined,
                          'Create group', () => _newGroupSheet(context)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _quickAction(p, Icons.qr_code_scanner_rounded,
                          'Scan QR', () => context.push('/scan'),
                          dark: true),
                    ),
                  ]),

                  // Weather at the session's location fix (nothing without
                  // one): conditions, today's range, and a remark for the day.
                  const WeatherCard(padding: EdgeInsets.only(top: 12)),

                  // Gamification: streak, this week's challenges, next unlock.
                  const YourWeekCard(),

                  // The one thing to look at next: live now, else the soonest
                  // by real start instant. Nothing coming up → ask for the
                  // location (so Home can suggest games nearby) or, with it
                  // already shared, point at Browse.
                  if (_nextUp(f.upcoming) case final EventSummary n) ...[
                    const SizedBox(height: 14),
                    _NextUpCard(event: n, live: _live(n)),
                  ] else if (f.upcoming.isNotEmpty ||
                      f.past.isNotEmpty ||
                      ref.watch(locationProvider).location == null) ...[
                    // (A brand-new account with a fix already shared gets the
                    // "Nothing here yet" card below instead — one card, not two.)
                    const SizedBox(height: 14),
                    const _NothingUpNextCard(),
                  ],

                  // Sport filter — All or exactly one sport
                  if (cats.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _chip(p, 'All', _sport == null,
                              () => setState(() => _sport = null)),
                          for (final e in cats.entries)
                            _chip(
                                p,
                                '${e.value} ${e.key}'.trim(),
                                _sport == e.key,
                                () => setState(() =>
                                    _sport = _sport == e.key ? null : e.key)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  ...[
                    if (f.upcoming.isEmpty && f.past.isEmpty)
                      GlassCard(
                        padding: const EdgeInsets.all(22),
                        child: Column(children: [
                          const Text('🧭', style: TextStyle(fontSize: 28)),
                          const SizedBox(height: 8),
                          Text('Nothing here yet',
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                            "You're not in any group yet, so there are no "
                            "events on your Home. Browse what's happening on "
                            'SportPadi and find your crew.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: p.muted, fontSize: 12.5),
                          ),
                          const SizedBox(height: 12),
                          SpButton(
                            label: 'Browse events',
                            icon: Icons.explore_outlined,
                            onTap: () => ref
                                .read(homeTabIndexProvider.notifier)
                                .state = 1,
                          ),
                        ]),
                      )
                    else
                      _calendarPanel(context, p, panelList, liveList, todayList,
                          upcomingList, all),

                    // AdMob native (Android). Takes no space until it fills.
                    const AdMobNativeCard(padding: EdgeInsets.only(top: 14)),

                    // Discovery. Below the player's own calendar and above the
                    // ads — it's the answer to "nothing on this week", which is
                    // exactly when someone opens Home and leaves. Rendered on
                    // the empty path too: a brand-new account needs it most.
                    const SizedBox(height: 22),
                    SuggestedEventsSection(categoryId: sportCategoryId),

                    const SizedBox(height: 10),
                    const AdDisplay(slots: ['home_ads'], carousel: true),
                    // Past events (hidden when the whole feed is empty —
                    // the Browse CTA covers it).
                    if (!(f.upcoming.isEmpty && f.past.isEmpty)) ...[
                      const SizedBox(height: 22),
                      PastEventsSection(events: past, userId: me?.userId),
                    ],
                  ],
                ],
              ),
            );
          },
        )),
      ),
    );
  }

  /// Live now, else the first event that hasn't finished yet by the clock:
  /// the server resolves each event's wall clock in its venue zone to real
  /// instants (startsAt / endsAt), so this is one UTC comparison against
  /// "now" — correct whatever zone the viewer or the venue is in. An event
  /// that has started but not ended still counts (you can still get there);
  /// one with no time at all counts for its whole day. Sorted by start.
  static EventSummary? _nextUp(List<EventSummary> upcoming) {
    for (final e in upcoming) {
      if (_live(e)) return e;
    }
    // The feed arrives soonest-first from the server, so the first event
    // that hasn't ended by this device's clock is the one.
    final now = DateTime.now().toUtc();
    for (final e in upcoming) {
      final end = e.endsAt ?? e.startsAt?.add(const Duration(hours: 2));
      if (end != null && !end.isBefore(now)) return e;
    }
    return null;
  }

  // ── Pieces ────────────────────────────────────────────────────────────────

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

  Widget _chip(AppPalette p, String label, bool active, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: active ? p.hero : p.surface,
          shape:
              StadiumBorder(side: BorderSide(color: active ? p.hero : p.line)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(label,
                  style: TextStyle(
                      color: active ? p.onHero : p.ink.withAlpha(200),
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600)),
            ),
          ),
        ),
      );

  static const _wd1 = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _wd3 = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mo = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// "Today" / "Tomorrow" / "Sat 4 Oct" for an agenda day heading.
  static String _dayLabel(String key) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final parts = key.split('-').map(int.parse).toList();
    final d = DateTime(parts[0], parts[1], parts[2]);
    final diff = d.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return '${_wd3[d.weekday - 1]} ${d.day} ${_mo[d.month - 1].substring(0, 3)}';
  }

  /// The dashboard calendar (2026): one card with a two-week day strip,
  /// range chips (Live / Today / Upcoming / All) and an agenda grouped by day
  /// on a timeline. Wards' events are part of the same calendar: under each
  /// day a green dot marks your events (red when live) and a violet dot marks
  /// ward events; ward rows carry a "Ward · Tobi" badge.
  Widget _calendarPanel(
      BuildContext context,
      AppPalette p,
      List<EventSummary> panelList,
      List<EventSummary> liveList,
      List<EventSummary> todayList,
      List<EventSummary> upcomingList,
      List<EventSummary> all) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = 0; i < 14; i++) today.add(Duration(days: i))];
    // Per strip day: your own events, whether any is live, and your wards'
    // events (an event a ward is going to counts as ward activity).
    final onDay = <String, ({bool mine, bool live, bool ward})>{};
    for (final e in all) {
      final k = _eventKey(e);
      if (k == null) continue;
      final d = onDay[k] ?? (mine: false, live: false, ward: false);
      final isWard = e.forWards.isNotEmpty;
      onDay[k] = (
        mine: d.mine || !isWard,
        live: d.live || _live(e),
        ward: d.ward || isWard,
      );
    }
    final selectedDay = _day;
    final monthLabel = selectedDay != null
        ? _mo[int.parse(selectedDay.split('-')[1]) - 1]
        : _mo[today.month - 1];

    final ranges = <({String key, String label, int count, bool live})>[
      if (liveList.isNotEmpty)
        (key: 'live', label: 'Live', count: liveList.length, live: true),
      (key: 'today', label: 'Today', count: todayList.length, live: false),
      (
        key: 'upcoming',
        label: 'Upcoming',
        count: upcomingList.length,
        live: false
      ),
      (key: 'all', label: 'All', count: all.length, live: false),
    ];

    Widget rangeChip(({String key, String label, int count, bool live}) r) {
      final active = _day == null && _range == r.key;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: active ? p.hero : p.surface2,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => setState(() {
              _range = r.key;
              _day = null;
              _agendaOpen = false;
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (r.live) ...[
                  const _PulseDot(),
                  const SizedBox(width: 6),
                ],
                Text(r.label,
                    style: TextStyle(
                        color: active ? p.onHero : p.ink,
                        fontSize: 12.5,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w600)),
                if (r.count > 0) ...[
                  const SizedBox(width: 6),
                  Text('${r.count}',
                      style: TextStyle(
                          color: active ? p.heroMuted : p.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
          ),
        ),
      );
    }

    Widget dayCell(DateTime d) {
      final k = _key(d);
      final isToday = k == _key(today);
      final selected =
          _day == k || (_day == null && _range == 'today' && isToday);
      final info = onDay[k];
      final live = info?.live ?? false;
      final mineDot = info != null && (info.mine || info.live);
      final wardDot = info?.ward ?? false;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _day = _day == k ? null : k;
            _agendaOpen = false;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? p.hero
                  : isToday
                      ? p.accentTint
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_wd1[d.weekday - 1],
                  style: TextStyle(
                      color: selected ? p.heroMuted : p.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text('${d.day}',
                  style: TextStyle(
                      color: selected
                          ? p.onHero
                          : isToday
                              ? p.greenText
                              : p.ink,
                      fontSize: 16,
                      height: 1.1,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              SizedBox(
                height: 5,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (mineDot)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: live
                            ? const Color(0xFFE02424)
                            : selected
                                ? const Color(0xFF6EDC9E)
                                : p.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (mineDot && wardDot) const SizedBox(width: 3),
                  if (wardDot)
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: selected ? p.wardTint : p.ward,
                        shape: BoxShape.circle,
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      );
    }

    // Agenda: grouped by day, capped until expanded.
    const cap = 5;
    final shown = _agendaOpen || panelList.length <= cap
        ? panelList
        : panelList.sublist(0, cap);
    final groups = <String, List<EventSummary>>{};
    for (final e in shown) {
      groups.putIfAbsent(_eventKey(e) ?? '', () => []).add(e);
    }

    final Widget agenda;
    if (panelList.isEmpty) {
      agenda = _calendarEmpty(
        p,
        Icons.event_available_outlined,
        _day != null
            ? 'Nothing on ${_dayLabel(_day!).toLowerCase().startsWith('to') ? _dayLabel(_day!).toLowerCase() : _dayLabel(_day!)}'
            : _range == 'live'
                ? 'Nothing live right now'
                : _range == 'today'
                    ? 'Nothing happening today'
                    : 'Nothing coming up',
        _sport != null
            ? 'No $_sport events here — try another sport or day.'
            : 'Across the groups you belong to or follow.',
        action: _day == null && _range != 'today'
            ? SpButton(
                label: 'Browse events',
                icon: Icons.explore_outlined,
                onTap: () => ref.read(homeTabIndexProvider.notifier).state = 1,
              )
            : null,
      );
    } else {
      agenda =
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final g in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Text(g.key.isEmpty ? 'Date to be set' : _dayLabel(g.key),
                style: TextStyle(
                    color: p.muted,
                    fontSize: 11.5,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700)),
          ),
          for (var i = 0; i < g.value.length; i++)
            _eventRow(context, p, g.value[i], last: i == g.value.length - 1),
        ],
        if (panelList.length > cap)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _agendaOpen = !_agendaOpen),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(
                      _agendaOpen
                          ? 'Show less'
                          : 'Show all ${panelList.length}',
                      style: TextStyle(
                          color: p.greenText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  Icon(
                      _agendaOpen
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: p.greenText),
                ]),
              ),
            ),
          ),
      ]);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(28),
        border: dark ? Border.all(color: p.line) : null,
        boxShadow: cardShadow(context),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Header: what this is, and the month you're looking at.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your calendar',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                    Text(
                        '$monthLabel · ${all.length} upcoming across your groups',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ]),
            ),
            if (_day != null)
              TextButton(
                onPressed: () => setState(() {
                  _day = null;
                  _agendaOpen = false;
                }),
                style: TextButton.styleFrom(
                    foregroundColor: p.greenText,
                    textStyle: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                child: const Text('Clear day'),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        // Two-week strip.
        SizedBox(
          height: 70,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [for (final d in days) dayCell(d)],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [for (final r in ranges) rangeChip(r)],
          ),
        ),
        const SizedBox(height: 4),
        Divider(height: 16, thickness: 1, color: p.surface2),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: agenda,
        ),
      ]),
    );
  }

  Widget _calendarEmpty(AppPalette p, IconData icon, String title, String body,
          {Widget? action}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
        child: Column(children: [
          SpIconTile(icon, size: 52, iconSize: 24),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
          if (action != null) ...[const SizedBox(height: 14), action],
        ]),
      );

  /// One agenda row on the timeline: start (and end) time, a dot on the
  /// rail, then title, group and venue. Live rows go red; ward events violet
  /// (with a "Ward · Tobi" badge); tournaments orange.
  Widget _eventRow(BuildContext context, AppPalette p, EventSummary e,
      {bool last = false}) {
    final live = _live(e);
    final t = e.isTournament;
    final start = formatClock(e.startTime);
    final end = formatClock(e.endTime);
    final railColor = live
        ? p.danger
        : e.forWards.isNotEmpty
            ? p.ward
            : t
                ? p.orange
                : p.accent;
    final sub = [
      if (e.groupName != null) e.groupName!,
      if (e.locationName != null) e.locationName!,
    ].join(' · ');

    return InkWell(
      onTap: () => t
          ? context.push('/tournaments/${e.id}')
          : context.push('/events/${e.slug.isNotEmpty ? e.slug : e.id}'),
      borderRadius: BorderRadius.circular(18),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Time column.
          SizedBox(
            width: 58,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, left: 4),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(live ? 'Now' : (start ?? 'TBC'),
                        style: TextStyle(
                            color: live ? p.danger : p.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                    if (!live && end != null)
                      Text(end, style: TextStyle(color: p.muted, fontSize: 11)),
                  ]),
            ),
          ),
          // Rail.
          SizedBox(
            width: 18,
            child: Column(children: [
              const SizedBox(height: 15),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: railColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.surface, width: 2),
                  boxShadow: [
                    BoxShadow(color: railColor.withAlpha(60), spreadRadius: 3)
                  ],
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.only(top: 4),
                    color: p.surface2,
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          // Content.
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(
                color: live
                    ? p.liveTint
                    : t
                        ? p.orangeTint
                        : p.surface2,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
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
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        if (sub.isNotEmpty)
                          Text(sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: p.muted, fontSize: 12)),
                        if (_wardChip(e) != null ||
                            e.audienceTeams.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            if (_wardChip(e) case final String chip)
                              SpBadge(chip,
                                  icon: Icons.supervisor_account_rounded,
                                  tone: p.wardInk),
                            // Team event: "For U12 Lions".
                            if (e.audienceTeams.isNotEmpty)
                              AudienceBadge(e.audienceTeams),
                          ]),
                        ],
                      ]),
                ),
                if (live) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: p.danger,
                        borderRadius: BorderRadius.circular(999)),
                    child: const Text('LIVE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                ] else if (t) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.emoji_events_outlined,
                      size: 18, color: p.orangeInk),
                ] else
                  Icon(Icons.chevron_right_rounded, size: 18, color: p.muted),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _newGroupSheet(BuildContext context) async {
    final p = context.palette;
    final name = TextEditingController();
    final desc = TextEditingController();
    final created = await showSpSheet<String>(
      context,
      builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SpSheetHeader(
              icon: Icons.group_add_outlined,
              title: 'Create a group',
              subtitle:
                  'Name it now — you can add a crest, sports and more later.',
            ),
            TextField(
              controller: name,
              style: TextStyle(color: p.ink, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Group name',
                hintStyle: TextStyle(color: p.muted, fontSize: 13.5),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: p.line)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: desc,
              maxLines: 2,
              style: TextStyle(color: p.ink, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Description (optional)',
                hintStyle: TextStyle(color: p.muted, fontSize: 13.5),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: p.line)),
              ),
            ),
            const SizedBox(height: 14),
            SpButton(
              label: 'Create group',
              icon: Icons.group_add_outlined,
              expand: true,
              onTap: () async {
                final n = name.text.trim();
                if (n.isEmpty) return;
                try {
                  final id = await ref
                      .read(groupsRepositoryProvider)
                      .createGroup(n, desc.text.trim());
                  if (ctx.mounted) Navigator.pop(ctx, id);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text('$e')));
                  }
                }
              },
            ),
          ]),
    );
    if (created != null && created.isNotEmpty && context.mounted) {
      context.push('/groups/$created');
    }
  }
}

/// The "beeping" live indicator — a small red dot that pulses forever.
class _PulseDot extends StatefulWidget {
  const _PulseDot();
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.25, end: 1.0)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Color(0xFFDC2626),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Home header: greeting + first name, the notifications bell (orange dot
/// when unread) and the avatar wearing the level ring — tapping it opens the
/// side menu (what the old app bar's hamburger did).
class _HomeHeader extends ConsumerWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final me = ref.watch(meProvider).valueOrNull;
    final week = ref.watch(yourWeekProvider).valueOrNull;
    final unread = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    final h = DateTime.now().hour;
    final greeting = h < 12
        ? 'Good morning'
        : h < 17
            ? 'Good afternoon'
            : 'Good evening';
    final first =
        capitalizeFirst(me?.displayName.trim().split(RegExp(r'\s+')).first);
    final initial = first.isNotEmpty ? first[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(greeting,
                style: TextStyle(
                    color: p.muted, fontSize: 13, fontWeight: FontWeight.w500)),
            Text(first.isEmpty ? 'Welcome' : first,
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
        // Inbox (announcements) sits beside the bell with its own badge.
        const InboxHeaderButton(),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
          child: Material(
            color: p.surface,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => context.push('/notifications'),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, boxShadow: cardShadow(context)),
                child: Stack(alignment: Alignment.center, children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 23, color: p.ink),
                  if (unread > 0)
                    Positioned(
                      top: 10,
                      right: 11,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: p.orange,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.surface, width: 2),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: 'Menu',
          child: GestureDetector(
            onTap: () => showSideMenu(context),
            child: SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    ProgressRing(
                      value: week?.progress ?? 0,
                      size: 48,
                      stroke: 3.5,
                      child: CircleAvatar(
                        radius: 19,
                        backgroundColor: p.hero,
                        backgroundImage: me?.avatarUrl != null
                            ? NetworkImage(me!.avatarUrl!)
                            : null,
                        child: me?.avatarUrl == null
                            ? Text(initial,
                                style: TextStyle(
                                    color: p.onHero,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15))
                            : null,
                      ),
                    ),
                    // What's waiting in the menu this avatar opens.
                    Positioned(
                      right: 0,
                      top: 0,
                      child: SideMenuAttentionCount(border: p.bg),
                    ),
                    if (week != null)
                      Positioned(
                        right: -4,
                        bottom: -2,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: p.orange,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: p.bg, width: 2),
                          ),
                          child: Text('${week.level}',
                              style: const TextStyle(
                                  color: Color(0xFF1A0E04),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  height: 1)),
                        ),
                      ),
                  ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// "Next up": the live event, or the soonest one, as the dark hero card with
/// a faint pitch drawn behind it. Live → Check in (scanner); else → the event.
/// Home when nothing is coming up. Without a location fix the card asks for
/// one — that's what lets Home suggest games nearby — with Settings as the
/// way back from a permanent refusal; with a fix, it points at Browse.
class _NothingUpNextCard extends ConsumerWidget {
  const _NothingUpNextCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final st = ref.watch(locationProvider);
    final hasFix = st.location != null;
    final String title;
    final String body;
    final String cta;
    final IconData icon;
    final VoidCallback onTap;
    if (hasFix) {
      icon = Icons.explore_outlined;
      title = 'Nothing up next';
      body = 'No game on your calendar yet. See what\'s on near you and '
          'get one in.';
      cta = 'Browse games';
      onTap = () => ref.read(homeTabIndexProvider.notifier).state = 1;
    } else if (st.denied) {
      icon = Icons.location_off_rounded;
      title = 'Nothing up next';
      body = 'Location is off for SportPadi. Turn it on in Settings and '
          'we\'ll suggest games near you.';
      cta = 'Open Settings';
      onTap = () => Geolocator.openAppSettings();
    } else {
      icon = Icons.location_searching_rounded;
      title = 'Nothing up next';
      body = st.error ??
          'Allow SportPadi to read your location and we\'ll suggest games '
              'near you to fill the gap.';
      cta = st.loading ? 'Finding you…' : 'Allow location';
      onTap = () => ref.read(locationProvider.notifier).request();
    }
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        SpIconTile(icon,
            bg: hasFix ? p.accentTint : p.surface2,
            fg: hasFix ? p.greenText : p.muted,
            size: 44,
            iconSize: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(body,
                    style: TextStyle(
                        color: p.muted, fontSize: 12.5, height: 1.4)),
                const SizedBox(height: 10),
                SpButton(
                  label: cta,
                  icon: hasFix
                      ? Icons.explore_outlined
                      : st.denied
                          ? Icons.settings_outlined
                          : Icons.my_location_rounded,
                  tone: hasFix ? SpButtonTone.ink : SpButtonTone.brand,
                  onTap: st.loading ? null : onTap,
                ),
              ]),
        ),
      ]),
    );
  }
}

class _NextUpCard extends StatelessWidget {
  const _NextUpCard({required this.event, required this.live});
  final EventSummary event;
  final bool live;

  String _eyebrow() {
    if (live) return 'LIVE NOW';
    final d = event.eventDate?.toUtc();
    if (d == null) return 'NEXT UP';
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final day = DateTime.utc(d.year, d.month, d.day);
    final n = day.difference(today).inDays;
    if (n <= 0) return 'NEXT UP · TODAY';
    if (n == 1) return 'NEXT UP · TOMORROW';
    return 'NEXT UP · IN $n DAYS';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    final clock = formatClock(e.startTime);
    final when = '${formatDay(e.eventDate)}${clock != null ? ' · $clock' : ''}';
    void open() => e.isTournament
        ? context.push('/tournaments/${e.id}')
        : context.push('/events/${e.slug.isNotEmpty ? e.slug : e.id}');
    return Material(
      color: p.hero,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: open,
        child: Stack(children: [
          Positioned(
            right: -60,
            top: -20,
            child: CustomPaint(
              size: const Size(260, 200),
              painter: _PitchPainter(p.onHero.withAlpha(20)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (live) ...[
                  const _PulseDot(),
                  const SizedBox(width: 6),
                ],
                Text(_eyebrow(),
                    style: TextStyle(
                        color: live
                            ? const Color(0xFFFF8A8A)
                            : const Color(0xFF6EDC9E),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.3)),
              ]),
              const SizedBox(height: 10),
              Text(
                  '${e.categoryEmoji != null ? '${e.categoryEmoji} ' : ''}${e.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.onHero,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      height: 1.2)),
              const SizedBox(height: 10),
              _line(p, Icons.calendar_today_rounded, when),
              if (e.locationName != null && e.locationName!.trim().isNotEmpty)
                _line(p, Icons.place_outlined, e.locationName!),
              if (e.groupName != null)
                _line(p, Icons.groups_outlined, e.groupName!),
              if (_HomeScreenState._wardChip(e) case final String chip)
                _line(p, Icons.supervisor_account_rounded, chip),
              if (audienceLabel(e.audienceTeams) case final String who)
                _line(p, Icons.shield_outlined, who),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Text(
                    (e.interestCount ?? 0) > 0
                        ? '${e.interestCount} RSVP${e.interestCount == 1 ? '' : 's'}'
                        : '',
                    style: TextStyle(color: p.heroMuted, fontSize: 12.5),
                  ),
                ),
                Material(
                  color: p.onHero,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: live ? () => context.push('/scan') : open,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            live
                                ? Icons.qr_code_scanner_rounded
                                : Icons.arrow_forward_rounded,
                            size: 17,
                            color: p.hero),
                        const SizedBox(width: 6),
                        Text(live ? 'Check in' : 'View',
                            style: TextStyle(
                                color: p.hero,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _line(AppPalette p, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(children: [
          Icon(icon, size: 15, color: p.heroMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.heroMuted, fontSize: 13)),
          ),
        ]),
      );
}

/// Faint pitch markings behind the Next up card.
class _PitchPainter extends CustomPainter {
  _PitchPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
        RRect.fromLTRBR(10, 10, size.width - 10, size.height - 10,
            const Radius.circular(6)),
        paint);
    canvas.drawLine(Offset(size.width / 2, 10),
        Offset(size.width / 2, size.height - 10), paint);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 34, paint);
    canvas.drawRect(Rect.fromLTWH(10, size.height / 2 - 40, 44, 80), paint);
    canvas.drawRect(
        Rect.fromLTWH(size.width - 54, size.height / 2 - 40, 44, 80), paint);
  }

  @override
  bool shouldRepaint(_PitchPainter old) => old.color != color;
}
