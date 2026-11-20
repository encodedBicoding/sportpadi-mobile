import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/highlights/highlight_models.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/highlights/highlight_visitor.dart';
import 'package:sportpadi_mobile/features/highlights/highlights_screen.dart';
import 'package:sportpadi_mobile/features/players/scout_header.dart';

/// Follow, beside the player a highlight is about (owner, 2026-11-18:
/// Discover is for finding players, and this is how a following grows —
/// workspace `docs/wiki/highlights.md`). Web twin:
/// `components/highlights/HighlightCard.tsx` + `follows.ts`.

/// Who this viewer has followed (or unfollowed, on a profile) since the
/// posts on screen were fetched: user id → following. Every highlight list
/// (the two feeds, a profile's grid, a match reel, one post) keeps its own
/// copy of its posts; the button reads this first, so a follow takes the
/// button off EVERY post by that player at once, wherever it sits. Starts
/// empty for each account.
final highlightFollowSeenProvider = StateProvider<Map<String, bool>>((ref) {
  ref.watch(authControllerProvider.select((s) => s.valueOrNull?.user?.id));
  return const <String, bool>{};
});

/// The same, for a REQUEST of mine that waits (a private adult): user id →
/// requested. Its own map, never folded into "following" (review
/// profile-header-app MED-2: the reel said "Following ✓" after a request).
final highlightRequestSeenProvider = StateProvider<Map<String, bool>>((ref) {
  ref.watch(authControllerProvider.select((s) => s.valueOrNull?.user?.id));
  return const <String, bool>{};
});

/// Record where I now stand with [userId] (a follow, a request, neither),
/// from anywhere in the app — the reel's pill and the profile's button agree
/// both ways.
void noteHighlightFollow(ProviderContainer c, String userId, bool following,
    {bool requested = false}) {
  if (userId.isEmpty) return;
  final req = requested && !following;
  final seen = c.read(highlightFollowSeenProvider);
  if (seen[userId] != following) {
    c.read(highlightFollowSeenProvider.notifier).state = {
      ...seen,
      userId: following,
    };
  }
  final asked = c.read(highlightRequestSeenProvider);
  if (asked[userId] != req) {
    c.read(highlightRequestSeenProvider.notifier).state = {
      ...asked,
      userId: req,
    };
  }
}

/// A follow / unfollow of [userId] went through somewhere (this button, or
/// their profile's [FollowButton]): every post by them says so, and the
/// Following feed starts afresh the next time it opens — its posts changed.
/// (While it is the one on screen it re-saves itself as it scrolls, and is
/// never reloaded under the viewer's thumb.)
void highlightFollowChanged(ProviderContainer c, String userId, bool following,
    {bool requested = false}) {
  noteHighlightFollow(c, userId, following, requested: requested);
  c.read(highlightFeedMemoryProvider).feeds.remove('following');
}

/// Who is signed in right now, as far as the follow bookkeeping cares: an
/// answer that lands after this changed belongs to an account that is gone
/// and is dropped (review LOW-2; the web's `mine()` guard).
String? signedInUserId(ProviderContainer c) =>
    c.read(authControllerProvider).valueOrNull?.user?.id;

/// Follow [userId] from a highlight: the button goes at once (every post by
/// them), the follow is sent through the profile's own route
/// (`POST /api/mobile/players/:id/follow`, as [FollowButton] does), and what
/// depends on follows is read again — their follower count, my own
/// "following", open follower lists, and the Following feed the next time it
/// opens. On a refusal the button comes back and the error is rethrown for
/// the caller to show.
///
/// Returns what the SERVER made of it — a follow, or a request to a private
/// adult (`requested: true`, review profile-header-app MED-2) — or null, and
/// writes nothing and throws nothing, when the signed-in account changed
/// while the follow was on its way: the next person's state is not the last
/// one's. [asking]: what the post said a tap would be (`canRequest` without
/// `canFollow`), written at once and corrected by the answer.
///
/// Takes the container, not a `WidgetRef`: the card may be scrolled away
/// (and disposed) before the server answers.
Future<({bool following, bool requested})?> followHighlightSubject(
    ProviderContainer c, String userId,
    {bool asking = false}) async {
  final who = signedInUserId(c);
  if (who == null) return null;
  noteHighlightFollow(c, userId, !asking, requested: asking);
  final Object? answer;
  try {
    answer = (await c.read(dioProvider).post('/api/mobile/players/$userId/follow'))
        .data;
  } catch (_) {
    if (signedInUserId(c) != who) return null;
    noteHighlightFollow(c, userId, false);
    rethrow;
  }
  if (signedInUserId(c) != who) return null;
  // An older server answers without `requested`: read a missing
  // `following` as the follow it then always was.
  final following =
      answer is Map ? answer['following'] != false : !asking;
  final requested = answer is Map && answer['requested'] == true;
  c.invalidate(followStateProvider);
  followsChanged.value++;
  highlightFollowChanged(c, userId, following, requested: requested);
  return (following: following, requested: requested);
}

