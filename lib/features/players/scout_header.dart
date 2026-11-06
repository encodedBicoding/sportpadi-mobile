import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The scouting half of a public profile (docs/design/scouting-profile.md) —
/// web twin: components/players/ScoutHeader.tsx.
///
/// Follow / Message, the headline tiles, honours and recent matches with the
/// player's match rating. Everything shown comes from officiated games: a
/// scout reads a record, not a self-description.

// ── data ────────────────────────────────────────────────────────────────────

/// `{ honours, recent, avgRating, ratedGames, games }` — the slowest profile
/// read, so it's its own provider and never holds the page. A failure reads
/// as "nothing to show" (a 403 is a private record, already handled above).
final playerHonoursProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, userId) async {
  try {
    final res = await ref
        .watch(dioProvider)
        .get('/api/mobile/players/$userId/honours');
    return res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
});

class FollowState {
  const FollowState({
    required this.followers,
    required this.followingCount,
    required this.following,
    required this.isMe,
  });
  final int followers;
  final int followingCount;
  final bool following;
  final bool isMe;

  factory FollowState.fromJson(Map<String, dynamic> j) => FollowState(
        followers: parseInt(j['followers']) ?? 0,
        followingCount: parseInt(j['followingCount']) ?? 0,
        following: j['following'] == true,
        isMe: j['isMe'] == true,
      );

  FollowState copyWith({int? followers, bool? following}) => FollowState(
        followers: followers ?? this.followers,
        followingCount: followingCount,
        following: following ?? this.following,
        isMe: isMe,
      );
}

final followStateProvider = FutureProvider.autoDispose
    .family<FollowState, String>((ref, userId) async {
  try {
    final res =
        await ref.watch(dioProvider).get('/api/mobile/players/$userId/follow');
    return FollowState.fromJson(
        res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {});
  } catch (_) {
    return const FollowState(
        followers: 0, followingCount: 0, following: false, isMe: false);
  }
});

/// `{ ok, reason, conversationId }` — may I message them from their profile?
final canMessageProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, userId) async {
  try {
    final res = await ref.watch(dioProvider).get('/api/mobile/messages',
        queryParameters: {'view': 'can-message', 'userId': userId});
    return res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{'ok': false};
  } catch (_) {
    return <String, dynamic>{'ok': false};
  }
});

// ── byline + chips ──────────────────────────────────────────────────────────

/// "Striker · Surrey, BC" and the sport / team chips a scout scans first.
class ScoutByline extends StatelessWidget {
  const ScoutByline({
    super.key,
    required this.primary,
    required this.sports,
    required this.teams,
    required this.playsIn,
  });

  /// The record category they play most (`{ categoryId, name, emoji, setup }`).
  final Map<String, dynamic>? primary;
  final List<Map<String, dynamic>> sports;
  final List<Map<String, dynamic>> teams;
  final String? playsIn;

