import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/links/link_resolver.dart'
    show resolveLinkRoute;
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/highlights/highlights_repository.dart'
    show highlightsChanged;
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/highlights/highlight_follow.dart';
import 'package:sportpadi_mobile/features/players/player_record.dart';
import 'package:sportpadi_mobile/features/players/profile_header.dart'
    show ProfilePill;
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// The scouting half of a public profile (docs/design/scouting-profile.md) —
/// web twin: components/players/ScoutHeader.tsx.
///
/// Follow / Message (the pills under the header, `profile_header.dart`), the
/// per-sport rating tiles, honours and recent matches with the player's match
/// rating (the Records tab since the Instagram-style header, 2026-11-19).
/// Everything shown comes from officiated games: a scout reads a record, not
/// a self-description.

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

/// `follows.state` (docs/wiki/api.md "Follows and follow requests"). A server
/// from before requests sends none of the request fields: they read as "no
/// request, public, may see it", the old behaviour.
class FollowState {
  const FollowState({
    required this.followers,
    required this.followingCount,
    required this.following,
    required this.isMe,
    this.canFollow = true,
    this.requested = false,
    this.canRequest = false,
    this.isPrivate = false,
    this.canSeeProfile = true,
    this.hiddenReason,
    this.followsMe = false,
    this.requestCount = 0,
    this.highlights,
  });
  final int followers;
  final int followingCount;

  /// I follow them (accepted).
  final bool following;
  final bool isMe;

  /// Follow goes straight through (2026-11-19): false for a guardian on their
  /// own child's profile, a profile hidden from me — and a private adult I
  /// don't follow ([canRequest] then). A server that doesn't send it is read
  /// as true, the old behaviour.
  final bool canFollow;

  /// My follow request to them is waiting.
  final bool requested;

  /// Follow would send a request (an adult's private profile).
  final bool canRequest;

  /// Their "private profile" is on (the lock beside the @username).
  final bool isPrivate;

  /// I may see the profile in full (theirs, public, or an accepted follower).
  final bool canSeeProfile;

  /// Why not: "private" (the private-profile header) or "limited" (a child
  /// their guardians keep limited).
  final String? hiddenReason;

  /// They follow me (accepted) — "Follow back", "Follows you".
  final bool followsMe;

  /// My own profile: follow requests waiting for me (0 otherwise).
  final int requestCount;

  /// The header's post count (2026-11-20): exactly the ready highlights my
  /// grid of them lists (a private adult I'm not let into: what an accepted
  /// follower's lists). Null — a child kept limited, a guest the visitor rule
  /// keeps out, or a server older than the count — hides the cell.
  final int? highlights;

  factory FollowState.fromJson(Map<String, dynamic> j) => FollowState(
        followers: parseInt(j['followers']) ?? 0,
        followingCount: parseInt(j['followingCount']) ?? 0,
        following: j['following'] == true,
        isMe: j['isMe'] == true,
        canFollow: j['canFollow'] != false,
        requested: j['requested'] == true,
        canRequest: j['canRequest'] == true,
        isPrivate: j['isPrivate'] == true,
        canSeeProfile: j['canSeeProfile'] != false,
        hiddenReason: parseStr(j['hiddenReason']),
        followsMe: j['followsMe'] == true,
        requestCount: parseInt(j['requestCount']) ?? 0,
        highlights: parseInt(j['highlights']),
      );
}

/// Bumped after I follow / unfollow someone, so open follower lists
/// (which page with their own state, not a provider) re-read.
final followsChanged = ValueNotifier<int>(0);

