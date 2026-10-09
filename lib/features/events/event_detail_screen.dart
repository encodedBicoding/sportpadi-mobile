import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/games/game_models.dart';
import 'package:sportpadi_mobile/data/games/games_repository.dart';
import 'package:sportpadi_mobile/data/groups/member_models.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/data/progression/progression_repository.dart';
import 'package:sportpadi_mobile/data/teams/team_models.dart'
    show AudienceTeamOption;
import 'package:sportpadi_mobile/data/teams/teams_repository.dart'
    show eventAudiencesProvider;
import 'package:sportpadi_mobile/data/groups/members_repository.dart';
import 'package:sportpadi_mobile/features/ads/ad_anchor.dart';
import 'package:sportpadi_mobile/features/events/event_menu.dart';
import 'package:sportpadi_mobile/features/events/event_tickets_card.dart';
import 'package:sportpadi_mobile/features/games/basketball_widgets.dart';
import 'package:sportpadi_mobile/features/games/volleyball_widgets.dart';
import 'package:sportpadi_mobile/features/wards/ward_pickers.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/event_audience.dart';
import 'package:sportpadi_mobile/shared/widgets/event_spots.dart';
import 'package:sportpadi_mobile/shared/widgets/event_reminders.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/core/referral/referral.dart';
import 'package:sportpadi_mobile/features/events/rsvp_info_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/verified_badge.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';

const _cancelRepeatingCopy =
    'Anyone who paid for a ticket gets the ticket price back automatically. '
    'This is a repeating event — cancelling stops the series; it will not be '
    're-created. This cannot be undone.';
const _cancelOnceCopy =
    'Anyone who paid for a ticket gets the ticket price back automatically. '
    'If no money ever changed hands, the event is removed entirely. This '
    'cannot be undone.';
const _processingFeeNote =
    "SportPadi's processing fee is non-refundable: buyers get the ticket price "
    "back, and if your group covers the fees, the processing fee on each sale "
    "isn't returned to your group either.";

