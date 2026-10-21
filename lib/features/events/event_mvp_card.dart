import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/games/games_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';

/// A completed event's MVP vote and awards (web `components/events/EventMvpCard.tsx`,
/// api `events/mvp.ts`). While the vote is open: the three nominees with
/// their record across the event's games and a Vote button for members who
/// checked in (anonymous, no running tally). Once it closes: the MVP
/// spotlight (by votes, or by stats when too few voted), the vote split and
/// the sport's stat awards. Events without a vote still show the MVP by stats
/// and the awards; nothing when the event had no completed games.
///
/// With [gameId] instead it's a tournament / league MATCH's own vote, MVP and
/// stat awards (api `games/mvp.ts`); a league MVP confirmed by the organiser
/// shows as such.
class EventMvpCard extends ConsumerStatefulWidget {
  const EventMvpCard({super.key, this.eventId = '', this.gameId});
  final String eventId;
  final String? gameId;

  @override
  ConsumerState<EventMvpCard> createState() => _EventMvpCardState();
}

const _gold = Color(0xFFF7C948);
const _goldDeep = Color(0xFFE0A91C);

class _EventMvpCardState extends ConsumerState<EventMvpCard> {
  Timer? _tick;
  String? _voting;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _vote(String playerId) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _voting = playerId);
    try {
      final gid = widget.gameId;
      if (gid != null) {
        await ref.read(gamesRepositoryProvider).voteMvp(gid, playerId);
        ref.invalidate(gameMvpProvider(gid));
      } else {
        await ref.read(eventsRepositoryProvider).voteMvp(widget.eventId, playerId);
        ref.invalidate(eventMvpProvider(widget.eventId));
      }
      messenger.showSnackBar(const SnackBar(content: Text('Vote in — it stays anonymous.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : 'Could not save your vote.')));
    } finally {
      if (mounted) setState(() => _voting = null);
    }
  }

  static String _left(DateTime closes) {
    final ms = closes.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 'closing…';
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    return h > 0 ? '${h}h ${m}m left' : '${m}m left';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final gid = widget.gameId;
    final d = gid != null
        ? ref.watch(gameMvpProvider(gid)).valueOrNull
        : ref.watch(eventMvpProvider(widget.eventId)).valueOrNull;
    // Any completed local event with games has a stats MVP + awards; the vote is extra.
    if (d == null) return const SizedBox.shrink();
    final poll = d['poll'] is Map ? Map<String, dynamic>.from(d['poll'] as Map) : null;
    final mvp = d['mvp'] is Map ? Map<String, dynamic>.from(d['mvp'] as Map) : null;
    final awards = [for (final a in (d['awards'] as List? ?? const [])) if (a is Map) Map<String, dynamic>.from(a)];
    if (poll == null && mvp == null && awards.isEmpty) return const SizedBox.shrink();
    final open = poll?['open'] == true;
    final closes = DateTime.tryParse('${poll?['closesAt'] ?? ''}')?.toLocal();
    final nominees = [for (final n in (poll?['nominees'] as List? ?? const [])) if (n is Map) Map<String, dynamic>.from(n)];
    final myVote = poll?['myVote'] as String?;
    final canVote = poll?['canVote'] == true;
    final total = (poll?['totalVotes'] as num?)?.toInt();
    // On a match page: 'match' = this match's own vote; 'event' = a local game
    // showing its event's (the vote and awards cover the whole session).
    final scope = d['scope'] as String?;
    final ofEvent = scope == 'event' && d['event'] is Map ? Map<String, dynamic>.from(d['event'] as Map) : null;

    List<String> strs(dynamic v) => [for (final x in (v as List? ?? const [])) '$x'];

    Widget chips(List<String> items, {bool dark = false}) => Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final s in items)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: dark ? Colors.white.withAlpha(26) : p.surface2, borderRadius: BorderRadius.circular(99)),
                child: Text(s,
                    style: TextStyle(
                        color: dark ? Colors.white.withAlpha(217) : p.muted, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
          ],
        );

    final header = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B1408), Color(0xFF3A2A07), Color(0xFF6B4B0C)]),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${open ? 'MVP VOTE' : 'AWARDS'}${ofEvent != null ? ' · WHOLE EVENT' : ''}',
              style: const TextStyle(color: _gold, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
          const Spacer(),
          if (open && closes != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: Colors.white.withAlpha(26), borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.schedule_rounded, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Text(_left(closes), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ]),
            ),
        ]),
        if (open) ...[
          const SizedBox(height: 6),
          const Text('Who was the MVP?', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
              '${scope == 'match' ? 'The three standouts from this match.' : "The three standouts from the event's games."} Votes are anonymous — results when voting closes.',
              style: TextStyle(color: Colors.white.withAlpha(178), fontSize: 12.5)),
        ] else if (mvp != null) ...[
          const SizedBox(height: 12),
          Center(
            child: Column(children: [
              Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: _gold, shape: BoxShape.circle),
                  child: PersonAvatar(url: mvp['avatarUrl'] as String?, name: '${mvp['name'] ?? '?'}', size: 80),
                ),
                Positioned(
                  bottom: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(99)),
                    child: const Text('MVP',
                        style: TextStyle(color: Color(0xFF3A2A07), fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => openPlayerProfile(context, ref, mvp['playerId'] as String?),
                child: Text('${mvp['name'] ?? 'Player'}',
                    style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 2),
              Text(
                  mvp['by'] == 'votes'
                      ? 'Voted by the players · ${mvp['votes']} of ${total ?? mvp['votes']} votes'
                      : mvp['by'] == 'organiser'
                          ? 'Confirmed by the organiser'
                          : poll != null
                          ? 'Picked by stats — too few votes'
                          : 'Picked by stats',
                  style: TextStyle(color: Colors.white.withAlpha(178), fontSize: 12)),
              const SizedBox(height: 8),
              chips(strs(mvp['summary']), dark: true),
            ]),
          ),
        ],
      ]),
    );

    Widget nomineeCard(Map<String, dynamic> n) {
      final id = '${n['playerId']}';
      final mine = myVote == id;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: mine ? const Color(0x33E0A91C) : p.surface2.withAlpha(150),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: mine ? _goldDeep : p.line),
        ),
        child: Row(children: [
          PersonAvatar(url: n['avatarUrl'] as String?, name: '${n['name'] ?? '?'}', size: 54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                onTap: () => openPlayerProfile(context, ref, id),
                child: Text('${n['name'] ?? 'Player'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 5),
              Align(alignment: Alignment.centerLeft, child: chips(strs(n['summary']))),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: mine ? _goldDeep : p.hero,
                foregroundColor: mine ? const Color(0xFF2B1F05) : p.onHero,
                disabledBackgroundColor: mine ? _goldDeep : p.surface2,
                disabledForegroundColor: mine ? const Color(0xFF2B1F05) : p.muted,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: !canVote || mine || _voting != null ? null : () => _vote(id),
              child: _voting == id
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(mine ? '✓ Voted' : (myVote != null ? 'Change' : 'Vote'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      );
    }

    Widget splitRow(Map<String, dynamic> n) {
      final votes = (n['votes'] as num?)?.toInt() ?? 0;
      final share = (total ?? 0) > 0 ? votes / total! : 0.0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          PersonAvatar(url: n['avatarUrl'] as String?, name: '${n['name'] ?? '?'}', size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('${n['name'] ?? 'Player'}${myVote == n['playerId'] ? ' · your vote' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
                Text('$votes vote${votes == 1 ? '' : 's'}',
                    style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                    value: share, minHeight: 6, backgroundColor: p.surface2, valueColor: const AlwaysStoppedAnimation(_goldDeep)),
              ),
            ]),
          ),
        ]),
      );
    }

    Widget awardTile(Map<String, dynamic> a) {
      final w = a['winner'] is Map ? Map<String, dynamic>.from(a['winner'] as Map) : const <String, dynamic>{};
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.surface2.withAlpha(150), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14)),
            child: Text('${a['icon'] ?? '🏅'}', style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${a['label'] ?? ''}'.toUpperCase(),
                  style: TextStyle(color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
              GestureDetector(
                onTap: () => openPlayerProfile(context, ref, w['playerId'] as String?),
                child: Text('${w['name'] ?? 'Player'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              Text('${w['detail'] ?? ''}', style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
        ]),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(26),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header,
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (ofEvent != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () {
                      final slug = '${ofEvent['slug'] ?? ''}';
                      context.push('/events/${slug.isNotEmpty ? slug : ofEvent['id']}');
                    },
                    child: Text.rich(TextSpan(style: TextStyle(color: p.muted, fontSize: 12.5), children: [
                      const TextSpan(text: 'For all of '),
                      TextSpan(
                          text: '${ofEvent['title'] ?? 'the event'}',
                          style: TextStyle(color: p.ink, fontWeight: FontWeight.w600)),
                      const TextSpan(text: ', not just this game.'),
                    ])),
                  ),
                ),
              if (poll != null) ...[
                for (final n in nominees) open ? nomineeCard(n) : splitRow(n),
              ],
              if (open && poll?['reason'] is String)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.lock_outline_rounded, size: 14, color: p.muted),
                    const SizedBox(width: 4),
                    Flexible(child: Text('${poll!['reason']}', style: TextStyle(color: p.muted, fontSize: 12))),
                  ]),
                ),
              if (!open && awards.isNotEmpty) ...[
                if (poll != null) const SizedBox(height: 6),
                for (final a in awards) awardTile(a),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