/// `follows.state`. A failure is an ERROR, not a made-up answer (review
/// profile-header-app LOW): the old fallback said "may follow, may see",
/// which put a Follow pill and "Follow this account…" in front of a child
/// viewer. Readers use `valueOrNull` (null = unknown: no pill, '–' counts)
/// and the locked page offers a retry.
final followStateProvider = FutureProvider.autoDispose
    .family<FollowState, String>((ref, userId) async {
  // A post made, deleted or re-linked anywhere in the app changes a profile
  // header's "N highlights" (review profile-counts-records MED-2): re-read,
  // as the grids do. The last answer stays on screen meanwhile.
  void changed() => ref.invalidateSelf();
  highlightsChanged.addListener(changed);
  ref.onDispose(() => highlightsChanged.removeListener(changed));
  try {
    final res =
        await ref.watch(dioProvider).get('/api/mobile/players/$userId/follow');
    return FollowState.fromJson(
        res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {});
  } catch (e) {
    throw apiError(e, fallback: l10n.profile_couldNotLoad);
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
    this.alignStart = false,
    this.showByline = true,
  });

  /// Left-aligned chips (the Instagram-style profile header).
  final bool alignStart;

  /// False when the byline is shown elsewhere (the header puts it under the
  /// name) and only the chips are wanted here.
  final bool showByline;

  /// "Striker · Surrey, BC" — their position and where they play.
  String get byline => [_position, playsIn].whereType<String>().join(' · ');

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
    final line = showByline ? byline : '';
    final name = parseStr(primary?['name']);
    final emoji = parseStr(primary?['emoji']);
    return Column(
        crossAxisAlignment:
            alignStart ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
      if (line.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(line,
            textAlign: alignStart ? TextAlign.start : TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: p.muted, fontSize: 13)),
      ],
      if (name != null || teams.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(
          alignment: alignStart ? WrapAlignment.start : WrapAlignment.center,
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
                // The team's page. The web links it as
                // /groups/<group>/teams/<team>; the app's page for a group
                // team is /teams/<team> (link_resolver maps one to the
                // other) — pushing the web's path verbatim found no route
                // and broke the page.
                onTap: parseStr(t['id']) == null
                    ? null
                    : () => context.push('/teams/${parseStr(t['id'])}'),
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

/// The follow pill, Instagram's states (`follows.state`): Following ▾ (a
/// sheet to unfollow — with a warning on a private profile, where coming
/// back takes a new request), Requested (a tap withdraws the request),
/// Follow back (they follow me), Follow (straight through, or a request to a
/// private adult). Nothing when the server would refuse either (a guardian
/// on their own child, a hidden child, a managed account) or on your own
/// profile. No follower count on it (the owner asked): the counts are the
/// header's. Signed-out viewers are sent to sign in.
class FollowButton extends ConsumerStatefulWidget {
  const FollowButton({
    super.key,
    required this.userId,
    this.name,
    this.compact = false,
    this.expand = false,
  });
  final String userId;

  /// The unfollow sheet's title.
  final String? name;
  final bool compact;

  /// Fill the width it is given (the header's pills row).
  final bool expand;
  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  bool _busy = false;

  /// The server's answer to my last tap, shown until the re-read of
  /// `follows.state` lands (review profile-header-app MED-1: the pill showed
  /// its OLD label for a round trip — Riverpod keeps the previous value while
  /// an invalidated provider re-reads — and a second tap then undid the
  /// first). The spinner stays up for that whole time; no tap goes through.
  ({bool following, bool requested})? _answer;

  /// follow | unfollow | cancel (my waiting request).
  Future<void> _act(String kind) async {
    final me = ref.read(meProvider).valueOrNull;
    if (me == null) {
      context.push('/sign-in');
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final who = signedInUserId(container);
    try {
      final dio = ref.read(dioProvider);
      final path = '/api/mobile/players/${widget.userId}/follow';
      final Object? answer;
      if (kind == 'unfollow') {
        answer = (await dio.delete(path)).data;
      } else if (kind == 'cancel') {
        answer = (await dio.post(path, data: {'action': 'cancel-request'})).data;
      } else {
        // On a private adult this is a request (`requested: true` back).
        answer = (await dio.post(path)).data;
      }
      final following = answer is Map && answer['following'] == true;
      final requested = answer is Map && answer['requested'] == true;
      if (mounted) {
        setState(() => _answer = (following: following, requested: requested));
      }
      // The Follow button on their highlights reads this too: a reel kept
      // in memory must neither offer a follow just made here nor hide one
      // just undone — nor call a request a follow.
      // ...unless another account signed in meanwhile (review LOW-2).
      if (signedInUserId(container) == who) {
        highlightFollowChanged(container, widget.userId, following,
            requested: requested);
      }
      // Every follow count on screen, not just theirs: my own "following"
      // on the Me tab (kept alive by the shell, so it never re-reads by
      // itself) and any list showing either of us. A private profile's page
      // re-reads itself when this says it may now (or may no longer) be seen.
      ref.invalidate(followStateProvider);
      followsChanged.value++;
      // Hold the spinner (and the answer) until the fresh state is here.
      if (mounted) {
        try {
          await ref.read(followStateProvider(widget.userId).future);
        } catch (_) {
          // The pill shows the answer it has; a pull re-reads.
        }
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(apiError(e, fallback: l10n.profile_couldNotUpdate2).message)));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _answer = null;
        });
      }
    }
  }

  /// "Requested" asks before it withdraws (as Instagram does): with the
  /// request notice's weekly cooldown, a mis-tap and a re-ask would leave them
  /// with no notification.
  void _withdrawSheet() {
    showSpSheet<void>(
      context,
      builder: (ctx) {
        final p = ctx.palette;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpSheetHeader(
              title: ctx.l10n.profile_withdrawRequestTitle,
              subtitle: ctx.l10n.profile_withdrawRequestText,
            ),
            Material(
              color: Colors.transparent,
              shape: StadiumBorder(side: BorderSide(color: p.line)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _act('cancel');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Text(ctx.l10n.profile_cancelRequest,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: p.danger,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _unfollowSheet(FollowState s) {
    showSpSheet<void>(
      context,
      builder: (ctx) {
        final p = ctx.palette;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpSheetHeader(
              title: widget.name ?? ctx.l10n.profile_following,
              subtitle: s.isPrivate ? ctx.l10n.profile_unfollowPrivateNote : null,
            ),
            Material(
              color: Colors.transparent,
              shape: StadiumBorder(side: BorderSide(color: p.line)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _act('unfollow');
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Text(ctx.l10n.profile_unfollow,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: p.danger,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(followStateProvider(widget.userId)).valueOrNull;
    // Never on your own profile — decided here too, so a failed or not-yet-
    // deployed follow call can't show a "Follow yourself" button.
    final me = ref.watch(meProvider).valueOrNull?.userId;
    if (s == null || s.isMe || (me != null && me == widget.userId)) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    final a = _answer;
    final following = a?.following ?? s.following;
    final requested = a != null ? a.requested && !a.following : s.requested;
    if (following) {
      return ProfilePill(
        label: l.profile_following,
        trailingIcon: Icons.expand_more_rounded,
        busy: _busy,
        compact: widget.compact,
        expand: widget.expand,
        onTap: () => _unfollowSheet(s),
      );
    }
    if (requested) {
      return ProfilePill(
        label: l.profile_requested,
        tooltip: l.profile_cancelRequest,
        busy: _busy,
        compact: widget.compact,
        expand: widget.expand,
        onTap: _withdrawSheet,
      );
    }
    // Nothing to offer when the follow would be refused (the reel's rule
    // too).
    if (!s.canFollow && !s.canRequest && a == null) {
      return const SizedBox.shrink();
    }
    return ProfilePill(
      label: s.followsMe ? l.profile_followBack : l.profile_follow,
      icon: Icons.person_add_alt_1,
      filled: true,
      busy: _busy,
      compact: widget.compact,
      expand: widget.expand,
      onTap: () => _act('follow'),
    );
  }
}

/// Message — opens the existing thread, or a sheet for the first message.
/// Hidden when the rules say no (their own profile, a minor, a private profile).
class MessageButton extends ConsumerWidget {
  const MessageButton(
      {super.key, required this.userId, required this.name, this.expand = false});
  final String userId;
  final String name;

  /// Fill the width it is given (the header's pills row).
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).valueOrNull;
    if (me?.userId == userId) return const SizedBox.shrink();
    final can = me == null ? null : ref.watch(canMessageProvider(userId)).valueOrNull;
    if (me != null && can != null && can['ok'] != true) {
      return const SizedBox.shrink();
    }
    return ProfilePill(
        label: context.l10n.profile_message,
        icon: Icons.chat_bubble_outline_rounded,
        expand: expand,
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
        });
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
            apiError(e, fallback: l10n.profile_couldNotSendTryAgain).message);
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
          Text(context.l10n.profile_message3(first),
              style: TextStyle(
                  color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              context.l10n.profile_sayWhoYouAreAnd,
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
            decoration: InputDecoration(
                hintText: context.l10n.profile_hiISawYourRecord,
                counterText: ''),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: p.danger, fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          SpButton(
            label: _sending ? context.l10n.profile_sending : context.l10n.profile_send,
            icon: Icons.send_rounded,
            expand: true,
            onTap: _sending ? null : _send,
          ),
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
      SpSectionTitle(context.l10n.profile_honours,
          count: (total ?? honours.length) == 0 ? null : (total ?? honours.length),
          trailing: trimmed && onMore != null
              ? TextButton(onPressed: onMore, child: Text(context.l10n.profile_seeAll))
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
                  context.l10n.profile_noHonoursYetMvpVotes,
                  style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
            ),
          ]),
        )
      else
        SpListCard(children: [
          for (final h in honours)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              // `href` is a web path (/e/<slug>, /events/<id>, /leagues/<x>):
              // resolved the way pushes and shared links are — /e/<slug> has
              // no app route of its own and pushed verbatim it broke the page.
              onTap: resolveLinkRoute(parseStr(h['href'])) == null
                  ? null
                  : () => context.push(resolveLinkRoute(parseStr(h['href']))!),
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
                        Text(parseStr(h['title']) ?? context.l10n.profile_award,
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
      SpSectionTitle(context.l10n.profile_recentMatches),
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
              g > 0
                  ? context.l10n.profile_p5StatsRecordedGamesOnSportPadi(g)
                  : context.l10n.profile_statsRecordedByMatchOfficiants,
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
  // Bumped by each reset so an older page still in flight is dropped.
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    followsChanged.addListener(_onFollowsChanged);
  }

  @override
  void dispose() {
    followsChanged.removeListener(_onFollowsChanged);
    super.dispose();
  }

  // I followed / unfollowed someone (here or on a profile opened from here).
  void _onFollowsChanged() {
    if (mounted) _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    final gen = reset ? ++_gen : _gen;
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
      if (!mounted || gen != _gen) return;
      setState(() {
        _items.addAll(listOf(m['items']));
        _cursor = parseStr(m['nextCursor']);
        _more = _cursor != null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = apiError(e, fallback: l10n.profile_couldNotLoad).message;
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
        title: Text(_which == 'followers' ? context.l10n.profile_followers : context.l10n.profile_following),
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
                                  ? context.l10n.profile_noFollowersYet
                                  : context.l10n.profile_notFollowingAnyoneYet,
                              style: TextStyle(color: p.muted)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: _items.length + (_more ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _items.length) {
                              return Center(
                                child: TextButton(
                                    onPressed: _load, child: Text(context.l10n.profile_showMore)),
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