  String? get _position {
    for (final t in teams) {
      final pos = parseStr(t['position']);
      if (pos != null) return pos;
    }
    final cid = primary?['categoryId'];
    for (final s in sports) {
      if (s['categoryId'] != cid) continue;
      final prefs = s['preferredPositions'];
      if (prefs is List && prefs.isNotEmpty) return '${prefs.first}';
    }
    for (final f in listOf(primary?['setup'])) {
      final key = '${f['key'] ?? ''}${f['label'] ?? ''}'.toLowerCase();
      if (key.contains('position')) {
        return parseStr(f['value'])?.split(',').first.trim();
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final byline = [_position, playsIn].whereType<String>().join(' · ');
    final name = parseStr(primary?['name']);
    final emoji = parseStr(primary?['emoji']);
    return Column(children: [
      if (byline.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(byline,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.muted, fontSize: 13)),
      ],
      if (name != null || teams.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            if (name != null)
              _Chip(
                  label: emoji != null ? '$emoji $name' : name,
                  bg: p.accentTint,
                  fg: p.greenText),
            for (final t in teams.take(2))
              _Chip(
                label: t['number'] != null
                    ? '${t['name']}  #${t['number']}'
                    : '${t['name']}',
                bg: p.surface2,
                fg: p.ink,
                onTap: () =>
                    context.push('/groups/${t['groupId']}/teams/${t['id']}'),
              ),
          ],
        ),
      ],
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label, required this.bg, required this.fg, this.onTap});
  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: bg,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(label,
                style: TextStyle(
                    color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      );
}

// ── follow counts + buttons ─────────────────────────────────────────────────

class FollowCounts extends ConsumerWidget {
  const FollowCounts({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final s = ref.watch(followStateProvider(userId)).valueOrNull;
    if (s == null) return const SizedBox.shrink();
    final n = TextStyle(
        color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w800);
    final l = TextStyle(color: p.muted, fontSize: 12.5);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        InkWell(
          onTap: () =>
              context.push('/players/$userId/followers?which=followers'),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${s.followers} ', style: n),
            TextSpan(text: 'followers', style: l),
          ])),
        ),
        Text('  ·  ', style: l),
        InkWell(
          onTap: () =>
              context.push('/players/$userId/followers?which=following'),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${s.followingCount} ', style: n),
            TextSpan(text: 'following', style: l),
          ])),
        ),
      ]),
    );
  }
}

/// Follow / Following — signed-out viewers are sent to sign in.
class FollowButton extends ConsumerStatefulWidget {
  const FollowButton({super.key, required this.userId, this.compact = false});
  final String userId;
  final bool compact;
  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  bool _busy = false;

