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
import 'package:sportpadi_mobile/data/groups/members_repository.dart';
import 'package:sportpadi_mobile/features/events/event_tickets_card.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Event detail — a faithful mobile port of the web /events/[slug] page:
/// photos, info, hosted-by (follow), stats, interest/check-in, organizer QR,
/// team assignment, and the post-assignment Games / Teams / Check-ins tabs.
class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  // Post-assignment tab: 0 = Games, 1 = Teams, 2 = Check-ins.
  int _tab = 0;
  String? _busy;

  String get slug => widget.slug;

  void _refetch() {
    ref.invalidate(eventDetailProvider(slug));
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
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        titleSpacing: 0,
        title: detail.valueOrNull == null
            ? const Text('Event',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))
            : Text(
                '${detail.valueOrNull!.categoryEmoji ?? '🏅'} ${detail.valueOrNull!.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
        actions: [
          if (detail.valueOrNull?.canManage == true &&
              detail.valueOrNull?.status == 'open')
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _openEdit(detail.valueOrNull!),
            ),
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 20),
            onPressed: () => _share(detail.valueOrNull),
          ),
          if (detail.valueOrNull != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: _statusBadge(detail.valueOrNull!.status, p)),
            ),
        ],
      ),
      body: AsyncView(
        value: detail,
        onRetry: _refetch,
        data: (e) => RefreshIndicator(
          onRefresh: () async => ref.refresh(eventDetailProvider(slug).future),
          child: _body(e),
        ),
      ),
    );
  }

  void _share(EventDetail? e) {
    if (e == null) return;
    final base = ref.read(appConfigProvider).apiBaseUrl;
    Clipboard.setData(ClipboardData(text: '$base/e/${e.slug}'));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  Future<void> _openEdit(EventDetail e) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditEventSheet(event: e),
    );
    if (saved == true) _refetch();
  }

  Widget _statusBadge(String? status, AppPalette p) {
    switch (status) {
      case 'open':
        return SpBadge('Open', tone: p.accent);
      case 'drafting':
        return const SpBadge('🎲 Drafting');
      case 'kicked_off':
        return SpBadge('⚡ Live', tone: p.amber);
      case 'completed':
        return SpBadge('Completed', tone: p.muted);
      default:
        return SpBadge(status ?? '', tone: p.muted);
    }
  }

  bool _isPast(EventDetail e) {
    final d = e.eventDate;
    if (d == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTime(d.year, d.month, d.day).isBefore(today);
  }

  Widget _body(EventDetail e) {
    final p = context.palette;
    final teamsAsync = ref.watch(eventTeamsProvider(e.id));
    final teams = teamsAsync.valueOrNull ?? const <EventTeam>[];
    final games = ref.watch(eventGamesProvider(e.id)).valueOrNull ??
        const <GameSummary>[];
    final hasGames = games.isNotEmpty;
    final showTabs = e.isTeamFlow && teams.isNotEmpty;
    // Web: feature groups keep taking check-ins after kickoff so late
    // arrivals land in the available pool.
    final canCheckIn =
        e.status == 'open' || (e.status == 'kicked_off' && e.hasLatePool);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        if (e.isPrivate) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(245, 167, 10, 0.10),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: const Color.fromRGBO(245, 167, 10, 0.4)),
            ),
            child: Row(children: [
              Icon(Icons.lock_outline, size: 14, color: p.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Private event — only members of ${e.groupName ?? 'this group'} can see it.',
                  style: TextStyle(color: p.amber, fontSize: 12),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        _Photos(event: e),
        if (e.canManage && e.status != 'completed') ...[
          const SizedBox(height: 10),
          _PhotoManager(event: e, onChanged: _refetch),
        ],
        const SizedBox(height: 14),
        _InfoCard(event: e),
        if (e.groupId != null) ...[
          const SizedBox(height: 12),
          _HostedByCard(
              groupId: e.groupId!,
              name: e.groupName ?? 'Group',
              imageUrl: e.groupImageUrl),
        ],
        const SizedBox(height: 12),
        _StatsRow(event: e),
        if (e.typicalAttendance != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${e.groupName != null ? "${e.groupName}'s " : ''}${e.categoryName ?? 'These'} events usually draw ~${e.typicalAttendance} players',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ),
        ],
        if (e.status != 'cancelled') EventTicketsCard(eventId: e.id),
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
              _refetch();
              ref.invalidate(eventTeamsProvider(e.id));
            },
          ),
        ],
        if (showTabs) ...[
          const SizedBox(height: 16),
          if (e.canManage && e.interestedPeople.isNotEmpty) ...[
            _InterestedList(people: e.interestedPeople),
            const SizedBox(height: 12),
          ],
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
              onComplete: () => _do('complete', () async {
                await ref
                    .read(eventsRepositoryProvider)
                    .setEventStatus(e.id, 'completed');
              }),
              onReset: () => _do('reset', () async {
                await ref.read(eventsRepositoryProvider).resetTeams(e.id);
                ref.invalidate(eventTeamsProvider(e.id));
              }),
            ),
            const SizedBox(height: 12),
          ],
          if (e.status == 'kicked_off' &&
              (e.canManage || e.hasLatePool)) ...[
            _PoolSection(event: e, teams: teams, onChanged: () {
              _refetch();
              ref.invalidate(eventTeamsProvider(e.id));
              ref.invalidate(availablePoolProvider(e.id));
            }),
            const SizedBox(height: 12),
          ],
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
        ] else ...[
          if (e.canManage && e.interestedPeople.isNotEmpty) ...[
            const SizedBox(height: 16),
            _InterestedList(people: e.interestedPeople),
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
                : () => _do('complete', () async {
                      await ref
                          .read(eventsRepositoryProvider)
                          .setEventStatus(e.id, 'completed');
                    }),
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
            color: p.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _busy != null ? null : () => _cancelEvent(e),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color.fromRGBO(222, 33, 33, 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_busy_outlined,
                        size: 16, color: p.danger),
                    const SizedBox(width: 6),
                    Text('Cancel event',
                        style: TextStyle(
                            color: p.danger,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _cancelEvent(EventDetail e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this event?'),
        content: const Text(
            'Anyone who paid for a ticket is refunded automatically. If no '
            'money ever changed hands, the event is removed entirely. This '
            'cannot be undone.'),
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
// Photos — carousel of event images, emoji hero fallback.
// ---------------------------------------------------------------------------

class _Photos extends StatelessWidget {
  const _Photos({required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final images = <String>[
      if (e.thumbnailUrl != null) e.thumbnailUrl!,
      ...e.images.where((x) => x != e.thumbnailUrl),
    ];
    if (images.isEmpty) {
      return GradientHero(emoji: e.categoryEmoji ?? '🏅', height: 170);
    }
    if (images.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: CachedNetworkImage(
          imageUrl: images.first,
          height: 190,
          width: double.infinity,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) =>
              GradientHero(emoji: e.categoryEmoji ?? '🏅', height: 190),
        ),
      );
    }
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: CachedNetworkImage(
            imageUrl: images[i],
            height: 190,
            width: 300,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              width: 300,
              color: context.palette.surface2,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info card — category, competitiveness, date, time, venue + directions,
// description. Mirrors the web info card line for line.
// ---------------------------------------------------------------------------

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.event});
  final EventDetail event;

  static const _competitive = {
    'non_competitive': ('Non-competitive', Color(0xFF059669)),
    'moderate': ('Moderately competitive', Color(0xFFD97706)),
    'high': ('Highly competitive', Color(0xFFDC2626)),
  };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    final time = [
      formatClock(e.startTime),
      if (e.endTime != null) formatClock(e.endTime),
    ].where((s) => s != null && s.isNotEmpty).join(' – ');
    final comp = e.competitiveLevel != null
        ? _competitive[e.competitiveLevel!]
        : null;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (e.categoryName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Text(e.categoryEmoji ?? '🏅',
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Text(e.categoryName!,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          if (comp != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(Icons.sports_kabaddi_rounded, size: 16, color: p.accent),
                const SizedBox(width: 8),
                SpBadge(comp.$1, tone: comp.$2),
              ]),
            ),
          if (e.eventDate != null)
            InfoRow(Icons.calendar_today_rounded, formatDayYear(e.eventDate)),
          EventTicketedLine(eventId: e.id),
          if (time.isNotEmpty) InfoRow(Icons.schedule_rounded, time),
          if (e.locationName != null)
            InfoRow(
              Icons.place_rounded,
              e.locationName!,
              trailing: InkWell(
                onTap: () => _openMaps(e),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Directions',
                        style: TextStyle(
                            color: p.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 3),
                    Icon(Icons.open_in_new_rounded,
                        size: 12, color: p.accent),
                  ]),
                ),
              ),
            ),
          if (e.description != null && e.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: Text(e.description!,
                  style: TextStyle(
                      color: p.muted, fontSize: 13.5, height: 1.55)),
            ),
          ],
        ],
      ),
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