/// Event detail — a faithful mobile port of the web /events/[slug] page:
/// photos, info, hosted-by (follow), stats, interest/check-in, organizer QR,
/// team assignment, and the post-assignment Games / Teams / Check-ins tabs.
class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen>
    with WidgetsBindingObserver {
  // Post-assignment tab: 0 = Games, 1 = Teams, 2 = Check-ins.
  int _tab = 0;
  String? _busy;
  Timer? _live;
  ProviderSubscription<AsyncValue<EventDetail>>? _watch;
  ProviderSubscription<AsyncValue<EventDetail>>? _balanceWatch;
  bool _balanceChecked = false;
  // Realtime: the event's SSE ping stream (games created/scored/deleted,
  // teams, check-ins, status) → refetch everything on the page.
  ProviderSubscription<AsyncValue<EventDetail>>? _streamWatch;
  StreamSubscription<void>? _pingSub;
  Timer? _pingRetry;
  Timer? _pingDebounce;
  String? _pingEventId;
  int _pingBackoff = 2;
  int _liveTicks = 0;
  // Just assigned teams: bring the Games tab (and its "Start the first
  // match") into view once the teams have loaded.
  final _playKey = GlobalKey();
  bool _jumpToPlay = false;

  String get slug => widget.slug;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Around game day the screen stays live: a check-in (scanned on this or
    // any other device) shows up within seconds — no pull-to-refresh needed.
    // The event stream below is the fast path; this is the safety net (games
    // and teams every 15s, in case a ping is missed).
    _live = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final e = ref.read(eventDetailProvider(slug)).valueOrNull;
      if (e == null) return;
      if (e.status == 'completed' || e.status == 'cancelled') return;
      final d = e.eventDate;
      if (d == null) return;
      final diff = d.difference(DateTime.now()).inHours.abs();
      if (e.status == 'live' || e.status == 'kicked_off' || diff <= 36) {
        if (++_liveTicks % 3 == 0) {
          _refreshAll();
        } else {
          ref.invalidate(eventDetailProvider(slug));
        }
      }
    });
    _streamWatch = ref.listenManual(eventDetailProvider(slug),
        fireImmediately: true, (prev, next) {
      final e = next.valueOrNull;
      if (e != null && mounted) _listenEvent(e.id);
    });
    // Loud feedback when a refresh brings news: your own check-in landed, or
    // (for organizers) a player just scanned in — mirrors the web live feed.
    _watch = ref.listenManual(eventDetailProvider(slug), (prev, next) {
      final a = prev?.valueOrNull;
      final b = next.valueOrNull;
      if (a == null || b == null || !mounted) return;
      if (!a.myCheckedIn && b.myCheckedIn) {
        HapticFeedback.mediumImpact();
        _flash("You're checked in ✅");
        return;
      }
      if (b.canManage) {
        final before = a.attendees
            .where((x) => x.checkedInAt != null)
            .map((x) => x.userId)
            .toSet();
        final fresh = b.attendees
            .where((x) => x.checkedInAt != null && !before.contains(x.userId))
            .toList();
        if (fresh.isNotEmpty) {
          HapticFeedback.mediumImpact();
          _flash(fresh.length == 1
              ? '🎉 ${fresh.first.displayName} checked in'
              : '🎉 ${fresh.first.displayName} +${fresh.length - 1} checked in');
        }
      }
    });

    // Compulsory balance-by-attribute setup: once the event resolves, ask the
    // server whether this viewer still owes their role/position for the
    // event's category (smart-balancing sports only) and block until saved.
    _balanceWatch = ref.listenManual(eventDetailProvider(slug),
        fireImmediately: true, (prev, next) {
      final e = next.valueOrNull;
      if (e == null || _balanceChecked || !mounted) return;
      _balanceChecked = true;
      _checkBalanceSetup(e.id);
    });
  }

  Future<void> _checkBalanceSetup(String eventId) async {
    final data = await ref.read(eventsRepositoryProvider).balanceSetup(eventId);
    if (!mounted || data == null) return;
    if (data['required'] != true) return;
    final field = data['field'];
    final categoryId = data['categoryId'];
    if (field is! Map || categoryId is! String || categoryId.isEmpty) return;
    await _showBalanceSheet(
      categoryId: categoryId,
      categoryName: (data['categoryName'] as String?) ?? 'this sport',
      label: (field['label'] as String?) ?? 'position',
      options: field['options'] is List
          ? (field['options'] as List).map((x) => x.toString()).toList()
          : const <String>[],
      maxPicks: field['maxPicks'] is int ? field['maxPicks'] as int : 3,
    );
  }

  Future<void> _showBalanceSheet({
    required String categoryId,
    required String categoryName,
    required String label,
    required List<String> options,
    required int maxPicks,
  }) async {
    final p = context.palette;
    final picked = <String>{};
    final freeCtrl = TextEditingController();
    var saving = false;
    await showSpSheet<void>(
      context,
      isDismissible: false,
      enableDrag: false,
      framed: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (ctx, setSheet) {
            final canSave = options.isNotEmpty
                ? picked.isNotEmpty
                : freeCtrl.text.trim().isNotEmpty;
            Future<void> doSave() async {
              if (saving || !canSave) return;
              setSheet(() => saving = true);
              try {
                final roles = options.isNotEmpty
                    ? picked.toList()
                    : [freeCtrl.text.trim()];
                await ref
                    .read(eventsRepositoryProvider)
                    .saveBalanceRoles(categoryId, roles);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) _flash("You're set for $categoryName ✅");
              } catch (e) {
                setSheet(() => saving = false);
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text(e.toString()),
                    behavior: SnackBarBehavior.floating,
                  ));
                }
              }
            }

            return Container(
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, 28 + MediaQuery.of(ctx).viewInsets.bottom),
              decoration: BoxDecoration(
                color: Theme.of(ctx).scaffoldBackgroundColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: p.muted.withAlpha(90),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Set your ${label.toLowerCase()}',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(
                      '$categoryName events use smart team balancing, and it '
                      'needs every player\'s ${label.toLowerCase()}. '
                      '${maxPicks == 1 ? 'Pick one' : 'Pick up to $maxPicks'} — '
                      'you can change this later from your profile.',
                      style:
                          TextStyle(color: p.muted, fontSize: 13, height: 1.45),
                    ),
                    const SizedBox(height: 14),
                    if (options.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final opt in options)
                            GestureDetector(
                              onTap: () => setSheet(() {
                                if (picked.contains(opt)) {
                                  picked.remove(opt);
                                } else if (maxPicks == 1) {
                                  picked
                                    ..clear()
                                    ..add(opt);
                                } else if (picked.length < maxPicks) {
                                  picked.add(opt);
                                }
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: picked.contains(opt)
                                      ? p.accent.withAlpha(36)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(
                                    color: picked.contains(opt)
                                        ? p.accent
                                        : p.muted.withAlpha(80),
                                  ),
                                ),
                                child: Text(
                                  opt,
                                  style: TextStyle(
                                    color: picked.contains(opt)
                                        ? p.accent
                                        : p.muted,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    else
                      TextField(
                        controller: freeCtrl,
                        onChanged: (_) => setSheet(() {}),
                        maxLength: 60,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: 'Your ${label.toLowerCase()}',
                          counterText: '',
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48)),
                      onPressed: canSave && !saving ? doSave : null,
                      child: Text(saving ? 'Saving…' : 'Save & continue'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    freeCtrl.dispose();
  }

  void _flash(String msg) {
    final p = context.palette;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              fontWeight: FontWeight.w700, color: Colors.white)),
      backgroundColor: p.accent,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _live?.cancel();
    _watch?.close();
    _balanceWatch?.close();
    _streamWatch?.close();
    _pingSub?.cancel();
    _pingRetry?.cancel();
    _pingDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the background: catch up, and reopen the stream if the OS
    // closed it.
    if (state != AppLifecycleState.resumed || !mounted) return;
    _refreshAll();
    final id = _pingEventId;
    if (id != null && _pingSub == null) _listenEvent(id, force: true);
  }

  void _listenEvent(String eventId, {bool force = false}) {
    // Already listening — or waiting out a reconnect backoff (the event
    // refetches every few seconds and must not skip that wait).
    if (!force &&
        _pingEventId == eventId &&
        (_pingSub != null || (_pingRetry?.isActive ?? false))) {
      return;
    }
    _pingEventId = eventId;
    _pingRetry?.cancel();
    _pingSub?.cancel();
    _pingSub = ref.read(eventsRepositoryProvider).eventPings(eventId).listen(
      (_) {
        _pingBackoff = 2; // healthy stream
        // Pings come in bursts (a goal = activity + lock); refetch once.
        _pingDebounce?.cancel();
        _pingDebounce = Timer(const Duration(milliseconds: 300), () {
          if (mounted) _refreshAll();
        });
      },
      onError: (_) => _retryEventStream(),
      onDone: _retryEventStream,
      cancelOnError: true,
    );
  }

  void _retryEventStream() {
    _pingSub = null;
    if (!mounted) return;
    _pingRetry?.cancel();
    _pingRetry = Timer(Duration(seconds: _pingBackoff), () {
      final id = _pingEventId;
      if (!mounted || id == null) return;
      _pingBackoff = (_pingBackoff * 2).clamp(2, 30);
      _listenEvent(id, force: true);
    });
  }

  /// Refetch every piece of the page — the event, its games (with scores),
  /// teams and the available pool. Used by pull-to-refresh, realtime pings
  /// and the game-day safety poll.
  void _refreshAll() {
    final e = ref.read(eventDetailProvider(slug)).valueOrNull;
    ref.invalidate(eventDetailProvider(slug));
    if (e == null) return;
    ref.invalidate(eventGamesProvider(e.id));
    ref.invalidate(eventTeamsProvider(e.id));
    ref.invalidate(availablePoolProvider(e.id));
  }

  /// Pull-to-refresh: everything, and wait for it so the spinner means it.
  Future<void> _pullRefresh() async {
    final e = ref.read(eventDetailProvider(slug)).valueOrNull;
    _refreshAll();
    await Future.wait<void>([
      ref.read(eventDetailProvider(slug).future).then((_) {}, onError: (_) {}),
      if (e != null)
        ref.read(eventGamesProvider(e.id).future).then((_) {}, onError: (_) {}),
      if (e != null)
        ref.read(eventTeamsProvider(e.id).future).then((_) {}, onError: (_) {}),
    ]);
  }

  void _refetch() => _refreshAll();

  /// "See event QR code": the live QR in a sheet, big enough to scan off
  /// the screen. It names this organiser and refreshes while open.
  Future<void> _showQrSheet(EventDetail e) async {
    await showSpSheet<void>(
      context,
      builder: (ctx) {
        final p = ctx.palette;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpSheetHeader(
              icon: Icons.qr_code_2_rounded,
              title: 'Event QR code',
              subtitle: e.status == 'kicked_off'
                  ? 'Late arrivals who scan this join the available pool.'
                  : 'Players scan this to check in.',
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _LiveQr(event: e, size: 240),
              ),
            ),
            const SizedBox(height: 8),
            Text('Refreshes every 30 seconds — screenshots won’t work.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 11.5)),
            // "Check someone in" is hidden until further notice.
          ],
        );
      },
    );
  }

  /// Manual completion ends the event for everyone — always confirm first
  /// (a stray tap by one admin closes it for the whole group).
  Future<bool> _confirmComplete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete this event?'),
        content: const Text(
            'This ends the event for everyone — check-ins close and results '
            'are finalized. If the game is still being played, keep it open.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it open')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Complete event')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _do(String key, Future<void> Function() op) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      await op();
      _refetch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final detail = ref.watch(eventDetailProvider(slug));
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          AsyncView(
            value: detail,
            onRetry: _refetch,
            data: (e) => RefreshIndicator(
              onRefresh: _pullRefresh,
              child: _body(e),
            ),
          ),
          // While loading (or on error) there's no cover to carry the back
          // button — keep one on screen regardless.
          if (detail.valueOrNull == null)
            Positioned(
              left: 16,
              top: 12,
              child: SpRoundButton(
                icon: Icons.arrow_back_ios_new_rounded,
                iconSize: 18,
                tooltip: 'Back',
                onTap: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
              ),
            ),
        ]),
      ),
    );
  }

  void _share(EventDetail? e) {
    if (e == null) return;
    final base = ref.read(appConfigProvider).apiBaseUrl;
    // Carries who shared it (gamification: community XP for bringing people).
    final me = ref.read(meProvider).valueOrNull?.userId;
    Clipboard.setData(
        ClipboardData(text: withRef('$base/e/${e.slug}', me, 'event', e.id)));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  /// Organizers: the event's photos, in a sheet (from the "More" menu). It
  /// follows the live event, so adds / removes / a new cover show at once.
  Future<void> _openPhotos() async {
    await showSpSheet<void>(
      context,
      builder: (_) => Consumer(builder: (context, ref, _) {
        final p = context.palette;
        final ev = ref.watch(eventDetailProvider(slug)).valueOrNull;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpSheetHeader(
              icon: Icons.add_photo_alternate_outlined,
              iconBg: p.accentTint,
              iconFg: p.greenText,
              title: 'Event photos',
              subtitle: 'Tap a photo to make it the cover or remove it',
            ),
            if (ev == null)
              const Center(child: CircularProgressIndicator())
            else
              _PhotoManager(event: ev, onChanged: _refetch),
          ],
        );
      }),
    );
  }

  Future<void> _openEdit(EventDetail e) async {
    final saved = await showSpSheet<bool>(
      context,
      framed: false,
      builder: (_) => _EditEventSheet(event: e),
    );
    if (saved == true) _refetch();
  }

  bool _isPast(EventDetail e) {
    // The server computes this in the EVENT's own timezone (venue coords →
    // IANA zone, stored on create/edit) against endTime — or end of that day
    // when no end time is set. Device-local date math is wrong across zones.
    final ended = e.hasEnded;
    if (ended != null) return ended;
    // Legacy fallback for old payloads without the field.
    final d = e.eventDate;
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(d.year, d.month, d.day, d.hour).isBefore(today);
  }

  Widget _body(EventDetail e) {
    final p = context.palette;
    final teamsAsync = ref.watch(eventTeamsProvider(e.id));
    final teams = teamsAsync.valueOrNull ?? const <EventTeam>[];
    final games = ref.watch(eventGamesProvider(e.id)).valueOrNull ??
        const <GameSummary>[];
    final hasGames = games.isNotEmpty;
    final showTabs = e.isTeamFlow && teams.isNotEmpty;
    if (showTabs && _jumpToPlay) {
      _jumpToPlay = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _playKey.currentContext;
        if (c != null && c.mounted) {
          Scrollable.ensureVisible(c,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic);
        }
      });
    }
    // Web: feature groups keep taking check-ins after kickoff so late
    // arrivals land in the available pool.
    final canCheckIn =
        e.status == 'open' || (e.status == 'kicked_off' && e.hasLatePool);
    // Photos, Message participants and Reminders live in the "More" menu
    // beside Share (EventMenuButton), each in its own sheet.
    final children = <Widget>[
      if (e.groupId != null) ...[
        _HostedByCard(
            groupId: e.groupId!,
            name: e.groupName ?? 'Group',
            imageUrl: e.groupImageUrl,
            verified: e.groupVerified),
      ],
      // The matches section pushes the check-in QR down the page —
      // organisers get a one-tap way back to it.
      if (showTabs && e.canManage && canCheckIn && e.qrCode != null) ...[
        const SizedBox(height: 12),
        _QrShortcut(onTap: (_) => _showQrSheet(e)),
      ],
      if (showTabs) ...[
        // Teams are set: the matches are what everyone's here for, so the
        // Games / Teams / Check-ins switch sits right under "Hosted by" —
        // nobody scrolls to start or follow a match.
        SizedBox(key: _playKey, height: 16),
        _TabRow(
          tab: e.canCreateGames && _tab == 0 ? 0 : (_tab == 0 ? 1 : _tab),
          showGames: e.canCreateGames,
          onChanged: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 12),
        if (_tab == 0 && e.canCreateGames)
          _GamesTab(event: e, teams: teams, onChanged: _refetch)
        else if (_tab <= 1)
          _TeamsTab(teams: teams)
        else
          _CheckinsList(event: e, onChanged: _refetch),
        const SizedBox(height: 12),
        if (e.canManage && e.status == 'kicked_off') ...[
          _OrganizerTeamControls(
            hasGames: hasGames,
            busy: _busy,
            onReshuffle: () async {
              final count = await _AssignTeamsCard.pickCount(context);
              if (count == null) return;
              await _do('assign', () async {
                await ref
                    .read(eventsRepositoryProvider)
                    .generateTeams(e.id, teamCount: count);
                ref.invalidate(eventTeamsProvider(e.id));
              });
            },
            onComplete: () async {
              if (!await _confirmComplete()) return;
              await _do('complete', () async {
                await ref
                    .read(eventsRepositoryProvider)
                    .setEventStatus(e.id, 'completed');
              });
            },
            onReset: () => _do('reset', () async {
              await ref.read(eventsRepositoryProvider).resetTeams(e.id);
              ref.invalidate(eventTeamsProvider(e.id));
            }),
          ),
          const SizedBox(height: 12),
        ],
        if (e.status == 'kicked_off' && (e.canManage || e.hasLatePool)) ...[
          _PoolSection(
              event: e,
              teams: teams,
              onChanged: () {
                _refetch();
                ref.invalidate(eventTeamsProvider(e.id));
                ref.invalidate(availablePoolProvider(e.id));
              }),
          const SizedBox(height: 12),
        ],
        if (e.canManage && e.interestedPeople.isNotEmpty) ...[
          _InterestedList(
              people: e.interestedPeople,
              capacity: e.capacity,
              canRelease: e.status != 'completed' && e.status != 'cancelled',
              eventId: e.id,
              onChanged: _refetch),
          const SizedBox(height: 12),
        ],
        const _PlayEnd(),
      ],
      if (e.status != 'cancelled') EventTicketsCard(eventId: e.id),
      // Cancelled + organizer → surface any refunds still outstanding, with a
      // safe (idempotent) retry.
      if (e.canManage && e.status == 'cancelled') ...[
        const SizedBox(height: 12),
        _RefundRetryCard(eventId: e.id),
      ],
      if (canCheckIn) ...[
        const SizedBox(height: 12),
        _EngageBlock(event: e, onChanged: _refetch),
      ],
      if (e.canManage && canCheckIn && e.qrCode != null) ...[
        const SizedBox(height: 12),
        _QrCard(event: e),
      ],
      if (e.isTeamFlow && e.canManage && e.status == 'open') ...[
        const SizedBox(height: 12),
        _AssignTeamsCard(
          event: e,
          busy: _busy == 'assign',
          onAssign: (count) => _do('assign', () async {
            await ref
                .read(eventsRepositoryProvider)
                .generateTeams(e.id, teamCount: count);
            // Land on Games, in view: the next step is the first match.
            if (mounted) {
              setState(() {
                _tab = 0;
                _jumpToPlay = true;
              });
            }
            ref.invalidate(eventTeamsProvider(e.id));
          }),
          onDraft: () async {
            final count = await _AssignTeamsCard.pickCount(context);
            if (count == null) return;
            await _do('draft', () async {
              await ref
                  .read(eventsRepositoryProvider)
                  .draftStart(e.id, teamCount: count);
            });
          },
        ),
      ],
      if (e.isTeamFlow && e.status == 'drafting') ...[
        const SizedBox(height: 16),
        _DraftBoard(
          eventId: e.id,
          onDone: () {
            // Draft finished: land on Games, in view.
            setState(() {
              _tab = 0;
              _jumpToPlay = true;
            });
            _refetch();
            ref.invalidate(eventTeamsProvider(e.id));
          },
        ),
      ],
      if (!showTabs) ...[
        if (e.canManage && e.interestedPeople.isNotEmpty) ...[
          const SizedBox(height: 16),
          _InterestedList(
              people: e.interestedPeople,
              capacity: e.capacity,
              canRelease: e.status != 'completed' && e.status != 'cancelled',
              eventId: e.id,
              onChanged: _refetch),
        ],
        const SizedBox(height: 16),
        _CheckinsList(event: e, onChanged: _refetch),
      ],
      if (!e.isTeamFlow &&
          e.canManage &&
          e.status == 'open' &&
          !_isPast(e) &&
          e.attendeeCount >= 1) ...[
        const SizedBox(height: 14),
        SpButton(
          label: 'Complete event',
          icon: Icons.flag_outlined,
          expand: true,
          onTap: _busy != null
              ? null
              : () async {
                  if (!await _confirmComplete()) return;
                  await _do('complete', () async {
                    await ref
                        .read(eventsRepositoryProvider)
                        .setEventStatus(e.id, 'completed');
                  });
                },
        ),
      ],
      if (e.canManage && e.status != 'completed' && _isPast(e)) ...[
        const SizedBox(height: 14),
        SpButton(
          label: 'Close this past event',
          icon: Icons.flag_outlined,
          expand: true,
          onTap: _busy != null ? null : () => _closePast(e),
        ),
      ],
      if (e.canManage &&
          e.status != 'completed' &&
          e.status != 'cancelled') ...[
        const SizedBox(height: 10),
        Material(
          color: p.liveTint,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: _busy != null ? null : () => _cancelEvent(e),
            child: SizedBox(
              height: 50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy_outlined, size: 17, color: p.danger),
                  const SizedBox(width: 7),
                  Text('Cancel event',
                      style: TextStyle(
                          color: p.danger,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ],
      // Owner-console ad spot (anchor "event.detail_bottom"); nothing unless set.
      const AdAnchor(
          anchor: 'event.detail_bottom',
          padding: EdgeInsets.only(top: 14)),
    ];
    // The cover + title card is full-bleed; everything else sits in the
    // 20px page gutter. Pin the Games / Teams / Check-ins switch while
    // everything above scrolls away — same behaviour as the group page.
    final hero = SliverToBoxAdapter(
      child: _EventHero(
        event: e,
        onShare: () => _share(e),
        onEdit: e.canManage && e.status == 'open' ? () => _openEdit(e) : null,
        menu: EventMenuButton(
          event: e,
          onPhotos: e.canManage && e.status != 'completed'
              ? () => _openPhotos()
              : null,
        ),
      ),
    );
    final ti = children.indexWhere((w) => w is _TabRow);
    final te = children.indexWhere((w) => w is _PlayEnd);
    if (ti < 0) {
      return CustomScrollView(slivers: [
        hero,
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
          sliver: SliverList(delegate: SliverChildListDelegate(children)),
        ),
      ]);
    }
    return CustomScrollView(slivers: [
      hero,
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        sliver: SliverList(
            delegate: SliverChildListDelegate(children.sublist(0, ti))),
      ),
      // The switch stays pinned only while its own section (the tabs'
      // content, team controls, pool) is on screen, then scrolls away with
      // it — tickets, check-in and the rest follow below.
      SliverMainAxisGroup(slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedTabs(
            child: Container(
              color: p.bg,
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
              child: children[ti],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          sliver: SliverList(
              delegate: SliverChildListDelegate(
                  children.sublist(ti + 1, te < 0 ? children.length : te))),
        ),
      ]),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
        sliver: SliverList(
            delegate: SliverChildListDelegate(
                te < 0 ? const <Widget>[] : children.sublist(te + 1))),
      ),
    ]);
  }

  Future<void> _cancelEvent(EventDetail e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this event?'),
        content: Text(
          '${e.repeats ? _cancelRepeatingCopy : _cancelOnceCopy}\n\n$_processingFeeNote',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel event')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _busy = 'cancel');
    try {
      final r = await ref.read(eventsRepositoryProvider).cancelEvent(e.id);
      final refunded = (r['refunded'] as num?)?.toInt() ?? 0;
      messenger.showSnackBar(SnackBar(
          content: Text(r['deleted'] == true
              ? 'Event deleted'
              : r['queued'] == true
                  ? 'Event cancelled — ticket refunds are processing.'
                  : refunded > 0
                      ? 'Event cancelled — refunded $refunded ticket holder${refunded == 1 ? '' : 's'}.'
                      : 'Event cancelled')));
      if (router.canPop()) router.pop();
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text('$err')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _closePast(EventDetail e) async {
    bool recreate = false;
    if (e.repeats) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Repeat this event?'),
          content: Text(
              'This event repeats ${_recurrenceLabel(e.recurrence)}. Create the next occurrence when you close this one?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'end'),
                child: const Text('Just end it')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'recreate'),
                child: const Text('End & recreate')),
          ],
        ),
      );
      if (choice == null) return;
      recreate = choice == 'recreate';
    }
    await _do('close', () async {
      await ref
          .read(eventsRepositoryProvider)
          .completeEvent(e.id, recreate: recreate);
    });
  }

  String _recurrenceLabel(String r) {
    switch (r) {
      case 'daily':
        return 'every day';
      case 'weekly':
        return 'every week';
      case 'biweekly':
        return 'every 2 weeks';
      case 'monthly':
        return 'every month';
      case 'yearly':
        return 'every year';
      default:
        return r;
    }
  }
}

