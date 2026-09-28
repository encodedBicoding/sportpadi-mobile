import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/features/home/suggested_events_section.dart';
import 'package:sportpadi_mobile/shared/widgets/event_tile_square.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_app_bar.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart'
    show homeTabIndexProvider;
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/ads/admob.dart';
import 'package:sportpadi_mobile/features/ads/ad_display.dart';
import 'package:sportpadi_mobile/features/progression/progression_widgets.dart';

/// Home — the user's personal dashboard: their upcoming events across every
/// group they belong to (live events beep on the tab), a Kids tab (future),
/// a sport filter, their past events, and quick actions (new group, scan…).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _range = 'today'; // live | today | upcoming | kids | all
  String? _sport; // category name filter, null = All

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

  // Kids/wards aren't implemented yet — the tab only appears once the user
  // actually has a ward linked to their account (wire this up when wards
  // land).
  bool get _hasWards => false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final feed = ref.watch(myFeedProvider);
    final me = ref.watch(meProvider).valueOrNull;

    return Scaffold(
      appBar: const SpAppBar(),
      body: AsyncView(
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
          List<EventSummary> bySport(List<EventSummary> list) => _sport == null
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
                      orElse: () => const EventSummary(
                          id: '', title: '', slug: ''))
                  .categoryId;
          final panelList = _range == 'live'
              ? liveList
              : _range == 'today'
                  ? todayList
                  : _range == 'upcoming'
                      ? upcomingList
                      : all;

          return RefreshIndicator(
            onRefresh: () => ref.refresh(myFeedProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // Greeting
                Text(
                  me != null
                      ? 'Hi, ${me.displayName.split(' ').first} 👋'
                      : 'Home',
                  style: TextStyle(
                      color: p.ink, fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                    "Here's what's on across the groups you belong to and follow.",
                    style: TextStyle(color: p.muted, fontSize: 13)),

                // Local ads — invisible until the owner activates mobile
                // slots with this key; location-targeted server-side.
                const SizedBox(height: 12),
                const AdDisplay(slots: ['mobile_home'], carousel: true),

                // Quick actions
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: _quickAction(p, Icons.group_add_outlined,
                        'New group', () => _newGroupSheet(context)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _quickAction(p, Icons.qr_code_scanner_rounded,
                        'Scan QR', () => context.push('/scan')),
                  ),
                ]),

                // Gamification: streak, this week's challenges, next unlock.
                const YourWeekCard(),

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
                          onTap: () =>
                              ref.read(homeTabIndexProvider.notifier).state = 1,
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
                  const SizedBox(height: 18),
                  SuggestedEventsSection(categoryId: sportCategoryId),

                  const SizedBox(height: 10),
                  const AdDisplay(slots: ['home_ads'], carousel: true),
                  // Past events (hidden when the whole feed is empty —
                  // the Browse CTA covers it).
                  if (!(f.upcoming.isEmpty && f.past.isEmpty)) ...[
                    const SizedBox(height: 18),
                    const Eyebrow('Past events'),
                    const SizedBox(height: 10),
                    if (past.isEmpty)
                      GlassCard(
                        child: Center(
                          child: Text('No past events in the last two months.',
                              style: TextStyle(color: p.muted, fontSize: 13)),
                        ),
                      )
                    else
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        children: [
                          // Your record there, not the event's scoresheet;
                          // the event is one deliberate tap further in.
                          for (final e in past)
                            EventTileSquare(
                              event: e,
                              onTap: me?.userId == null
                                  ? null
                                  : () => context.push(e.isTournament
                                      ? '/players/${me!.userId}/tournaments/${e.id}'
                                      : '/players/${me!.userId}/events/${e.id}'),
                            ),
                        ],
                      ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Pieces ────────────────────────────────────────────────────────────────

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

  Widget _chip(AppPalette p, String label, bool active, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: active ? p.accent : p.surface,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: active ? p.accent : p.line),
              ),
              child: Text(label,
                  style: TextStyle(
                      color: active ? Colors.white : p.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );

  /// Folder-tab calendar panel: Live / Upcoming / Kids (wards only) /
  /// View All tabs sitting on a connected card of event rows — tabs with
  /// content pulse.
  Widget _calendarPanel(
      BuildContext context,
      AppPalette p,
      List<EventSummary> panelList,
      List<EventSummary> liveList,
      List<EventSummary> todayList,
      List<EventSummary> upcomingList,
      List<EventSummary> all) {
    final tabs = <({String key, String label, int count, bool live})>[
      (key: 'live', label: 'Live', count: liveList.length, live: true),
      (key: 'today', label: 'Today', count: todayList.length, live: false),
      (
        key: 'upcoming',
        label: 'Upcoming',
        count: upcomingList.length,
        live: false
      ),
      if (_hasWards) (key: 'kids', label: 'Kids', count: 0, live: false),
      (key: 'all', label: 'View All', count: all.length, live: false),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Tabs
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 4),
        child: Row(children: [
          for (final t in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: () => setState(() => _range = t.key),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: _range == t.key
                        ? p.surface
                        : t.key == 'all'
                            ? p.accent
                            : p.accent.withAlpha(46),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                    border: _range == t.key
                        ? Border(
                            top: BorderSide(color: p.line),
                            left: BorderSide(color: p.line),
                            right: BorderSide(color: p.line),
                          )
                        : null,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      t.label,
                      style: TextStyle(
                        color: _range == t.key
                            ? p.ink
                            : t.key == 'all'
                                ? Colors.white
                                : p.ink.withAlpha(210),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (t.count > 0) ...[
                      const SizedBox(width: 6),
                      _PulseDot(
                          color: t.live
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF10B981)),
                    ],
                  ]),
                ),
              ),
            ),
        ]),
      ),
      // Panel
      Container(
        constraints: const BoxConstraints(minHeight: 210),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border.all(color: p.line),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: _range == 'kids'
            ? SizedBox(
                height: 190,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🧒', style: TextStyle(fontSize: 28)),
                    const SizedBox(height: 8),
                    Text('Kids & wards are coming soon',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      "You'll be able to follow your kids' events across "
                      'their groups right here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ],
                ),
              )
            : panelList.isEmpty
                ? SizedBox(
                    height: 190,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _range == 'live'
                              ? 'Nothing live right now.'
                              : _range == 'today'
                                  ? 'Nothing happening today.'
                                  : _sport != null
                                      ? 'No upcoming $_sport events.'
                                      : 'No upcoming events across the groups you belong to or follow.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.muted, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        SpButton(
                          label: 'Browse events',
                          icon: Icons.explore_outlined,
                          onTap: () =>
                              ref.read(homeTabIndexProvider.notifier).state = 1,
                        ),
                      ],
                    ),
                  )
                : Column(children: [
                    for (final e in panelList) _eventRow(context, p, e),
                  ]),
      ),
    ]);
  }

  /// Reference-style row: date block, title + group, time / LIVE.
  Widget _eventRow(BuildContext context, AppPalette p, EventSummary e) {
    final d = e.eventDate?.toUtc();
    const wd = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return InkWell(
      onTap: () => e.isTournament
          ? context.push('/tournaments/${e.id}')
          : context.push('/events/${e.slug.isNotEmpty ? e.slug : e.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(children: [
          Column(children: [
            Text(d != null ? wd[d.weekday - 1] : '—',
                style: TextStyle(
                    color: p.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700)),
            Text(d != null ? '${d.day}' : '—',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    height: 1.1)),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (e.groupName != null)
                Text(e.groupName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 11)),
              Text(
                  '${e.categoryEmoji != null ? '${e.categoryEmoji} ' : ''}${e.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
          const SizedBox(width: 8),
          if (e.isLive || e.status == 'kicked_off')
            Row(mainAxisSize: MainAxisSize.min, children: [
              const _PulseDot(),
              const SizedBox(width: 5),
              Text('LIVE',
                  style: TextStyle(
                      color: p.danger,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900)),
            ])
          else
            Text(formatClock(e.startTime) ?? formatDay(e.eventDate),
                style: TextStyle(
                    color: p.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Future<void> _newGroupSheet(BuildContext context) async {
    final p = context.palette;
    final name = TextEditingController();
    final desc = TextEditingController();
    final created = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Create a group',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    style: TextStyle(color: p.ink, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Group name',
                      hintStyle: TextStyle(color: p.muted, fontSize: 13.5),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
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
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
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
          ),
        ),
      ),
    );
    if (created != null && created.isNotEmpty && context.mounted) {
      context.push('/groups/$created');
    }
  }
}

/// The "beeping" live indicator — a small red dot that pulses forever.
class _PulseDot extends StatefulWidget {
  const _PulseDot({this.color = const Color(0xFFDC2626)});
  final Color color;
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
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