  Future<void> _toggle(FollowState s) async {
    final me = ref.read(meProvider).valueOrNull;
    if (me == null) {
      context.push('/sign-in');
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dio = ref.read(dioProvider);
      if (s.following) {
        await dio.delete('/api/mobile/players/${widget.userId}/follow');
      } else {
        await dio.post('/api/mobile/players/${widget.userId}/follow');
      }
      ref.invalidate(followStateProvider(widget.userId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(apiError(e, fallback: 'Could not update.').message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = ref.watch(followStateProvider(widget.userId)).valueOrNull;
    // Never on your own profile — decided here too, so a failed or not-yet-
    // deployed follow call can't show a "Follow yourself" button.
    final me = ref.watch(meProvider).valueOrNull?.userId;
    if (s == null || s.isMe || (me != null && me == widget.userId)) {
      return const SizedBox.shrink();
    }
    final following = s.following;
    final bg = following ? p.surface2 : p.hero;
    final fg = following ? p.ink : p.onHero;
    return Material(
      color: bg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: _busy ? null : () => _toggle(s),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 12 : 16,
              vertical: widget.compact ? 7 : 11),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_busy)
              SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            else
              Icon(following ? Icons.check_rounded : Icons.person_add_alt_1,
                  size: 16, color: fg),
            const SizedBox(width: 6),
            Text(following ? 'Following' : 'Follow',
                style: TextStyle(
                    color: fg,
                    fontSize: widget.compact ? 13 : 14,
                    fontWeight: FontWeight.w700)),
            if (!widget.compact && s.followers > 0) ...[
              const SizedBox(width: 4),
              Text('· ${s.followers}',
                  style: TextStyle(
                      color: fg.withAlpha(180),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Message — opens the existing thread, or a sheet for the first message.
/// Hidden when the rules say no (their own profile, a minor, a private profile).
class MessageButton extends ConsumerWidget {
  const MessageButton({super.key, required this.userId, required this.name});
  final String userId;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final me = ref.watch(meProvider).valueOrNull;
    if (me?.userId == userId) return const SizedBox.shrink();
    final can = me == null ? null : ref.watch(canMessageProvider(userId)).valueOrNull;
    if (me != null && can != null && can['ok'] != true) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: p.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {
          if (me == null) {
            context.push('/sign-in');
            return;
          }
          final convId = parseStr(can?['conversationId']);
          if (convId != null) {
            context.push('/inbox/messages/$convId');
            return;
          }
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _FirstMessageSheet(userId: userId, name: name),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 16, color: p.ink),
            const SizedBox(width: 6),
            Text('Message',
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

class _FirstMessageSheet extends ConsumerStatefulWidget {
  const _FirstMessageSheet({required this.userId, required this.name});
  final String userId;
  final String name;
  @override
  ConsumerState<_FirstMessageSheet> createState() => _FirstMessageSheetState();
}

class _FirstMessageSheetState extends ConsumerState<_FirstMessageSheet> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await ref.read(dioProvider).post('/api/mobile/messages',
          data: {'action': 'start-direct', 'userId': widget.userId, 'body': body});
      final id = parseStr((res.data as Map?)?['conversationId']);
      ref.invalidate(canMessageProvider(widget.userId));
      if (!mounted) return;
      Navigator.of(context).pop();
      if (id != null) context.push('/inbox/messages/$id');
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            apiError(e, fallback: 'Could not send. Try again.').message);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final first = widget.name.split(RegExp(r'\s+')).first;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: p.line, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          Text('Message $first',
              style: TextStyle(
                  color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              "Say who you are and why you're getting in touch. They can reply, mute or report the thread.",
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                hintText: 'Hi — I saw your record on SportPadi…',
                counterText: ''),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: p.danger, fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          SpButton(
            label: _sending ? 'Sending…' : 'Send',
            icon: Icons.send_rounded,
            expand: true,
            onTap: _sending ? null : _send,
          ),
        ]),
      ),
    );
  }
}

// ── headline tiles ──────────────────────────────────────────────────────────

/// Games · the sport's first two tallies · average rating (the sport they
/// play most — stats never cross sports).
class HeadlineTiles extends StatelessWidget {
  const HeadlineTiles({
    super.key,
    required this.primary,
    required this.games,
    required this.avgRating,
    required this.loaded,
  });
  final Map<String, dynamic>? primary;
  final int? games;
  final double? avgRating;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final fields = listOf(primary?['fields']).take(2).toList();
    final counts = mapOf(mapOf(primary?['overall'])['counts']);
    final played = parseInt(mapOf(primary?['overall'])['games']) ?? 0;
    String v(dynamic x) => loaded ? '${x ?? 0}' : '–';
    return Row(children: [
      _Tile(value: v(games ?? played), label: 'Games'),
      for (final f in fields) ...[
        const SizedBox(width: 8),
        _Tile(value: v(counts[f['key']]), label: '${f['label'] ?? f['key']}'),
      ],
      if (fields.length < 2) ...[
        const SizedBox(width: 8),
        _Tile(value: v(played), label: parseStr(primary?['name']) ?? 'Played'),
      ],
      const SizedBox(width: 8),
      _Tile(
          value: avgRating == null ? '–' : avgRating!.toStringAsFixed(1),
          label: 'Avg rating',
          accent: true),
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label, this.accent = false});
  final String value;
  final String label;
  final bool accent;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: accent ? p.accentTint : p.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: accent ? p.greenText : p.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 11)),
        ]),
      ),
    );
  }
}

// ── honours + recent matches ────────────────────────────────────────────────

class RatingPill extends StatelessWidget {
  const RatingPill(this.value, {super.key, this.small = false});
  final double? value;
  final bool small;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final v = value;
    Color bg;
    Color fg;
    if (v == null) {
      bg = p.surface2;
      fg = p.muted;
    } else if (v >= 7.5) {
      bg = p.accentDeep;
      fg = Colors.white;
    } else if (v >= 6) {
      bg = p.surface2;
      fg = p.ink;
    } else {
      bg = p.orangeTint;
      fg = p.orangeInk;
    }
    return Container(
      constraints: BoxConstraints(minWidth: small ? 40 : 46),
      padding: EdgeInsets.symmetric(
          horizontal: small ? 8 : 10, vertical: small ? 4 : 6),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      alignment: Alignment.center,
      child: Text(v == null ? '–' : v.toStringAsFixed(1),
          style: TextStyle(
              color: fg,
              fontSize: small ? 12.5 : 13.5,
              fontWeight: FontWeight.w800)),
    );
  }
}