// ---------------------------------------------------------------------------
// Hosted by — group card with Follow.
// ---------------------------------------------------------------------------

class _HostedByCard extends ConsumerStatefulWidget {
  const _HostedByCard(
      {required this.groupId, required this.name, this.imageUrl});
  final String groupId;
  final String name;
  final String? imageUrl;

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
      final st = await ref
          .read(eventsRepositoryProvider)
          .followState(widget.groupId);
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
      await ref
          .read(eventsRepositoryProvider)
          .setFollow(widget.groupId, !was);
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
              child: ClipOval(
                child: Crest(
                    logoUrl: widget.imageUrl,
                    label: widget.name,
                    size: 44),
              ),
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
              color: following ? p.surface2 : p.accent,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _busy || _following == null ? null : _toggle,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  child: Text(
                    following ? 'Following' : 'Follow',
                    style: TextStyle(
                      color: following ? p.ink : Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
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
// Stats row — Interested / Checked in / You.
// ---------------------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget cell(String value, String label, Color color) => Expanded(
          child: GlassCard(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(color: p.muted, fontSize: 11)),
            ]),
          ),
        );
    return Row(children: [
      cell('${event.interestCount}', 'Interested', const Color(0xFFEC4899)),
      const SizedBox(width: 10),
      cell('${event.attendeeCount}', 'Checked in', p.accent),
      const SizedBox(width: 10),
      cell(event.myCheckedIn ? '✅' : '—', 'You', p.ink),
    ]);
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
  static const _pink = Color(0xFFEC4899);

  Future<void> _toggleInterest() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(eventsRepositoryProvider)
          .toggleInterest(widget.event.id);
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

  Future<void> _checkOut() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(eventsRepositoryProvider).checkOut(widget.event.id);
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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = widget.event;
    final open = e.status == 'open';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          if (open)
            Expanded(
              child: Material(
                color: e.myInterested ? _pink : p.surface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _busy ? null : _toggleInterest,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: e.myInterested
                              ? _pink
                              : const Color.fromRGBO(236, 72, 153, 0.4)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          e.myInterested
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 16,
                          color: e.myInterested ? Colors.white : _pink,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          e.myInterested ? 'Interested' : "I'm interested",
                          style: TextStyle(
                            color: e.myInterested ? Colors.white : _pink,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (open && e.myCheckedIn) const SizedBox(width: 10),
          if (e.myCheckedIn)
            Expanded(
              child: open
                  ? Material(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _busy ? null : _checkOut,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color.fromRGBO(
                                    222, 33, 33, 0.4)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.logout_rounded,
                                  size: 16, color: p.danger),
                              const SizedBox(width: 6),
                              Text('Check out',
                                  style: TextStyle(
                                      color: p.danger,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text("✅  You're checked in",
                          style: TextStyle(
                              color: p.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
            ),
        ]),
        if (!e.myCheckedIn) ...[
          const SizedBox(height: 10),
          SpButton(
            label: 'Scan to check in',
            icon: Icons.qr_code_scanner_rounded,
            expand: true,
            onTap: () async {
              await context.push('/scan');
              widget.onChanged();
            },
          ),
          const SizedBox(height: 6),
          Text(
            e.status == 'kicked_off'
                ? 'Teams are already set — scan the event QR at the venue to join the available pool.'
                : "Scan the event's QR code at the venue to check in.",
            textAlign: TextAlign.center,
            style: TextStyle(color: context.palette.muted, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Organizer QR — players scan this at the venue.
// ---------------------------------------------------------------------------

class _QrCard extends StatelessWidget {
  const _QrCard({required this.event});
  final EventDetail event;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = event;
    return GlassCard(
      child: Column(children: [
        const Eyebrow('Event check-in QR'),
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
          child: QrImageView(
            data: e.qrCode!,
            size: 190,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(e.qrCode!,
            style: TextStyle(
                color: p.muted,
                fontSize: 10.5,
                fontFamily: 'monospace')),
      ]),
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
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final p = ctx.palette;
        return Container(
          decoration: BoxDecoration(
            color: p.bg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How many teams?',
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Checked-in players are shuffled evenly and the event kicks off.',
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
          ),
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
                    color: p.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
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

  Widget _chip(BuildContext context, String label, IconData icon,
      VoidCallback? onTap) {
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
                    color: p.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
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
    final p = context.palette;
    Widget btn(int i, IconData icon, String label) {
      final active = tab == i;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(i),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? p.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: active ? p.accent : p.muted),
                const SizedBox(width: 5),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: active ? p.accent : p.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Row(children: [
        if (showGames) btn(0, Icons.sports_esports_outlined, 'Games'),
        btn(1, Icons.shield_outlined, 'Teams'),
        btn(2, Icons.checklist_rounded, 'Check-ins'),
      ]),
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
        if (list.isEmpty)
          GlassCard(
            child: Text(
              event.canManage
                  ? 'No games yet — create the first match below.'
                  : 'No games yet.',
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
          )
        else
          for (final g in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                onTap: () => context.push('/games/${g.id}'),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
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
        if (event.canManage && teams.length >= 2) ...[
          const SizedBox(height: 4),
          SpButton(
            label: 'New match',
            icon: Icons.add_rounded,
            expand: true,
            onTap: () => _createMatch(context, ref),
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
    final selected = <String>{};
    final officiants = <String>{};
    var useOfficiants = false;
    final duration = TextEditingController();
    List<GroupMemberItem> candidates = const [];
    if (event.groupId != null) {
      try {
        candidates =
            (await ref.read(groupMembersProvider(event.groupId!).future))
                .items;
      } catch (_) {
        candidates = const [];
      }
    }
    if (!context.mounted) return;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final p = ctx.palette;
          return Container(
            decoration: BoxDecoration(
              color: p.bg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pick the teams playing',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
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
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Text('Duration (minutes, optional)',
                        style:
                            TextStyle(color: p.muted, fontSize: 12.5)),
                  ),
                  SizedBox(
                    width: 76,
                    child: TextField(
                      controller: duration,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: p.ink, fontSize: 13.5),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '—',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: p.line)),
                      ),
                    ),
                  ),
                ]),
                if (candidates.isNotEmpty) ...[
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: useOfficiants,
                    onChanged: (v) =>
                        setSheet(() => useOfficiants = v == true),
                    title: Text('Add officiants',
                        style: TextStyle(color: p.ink, fontSize: 14)),
                    subtitle: Text(
                        'Extra people (besides group admins) who can record stats.',
                        style: TextStyle(color: p.muted, fontSize: 11)),
                  ),
                  if (useOfficiants)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final m in candidates)
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
                const SizedBox(height: 8),
                SpButton(
                  label: 'Create match',
                  expand: true,
                  onTap: selected.length >= 2
                      ? () => Navigator.pop(ctx, true)
                      : null,
                ),
              ],
            ),
          );
        },
      ),
    );
    if (ok != true || selected.length < 2) return;
    try {
      final gameId =
          await ref.read(eventsRepositoryProvider).createGame(
                event.id,
                selected.toList(),
                durationMinutes: int.tryParse(duration.text.trim()),
                officiantIds:
                    useOfficiants ? officiants.toList() : const [],
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

class _TeamsTab extends StatelessWidget {
  const _TeamsTab({required this.teams});
  final List<EventTeam> teams;

  Color _color(String? hex, AppPalette p) {
    if (hex == null || hex.isEmpty) return p.accent;
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    return Color(int.tryParse(h, radix: 16) ?? 0xFF22C55E);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(children: [
      for (final t in teams)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _teamBox(context, t, p),
        ),
    ]);
  }

  Widget _teamBox(BuildContext context, EventTeam t, AppPalette p) {
    final color = _color(t.color, p);
    final starters = t.players.where((x) => !x.isSub).length;
    final subs = t.players.where((x) => x.isSub).length;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openRoster(context, t, color),
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
                        decoration: BoxDecoration(
                            color: color, shape: BoxShape.circle),
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
                                border:
                                    Border.all(color: p.surface, width: 2),
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
                                border:
                                    Border.all(color: p.surface, width: 2),
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

  void _openRoster(BuildContext context, EventTeam t, Color color) {
    final p = context.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
                    trailing: x.isSub
                        ? const _RosterTag(text: 'SUB')
                        : null,
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
// Interested list (organizer) — pink name chips.
// ---------------------------------------------------------------------------

class _InterestedList extends StatelessWidget {
  const _InterestedList({required this.people});
  final List<Attendee> people;
  static const _pink = Color(0xFFEC4899);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow('Interested · ${people.length}'),
        const SizedBox(height: 8),
        GlassCard(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final x in people)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(236, 72, 153, 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: const Color.fromRGBO(236, 72, 153, 0.25)),
                ),
                child: Text(x.displayName,
                    style: const TextStyle(
                        color: _pink,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ),
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
        Eyebrow('Checked in · ${e.attendeeCount}'),
        const SizedBox(height: 8),
        if (e.attendees.isEmpty)
          GlassCard(
            child: Center(
              child: Text('No players checked in yet.',
                  style: TextStyle(color: p.muted, fontSize: 13)),
            ),
          )
        else
          for (var i = 0; i < e.attendees.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color.fromRGBO(23, 166, 94, 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Text('${i + 1}',
                        style: TextStyle(
                            color: p.accent,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  ClipOval(
                    child: Crest(
                        logoUrl: e.attendees[i].avatarUrl,
                        label: e.attendees[i].displayName,
                        size: 30),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.attendees[i].displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600)),
                        if (e.attendees[i].checkedInAt != null)
                          Text(timeAgo(e.attendees[i].checkedInAt),
                              style: TextStyle(
                                  color: p.muted, fontSize: 11)),
                      ],
                    ),
                  ),
                  if (canEdit)
                    InkWell(
                      onTap: () => _checkOut(
                          context, ref, e.attendees[i].userId),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.person_remove_outlined,
                            size: 18, color: p.muted),
                      ),
                    ),
                ]),
              ),
            ),
      ],
    );
  }

  Future<void> _checkOut(
      BuildContext context, WidgetRef ref, String playerId) async {
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
  bool _busy = false;
  String? _error;

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
    final picked =
        await showTimePicker(context: context, initialTime: initial);
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(eventsRepositoryProvider).updateEvent(widget.event.id, {
        'title': title,
        'description':
            _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        if (_date != null)
          'eventDate':
              DateTime.utc(_date!.year, _date!.month, _date!.day)
                  .toIso8601String(),
        'startTime': _start,
        'endTime': _end,
        'locationName':
            _venue.text.trim().isEmpty ? null : _venue.text.trim(),
        'recurrence': _recurrence,
        'visibility': _private ? 'private' : 'public',
        'competitiveLevel': _competitive,
      });
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
                    color: p.ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
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
            Row(children: [
              Expanded(
                child: Text('Private event (members only)',
                    style: TextStyle(color: p.ink, fontSize: 13.5)),
              ),
              Switch(
                value: _private,
                onChanged: (v) => setState(() => _private = v),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(color: p.danger, fontSize: 12.5)),
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
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: p.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(color: p.muted, fontSize: 10.5)),
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
                color: p.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600)),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color:
                            value == entry.key ? p.accent : p.line),
                  ),
                  child: Text(entry.value,
                      style: TextStyle(
                        color: value == entry.key
                            ? Colors.white
                            : p.ink,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            'These players checked in after teams were set. Upgrade the '
            'group plan to slot late arrivals into teams.',
            style: TextStyle(color: p.amber, fontSize: 11.5),
          ),
        ],
        const SizedBox(height: 8),
        for (final x in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassCard(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                ClipOval(
                  child: Crest(
                      logoUrl: x.avatarUrl,
                      label: x.displayName,
                      size: 30),
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
                            style: TextStyle(
                                color: p.muted, fontSize: 11)),
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
                        padding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        child: Text('Add',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
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
    final teamId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add ${x.displayName} to…',
                style: TextStyle(
                    color: p.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            for (final t in teams)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title:
                    Text(t.name, style: TextStyle(color: p.ink)),
                subtitle: Text('${t.players.length} players',
                    style:
                        TextStyle(color: p.muted, fontSize: 11.5)),
                onTap: () => Navigator.pop(ctx, t.id),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'AUTO'),
              child: const Text('Auto-slot (best fit)'),
            ),
          ],
        ),
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
              _save(next,
                  e.thumbnailUrl == url ? null : e.thumbnailUrl);
            },
          ),
        ]),
      ),
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
                            child: CircularProgressIndicator(
                                strokeWidth: 2)))
                    : Icon(Icons.add_photo_alternate_outlined,
                        color: p.accent),
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
                  errorWidget: (_, __, ___) =>
                      Container(color: p.surface2),
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
    _sub = ref
        .read(eventsRepositoryProvider)
        .draftPings(widget.eventId)
        .listen(
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
            if (raw is Map) _teamTile(context, Map<String, dynamic>.from(raw), currentIdx),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
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
            color: onClock ? p.accent : p.line,
            width: onClock ? 1.6 : 1),
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
                  style: TextStyle(
                      color: p.ink, fontSize: 12, height: 1.4)),
            ),
          if (subs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Subs: $subs',
                  style: TextStyle(
                      color: p.muted, fontSize: 11.5, height: 1.4)),
            ),
        ],
      ),
    );
  }

  Widget _poolChip(
      BuildContext context, Map<String, dynamic> m, bool canPick) {
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
          padding:
              const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: canPick ? p.accent : p.line),
          ),
          child: Text(name,
              style: TextStyle(
                  color: p.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel the draft?'),
        content:
            const Text('Picks are discarded and the event reopens.'),
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
      await _act(() =>
          ref.read(eventsRepositoryProvider).draftCancel(widget.eventId));
      widget.onDone();
    }
  }
}