// ---------------------------------------------------------------------------
// Hero (2026) — edge-to-edge cover (photos, or a drawn pitch) with floating
// back / edit / share, and the title card overlapping its bottom edge:
// sport, level and status pills, title, group, when / where, the headline
// numbers and the description.
// ---------------------------------------------------------------------------

class _EventHero extends StatefulWidget {
  const _EventHero(
      {required this.event, required this.onShare, this.onEdit, this.menu});
  final EventDetail event;
  final VoidCallback onShare;
  final VoidCallback? onEdit;

  /// The "More" menu (EventMenuButton), beside Share.
  final Widget? menu;

  @override
  State<_EventHero> createState() => _EventHeroState();
}

class _EventHeroState extends State<_EventHero> {
  static const double _coverH = 250;
  static const double _overlap = 48;
  int _page = 0;
  bool _more = false;

  static const _competitive = {
    'non_competitive': 'Non-competitive',
    'moderate': 'Moderately competitive',
    'high': 'Highly competitive',
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = widget.event;
    final images = <String>[
      if (e.thumbnailUrl != null) e.thumbnailUrl!,
      ...e.images.where((x) => x != e.thumbnailUrl),
    ];

    Widget pitch() => CustomPaint(
          painter: _CoverPitch(const Color(0xFF1E6B45)),
          child: Center(
            child: Text(e.categoryEmoji ?? '',
                style: const TextStyle(fontSize: 56)),
          ),
        );

    Widget image(String url) => CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: _coverH,
          errorWidget: (_, __, ___) => pitch(),
        );

    final cover = ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: SizedBox(
        height: _coverH,
        width: double.infinity,
        child: Stack(fit: StackFit.expand, children: [
          if (images.isEmpty)
            pitch()
          else if (images.length == 1)
            image(images.first)
          else
            PageView.builder(
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => image(images[i]),
            ),
          // Shade the top so the round buttons read on any photo.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x59000000), Color(0x00000000)],
                  stops: [0.0, 0.45],
                ),
              ),
            ),
          ),
          if (images.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: _overlap + 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < images.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color:
                            i == _page ? Colors.white : const Color(0x80FFFFFF),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
        ]),
      ),
    );

    final canPop = context.canPop() || Navigator.of(context).canPop();
    return Stack(children: [
      Positioned(left: 0, right: 0, top: 0, child: cover),
      Positioned(
        left: 16,
        top: 12,
        child: SpRoundButton(
          icon: canPop ? Icons.arrow_back_ios_new_rounded : Icons.home_outlined,
          iconSize: canPop ? 18 : 21,
          tooltip: canPop ? 'Back' : 'Home',
          onTap: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      Positioned(
        right: 16,
        top: 12,
        child: Row(children: [
          if (widget.onEdit != null) ...[
            SpRoundButton(
                icon: Icons.edit_outlined,
                tooltip: 'Edit event',
                onTap: widget.onEdit!),
            const SizedBox(width: 8),
          ],
          SpRoundButton(
              icon: Icons.ios_share_rounded,
              tooltip: 'Share',
              onTap: widget.onShare),
          if (widget.menu != null) ...[
            const SizedBox(width: 8),
            widget.menu!,
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, _coverH - _overlap, 16, 0),
        child: _titleCard(context, p, e),
      ),
    ]);
  }

  Widget _pill(String label, Color bg, Color fg,
          {IconData? icon, bool dot = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot) ...[
            Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ] else if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          // Flexible: long team names ("For U12 Lions, U14 Hawks") ellipsize
          // inside the header Wrap instead of overflowing.
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  Widget _titleCard(BuildContext context, AppPalette p, EventDetail e) {
    final time = [
      formatClock(e.startTime),
      if (e.endTime != null) formatClock(e.endTime),
    ].where((s) => s != null && s.isNotEmpty).join(' – ');
    final level =
        e.competitiveLevel != null ? _competitive[e.competitiveLevel!] : null;
    final status = switch (e.status) {
      'open' => _pill('Open', p.accentTint, p.greenText, dot: true),
      'drafting' => _pill('Drafting', p.orangeTint, p.orangeInk),
      'kicked_off' => _pill('Live', p.liveTint, p.danger, dot: true),
      'completed' => _pill('Completed', p.surface2, p.muted),
      'cancelled' => _pill('Cancelled', p.liveTint, p.danger),
      _ => null,
    };
    final desc = e.description?.trim() ?? '';

    Widget stat(String value, String label, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 20,
                      height: 1.1,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(color: p.muted, fontSize: 11)),
            ]),
          ),
        );

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (e.categoryName != null)
            _pill(
                '${e.categoryEmoji != null ? '${e.categoryEmoji} ' : ''}${e.categoryName}',
                p.accentTint,
                p.greenText),
          if (level != null) _pill(level, p.orangeTint, p.orangeInk),
          if (status != null) status,
          if (e.isPrivate)
            _pill(e.audienceTeams.isEmpty ? 'Members only' : 'Team only',
                p.surface2, p.muted,
                icon: Icons.lock_outline_rounded),
          // Team event: "For U12 Lions".
          if (audienceLabel(e.audienceTeams) case final String who)
            _pill(who, p.accentTint, p.greenText, icon: Icons.shield_outlined),
        ]),
        const SizedBox(height: 12),
        Text(e.title,
            style: TextStyle(
                color: p.ink,
                fontSize: 22,
                height: 1.25,
                letterSpacing: -0.3,
                fontWeight: FontWeight.w800)),
        if (e.groupName != null) ...[
          const SizedBox(height: 4),
          InkWell(
            onTap: e.groupId == null
                ? null
                : () => context.push('/groups/${e.groupId}'),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: p.accent, shape: BoxShape.circle)),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(e.groupName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (e.eventDate != null)
          InfoRow(Icons.calendar_today_rounded, formatDayYear(e.eventDate)),
        if (time.isNotEmpty) InfoRow(Icons.schedule_rounded, time),
        EventTicketedLine(eventId: e.id),
        if (e.locationName != null)
          InfoRow(
            Icons.place_outlined,
            e.locationName!,
            trailing: Material(
              color: p.accentTint,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => _openMaps(e),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.near_me_outlined, size: 13, color: p.greenText),
                    const SizedBox(width: 4),
                    Text('Directions',
                        style: TextStyle(
                            color: p.greenText,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
          ),
        const SizedBox(height: 14),
        Row(children: [
          stat('${e.interestCount}',
              e.capacity.rsvpRequired ? 'Going' : 'RSVPs', p.ink),
          const SizedBox(width: 8),
          stat('${e.attendeeCount}', 'Checked in', p.greenText),
          const SizedBox(width: 8),
          if (e.capacity.capped)
            stat(
                e.capacity.full ? 'Full' : '${e.capacity.spotsLeft}',
                e.capacity.full
                    ? 'of ${e.capacity.maxPlayers} spots'
                    : 'Spots left',
                e.capacity.full ? p.muted : p.ink)
          else if (e.typicalAttendance != null)
            stat('~${e.typicalAttendance}', 'Usually', p.ink)
          else
            stat(e.myCheckedIn ? 'In' : '—', 'You',
                e.myCheckedIn ? p.greenText : p.muted),
        ]),
        if (desc.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(desc,
              maxLines: _more ? null : 4,
              overflow: _more ? TextOverflow.visible : TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.55)),
          if (desc.length > 180 || '\n'.allMatches(desc).length > 3)
            GestureDetector(
              onTap: () => setState(() => _more = !_more),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_more ? 'Show less' : 'Read more',
                    style: TextStyle(
                        color: p.greenText,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ]),
    );
  }

  Future<void> _openMaps(EventDetail e) async {
    final query = e.locationLat != null && e.locationLng != null
        ? '${e.locationLat},${e.locationLng}'
        : Uri.encodeComponent(e.locationName ?? '');
    final url =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}

/// A plain pitch — the cover when an event has no photo.
class _CoverPitch extends CustomPainter {
  _CoverPitch(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final line = Paint()
      ..color = const Color(0x24FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final r = Rect.fromLTWH(20, 20, size.width - 40, size.height - 40);
    canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(8)), line);
    canvas.drawLine(
        Offset(size.width / 2, r.top), Offset(size.width / 2, r.bottom), line);
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 34, line);
    canvas.drawRect(Rect.fromLTWH(r.left, size.height / 2 - 40, 44, 80), line);
    canvas.drawRect(
        Rect.fromLTWH(r.right - 44, size.height / 2 - 40, 44, 80), line);
  }

  @override
  bool shouldRepaint(covariant _CoverPitch old) => old.color != color;
}

// ---------------------------------------------------------------------------
// Hosted by — group card with Follow.
// ---------------------------------------------------------------------------

class _HostedByCard extends ConsumerStatefulWidget {
  const _HostedByCard(
      {required this.groupId,
      required this.name,
      this.imageUrl,
      this.verified = false});
  final String groupId;
  final String name;
  final String? imageUrl;
  final bool verified;

  @override
  ConsumerState<_HostedByCard> createState() => _HostedByCardState();
}