class HonoursSection extends StatelessWidget {
  const HonoursSection(
      {super.key,
      required this.honours,
      required this.loading,
      this.total,
      this.onMore});
  final List<Map<String, dynamic>> honours;
  final bool loading;

  /// When the list is a cut (top 3 on your own profile): the full count and
  /// where the rest are.
  final int? total;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final trimmed = total != null && total! > honours.length;
    final empty = !loading && honours.isEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SpSectionTitle('Honours',
          count: (total ?? honours.length) == 0 ? null : (total ?? honours.length),
          trailing: trimmed && onMore != null
              ? TextButton(onPressed: onMore, child: const Text('See all'))
              : null),
      const SizedBox(height: 8),
      if (loading)
        Container(
            height: 110,
            decoration: BoxDecoration(
                color: p.surface2, borderRadius: BorderRadius.circular(22)))
      else if (empty)
        GlassCard(
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: p.surface2, borderRadius: BorderRadius.circular(12)),
              child: const Text('🏅', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  "No honours yet. MVP votes, tournament and league awards, personal bests and streaks land here as they're earned.",
                  style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
            ),
          ]),
        )
      else
        SpListCard(children: [
          for (final h in honours)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: parseStr(h['href']) == null
                  ? null
                  : () => context.push(h['href'] as String),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: h['kind'] == 'mvp'
                          ? const Color(0xFFFFF4D6)
                          : p.surface2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(parseStr(h['icon']) ?? '🏅',
                        style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(parseStr(h['title']) ?? 'Award',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                            [
                              parseStr(h['detail']),
                              _monthYear(parseDate(h['at'])),
                            ].whereType<String>().join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
        ]),
      const SizedBox(height: 18),
    ]);
  }
}

String? _monthYear(DateTime? d) {
  if (d == null) return null;
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[d.month - 1]} ${d.year}';
}

String _dayMonth(DateTime? d) {
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]}';
}

class RecentMatchesSection extends StatelessWidget {
  const RecentMatchesSection(
      {super.key,
      required this.recent,
      required this.loading,
      required this.playerId});
  final List<Map<String, dynamic>> recent;
  final bool loading;
  final String playerId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (!loading && recent.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SpSectionTitle('Recent matches'),
      const SizedBox(height: 8),
      if (loading)
        Container(
            height: 150,
            decoration: BoxDecoration(
                color: p.surface2, borderRadius: BorderRadius.circular(22)))
      else
        SpListCard(children: [
          for (final m in recent) _MatchRow(m: m, playerId: playerId),
        ]),
      const SizedBox(height: 18),
    ]);
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.m, required this.playerId});
  final Map<String, dynamic> m;
  final String playerId;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final us = mapOf(m['us']);
    final them = m['them'] is Map ? mapOf(m['them']) : null;
    final result = parseStr(m['result']);
    final score = them == null
        ? '${us['name']} · ${us['score']}'
        : '${us['name']} ${us['score']}–${them['score']} ${them['name']}';
    final line = [
      for (final l in listOf(m['line']))
        '${parseStr(l['icon']) ?? l['label']} ${l['value']}'
    ].join(' · ');
    final sub = [
      m['scope'] == 'tournament' ? (parseStr(m['eventTitle']) ?? 'Tournament') : 'Pickup',
      _dayMonth(parseDate(m['date'])),
      if (line.isNotEmpty) line,
    ].join(' · ');
    final (Color bg, Color fg, String letter) = switch (result) {
      'win' => (p.accentTint, p.greenText, 'W'),
      'loss' => (p.orangeTint, p.orangeInk, 'L'),
      'draw' => (p.surface2, p.muted, 'D'),
      _ => (p.surface2, p.muted, '·'),
    };
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/players/$playerId/events/${m['eventId']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(12)),
            child: Text(letter,
                style: TextStyle(
                    color: fg, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(score,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 8),
          RatingPill(parseDouble(m['rating']), small: true),
        ]),
      ),
    );
  }
}