/// The compact outlined "Follow" pill beside a player's name on the reel.
/// Shown only when the server says the follow would go through or would be a
/// request, and the viewer neither follows them nor has asked; after a tap it
/// reads "Following ✓" — or "Requested", by the server's answer — for a
/// moment on this card, then goes. No unfollow here: that stays on the
/// profile.
///
/// A signed-out visitor ([onVisitor] given and `highlightVisitorProvider`
/// true) sees the pill on every post that is up — the server only hands them
/// public adults' posts, and says `canFollow: false` to nobody in particular —
/// and a tap calls [onVisitor] (the sign-up sheet) instead of following.
class HighlightFollowButton extends ConsumerStatefulWidget {
  const HighlightFollowButton(
      {super.key, required this.item, this.gap = 0, this.onVisitor});

  final HighlightItem item;

  /// A visitor tapped it: ask them to sign up.
  final VoidCallback? onVisitor;

  /// Space before the pill — only taken while there is a pill to show.
  final double gap;

  @override
  ConsumerState<HighlightFollowButton> createState() =>
      _HighlightFollowButtonState();
}

class _HighlightFollowButtonState extends ConsumerState<HighlightFollowButton> {
  static const _flashFor = Duration(milliseconds: 1500);
  static const _shadow = [Shadow(color: Color(0x99000000), blurRadius: 6)];

  /// The moment after a tap: null, or what it became — "following" /
  /// "requested" (the server's answer corrects the first guess).
  String? _justFollowed;
  bool _sending = false;
  Timer? _flash;

  @override
  void dispose() {
    _flash?.cancel();
    super.dispose();
  }

  Future<void> _follow() async {
    final userId = widget.item.subject.userId;
    if (_sending || userId.isEmpty) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final fallback = context.l10n.event_couldNotFollow;
    final f = widget.item.follow;
    final asking = !f.canFollow && f.canRequest;
    setState(() {
      _sending = true;
      _justFollowed = asking ? 'requested' : 'following';
    });
    _flash?.cancel();
    _flash = Timer(_flashFor, () {
      if (mounted) setState(() => _justFollowed = null);
    });
    try {
      // null = another account is signed in now: nothing of this is theirs.
      final made =
          await followHighlightSubject(container, userId, asking: asking);
      if (made != null && mounted && _justFollowed != null) {
        setState(() => _justFollowed =
            made.following ? 'following' : 'requested');
      }
    } catch (e) {
      _flash?.cancel();
      if (mounted) setState(() => _justFollowed = null);
      messenger.showSnackBar(
          SnackBar(content: Text(apiError(e, fallback: fallback).message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final subject = item.subject.userId;
    final me = ref.watch(
        authControllerProvider.select((s) => s.valueOrNull?.user?.id));
    final seen =
        ref.watch(highlightFollowSeenProvider.select((m) => m[subject]));
    final asked =
        ref.watch(highlightRequestSeenProvider.select((m) => m[subject]));
    final following = seen ?? item.follow.following;
    final requested = asked ?? item.follow.requested;
    final visitor =
        widget.onVisitor != null && ref.watch(highlightVisitorProvider);
    if (visitor) {
      if (!item.isReady || subject.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsetsDirectional.only(start: widget.gap),
        child: _button(context.l10n, item, onTap: widget.onVisitor),
      );
    }
    // Only on a post that is up: not on one the server's check took down,
    // nor on the author's own unfinished one (review LOW-3).
    final canFollow = item.isReady &&
        (item.follow.canFollow || item.follow.canRequest) &&
        subject.isNotEmpty &&
        subject != me;
    final flash = _justFollowed;
    if (!canFollow || ((following || requested) && flash == null)) {
      return const SizedBox.shrink();
    }
    final l = context.l10n;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: widget.gap),
      child: flash != null
          ? _followed(l, requested: flash == 'requested')
          : _button(l, item, onTap: _sending ? null : _follow),
    );
  }

  Widget _followed(AppLocalizations l, {bool requested = false}) => Semantics(
        liveRegion: true,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: const ShapeDecoration(
              color: Color(0x33FFFFFF), shape: StadiumBorder()),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_rounded, size: 15, color: Colors.white),
            const SizedBox(width: 4),
            // Its own word, not profile_following: that one is gendered in
            // Arabic ("you follow her"), and this shows on every player. A
            // request is "Requested" (profile_requested — neutral).
            Text(requested ? l.profile_requested : l.highlights_followingNow,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    shadows: _shadow)),
          ]),
        ),
      );

  Widget _button(AppLocalizations l, HighlightItem item,
          {required VoidCallback? onTap}) =>
      Semantics(
      button: true,
      label: l.highlights_followName(item.subject.displayName),
      excludeSemantics: true,
      // A taller hit area than the pill itself (it sits in a 38 px row).
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: const ShapeDecoration(
              color: Color(0x40000000),
              shape: StadiumBorder(
                  side: BorderSide(color: Color(0xD9FFFFFF), width: 1.2)),
            ),
            child: Text(l.profile_follow,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    shadows: _shadow)),
          ),
        ),
      ),
    );
}