class _HostedByCardState extends ConsumerState<_HostedByCard> {
  bool? _following;
  int _followers = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st =
          await ref.read(eventsRepositoryProvider).followState(widget.groupId);
      if (mounted) {
        setState(() {
          _following = st.following;
          _followers = st.followers;
        });
      }
    } catch (_) {
      // Card still renders without follow state.
    }
  }

  Future<void> _toggle() async {
    final was = _following ?? false;
    setState(() {
      _busy = true;
      _following = !was;
      _followers += was ? -1 : 1;
    });
    try {
      await ref.read(eventsRepositoryProvider).setFollow(widget.groupId, !was);
    } catch (e) {
      if (mounted) {
        setState(() {
          _following = was;
          _followers += was ? 1 : -1;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final following = _following ?? false;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Hosted by'),
          const SizedBox(height: 10),
          Row(children: [
            InkWell(
              onTap: () => context.push('/groups/${widget.groupId}'),
              child:
                  Crest(logoUrl: widget.imageUrl, label: widget.name, size: 48),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () => context.push('/groups/${widget.groupId}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(widget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5)),
                      ),
                      if (widget.verified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 16),
                      ],
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: p.muted),
                    ]),
                    Text(
                      '$_followers follower${_followers == 1 ? '' : 's'}',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: following ? p.surface2 : p.hero,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _busy || _following == null ? null : _toggle,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    following ? 'Following' : 'Follow',
                    style: TextStyle(
                      color: following ? p.ink : p.onHero,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Interest + check-in block (web: pink interest button + check-in state).
// ---------------------------------------------------------------------------

class _EngageBlock extends ConsumerStatefulWidget {
  const _EngageBlock({required this.event, required this.onChanged});
  final EventDetail event;
  final VoidCallback onChanged;

  @override
  ConsumerState<_EngageBlock> createState() => _EngageBlockState();
}

class _EngageBlockState extends ConsumerState<_EngageBlock> {
  bool _busy = false;
  Future<void> _toggleInterest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final going = await ref
          .read(eventsRepositoryProvider)
          .toggleInterest(widget.event.id);
      widget.onChanged();
      // Gamification is reactive (server-side, in the same request): an
      // RSVP moves "Your week", taking it back undoes it.
      _refreshProgression(ref);
      // What the RSVP means — and, on a paid-spot event, the way to lock it in.
      if (going && mounted) {
        await RsvpInfoSheet.maybeShow(context, ref,
            eventId: widget.event.id,
            rsvpRequired: widget.event.capacity.rsvpRequired);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Guardians: RSVP themselves and/or their wards from one sheet.
  Future<void> _pickWhoIsGoing() async {
    if (_busy) return;
    final joined = await showWhoIsGoingSheet(context, event: widget.event);
    if (!mounted) return;
    widget.onChanged();
    _refreshProgression(ref);
    if (joined == true) {
      await RsvpInfoSheet.maybeShow(context, ref,
          eventId: widget.event.id,
          rsvpRequired: widget.event.capacity.rsvpRequired);
    }
  }

  Future<void> _checkOut() async {
    if (_busy) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check out of this event?'),
        content: Text(
            widget.event.canManage
                ? "You'll be taken off the attendee list. To check in again, scan another admin's QR."
                : "You'll be taken off the attendee list. You can check in again by scanning the event QR."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay checked in')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Check out',
                  style: TextStyle(color: Color(0xFFDC2626)))),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(eventsRepositoryProvider).checkOut(widget.event.id);
      widget.onChanged();
      _refreshProgression(ref);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = widget.event;
    final open = e.status == 'open';
    // Guardians RSVP for themselves and their wards through one sheet.
    final hasWards = e.myWards.isNotEmpty;
    final goingNames = [
      if (e.myInterested) 'You',
      for (final w in e.myWards)
        if (w.interested) w.firstName,
    ];
    final going = hasWards ? goingNames.isNotEmpty : e.myInterested;
    // "RSVP required" + every spot taken, and the viewer holds none of them.
    final spotsGone = e.capacity.rsvpRequired && e.capacity.full && !going;
    final wardChips = [
      for (final w in e.myWards)
        if (w.checkedIn)
          SpBadge('${w.firstName} · checked in',
              icon: Icons.check_circle_rounded, tone: p.greenText)
        else if (w.interested)
          SpBadge('${w.firstName} · going',
              icon: Icons.event_available_rounded),
    ];

    Widget pill({
      required String label,
      required IconData icon,
      required Color bg,
      required Color fg,
      VoidCallback? onTap,
      Color? border,
    }) =>
        Material(
          color: bg,
          shape: StadiumBorder(
              side:
                  border != null ? BorderSide(color: border) : BorderSide.none),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: SizedBox(
              height: 52,
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: fg,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        );

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (e.capacity.shows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SpotsBanner(capacity: e.capacity, myInterested: going),
            ),
          if (e.myCheckedIn)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: p.accentTint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                Icon(Icons.check_circle_rounded, size: 20, color: p.greenText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text("You're checked in",
                      style: TextStyle(
                          color: p.greenText,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          Row(children: [
            if (open)
              Expanded(
                child: pill(
                  label: spotsGone
                      ? 'Full'
                      : hasWards
                          ? (going
                              ? 'Going: ${goingNames.join(', ')}'
                              : "RSVP — who's going?")
                          : (e.myInterested
                              ? "You're going"
                              : "RSVP — I'm in"),
                  icon: spotsGone
                      ? Icons.lock_outline
                      : going
                          ? Icons.event_available_rounded
                          : Icons.add_rounded,
                  bg: spotsGone
                      ? p.surface2
                      : going
                          ? p.accentTint
                          : p.hero,
                  fg: spotsGone
                      ? p.muted
                      : going
                          ? p.greenText
                          : p.onHero,
                  onTap: _busy || spotsGone
                      ? null
                      : (hasWards ? _pickWhoIsGoing : _toggleInterest),
                ),
              ),
            if (open && e.myCheckedIn) const SizedBox(width: 10),
            if (open && e.myCheckedIn)
              Expanded(
                child: pill(
                  label: 'Check out',
                  icon: Icons.logout_rounded,
                  bg: p.surface,
                  fg: p.danger,
                  border: p.danger.withAlpha(90),
                  onTap: _busy ? null : _checkOut,
                ),
              ),
          ]),
          if (wardChips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: wardChips),
          ],
          // Organisers scan ANOTHER admin's QR — their own QR names them, so
          // scanning it from a second phone is refused.
          if (e.canManage && !e.myCheckedIn) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: p.surface2,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified_user_outlined,
                      size: 16, color: p.greenText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                        "To check yourself in, scan the QR on another admin's phone — not your own.",
                        style: TextStyle(color: p.muted, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
          // A guardian who's already in can still scan for a ward.
          if (!e.myCheckedIn || e.myWards.any((w) => !w.checkedIn)) ...[
            if (open) const SizedBox(height: 10),
            pill(
              label: 'Scan to check in',
              icon: Icons.qr_code_scanner_rounded,
              bg: p.accentDeep,
              fg: Colors.white,
              onTap: () async {
                await context.push('/scan');
                widget.onChanged();
              },
            ),
            const SizedBox(height: 8),
            Text(
              e.status == 'kicked_off'
                  ? 'Teams are already set — scan the event QR at the venue to join the available pool.'
                  : "Scan the event's QR code at the venue to check in.",
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ],
          if (open && hasWards) ...[
            const SizedBox(height: 2),
            Text(
                'Tap the RSVP button to choose who’s going — you and your wards.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 11.5)),
          ] else if (open && e.myInterested && !e.myCheckedIn) ...[
            const SizedBox(height: 2),
            Text('Tap “You\'re going” to take your RSVP back.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Organizer QR — players scan this at the venue.
// ---------------------------------------------------------------------------

/// "See event QR code" — under Hosted by once the matches section has pushed
/// the QR card down the page; opens the live QR in a sheet.
class _QrShortcut extends StatelessWidget {
  const _QrShortcut({required this.onTap});
  final void Function(BuildContext from) onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.muted.withAlpha(40)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onTap(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: p.accentTint,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.qr_code_2_rounded, size: 19, color: p.greenText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('See event QR code',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  Text('Show it for late check-ins',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
          ]),
        ),
      ),
    );
  }
}

/// Marks the end of the post-assignment section (see `_body`'s slivers).
class _PlayEnd extends StatelessWidget {
  const _PlayEnd();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    return GlassCard(
      child: Column(children: [
        Text('Check-in QR',
            style: TextStyle(
                color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          e.status == 'kicked_off'
              ? 'Teams are set — late arrivals who scan this join the available pool.'
              : 'Show this at the venue — players scan it to check in.',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.muted, fontSize: 11.5),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: _LiveQr(event: e, size: 190),
        ),
        const SizedBox(height: 8),
        Text('Refreshes every 30 seconds — screenshots won’t work.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 11)),
        // "Check someone in" (manual_checkin_sheet.dart) is hidden until
        // further notice.
      ]),
    );
  }
}

/// The organiser's live check-in QR. It names this organiser and lapses in
/// ~2 minutes (server checkinQr.ts), so it's refetched every
/// `refreshSeconds` while on screen and on returning to the app — a
/// screenshot or printout stops checking people in, and scanning your OWN
/// QR is refused. Used by the QR card and the "See event QR code" sheet.
class _LiveQr extends ConsumerStatefulWidget {
  const _LiveQr({required this.event, required this.size});
  final EventDetail event;
  final double size;

  @override
  ConsumerState<_LiveQr> createState() => _LiveQrState();
}

class _LiveQrState extends ConsumerState<_LiveQr> with WidgetsBindingObserver {
  String? _value;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back on screen: the one shown may have lapsed in the background.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    _timer?.cancel();
    var every = 30;
    try {
      final r =
          await ref.read(eventsRepositoryProvider).checkInQr(widget.event.id);
      final v = r['value'];
      every = (r['refreshSeconds'] as num?)?.toInt() ?? 30;
      if (mounted && v is String && v.isNotEmpty) setState(() => _value = v);
    } catch (_) {
      // Keep the last one; try again sooner.
      every = 10;
    }
    if (!mounted) return;
    // Two refreshes can overlap (resume + timer): keep a single timer.
    _timer?.cancel();
    _timer = Timer(Duration(seconds: every.clamp(5, 60)), _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final value = _value ?? widget.event.qrCode ?? '';
    return QrImageView(
      data: value,
      size: widget.size,
      backgroundColor: Colors.white,
    );
  }
}

// ---------------------------------------------------------------------------
// Assign teams (organizer, open) — count picker → shuffle + kickoff.
// ---------------------------------------------------------------------------

class _AssignTeamsCard extends StatelessWidget {
  const _AssignTeamsCard(
      {required this.event,
      required this.busy,
      required this.onAssign,
      required this.onDraft});
  final EventDetail event;
  final bool busy;
  final void Function(int count) onAssign;
  final VoidCallback onDraft;

  static Future<int?> pickCount(BuildContext context) {
    return showSpSheet<int>(
      context,
      builder: (ctx) {
        final p = ctx.palette;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How many teams?',
                style: TextStyle(
                    color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
                'Checked-in players are shuffled evenly and the event kicks off.',
                style: TextStyle(color: p.muted, fontSize: 12.5)),
            const SizedBox(height: 14),
            Wrap(spacing: 10, children: [
              for (final n in [2, 3, 4, 5, 6])
                Material(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(ctx, n),
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.line),
                      ),
                      child: Text('$n',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
            ]),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.bolt_rounded, size: 16, color: p.amber),
            const SizedBox(width: 6),
            Text('Assign teams',
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text(
            'Assign the ${e.attendeeCount} checked-in player${e.attendeeCount == 1 ? '' : 's'} into teams — ${e.smartShuffle ? 'smart' : 'random'} shuffle.',
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SpButton(
            label: 'Assign teams',
            icon: Icons.bolt_rounded,
            expand: true,
            onTap: busy || e.attendeeCount < 1
                ? null
                : () async {
                    final count = await pickCount(context);
                    if (count != null) onAssign(count);
                  },
          ),
          const SizedBox(height: 8),
          Center(
            child: InkWell(
              onTap: busy || e.attendeeCount < 2 ? null : () => onDraft(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Or run a live captain draft',
                  style: TextStyle(
                      color: p.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Organizer controls after teams are assigned.
// ---------------------------------------------------------------------------

class _OrganizerTeamControls extends StatelessWidget {
  const _OrganizerTeamControls({
    required this.hasGames,
    required this.busy,
    required this.onReshuffle,
    required this.onComplete,
    required this.onReset,
  });
  final bool hasGames;
  final String? busy;
  final VoidCallback onReshuffle;
  final VoidCallback onComplete;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (!hasGames)
            _chip(context, 'Reshuffle', Icons.replay_rounded,
                busy == null ? onReshuffle : null),
          _chip(context, 'Complete', Icons.flag_outlined,
              busy == null ? onComplete : null),
          if (!hasGames)
            _chip(context, 'Reset teams', Icons.delete_outline_rounded,
                busy == null ? onReset : null),
        ]),
        if (hasGames) ...[
          const SizedBox(height: 6),
          Text(
            'Teams are locked while this event has games. Add late players from the pool, or make substitutions during a game.',
            style: TextStyle(color: p.muted, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _chip(
      BuildContext context, String label, IconData icon, VoidCallback? onTap) {
    final p = context.palette;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: p.accent),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab row — Games / Teams / Check-ins (web TabBtn replica).
// ---------------------------------------------------------------------------

class _TabRow extends StatelessWidget {
  const _TabRow(
      {required this.tab, required this.onChanged, this.showGames = true});
  final int tab;
  final ValueChanged<int> onChanged;
  // Web: the Games tab only exists when the group tier can create games.
  final bool showGames;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      if (showGames) (0, Icons.sports_soccer_rounded, 'Games'),
      (1, Icons.shield_outlined, 'Teams'),
      (2, Icons.how_to_reg_outlined, 'Check-ins'),
    ];
    final at = tabs.indexWhere((t) => t.$1 == tab);
    return SpSegmented(
      options: [for (final t in tabs) t.$3],
      icons: [for (final t in tabs) t.$2],
      index: at < 0 ? 0 : at,
      onChanged: (i) => onChanged(tabs[i].$1),
    );
  }
}

// ---------------------------------------------------------------------------
// Games tab — match list + "New match" (organizer).
// ---------------------------------------------------------------------------

class _GamesTab extends ConsumerWidget {
  const _GamesTab(
      {required this.event, required this.teams, required this.onChanged});
  final EventDetail event;
  final List<EventTeam> teams;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final games = ref.watch(eventGamesProvider(event.id));
    final list = games.valueOrNull ?? const <GameSummary>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Starting another match is never below the fold: the big button
        // leads the tab as soon as there's a game (the empty state has its
        // own "Start the first match" below).
        if (event.canManage && teams.length >= 2 && list.isNotEmpty) ...[
          SpButton(
            label: 'New match',
            icon: Icons.add_rounded,
            expand: true,
            onTap: () => _createMatch(context, ref),
          ),
          const SizedBox(height: 12),
        ],
        if (list.isEmpty && event.canManage)
          // The step most organisers miss: teams are assigned and nothing
          // says the match itself is something you start. Make it the
          // obvious next action, with the reason.
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: p.accent.withAlpha(30), shape: BoxShape.circle),
                    child: Icon(Icons.auto_awesome_rounded,
                        size: 16, color: p.accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            teams.length >= 2
                                ? 'Teams are set — next, start the match'
                                : 'Assign teams, then start the match',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'A match runs the clock and score live, records every goal, assist and card, and feeds the leaderboard. Without one, today leaves no stats behind.',
                            style: TextStyle(
                                color: p.muted, fontSize: 12, height: 1.35),
                          ),
                        ]),
                  ),
                ]),
                const SizedBox(height: 10),
                const Row(children: [
                  _NextStepChip(
                      icon: Icons.timer_outlined, label: 'Live score'),
                  SizedBox(width: 6),
                  _NextStepChip(icon: Icons.bar_chart_rounded, label: 'Stats'),
                  SizedBox(width: 6),
                  _NextStepChip(
                      icon: Icons.emoji_events_outlined, label: 'Leaderboard'),
                ]),
              ],
            ),
          )
        else if (list.isEmpty)
          GlassCard(
            child: Text('No games yet.',
                style: TextStyle(color: p.muted, fontSize: 13)),
          )
        else
          for (final g in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                onTap: () => context.push('/games/${g.id}'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      g.teams.map((t) => t.name).join(' vs '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    g.teams.map((t) => '${t.score}').join(' – '),
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 10),
                  SpBadge(
                    g.status == 'live'
                        ? 'LIVE'
                        : g.status == 'completed'
                            ? 'FT'
                            : g.status == 'abandoned'
                                ? 'ABD'
                                : 'SCHED',
                    tone: g.status == 'live' ? p.danger : p.muted,
                  ),
                  if (event.canManage && g.status != 'live') ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _deleteGame(context, ref, g.id),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline,
                            size: 17, color: p.muted),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
        if (event.canManage && teams.length >= 2 && list.isEmpty) ...[
          const SizedBox(height: 4),
          SpButton(
            label: 'Start the first match',
            icon: Icons.add_rounded,
            expand: true,
            onTap: () => _createMatch(context, ref),
          ),
        ] else if (event.canManage) ...[
          const SizedBox(height: 4),
          const SpButton(
            label: 'Assign teams first',
            icon: Icons.groups_outlined,
            expand: true,
            onTap: null,
          ),
        ],
      ],
    );
  }

  Future<void> _deleteGame(
      BuildContext context, WidgetRef ref, String gameId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this game?'),
        content: const Text(
            'The game and any recorded stats are removed. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(eventsRepositoryProvider).deleteGame(event.id, gameId);
      ref.invalidate(eventGamesProvider(event.id));
      onChanged();
      messenger.showSnackBar(const SnackBar(content: Text('Game deleted')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _createMatch(BuildContext context, WidgetRef ref) async {
    // Web GamesSection parity: VS sports (maxTeamsPerGame == 2, e.g. soccer)
    // pick two explicit teams with optional Home & Away; other sports pick
    // 2+ teams. Both support per-game team colors and officiants.
    final vsMode = event.maxTeamsPerGame == 2;
    final selected = <String>{};
    String? homeId;
    String? awayId;
    var useHomeAway = false;
    var uniqueColors = false;
    final colorMap = <String, String>{};
    final officiants = <String>{};
    var useOfficiants = false;
    var officiantQuery = '';
    final duration = TextEditingController();
    // Basketball: quarters or first-to-N, and the foul rules.
    final isBb = isBasketballSport(event.categoryName, event.categoryEmoji);
    var bbRules = const BasketballRules();
    // Volleyball: one set, best of 3 or best of 5.
    final isVb = isVolleyballSport(event.categoryName, event.categoryEmoji);
    var vbRules = const VolleyballRules();
    const palette = [
      '#22C55E',
      '#3B82F6',
      '#EAB308',
      '#EF4444',
      '#8B5CF6',
      '#EC4899',
      '#F97316',
      '#14B8A6',
    ];
    // Officiant candidates — same rule as web and as the server's own
    // validation: a group event offers the group's FULL roster (any admin or
    // member, checked in or not); a non-group event falls back to the
    // people who checked in. Using the paginated members page here used to
    // hide everyone past the first 18, and non-group events offered nobody.
    List<GroupMemberItem> candidates = const [];
    if (event.groupId != null) {
      try {
        candidates =
            await ref.read(groupAllMembersProvider(event.groupId!).future);
      } catch (_) {
        candidates = const [];
      }
    } else {
      candidates = [
        for (final a in event.attendees)
          GroupMemberItem(
            userId: a.userId,
            displayName: a.displayName,
            username: a.username,
            avatarUrl: a.avatarUrl,
            isWard: a.isWard,
          ),
      ];
    }
    // Wards can't sign in to run a game, so they never officiate.
    candidates = [
      for (final c in candidates)
        if (!c.isWard) c
    ]..sort((a, b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
    if (!context.mounted) return;

    Color hexColor(String? hex) {
      var h = (hex ?? '#22C55E').replaceAll('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.tryParse(h, radix: 16) ?? 0xFF22C55E);
    }

    List<String> pickedIds() => vsMode
        ? [if (homeId != null) homeId!, if (awayId != null) awayId!]
        : selected.toList();

    final ok = await showSpSheet<bool>(
      context,
      framed: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final p = ctx.palette;
          final canCreate = vsMode
              ? homeId != null && awayId != null && homeId != awayId
              : selected.length >= 2;

          Widget teamDropdown(
              String label, String? value, ValueChanged<String?> onChanged) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: p.muted, fontSize: 11.5)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  key: ValueKey('$label-$value'),
                  initialValue: value,
                  isExpanded: true,
                  hint: Text('Pick a team',
                      style: TextStyle(color: p.muted, fontSize: 13)),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  items: [
                    for (final t in teams)
                      DropdownMenuItem(
                        value: t.id,
                        child: Row(children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: hexColor(t.color),
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(t.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.ink, fontSize: 13.5)),
                          ),
                        ]),
                      ),
                  ],
                  onChanged: onChanged,
                ),
              ],
            );
          }

          return Container(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.9),
            decoration: BoxDecoration(
              color: p.bg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            // Rise above the keyboard so every field stays reachable.
            padding: EdgeInsets.fromLTRB(
                20, 18, 20, 28 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Create a game',
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (vsMode) ...[
                    teamDropdown(useHomeAway ? 'Home team' : 'Team 1', homeId,
                        (v) => setSheet(() => homeId = v)),
                    const SizedBox(height: 10),
                    teamDropdown(useHomeAway ? 'Away team' : 'Team 2', awayId,
                        (v) => setSheet(() => awayId = v)),
                    if (homeId != null && homeId == awayId)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Pick two different teams.',
                            style: TextStyle(color: p.danger, fontSize: 11.5)),
                      ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: useHomeAway,
                      onChanged: (v) => setSheet(() => useHomeAway = v == true),
                      title: Text('Use Home & Away',
                          style: TextStyle(color: p.ink, fontSize: 14)),
                    ),
                  ] else ...[
                    Text('Teams (pick 2 or more)',
                        style: TextStyle(color: p.muted, fontSize: 11.5)),
                    for (final t in teams)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: selected.contains(t.id),
                        onChanged: (v) => setSheet(() {
                          if (v == true) {
                            selected.add(t.id);
                          } else {
                            selected.remove(t.id);
                          }
                        }),
                        title: Text(t.name,
                            style: TextStyle(color: p.ink, fontSize: 14)),
                      ),
                  ],
                  // Per-game color overrides (web "Use unique team colors").
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: uniqueColors,
                    onChanged: (v) => setSheet(() => uniqueColors = v == true),
                    title: Text('Use unique team colors',
                        style: TextStyle(color: p.ink, fontSize: 14)),
                  ),
                  if (uniqueColors)
                    if (pickedIds().isEmpty)
                      Text('Pick teams above to set their colors.',
                          style: TextStyle(color: p.muted, fontSize: 11.5))
                    else
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: p.line),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final tid in pickedIds()) ...[
                              Builder(builder: (_) {
                                final t =
                                    teams.where((x) => x.id == tid).toList();
                                final name =
                                    t.isNotEmpty ? t.first.name : 'Team';
                                return Text(name,
                                    style: TextStyle(
                                        color: p.ink,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600));
                              }),
                              const SizedBox(height: 5),
                              Wrap(
                                spacing: 7,
                                children: [
                                  for (final c in palette)
                                    InkWell(
                                      onTap: () =>
                                          setSheet(() => colorMap[tid] = c),
                                      borderRadius: BorderRadius.circular(99),
                                      child: Container(
                                        width: 26,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          color: hexColor(c),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: colorMap[tid] == c
                                                ? p.ink
                                                : Colors.transparent,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                            Text(
                                "Overrides each team's default color for this game only.",
                                style:
                                    TextStyle(color: p.muted, fontSize: 10.5)),
                          ],
                        ),
                      ),
                  const SizedBox(height: 4),
                  if (isBb)
                    BasketballFormatFields(
                      value: bbRules,
                      onChanged: (v) => setSheet(() => bbRules = v),
                    )
                  else if (isVb)
                    VolleyballFormatFields(
                      value: vbRules,
                      onChanged: (v) => setSheet(() => vbRules = v),
                    )
                  else ...[
                    Row(children: [
                      Expanded(
                        child: Text('Duration (minutes, optional)',
                            style: TextStyle(color: p.muted, fontSize: 12.5)),
                      ),
                      SizedBox(
                        width: 76,
                        child: TextField(
                          controller: duration,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          style: TextStyle(color: p.ink, fontSize: 13.5),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '90',
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(color: p.line)),
                          ),
                        ),
                      ),
                    ]),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                          'A reference length — the live match clock counts up and stoppage time is added during the game.',
                          style: TextStyle(color: p.muted, fontSize: 10.5)),
                    ),
                  ],
                  ...[
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: useOfficiants,
                      onChanged: (v) =>
                          setSheet(() => useOfficiants = v == true),
                      title: Text('Use game officiants',
                          style: TextStyle(color: p.ink, fontSize: 14)),
                      subtitle: Text(
                          'Group admins can always score. Pick who else may update stats.',
                          style: TextStyle(color: p.muted, fontSize: 11)),
                    ),
                    if (useOfficiants && candidates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 6),
                        child: Text(
                            event.groupId == null
                                ? 'Nobody has checked in yet — officiants are picked from the people at the event.'
                                : 'No group members to choose from yet.',
                            style: TextStyle(color: p.muted, fontSize: 11.5)),
                      ),
                    if (useOfficiants && candidates.isNotEmpty) ...[
                      if (candidates.length > 4)
                        TextField(
                          onChanged: (v) => setSheet(() => officiantQuery = v),
                          textInputAction: TextInputAction.done,
                          style: TextStyle(color: p.ink, fontSize: 13),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Search by name or @handle',
                            prefixIcon:
                                const Icon(Icons.search_rounded, size: 18),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (final m in candidates)
                              if (officiantQuery.trim().isEmpty ||
                                  m.displayName.toLowerCase().contains(
                                      officiantQuery.trim().toLowerCase()) ||
                                  (m.username ?? '').toLowerCase().contains(
                                      officiantQuery
                                          .trim()
                                          .replaceFirst('@', '')
                                          .toLowerCase()))
                                CheckboxListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  value: officiants.contains(m.userId),
                                  onChanged: (v) => setSheet(() {
                                    if (v == true) {
                                      officiants.add(m.userId);
                                    } else {
                                      officiants.remove(m.userId);
                                    }
                                  }),
                                  title: Text(m.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: p.ink, fontSize: 13.5)),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 8),
                  SpButton(
                    label: 'Create game',
                    expand: true,
                    onTap: canCreate ? () => Navigator.pop(ctx, true) : null,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    final ids = pickedIds();
    if (ok != true || ids.length < 2) return;
    try {
      final gameId = await ref.read(eventsRepositoryProvider).createGame(
            event.id,
            ids,
            durationMinutes:
                isBb || isVb ? null : int.tryParse(duration.text.trim()),
            basketball: isBb ? bbRules.toJson() : null,
            volleyball: isVb ? vbRules.toJson() : null,
            homeTeamId: vsMode && useHomeAway ? homeId : null,
            teamColors: uniqueColors
                ? {
                    for (final tid in ids)
                      if (colorMap[tid] != null) tid: colorMap[tid]!,
                  }
                : const {},
            officiantIds: useOfficiants ? officiants.toList() : const [],
          );
      ref.invalidate(eventGamesProvider(event.id));
      onChanged();
      if (context.mounted && gameId != null && gameId.isNotEmpty) {
        context.push('/games/$gameId');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Teams tab — web EventTeamsTab replica: color-striped boxes, avatar stack,
// starter/sub counts, tap → roster sheet.
// ---------------------------------------------------------------------------

class _TeamsTab extends ConsumerWidget {
  const _TeamsTab({required this.teams});
  final List<EventTeam> teams;

  Color _color(String? hex, AppPalette p) {
    if (hex == null || hex.isEmpty) return p.accent;
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFF22C55E);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    // Web parity: outline + "You're here" on the viewer's own team.
    final meId = ref.watch(meProvider).valueOrNull?.userId;
    return Column(children: [
      for (final t in teams)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _teamBox(context, ref, t, p,
              mine: meId != null && t.players.any((x) => x.userId == meId)),
        ),
    ]);
  }

  Widget _teamBox(
      BuildContext context, WidgetRef ref, EventTeam t, AppPalette p,
      {bool mine = false}) {
    final color = _color(t.color, p);
    final starters = t.players.where((x) => !x.isSub).length;
    final subs = t.players.where((x) => x.isSub).length;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: mine ? p.accent : p.line, width: mine ? 1.6 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openRoster(context, ref, t, color),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(height: 4, color: color),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 13,
                        height: 13,
                        decoration:
                            BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(t.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5)),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: p.muted),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 28,
                      child: Stack(children: [
                        for (var i = 0;
                            i < (t.players.length > 6 ? 6 : t.players.length);
                            i++)
                          Positioned(
                            left: i * 20.0,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: p.surface, width: 2),
                              ),
                              child: ClipOval(
                                child: Crest(
                                    logoUrl: t.players[i].avatarUrl,
                                    label: t.players[i].displayName,
                                    size: 24),
                              ),
                            ),
                          ),
                        if (t.players.length > 6)
                          Positioned(
                            left: 6 * 20.0,
                            child: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: p.surface2,
                                shape: BoxShape.circle,
                                border: Border.all(color: p.surface, width: 2),
                              ),
                              child: Text('+${t.players.length - 6}',
                                  style: TextStyle(
                                      color: p.muted,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      _pill(context,
                          '$starters player${starters == 1 ? '' : 's'}'),
                      if (subs > 0) ...[
                        const SizedBox(width: 6),
                        _pill(context, '$subs sub${subs == 1 ? '' : 's'}'),
                      ],
                      if (mine) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: p.accent.withAlpha(31),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text("You're here",
                              style: TextStyle(
                                  color: p.accent,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, String text) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w600)),
    );
  }

  void _openRoster(
      BuildContext context, WidgetRef ref, EventTeam t, Color color) {
    final p = context.palette;
    showSpSheet<void>(
      context,
      framed: false,
      builder: (ctx) => Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                  width: 13,
                  height: 13,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t.name,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final x in t.players)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: ClipOval(
                        child: Crest(
                            logoUrl: x.avatarUrl,
                            label: x.displayName,
                            size: 32)),
                    title: Text(x.displayName,
                        style: TextStyle(color: p.ink, fontSize: 14)),
                    trailing: x.isSub ? const _RosterTag(text: 'SUB') : null,
                    onTap: () {
                      // Close the roster, then open their profile.
                      Navigator.of(ctx).pop();
                      openPlayerProfile(context, ref, x.userId);
                    },
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _RosterTag extends StatelessWidget {
  const _RosterTag({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: p.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              color: p.muted, fontSize: 9.5, fontWeight: FontWeight.w700)),
    );
  }
}

// ---------------------------------------------------------------------------
// RSVP list (organizer) — name chips; with "RSVP required" the chips show who
// holds a spot, and a no-show's spot can be released (web InterestedList).
// ---------------------------------------------------------------------------

class _InterestedList extends ConsumerStatefulWidget {
  const _InterestedList({
    required this.people,
    required this.capacity,
    required this.eventId,
    required this.onChanged,
    this.canRelease = false,
  });
  final List<Attendee> people;
  final EventCapacity capacity;
  final String eventId;
  final VoidCallback onChanged;
  final bool canRelease;

  @override
  ConsumerState<_InterestedList> createState() => _InterestedListState();
}

class _InterestedListState extends ConsumerState<_InterestedList> {
  String? _busy;

  Future<void> _release(Attendee x) async {
    final required = widget.capacity.rsvpRequired;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Release ${x.displayName}'s spot?"),
        content: Text(x.paid
            ? 'They paid, so their ticket price is refunded right now '
                "(service fees aren't). Their RSVP is taken back and they're "
                'notified; the spot opens for the next player.'
            : required
                ? "Their RSVP is taken back and they're notified. The spot "
                    'opens for the next player; they can RSVP again if spots '
                    'are left.'
                : "Their RSVP is taken back and they're notified. They can "
                    'RSVP again any time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(x.paid ? 'Release and refund' : 'Release spot')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = x.userId);
    try {
      final r = await ref
          .read(eventsRepositoryProvider)
          .releaseSpot(widget.eventId, x.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(!r.released
              ? 'They had no RSVP to release'
              : r.refunded
                  ? "Spot released — they've been told and their ticket "
                      'price is on its way back'
                  : "Spot released — they've been told")));
      widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _chip(Attendee x, AppPalette p) {
    final locked = widget.canRelease && x.checkedIn;
    final holding = widget.canRelease && !x.checkedIn && !x.paid && x.paying;
    // Paid players stay releasable: releasing refunds their ticket price on
    // the spot, so an organiser can make room for someone paying at the venue.
    final releasable = widget.canRelease && !x.checkedIn && !holding;
    final tail = locked || holding || releasable;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      PlayerTap(
        userId: x.userId,
        borderRadius: 999,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: x.checkedIn ? p.accentTint : p.surface2,
            borderRadius: tail
                ? const BorderRadius.horizontal(left: Radius.circular(999))
                : BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (x.checkedIn) ...[
              Icon(Icons.check_circle_rounded, size: 13, color: p.greenText),
              const SizedBox(width: 4),
            ],
            Text(x.displayName,
                style: TextStyle(
                    color: x.checkedIn ? p.greenText : p.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            if (x.isWard) ...[
              const SizedBox(width: 5),
              const WardBadge(),
            ],
            if (x.paid && !x.checkedIn) ...[
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: p.surface,
                  border: Border.all(color: p.line),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('PAID',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800)),
              ),
            ],
            if (x.paying && !x.paid) ...[
              const SizedBox(width: 4),
              Text('paying…',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 10,
                      fontStyle: FontStyle.italic)),
            ],
          ]),
        ),
      ),
      // A hold: theirs while they pay; it reopens by itself if they don't.
      if (holding)
        Tooltip(
          message:
              "Paying for this spot — it reopens by itself if they don't finish",
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 7, 9, 7),
            decoration: BoxDecoration(
              color: p.surface2,
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(999)),
            ),
            child: Text('HOLD',
                style: TextStyle(
                    color: p.muted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800)),
          ),
        ),
      // Locked: a checked-in player's spot can't be released (the server
      // refuses too) — the lock says why instead of a button that errors.
      if (locked)
        Tooltip(
          message: "Checked in — can't be released",
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 7, 9, 7),
            decoration: BoxDecoration(
              color: p.accentTint,
              borderRadius:
                  const BorderRadius.horizontal(right: Radius.circular(999)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_rounded, size: 12, color: p.greenText),
              const SizedBox(width: 3),
              Text('IN',
                  style: TextStyle(
                      color: p.greenText,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800)),
            ]),
          ),
        ),
      // Release: takes the RSVP back. For a paid player it also refunds the
      // ticket price straight away, so the tooltip says so.
      if (releasable)
        Material(
          color: p.surface2,
          borderRadius:
              const BorderRadius.horizontal(right: Radius.circular(999)),
          child: InkWell(
            onTap: _busy != null ? null : () => _release(x),
            // Long-press hint on what the button does to a paid player.
            onLongPress: !x.paid
                ? null
                : () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Releasing a paid player refunds their ticket price right away'))),
            borderRadius:
                const BorderRadius.horizontal(right: Radius.circular(999)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 9, 6),
              child: _busy == x.userId
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: p.muted))
                  : Icon(Icons.person_remove_outlined,
                      size: 14, color: p.muted),
            ),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = widget.capacity;
    final required = c.rsvpRequired;
    final people = widget.people;
    // Two groups so a checked-in player can never be mistaken for a no-show.
    final arrived = [for (final x in people) if (x.checkedIn) x];
    final holding = [for (final x in people) if (!x.checkedIn) x];
    final holdingLabel = required ? 'Holding a spot' : "RSVP'd";
    final notHereYet = arrived.isNotEmpty ? ' · not here yet' : '';
    Widget label(String text, Color color, {IconData? icon}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
            ],
            Text(text.toUpperCase(),
                style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w800)),
          ]),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SpSectionTitle(
          required ? 'Going · spots held' : 'RSVPs',
          count: c.capped ? null : people.length,
          trailing: c.capped
              ? Text(
                  '${people.length}/${c.maxPlayers}${c.full ? ' · Full' : ''}'
                  '${c.pendingHolds > 0 ? ' · ${c.pendingHolds} paying' : ''}',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700))
              : null,
        ),
        const SizedBox(height: 10),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (arrived.isNotEmpty) ...[
              label('Checked in · ${arrived.length}', p.greenText,
                  icon: Icons.check_circle_rounded),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final x in arrived) _chip(x, p),
              ]),
            ],
            if (arrived.isNotEmpty && holding.isNotEmpty)
              const SizedBox(height: 12),
            if (holding.isNotEmpty) ...[
              label(
                  '$holdingLabel · ${holding.length}$notHereYet', p.muted),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final x in holding) _chip(x, p),
              ]),
            ],
            if (widget.canRelease) ...[
              const SizedBox(height: 10),
              Text(
                  required
                      ? 'Someone not showing up? Release their spot so the next '
                          'player can RSVP. Releasing a paid player refunds '
                          'their ticket price right away; a paid no-show you '
                          "don't release is refunded once the event completes. "
                          'Checked-in players are locked.'
                      : "The remove button takes a no-show's RSVP back "
                          "(they're told). Checked-in players are locked.",
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ],
          ]),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Check-ins list — numbered roster with check-in time; organizer can check