/// "Stats recorded by match officiants · 38 games on SportPadi"
class RecordFootnote extends StatelessWidget {
  const RecordFootnote({super.key, required this.games});
  final int? games;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final g = games ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.emoji_events_outlined, size: 14, color: p.muted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
              'Stats recorded by match officiants${g > 0 ? ' · $g game${g == 1 ? '' : 's'} on SportPadi' : ''}',
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 11.5)),
        ),
      ]),
    );
  }
}

// ── followers screen ────────────────────────────────────────────────────────

/// /players/:id/followers?which=followers|following
class FollowersScreen extends ConsumerStatefulWidget {
  const FollowersScreen({super.key, required this.userId, this.which = 'followers'});
  final String userId;
  final String which;
  @override
  ConsumerState<FollowersScreen> createState() => _FollowersScreenState();
}

class _FollowersScreenState extends ConsumerState<FollowersScreen> {
  late String _which = widget.which == 'following' ? 'following' : 'followers';
  final _items = <Map<String, dynamic>>[];
  String? _cursor;
  bool _loading = true;
  bool _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _items.clear();
        _cursor = null;
      });
    }
    try {
      final res = await ref.read(dioProvider).get(
          '/api/mobile/players/${widget.userId}/follow',
          queryParameters: {
            'view': 'list',
            'which': _which,
            if (_cursor != null) 'cursor': _cursor,
          });
      final m = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
      if (!mounted) return;
      setState(() {
        _items.addAll(listOf(m['items']));
        _cursor = parseStr(m['nextCursor']);
        _more = _cursor != null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiError(e, fallback: 'Could not load.').message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = ref.watch(followStateProvider(widget.userId)).valueOrNull;
    final who = ref.watch(meProvider).valueOrNull;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: Text(_which == 'followers' ? 'Followers' : 'Following'),
        backgroundColor: p.bg,
        foregroundColor: p.ink,
        elevation: 0,
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SpSegmented(
            index: _which == 'followers' ? 0 : 1,
            options: const ['Followers', 'Following'],
            badges: [
              state == null || state.followers == 0 ? null : state.followers,
              state == null || state.followingCount == 0
                  ? null
                  : state.followingCount,
            ],
            onChanged: (i) {
              setState(() => _which = i == 0 ? 'followers' : 'following');
              _load(reset: true);
            },
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Text(_error!,
                          style: TextStyle(color: p.muted)))
                  : _items.isEmpty
                      ? Center(
                          child: Text(
                              _which == 'followers'
                                  ? 'No followers yet.'
                                  : 'Not following anyone yet.',
                              style: TextStyle(color: p.muted)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: _items.length + (_more ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _items.length) {
                              return Center(
                                child: TextButton(
                                    onPressed: _load, child: const Text('Show more')),
                              );
                            }
                            final u = _items[i];
                            final id = parseStr(u['userId']) ?? '';
                            final name = parseStr(u['displayName']) ?? 'Player';
                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => context.push('/players/$id'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(children: [
                                  ClipOval(
                                    child: Crest(
                                        logoUrl: parseStr(u['avatarUrl']),
                                        label: name,
                                        size: 40),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: p.ink,
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w700)),
                                        if (parseStr(u['username']) != null)
                                          Text('@${u['username']}',
                                              style: TextStyle(
                                                  color: p.muted, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  if (who?.userId != id)
                                    FollowButton(userId: id, compact: true),
                                ]),
                              ),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}