// people out while the event is open (web CheckedInList).
// ---------------------------------------------------------------------------

class _CheckinsList extends ConsumerWidget {
  const _CheckinsList({required this.event, required this.onChanged});
  final EventDetail event;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final e = event;
    final canEdit = e.canManage && e.status == 'open';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SpSectionTitle('Checked in', count: e.attendeeCount),
        const SizedBox(height: 10),
        if (e.attendees.isEmpty)
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const SpIconTile(Icons.how_to_reg_outlined, size: 48),
              const SizedBox(height: 10),
              Text('No players checked in yet.',
                  style: TextStyle(color: p.muted, fontSize: 13)),
            ]),
          )
        else
          SpListCard(children: [
            for (var i = 0; i < e.attendees.length; i++)
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () =>
                    openPlayerProfile(context, ref, e.attendees[i].userId),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Row(children: [
                    SizedBox(
                      width: 24,
                      child: Text('${i + 1}',
                          style: TextStyle(
                              color: p.muted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800)),
                    ),
                    ClipOval(
                      child: Crest(
                          logoUrl: e.attendees[i].avatarUrl,
                          label: e.attendees[i].displayName,
                          size: 38),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Flexible(
                              child: Text(e.attendees[i].displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (e.attendees[i].isWard) ...[
                              const SizedBox(width: 6),
                              const WardBadge(),
                            ],
                          ]),
                          if (e.attendees[i].checkedInAt != null)
                            Text(
                                'Checked in ${timeAgo(e.attendees[i].checkedInAt)}'
                                '${e.attendees[i].letInBy != null ? ' · let in by ${e.attendees[i].letInBy}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: p.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                    if (canEdit)
                      IconButton(
                        tooltip: 'Check out',
                        onPressed: () => _checkOut(context, ref,
                            e.attendees[i].userId, e.attendees[i].displayName),
                        icon: Icon(Icons.person_remove_outlined,
                            size: 19, color: p.muted),
                      ),
                  ]),
                ),
              ),
          ]),
      ],
    );
  }

  Future<void> _checkOut(BuildContext context, WidgetRef ref, String playerId,
      String playerName) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $playerName?'),
        content: Text(
            '$playerName will be taken off the checked-in list. They can check in again by scanning the event QR.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep them')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove',
                  style: TextStyle(color: Color(0xFFDC2626)))),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    try {
      await ref
          .read(eventsRepositoryProvider)
          .checkOut(event.id, playerId: playerId);
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Edit event (creator / group admin) — web EditEventDialog replica.
// ---------------------------------------------------------------------------

class _EditEventSheet extends ConsumerStatefulWidget {
  const _EditEventSheet({required this.event});
  final EventDetail event;

  @override
  ConsumerState<_EditEventSheet> createState() => _EditEventSheetState();
}

class _EditEventSheetState extends ConsumerState<_EditEventSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.event.title);
  late final TextEditingController _desc =
      TextEditingController(text: widget.event.description ?? '');
  late final TextEditingController _venue =
      TextEditingController(text: widget.event.locationName ?? '');
  late DateTime? _date = widget.event.eventDate?.toUtc();
  late String? _start = formatClock24(widget.event.startTime);
  late String? _end = formatClock24(widget.event.endTime);
  late String _recurrence = widget.event.recurrence;
  late bool _private = widget.event.isPrivate;
  late String? _competitive = widget.event.competitiveLevel;
  // Spots: cap + RSVP rule (sent only when changed; lowering never evicts).
  late final TextEditingController _maxPlayers = TextEditingController(
      text: widget.event.capacity.maxPlayers?.toString() ?? '');
  late String _rsvpPolicy = widget.event.capacity.rsvpPolicy;
  bool _busy = false;
  String? _error;

  // Who it's for: the whole group, or team(s). Sent only when changed.
  late final bool _initialForTeams = widget.event.audienceTeams.isNotEmpty;
  late final Set<String> _initialTeamIds = {
    for (final t in widget.event.audienceTeams) t.id
  };
  late bool _forTeams = _initialForTeams;
  late final Set<String> _teamIds = {..._initialTeamIds};

  // Reminder schedule: loaded from `?view=reminders`; sent only when changed.
  List<String>? _initialReminders;
  Set<String>? _reminders;
  bool _remindersFailed = false;

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    try {
      final r =
          await ref.read(eventsRepositoryProvider).reminders(widget.event.id);
      if (!mounted) return;
      final slots = orderReminderSlots(r.slots);
      setState(() {
        _initialReminders = slots;
        _reminders = {...slots};
      });
    } catch (_) {
      if (mounted) setState(() => _remindersFailed = true);
    }
  }

  bool get _audienceChanged {
    if (_forTeams != _initialForTeams) return true;
    if (!_forTeams) return false;
    return _teamIds.length != _initialTeamIds.length ||
        !_teamIds.containsAll(_initialTeamIds);
  }

  static const _recurrences = {
    'once': 'One-off',
    'daily': 'Daily',
    'weekly': 'Weekly',
    'biweekly': 'Every 2 weeks',
    'monthly': 'Monthly',
    'yearly': 'Yearly',
  };
  static const _levels = {
    'non_competitive': 'Non-competitive',
    'moderate': 'Moderate',
    'high': 'Highly competitive',
  };

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _venue.dispose();
    _maxPlayers.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime(bool start) async {
    final current = start ? _start : _end;
    TimeOfDay initial = const TimeOfDay(hour: 18, minute: 0);
    if (current != null && current.contains(':')) {
      final parts = current.split(':');
      initial = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 18,
          minute: int.tryParse(parts[1]) ?? 0);
    }
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    final hhmm =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (start) {
        _start = hhmm;
      } else {
        _end = hhmm;
      }
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    // Only touch the audience when the picker was actually shown and changed.
    final groupId = widget.event.groupId;
    final sendAudience = groupId != null &&
        ref.read(eventAudiencesProvider(groupId)).valueOrNull != null &&
        _audienceChanged;
    if (sendAudience && _forTeams && _teamIds.isEmpty) {
      setState(() => _error = 'Pick the team this event is for.');
      return;
    }
    // Null = unchanged (or never loaded) → not sent.
    final reminders = _reminders;
    final initialReminders = _initialReminders;
    final reminderPatch = reminders != null &&
            initialReminders != null &&
            !sameReminderSlots(reminders, initialReminders)
        ? orderReminderSlots(reminders)
        : null;
    // The sheet can be swiped away mid-save: invalidate through the
    // container, never `ref` after an await.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(eventsRepositoryProvider).updateEvent(widget.event.id, {
        'title': title,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        if (_date != null)
          'eventDate': DateTime.utc(_date!.year, _date!.month, _date!.day)
              .toIso8601String(),
        'startTime': _start,
        'endTime': _end,
        'locationName': _venue.text.trim().isEmpty ? null : _venue.text.trim(),
        'recurrence': _recurrence,
        'visibility': _private ? 'private' : 'public',
        'competitiveLevel': _competitive,
        if (int.tryParse(_maxPlayers.text.trim()) !=
            widget.event.capacity.maxPlayers)
          'maxPlayers': int.tryParse(_maxPlayers.text.trim()),
        if (_rsvpPolicy != widget.event.capacity.rsvpPolicy)
          'rsvpPolicy': _rsvpPolicy,
        // [] would mean "whole group" too; null says it explicitly.
        if (sendAudience) 'teamIds': _forTeams ? _teamIds.toList() : null,
        // [] = no reminders.
        if (reminderPatch != null) 'reminders': reminderPatch,
      });
      if (reminderPatch != null) {
        container.invalidate(eventRemindersProvider(widget.event.id));
      }
      // sendAudience is only true when groupId != null, and Dart promotes
      // groupId through that final bool — no second check needed.
      if (sendAudience) {
        container.invalidate(myFeedProvider);
        container.invalidate(groupEventsProvider(groupId));
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final groupId = widget.event.groupId;
    final audience = groupId == null
        ? null
        : ref.watch(eventAudiencesProvider(groupId)).valueOrNull;
    // Teams already on the event that this viewer can't pick stay listed, so
    // they can be seen (and removed).
    final audienceTeams = audience == null
        ? const <AudienceTeamOption>[]
        : [
            ...audience.teams,
            for (final t in widget.event.audienceTeams)
              if (!audience.hasTeam(t.id))
                AudienceTeamOption(id: t.id, name: t.name),
          ];
    final showAudience =
        audience != null && (audience.canCreate || _initialForTeams);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: ListView(
          shrinkWrap: true,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Edit event',
                style: TextStyle(
                    color: p.ink, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Description', alignLabelWithHint: true),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _pickerTile(
                  label: 'Date',
                  value: _date != null ? formatDayYear(_date) : 'Pick',
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _pickerTile(
                  label: 'Starts',
                  value: _start ?? '—',
                  onTap: () => _pickTime(true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _pickerTile(
                  label: 'Ends',
                  value: _end ?? '—',
                  onTap: () => _pickTime(false),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _venue,
              decoration: const InputDecoration(labelText: 'Venue'),
            ),
            const SizedBox(height: 14),
            _choiceRow<String>(
              label: 'Repeats',
              options: _recurrences,
              value: _recurrence,
              onChanged: (v) => setState(() => _recurrence = v ?? 'once'),
            ),
            const SizedBox(height: 10),
            _choiceRow<String?>(
              label: 'Competitiveness',
              options: {null: 'Not set', ..._levels},
              value: _competitive,
              onChanged: (v) => setState(() => _competitive = v),
            ),
            const SizedBox(height: 10),
            EventSpotsPicker(
              maxPlayers: _maxPlayers,
              rsvpPolicy: _rsvpPolicy,
              enabled: !_busy,
              onMaxPlayers: (_) => setState(() {}),
              onRsvpPolicy: (v) => setState(() => _rsvpPolicy = v),
            ),
            if (audience != null && showAudience) ...[
              const SizedBox(height: 14),
              EventAudiencePicker(
                groupName: widget.event.groupName,
                teams: audienceTeams,
                // Only admins can widen to the whole group; keep it
                // visible when the event already is one.
                allowEveryone: audience.canGeneral || !_initialForTeams,
                forTeams: _forTeams,
                selected: _teamIds,
                isPrivate: _private,
                onForTeamsChanged: (v) => setState(() => _forTeams = v),
                onToggleTeam: (id) => setState(() {
                  if (!_teamIds.remove(id)) _teamIds.add(id);
                }),
              ),
            ],
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text(
                    _forTeams
                        ? 'Private (only this team can open it)'
                        : 'Private event (members only)',
                    style: TextStyle(color: p.ink, fontSize: 13.5)),
              ),
              Switch(
                value: _private,
                onChanged: (v) => setState(() => _private = v),
              ),
            ]),
            if (!_remindersFailed) ...[
              const SizedBox(height: 10),
              if (_reminders == null)
                Text('Loading reminders…',
                    style: TextStyle(color: p.muted, fontSize: 12))
              else
                EventRemindersPicker(
                  selected: _reminders!,
                  enabled: !_busy,
                  onChanged: (v) => setState(() => _reminders = v),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
            ],
            const SizedBox(height: 16),
            SpButton(
              label: _busy ? 'Saving…' : 'Save changes',
              expand: true,
              onTap: _busy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerTile(
      {required String label,
      required String value,
      required VoidCallback onTap}) {
    final p = context.palette;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: p.muted, fontSize: 10.5)),
              const SizedBox(height: 2),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choiceRow<T>({
    required String label,
    required Map<T, String> options,
    required T value,
    required ValueChanged<T?> onChanged,
  }) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: p.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final entry in options.entries)
            Material(
              color: value == entry.key ? p.accent : p.surface,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => onChanged(entry.key),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: value == entry.key ? p.accent : p.line),
                  ),
                  child: Text(entry.value,
                      style: TextStyle(
                        color: value == entry.key ? Colors.white : p.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      )),
                ),
              ),
            ),
        ]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Late-arrival available pool — checked-in players not yet on a team.
// ---------------------------------------------------------------------------

class _PoolSection extends ConsumerWidget {
  const _PoolSection(
      {required this.event, required this.teams, required this.onChanged});
  final EventDetail event;
  final List<EventTeam> teams;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final pool = ref.watch(availablePoolProvider(event.id));
    final list = pool.valueOrNull ?? const <PoolPlayer>[];
    // Web AvailablePool: manage actions need the plan feature, not just
    // being an admin; admins without it see an upgrade note instead.
    final manage = event.canManage && event.hasLatePool;
    if (list.isEmpty) {
      if (!manage) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Available pool'),
          const SizedBox(height: 8),
          GlassCard(
            padding: const EdgeInsets.all(12),
            child: Text(
              "No one's waiting yet. Anyone who checks in after teams are "
              'set shows up here so you can slot them into a team — '
              'automatically or by hand.',
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Eyebrow('Available pool · ${list.length}')),
          if (manage)
            InkWell(
              onTap: () => _autoAssign(context, ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text('Auto-assign all',
                    style: TextStyle(
                        color: p.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        Text(
          'Late arrivals — waiting to be slotted into a team.',
          style: TextStyle(color: p.muted, fontSize: 11.5),
        ),
        if (event.canManage && !event.hasLatePool) ...[
          const SizedBox(height: 6),
          Text(
            // No upgrade prompts or plan names in the app (app-store rules).
            'These players checked in after teams were set. Slotting late '
            "arrivals into teams isn't enabled for this group.",
            style: TextStyle(color: p.amber, fontSize: 11.5),
          ),
        ],
        const SizedBox(height: 8),
        for (final x in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              onTap: () => openPlayerProfile(context, ref, x.userId),
              child: Row(children: [
                ClipOval(
                  child: Crest(
                      logoUrl: x.avatarUrl, label: x.displayName, size: 30),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(x.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600)),
                      if (x.positions.isNotEmpty)
                        Text(x.positions.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.muted, fontSize: 11)),
                    ],
                  ),
                ),
                if (manage)
                  Material(
                    color: p.surface2,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _addToTeam(context, ref, x),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        child: Text('Add',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
      ],
    );
  }

  Future<void> _autoAssign(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(eventsRepositoryProvider).poolAutoAssign(event.id);
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _addToTeam(
      BuildContext context, WidgetRef ref, PoolPlayer x) async {
    final p = context.palette;
    final teamId = await showSpSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add ${x.displayName} to…',
              style: TextStyle(
                  color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final t in teams)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(t.name, style: TextStyle(color: p.ink)),
              subtitle: Text('${t.players.length} players',
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
              onTap: () => Navigator.pop(ctx, t.id),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'AUTO'),
            child: const Text('Auto-slot (best fit)'),
          ),
        ],
      ),
    );
    if (teamId == null) return;
    try {
      await ref.read(eventsRepositoryProvider).poolAdd(
            event.id,
            x.userId,
            teamId: teamId == 'AUTO' ? null : teamId,
          );
      onChanged();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Photo manager (organizer) — add, set cover, remove. Uploads go through the
// same presigned-URL flow as the web.
// ---------------------------------------------------------------------------

class _PhotoManager extends ConsumerStatefulWidget {
  const _PhotoManager({required this.event, required this.onChanged});
  final EventDetail event;
  final VoidCallback onChanged;

  @override
  ConsumerState<_PhotoManager> createState() => _PhotoManagerState();
}

class _PhotoManagerState extends ConsumerState<_PhotoManager> {
  bool _busy = false;

  Future<void> _save(List<String> images, String? thumb) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(eventsRepositoryProvider)
          .setImages(widget.event.id, images, thumbnailUrl: thumb);
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await picked.readAsBytes();
      final type = picked.mimeType ?? 'image/jpeg';
      final url = await ref.read(eventsRepositoryProvider).uploadImage(
            bytes,
            type,
            assetType: 'eventImage',
            scopeId: widget.event.id,
          );
      final images = [...widget.event.images, url];
      await ref.read(eventsRepositoryProvider).setImages(
            widget.event.id,
            images,
            thumbnailUrl: widget.event.thumbnailUrl ?? url,
          );
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _photoMenu(String url) {
    final p = context.palette;
    final e = widget.event;
    showSpSheet<void>(
      context,
      builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Icon(Icons.star_outline_rounded, color: p.accent),
          title: const Text('Set as cover'),
          onTap: () {
            Navigator.pop(ctx);
            _save(e.images, url);
          },
        ),
        ListTile(
          leading: Icon(Icons.delete_outline_rounded, color: p.danger),
          title: const Text('Remove photo'),
          onTap: () {
            Navigator.pop(ctx);
            final next = e.images.where((x) => x != url).toList();
            _save(next, e.thumbnailUrl == url ? null : e.thumbnailUrl);
          },
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = widget.event;
    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _busy ? null : _add,
              child: Container(
                width: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.line),
                ),
                child: _busy
                    ? const Center(
                        child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : Icon(Icons.add_photo_alternate_outlined, color: p.accent),
              ),
            ),
          ),
          const SizedBox(width: 8),
          for (final url in e.images) ...[
            InkWell(
              onTap: _busy ? null : () => _photoMenu(url),
              child: Container(
                width: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: e.thumbnailUrl == url ? p.accent : p.line,
                    width: e.thumbnailUrl == url ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(color: p.surface2),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Captain draft board — live via SSE pings on draft:{eventId} + poll fallback.
// ---------------------------------------------------------------------------

class _DraftBoard extends ConsumerStatefulWidget {
  const _DraftBoard({required this.eventId, required this.onDone});
  final String eventId;
  final VoidCallback onDone;

  @override
  ConsumerState<_DraftBoard> createState() => _DraftBoardState();
}

class _DraftBoardState extends ConsumerState<_DraftBoard> {
  StreamSubscription<void>? _sub;
  Timer? _poll;
  Timer? _reconnect;
  bool _closed = false;
  bool _doneFired = false;

  @override
  void initState() {
    super.initState();
    _listen();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _closed = true;
    _sub?.cancel();
    _poll?.cancel();
    _reconnect?.cancel();
    super.dispose();
  }

  void _listen() {
    _sub?.cancel();
    _sub = ref.read(eventsRepositoryProvider).draftPings(widget.eventId).listen(
          (_) => _refresh(),
          onError: (_) => _scheduleReconnect(),
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 4), () {
      if (!_closed) _listen();
    });
  }

  void _refresh() {
    if (!_closed) ref.invalidate(draftProvider(widget.eventId));
  }

  Future<void> _act(Future<void> Function() op) async {
    try {
      await op();
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final draft = ref.watch(draftProvider(widget.eventId)).valueOrNull;
    if (draft == null) {
      return GlassCard(
        child: Text('Setting up the draft…',
            style: TextStyle(color: p.muted, fontSize: 13)),
      );
    }
    final isDone = draft['isDone'] == true;
    if (isDone && !_doneFired) {
      _doneFired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
    }
    final teams = draft['teams'] is List ? draft['teams'] as List : const [];
    final pool = draft['pool'] is List ? draft['pool'] as List : const [];
    final currentIdx = draft['currentTeamIndex'];
    final isYourTurn = draft['isYourTurn'] == true;
    final isOrganizer = draft['isOrganizer'] == true;
    final canPick = !isDone && (isYourTurn || isOrganizer);
    final picksMade = (draft['picksMade'] as num?)?.toInt() ?? 0;
    final totalPicks = (draft['totalPicks'] as num?)?.toInt() ?? 0;

    String turnLabel = 'Draft complete 🎉';
    if (!isDone && currentIdx is num) {
      final onClock = teams.cast<Map?>().firstWhere(
            (t) => (t?['index'] as num?)?.toInt() == currentIdx.toInt(),
            orElse: () => null,
          );
      final name = onClock?['name'] ?? 'Team ${currentIdx.toInt() + 1}';
      turnLabel = isYourTurn ? 'Your pick!' : '$name is picking…';
    }

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Eyebrow('Captain draft')),
            Text('$picksMade / $totalPicks picks',
                style: TextStyle(color: p.muted, fontSize: 11.5)),
          ]),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: isYourTurn
                  ? const Color.fromRGBO(23, 166, 94, 0.12)
                  : p.surface2,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              turnLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: isYourTurn ? p.accent : p.ink,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          for (final raw in teams)
            if (raw is Map)
              _teamTile(context, Map<String, dynamic>.from(raw), currentIdx),
          if (pool.isNotEmpty && !isDone) ...[
            const SizedBox(height: 8),
            Text('AVAILABLE',
                style: TextStyle(
                    color: p.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final raw in pool)
                if (raw is Map)
                  _poolChip(context, Map<String, dynamic>.from(raw), canPick),
            ]),
          ],
          const SizedBox(height: 10),
          Row(children: [
            if (draft['canUndoLast'] == true && !isDone)
              InkWell(
                onTap: () => _act(() => ref
                    .read(eventsRepositoryProvider)
                    .draftUndo(widget.eventId)),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text('Undo last pick',
                      style: TextStyle(
                          color: p.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            const Spacer(),
            if (isOrganizer && !isDone)
              InkWell(
                onTap: () => _confirmCancel(context),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text('Cancel draft',
                      style: TextStyle(
                          color: p.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _teamTile(
      BuildContext context, Map<String, dynamic> t, Object? currentIdx) {
    final p = context.palette;
    final onClock = currentIdx is num &&
        (t['index'] as num?)?.toInt() == currentIdx.toInt();
    Color color = p.accent;
    final hex = t['color'];
    if (hex is String && hex.isNotEmpty) {
      var h = hex.replaceAll('#', '');
      if (h.length == 6) h = 'FF$h';
      color = Color(int.tryParse(h, radix: 16) ?? 0xFF17A65E);
    }
    final captain = t['captain'] is Map
        ? (t['captain'] as Map)['displayName'] ?? 'Captain'
        : 'Captain';
    String names(dynamic v) => v is List
        ? v
            .whereType<Map>()
            .map((m) => m['displayName'] ?? '')
            .where((x) => '$x'.isNotEmpty)
            .join(', ')
        : '';
    final starters = names(t['starters']);
    final subs = names(t['subs']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: onClock ? p.accent : p.line, width: onClock ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
                width: 11,
                height: 11,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Expanded(
              child: Text('${t['name'] ?? 'Team'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700)),
            ),
            Text('C: $captain',
                style: TextStyle(color: p.muted, fontSize: 11.5)),
          ]),
          if (starters.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(starters,
                  style: TextStyle(color: p.ink, fontSize: 12, height: 1.4)),
            ),
          if (subs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Subs: $subs',
                  style:
                      TextStyle(color: p.muted, fontSize: 11.5, height: 1.4)),
            ),
        ],
      ),
    );
  }

  Widget _poolChip(BuildContext context, Map<String, dynamic> m, bool canPick) {
    final p = context.palette;
    final name = '${m['displayName'] ?? 'Player'}';
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: canPick
            ? () => _act(() => ref
                .read(eventsRepositoryProvider)
                .draftPick(widget.eventId, '${m['userId']}'))
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: canPick ? p.accent : p.line),
          ),
          child: Text(name,
              style: TextStyle(
                  color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel the draft?'),
        content: const Text('Picks are discarded and the event reopens.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep drafting')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel draft')),
        ],
      ),
    );
    if (ok == true) {
      await _act(
          () => ref.read(eventsRepositoryProvider).draftCancel(widget.eventId));
      widget.onDone();
    }
  }
}

/// Pins the event tab row to the top of the scroll view.
class _PinnedTabs extends SliverPersistentHeaderDelegate {
  const _PinnedTabs({required this.child});
  final Widget child;

  static const double _height = 58;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: _height, child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedTabs oldDelegate) =>
      oldDelegate.child != child;
}

/// Organizer card on a cancelled event: shows tickets still awaiting refund
/// and retries the sweep. Retrying is safe — the server claims each charge
/// and uses provider idempotency keys, so nobody can be refunded twice.
class _RefundRetryCard extends ConsumerStatefulWidget {
  const _RefundRetryCard({required this.eventId});
  final String eventId;
  @override
  ConsumerState<_RefundRetryCard> createState() => _RefundRetryCardState();
}

class _RefundRetryCardState extends ConsumerState<_RefundRetryCard> {
  Map<String, dynamic>? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st =
          await ref.read(eventsRepositoryProvider).refundStatus(widget.eventId);
      if (mounted) setState(() => _status = st);
    } catch (_) {/* stays hidden */}
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r =
          await ref.read(eventsRepositoryProvider).retryRefunds(widget.eventId);
      final refunded = (r['refunded'] as num?)?.toInt() ?? 0;
      messenger.showSnackBar(SnackBar(
          content: Text(r['queued'] == true
              ? 'Refund sweep queued — it runs in the background.'
              : refunded > 0
                  ? 'Refunded $refunded ticket${refunded == 1 ? '' : 's'}.'
                  : 'No refunds went through — try again shortly.')));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final remaining = (_status?['paidRemaining'] as num?)?.toInt() ?? 0;
    if (remaining <= 0) return const SizedBox.shrink();
    final refunded = (_status?['refunded'] as num?)?.toInt() ?? 0;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$remaining ticket${remaining == 1 ? '' : 's'} still awaiting refund'
            '${refunded > 0 ? ' ($refunded already refunded)' : ''}.',
            style: TextStyle(
                color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Retrying is safe — nobody is ever refunded twice.',
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: _busy ? null : _retry,
            child: Text(_busy ? 'Retrying…' : 'Retry refunds'),
          ),
        ],
      ),
    );
  }
}

/// One small "what you get" chip under the start-the-match card.
class _NextStepChip extends StatelessWidget {
  const _NextStepChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.line),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 13, color: p.muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 11)),
          ),
        ]),
      ),
    );
  }
}

/// "Your week" / XP / streak are recomputed server-side as part of an RSVP,
/// un-RSVP or check-out — refresh every place that shows them.
void _refreshProgression(WidgetRef ref) {
  ref.invalidate(yourWeekProvider);
  ref.invalidate(myProgressionProvider);
}
