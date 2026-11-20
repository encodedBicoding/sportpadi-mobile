import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/links/link_resolver.dart' show HomeTab;
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/data/highlights/highlight_models.dart';
import 'package:sportpadi_mobile/data/highlights/highlights_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart'
    show authControllerProvider;
import 'package:sportpadi_mobile/features/highlights/highlight_viewer.dart';
import 'package:sportpadi_mobile/features/highlights/highlight_visitor.dart';
import 'package:sportpadi_mobile/features/highlights/highlights_screen.dart'
    show highlightFeedMemoryProvider, highlightShowDiscover;
import 'package:sportpadi_mobile/features/shell/home_shell.dart'
    show homeTabIndexProvider;

/// The ids the API takes. A reel address is only ever minted by a timeline
/// badge, so anything else in `?gameId=` / `?activityId=` is not an origin —
/// the rule the web's `reelOriginOf` keeps, which is why `?gameId=junk` is
/// one post on both clients rather than a reel that ends at once.
final _reelUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

/// A profile tile's origin (`?from=player:<uuid>`, the web's
/// `playerReelHref`), and nothing looser: `from` names a player or nothing.
final _reelFrom = RegExp(
    r'^player:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$',
    caseSensitive: false);

/// One highlight by id (`/highlights/:id`) in the same viewer as the feed —
/// where a notification, a shared link, a timeline badge and a profile tile
/// all land.
///
/// What scrolling on shows depends on where the post was opened FROM
/// (workspace `docs/wiki/highlights.md`, "Where a highlight was opened
/// from") — one reel, three sources:
///  * [fromGameId] — only a match timeline's play badge sends it: the match
///    REEL, the post they tapped, then every other highlight of the whole
///    event, and running off the end takes them back to that timeline;
///  * [from] `player:<id>` — a profile's Highlights tile: that player's reel
///    (`byPlayer` + `firstId`: the tapped post, then the OLDER ones down to the
///    oldest — no wrap, the owner's call), and the end pops back to the
///    profile with the tile's id;
///  * neither — a notification, a shared link, a chat card: the post, then
///    ALL the other highlights of the player it is ABOUT (once `get` has said
///    who: their grid from the newest, no `firstId`), and the end stays on
///    "That's all from …" — a subject reel never navigates by itself.
/// A post whose subject this viewer isn't shown (no id) is one post, with no
/// page after it, as before.
///
/// The server answers 404 both for a post that doesn't exist and for one
/// this viewer may not see, so there is a single honest "can't be shown"
/// state for both — for a signed-out visitor it says the post may only be
/// visible signed in, and offers that (a ward's, an under-18's, a private
/// profile's post is; workspace `docs/wiki/highlights.md` "Visitors").
/// A visitor opens this page too (the router lets them), reel and all.
class HighlightDetailScreen extends ConsumerStatefulWidget {
  const HighlightDetailScreen(
      {super.key,
      required this.id,
      this.fromGameId,
      this.fromActivityId,
      this.from,
      this.openComments = false});
  final String id;

  /// `?from=` — `player:<uuid>` from a profile's Highlights tile; anything
  /// else is no origin. A match origin ([fromGameId]) wins over it.
  final String? from;

  /// `?comments=1`: open the post with its comments showing — where a
  /// visitor who signed up to comment comes back to.
  final bool openComments;

  /// The match whose timeline opened this post (`?gameId=` of the reel
  /// address both clients make). `byEvent` is keyed by a match — it answers
  /// for that match's EVENT — and that timeline is where the reel ends.
  final String? fromGameId;

  /// The stat whose badge was tapped (`?activityId=` of the same address).
  /// What was asked for is the row they came FROM, and popping restores the
  /// timeline's scroll OFFSET, not a row: a live match that gained — or
  /// lost — stats while they watched has moved that row. So every way out
  /// of a reel carries the stat and the timeline re-finds it
  /// (`game_screen.dart` `_scrollToStat`; `?stat=` when there is nothing to
  /// pop, which is the web's own parameter for the same thing).
  final String? fromActivityId;

  @override
  ConsumerState<HighlightDetailScreen> createState() =>
      _HighlightDetailScreenState();
}

class _HighlightDetailScreenState
    extends ConsumerState<HighlightDetailScreen> {
  /// The post as changed on this screen (a like, a comment count, a link).
  HighlightItem? _local;
  bool _deleted = false;

  /// It went away while it was open (deleted elsewhere, or no longer
  /// visible to this viewer).
  bool _gone = false;

  /// The first of the two extra reads of a freshly posted app video has
  /// been made.
  bool _settledOnce = false;

  /// No more of them are due.
  bool _settled = false;
  Timer? _poll;

  /// An app video is read again this long after it was posted, once more
  /// after [_settleAgainAfter] (the server's check can run late), and not
  /// at all once it is older than [_settleUntil].
  static const _settleAfter = Duration(seconds: 60);
  static const _settleAgainAfter = Duration(minutes: 3);
  static const _settleUntil = Duration(minutes: 5);

  // ── the reel (nothing below does anything without an origin) ───────────

  /// The reel's other highlights after the tapped post: the event's, in the
  /// event's order (`ready` posts pinned to stats that still stand, nothing
  /// else), or a player's older ones in grid order. A player's grid — and so a
  /// player or subject reel — also holds the VIEWER's own posts still
  /// processing or failed, as the grid does (nobody else is ever handed
  /// them): those few are re-read on the poll's tick ([_rereadProcessing]).
  final List<HighlightItem> _reel = [];
  String? _cursor;

  /// The server answered `nextCursor: null` — there is no next page. The one
  /// thing that lets [_snapBack] fire: on a page boundary the reel may well
  /// go on.
  bool _reelEnd = false;
  bool _reelLoading = false;

  /// Nothing NEW came back, page after page, with a cursor still on it:
  /// stop asking by ourselves and offer a button, as the feed does.
  bool _reelStalled = false;
  String? _reelError;

  /// Pages one load asks for before it offers that button. The contract's
  /// own case — "a page can be short, even empty, and still not be the
  /// last", because posts this viewer may not see were skipped — needs a
  /// handful.
  static const _reelHops = 6;

  /// A page of nothing NEW needs one more hop per page of the reel we
  /// already hold: the server hands out a page already seen on purpose, and
  /// such a repeat starts at the TOP of the reel, so it is as long as the
  /// reel is. [_reelPage] is the page size `byEvent` answers with when the
  /// app asks for no `limit` (the contract's default).
  static const _reelPage = 10;

  /// However long the reel, one load asks for no more than this: a spinner
  /// is all the viewer has while it runs, so a page already seen is worth a
  /// request, not a wait without end. It covers a reel of about
  /// ([_reelHopsMax] - [_reelHops]) x [_reelPage] posts already seen; deeper
  /// than that, "Keep looking" carries on from the same cursor — a tap, and
  /// honest about it, which beats a longer spinner.
  static const _reelHopsMax = 16;

  /// The page the viewer is on. [_postCount] or more is the page AFTER the
  /// last post — the one that loads more, or goes back to the match.
  int _index = 0;
  bool _snapped = false;

  /// The way out has been taken — by [_leaveReel], or by the route popping
  /// without it (the iOS back-swipe, Android's predictive back, the system
  /// back where `canPop` lets it through: the `PopScope` in [build] marks it).
  /// Every exit goes through one method and more than one can reach it in the
  /// same frame (the system back while the snap back's post-frame callback is
  /// pending, two quick taps, or a post that goes away inside the exit
  /// animation): a second `pop` would take the match timeline off the stack
  /// too.
  bool _left = false;

  /// [HighlightDetailScreen.fromGameId] and
  /// [HighlightDetailScreen.fromActivityId], each a uuid or nothing
  /// (`_reelUuid`): `?gameId=` with nothing — or nonsense — after it is no
  /// origin, as the web's `reelOriginOf` has it. Set in [initState], read
  /// everywhere after.
  String? _fromGame;

  /// The stat the reel started on, and the row every way out lands on. A
  /// reel without one is still a reel: it just ends at the match.
  String? _fromStat;

  /// The player whose grid opened this ([HighlightDetailScreen.from]), a uuid
  /// or nothing; never set beside [_fromGame].
  String? _fromPlayer;

  /// With no origin at all: the player the post is ABOUT, once `get` has
  /// answered ([_adoptSubject]) — if this viewer is shown who that is.
  String? _subject;
  bool _subjectKnown = false;

  /// The player a player reel or a subject reel runs through.
  String? get _reelPlayer => _fromPlayer ?? _subject;

  bool get _isReel => _fromGame != null || _reelPlayer != null;

  /// A reel whose way out is a PLACE — the match, or the profile it was
  /// opened from — rather than "the page underneath": the back control, a
  /// post that goes away, the system back and the end all take it there.
  bool get _leavesByHand => _fromGame != null || _fromPlayer != null;

  /// The end of this reel is its last page, with nowhere to go: EVERY subject
  /// reel (lead's decision, fix round: a shared post, a notification, a chat
  /// card stops on "That's all from …" as TikTok / IG do — it never pops by
  /// itself; review context-reels-app.md MED-1), and a guest's player reel
  /// with nothing underneath (a guest can't open a profile).
  bool get _endStays =>
      _fromGame == null &&
      (_fromPlayer == null ||
          (!context.canPop() && ref.read(highlightVisitorProvider)));

  /// The tapped post (item 0, this screen's own read) went away after it was
  /// shown — removed, deleted here, its file dead, a re-read answering 404 —
  /// while it heads a reel: it leaves the reel and the rest plays on, as on
  /// the web (review context-reels.md MED-1 / context-reels-app.md LOW-5),
  /// instead of the whole reel giving way to "can't be shown".
  bool _leadGone = false;

  /// The last copy of item 0 this screen showed (for the end card's name once
  /// it has gone). Set while building — a cache, not state.
  HighlightItem? _leadSeen;

  /// The reel's own address query, for a visitor coming back after signing
  /// up (null on the one-post screen and on a subject reel, whose address is
  /// the plain one).
  Map<String, String>? get _visitorReel {
    final player = _fromPlayer;
    if (player != null) return {'from': 'player:$player'};
    final game = _fromGame;
    if (game == null) return null;
    final stat = _fromStat;
    return {'gameId': game, if (stat != null) 'activityId': stat};
  }

  /// Posts in the pager: the tapped one, and the reel's after it.
  int get _postCount => (_leadGone ? 0 : 1) + (_isReel ? _reel.length : 0);

  @override
  void initState() {
    super.initState();
    final from = widget.fromGameId;
    _fromGame = from != null && _reelUuid.hasMatch(from) ? from : null;
    final stat = widget.fromActivityId;
    _fromStat = stat != null && _reelUuid.hasMatch(stat) ? stat : null;
    final player = _reelFrom.firstMatch(widget.from ?? '')?.group(1);
    _fromPlayer =
        _fromGame == null && player != null ? player.toLowerCase() : null;
    // A badge or a tile opened this: the reel's first page carries the
    // tapped post.
    if (_isReel) _loadReel();
    // Opened with no list behind it: the reel is the post's SUBJECT's, and
    // who that is is known once the post is.
    if (!_leavesByHand) {
      ref.listenManual<AsyncValue<HighlightItem>>(highlightProvider(widget.id),
          fireImmediately: true, (_, next) {
        final item = next.valueOrNull;
        if (item != null) _adoptSubject(item);
      });
    }
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _deleted || _gone) return;
      // The viewer's own unfinished posts further on in a player / subject
      // reel are read again too (review context-reels-app.md LOW-3).
      if (_isReel) _rereadProcessing();
      // Item 0 has left the reel: nothing of it to read again (a 404 there must
      // not take the reel away from a viewer who has moved on — LOW-5).
      if (_leadGone) return;
      final shown =
          _local ?? ref.read(highlightProvider(widget.id)).valueOrNull;
      if (shown == null) return;
      // A video uploaded from the web is converted by the server first; its
      // author watches it turn ready (there is no push for that yet).
      if (shown.status == 'processing') {
        ref.invalidate(highlightProvider(widget.id));
        return;
      }
      // A video posted from the app is published at once and CHECKED
      // afterwards (docs/wiki/highlights.md): within about a minute the
      // server may take it down, or move its file to a new address. So a
      // fresh one is read again — twice, while it still looks fine.
      final made = shown.createdAt;
      if (_settled ||
          made == null ||
          !shown.isVideo ||
          !shown.isReady ||
          shown.source != 'app') {
        return;
      }
      final age = DateTime.now().difference(made);
      if (age >= _settleUntil) {
        _settled = true;
      } else if (age >= _settleAgainAfter) {
        _settled = true;
        ref.invalidate(highlightProvider(widget.id));
      } else if (age >= _settleAfter && !_settledOnce) {
        _settledOnce = true;
        ref.invalidate(highlightProvider(widget.id));
      }
    });
  }

  /// The first answer for a post opened with no origin names the player it is
  /// about: from now on the screen is that player's reel, pinned on this
  /// post. Once — a fresher copy of the post changes nothing — and only for
  /// a subject this viewer is shown (a person the server masks has no id:
  /// the one post, as before). Never inside the listener's own call: it can
  /// fire from [initState], where a `setState` is not allowed, so the first
  /// page is asked for after the frame.
  void _adoptSubject(HighlightItem item) {
    if (_subjectKnown) return;
    _subjectKnown = true;
    final who = item.subject.userId;
    if (!_reelUuid.hasMatch(who)) return;
    _subject = who.toLowerCase();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadReel();
    });
  }

  bool _rereading = false;

  /// Your own posts still `processing` further on in the reel, a few at a
  /// time: a fresh copy replaces the old, one that has gone leaves the reel.
  Future<void> _rereadProcessing() async {
    if (_rereading) return;
    final due =
        _reel.where((x) => x.status == 'processing').take(3).toList();
    if (due.isEmpty) return;
    _rereading = true;
    try {
      for (final x in due) {
        try {
          final fresh = await ref.read(highlightsRepositoryProvider).get(x.id);
          if (!mounted) return;
          _patch(fresh);
        } catch (e) {
          if (!mounted) return;
          if (e is ApiException && (e.statusCode == 404 || e.statusCode == 400)) {
            _drop(x.id);
          }
        }
      }
    } finally {
      _rereading = false;
    }
  }

  /// Item 0 has gone (see [_leadGone]): out of the pager, the viewer kept on
  /// the post they were watching — the pager follows a shown post that moves
  /// up a place — and the reel carried on: the next page asked for, or, at its
  /// end, the way out its end always takes.
  void _dropLead() {
    if (_leadGone || !_isReel) return;
    setState(() {
      _leadGone = true;
      if (_index > 0) _index -= 1;
    });
    if (_reelEnd) {
      _snapBack();
    } else {
      _loadReel();
    }
  }

  /// A sheet or a dialog over this page is what `pop` takes (mobile-app.md):
  /// closed first, so a way out takes THIS page and the Back button left
  /// behind is never a dead one (review context-reels-app.md LOW-2).
  void _closeOverlays() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      route.navigator?.popUntil((r) => r == route);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `ModalRoute.isCurrent` changes here when a route — or a sheet — is
    // pushed or popped on top of this one. A snap back that was held back
    // because it would have taken that sheet off instead can happen now.
    _snapBack();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// One page of the reel. The first (no [_cursor] yet) asks for the tapped
  /// post as item 0 with `firstId`; a later page doesn't — the cursor carries
  /// that id, so the post cannot come back a second time.
  Future<void> _loadReel() async {
    final game = _fromGame;
    final player = _reelPlayer;
    if ((game == null && player == null) || _reelLoading || _reelEnd) return;
    setState(() {
      _reelLoading = true;
      _reelStalled = false;
      _reelError = null;
    });
    var cursor = _cursor;
    final fresh = <HighlightItem>[];
    var end = false;
    String? error;
    // A server older than the reel doesn't know `?eventOfGameId=`: the mobile
    // route dispatches modes in a chain and falls through to the FOLLOWING
    // FEED, so it answers 200, the right shape, the wrong posts
    // (reviews/highlights-t6.md MED-2). An app release leads the server
    // deploy and a deployed server cannot be fixed, so the app must notice.
    var noReel = false;
    var hops = _reelHops + _postCount ~/ _reelPage;
    if (hops > _reelHopsMax) hops = _reelHopsMax;
    // Once per load: the server refused the cursor ([isRefusedCursor]) and
    // the walk carried on from the top of the reel.
    var restarted = false;
    try {
      // The contract: a page may be short — even empty — and still not be
      // the last (posts this viewer may not see were skipped). Keep asking
      // until something NEW arrives or the server says that's all.
      for (var hop = 0; hop < hops; hop++) {
        final HighlightsPage<HighlightItem> page;
        try {
          // The match reel, or a player's (a profile tile's, or the post's
          // subject's). Both pin the tapped post on the first page only.
          page = game != null
              ? await ref.read(highlightsRepositoryProvider).byEvent(game,
                  firstId: cursor == null ? widget.id : null, cursor: cursor)
              : await ref.read(highlightsRepositoryProvider).byPlayer(player!,
                  // A profile reel pins the tapped post on its first page; a
                  // subject reel is the subject's whole grid (fix round 2,
                  // review MED-6), the opened post dropped by id below.
                  firstId: _fromPlayer != null && cursor == null
                      ? widget.id
                      : null,
                  // A restart after a refused cursor says so (`cursor=` empty):
                  // a pin gone since is then the grid from the top, not an
                  // empty reel that would end it early (review LOW-7).
                  cursor: restarted && cursor == null ? '' : cursor);
        } catch (e) {
          // A cursor the server can no longer open (a week old, a changed
          // server secret, a reel left open across the deploy that sealed
          // cursors): carry on from the TOP of the reel. That is the repeat
          // the filter below already pages through — it is what a cursor
          // whose anchor vanished reads as too — so nothing else changes.
          if (restarted || !isRefusedCursor(e, cursor)) rethrow;
          if (!mounted) return;
          restarted = true;
          cursor = null;
          // The refused request isn't one of the walk's pages: the repeat
          // from the top gets the whole budget (review LOW-3).
          hops += 1;
          continue;
        }
        if (!mounted) return;
        // Is this the reel at all, or the following feed an older server
        // fell through to ([_notAReel])? Only while nothing has been kept
        // yet: after that the reel is proven, and the server may then
        // legitimately repeat a post, which the filter below drops. Checking
        // every page until something is kept is what covers a pre-reel
        // server whose first feed page comes back EMPTY with a cursor — the
        // next one used to be appended unchecked (T8 review LOW-J). The PIN
        // is the first page's promise alone: a page read from the top of the
        // reel can carry the tapped post anywhere in it. A PLAYER reel needs
        // no such test: a server older than it ignores `firstId` and answers
        // the same player's grid — the right posts, newest first — so the
        // tapped post (item 0, this screen's own read) and the id filter
        // below are all it takes (docs/wiki/highlights.md).
        if (game != null &&
            fresh.isEmpty &&
            _reel.isEmpty &&
            _notAReel(page.items, pinned: cursor == null)) {
          noReel = true;
          break;
        }
        // Only what the reel does not already have counts as a page. The
        // server answers a page whose every id the client has DELIBERATELY:
        // a cursor whose anchor row vanished reads as the TOP of the reel,
        // and a cursor minted before a deploy is refused and the reel
        // restarts from there (docs/wiki/highlights.md, "The match reel").
        // Counting the RAW page broke this loop on nothing new — no post was
        // added, no stall was set, and the page after the last post stayed a
        // spinner that only a page CHANGE can refresh, so the reel hung
        // (T8 review MED-C). The hop budget above is what pages through such
        // a repeat: it is as long as the reel already is.
        final have = {
          widget.id,
          for (final i in _reel) i.id,
          for (final i in fresh) i.id
        };
        for (final item in page.items) {
          // A profile reel holds only what is OLDER than the post it opened;
          // a restart whose pin has gone brings the newer ones too (LOW-7).
          if (_newerThanLead(item)) continue;
          if (item.id.isNotEmpty && have.add(item.id)) fresh.add(item);
        }
        cursor = page.nextCursor;
        if (cursor == null) {
          end = true;
          break;
        }
        if (fresh.isNotEmpty) break;
      }
    } catch (e) {
      if (!mounted) return;
      error = '$e';
    }
    if (noReel) {
      // Nothing of the reel can be on screen: the check only runs while
      // nothing has been kept at all — `_reel` empty AND nothing accepted
      // this load — so what is dropped here is only ever an answer nobody
      // has seen. So be the screen this was before the reel — one post, no
      // page after it, nothing that can take them anywhere. With `_fromGame`
      // gone, `_isReel` is false: no further page is asked for and no way
      // back can fire, so this cannot come round again.
      setState(() {
        _fromGame = null;
        _reelStalled = false;
        _reelError = null;
        _reelLoading = false;
      });
      return;
    }
    final failed = error;
    final nextCursor = cursor;
    final reachedEnd = end;
    setState(() {
      // What DID come back is kept even if a later hop failed, and the cursor
      // with it: one load now walks up to [_reelHopsMax] pages, and throwing
      // fifteen good ones away because the sixteenth timed out means Retry
      // walks the whole repeat again — on a connection that drops one request
      // in ten, it never gets through. The cursor is the one the last page
      // that was KEPT handed over, so it never names a page nobody read.
      // Item 0 is the tapped post, read by id; nothing may appear twice.
      final seen = {widget.id, for (final i in _reel) i.id};
      for (final item in fresh) {
        if (item.id.isNotEmpty && seen.add(item.id)) _reel.add(item);
      }
      _cursor = nextCursor;
      if (failed == null) {
        _reelEnd = reachedEnd;
        _reelStalled = fresh.isEmpty && !reachedEnd;
      }
      _reelError = failed;
      _reelLoading = false;
    });
    // They may have been waiting for this answer on the page after the last
    // post: it may have been the end of the reel.
    _snapBack();
  }

  /// On a profile reel: is this post newer than the one it opened?
  bool _newerThanLead(HighlightItem item) {
    if (_fromPlayer == null) return false;
    final lead = (_local ?? _leadSeen)?.createdAt;
    final at = item.createdAt;
    return lead != null && at != null && at.isAfter(lead);
  }

  /// Is this first page of `byEvent` a reel, or the following feed an older
  /// server fell through to (MED-2)?
  ///
  /// Only the promises `byEvent` makes about its FIRST page can tell them
  /// apart, and only these three are safe to lean on:
  ///
  ///  * the post it was asked to pin is item 0 — or nowhere at all, which
  ///    the contract explicitly allows (a `firstId` this viewer may not see,
  ///    or whose stat was voided, or that was unlinked or removed between
  ///    the tap and the request, is simply left out) and which must NOT read
  ///    as a broken server: the reel then goes on without it, as it should.
  ///    Only the page that ASKED for the pin promises this, hence [pinned]:
  ///    a page read from the top of the reel (an anchor that vanished, a
  ///    cursor refused at a deploy) may carry the tapped post anywhere;
  ///  * every post is pinned to a stat — a reel is the timeline carried on,
  ///    so an unpinned post is no part of one, while a feed is full of them.
  ///    All but ONE: the server picks the event's posts by joining
  ///    `game_activities` and then re-reads the stats in a second query, so
  ///    a stat voided between the two arrives as `stat: null` in a perfectly
  ///    good reel (T8 review LOW-K), and dropping a real reel over the
  ///    server's own race is worse than letting a feed through one post
  ///    short of the test;
  ///  * they are all of ONE event.
  ///
  /// A page is checked only while nothing has been kept yet ([_loadReel]):
  /// after that the server may legitimately repeat a post (the anchor fix's
  /// bounded repeat), which the filter there drops.
  bool _notAReel(List<HighlightItem> items, {required bool pinned}) {
    if (items.isEmpty) return false;
    if (pinned && items.indexWhere((x) => x.id == widget.id) > 0) return true;
    String? event;
    var unpinned = 0;
    for (final item in items) {
      final stat = item.stat;
      if (stat == null) {
        // Two of them, or a page with nothing pinned in it at all, is a feed;
        // one is the voided-stat race above.
        unpinned++;
        if (unpinned > 1 || unpinned == items.length) return true;
        continue;
      }
      // The four event details are null together for a private event the
      // viewer isn't in the group of: nothing to compare, not a mismatch.
      final id = stat.eventId;
      if (id == null || id.isEmpty) continue;
      if (event != null && event != id) return true;
      event = id;
    }
    return false;
  }

  /// Running off the end of a reel goes back to the match timeline it
  /// started from, with no tap.
  ///
  /// Both halves must hold or the reel would be cut short: the viewer is on
  /// the page after the last post, AND the server has said there is no next
  /// page. While a page is still coming — or failed — that page says so
  /// instead, and this does nothing.
  void _snapBack() {
    if (!_isReel || _snapped || !_reelEnd || _index < _postCount) return;
    // A reel that ends where it is: its last page is the end card, and there
    // is nobody to take anywhere.
    if (_endStays) return;
    // `pop` takes the TOPMOST route (mobile-app.md): with a sheet or a
    // dialog over this page it would close that instead. Leave it for
    // [didChangeDependencies], which runs again when that one goes.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _snapped = true;
    // After this frame: a page change is reported from inside a scroll
    // notification, and leaving the route in the middle of one is asking
    // for trouble.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // A sheet that opened in this very frame is what `pop` would take, and
      // the guard above ran before that sheet existed: back to "not gone
      // yet", and [didChangeDependencies] has it when the sheet goes.
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
        _snapped = false;
        return;
      }
      if (_leavesByHand) {
        _leaveReel();
      } else {
        // A subject reel: back to the page it was opened over.
        _back();
      }
    });
  }

  /// Out of the reel and onto the stat it started from — the row they came
  /// from, which is what was asked for, not merely the match. A player reel
  /// the same way onto the profile it was opened from, at the tile.
  void _leaveReel() {
    final game = _fromGame;
    final player = _fromPlayer;
    if ((game == null && player == null) || _left) return;
    _left = true;
    _closeOverlays();
    // Pop, never push: the match timeline is the route underneath and
    // popping takes the reel off the stack, so the system Back button cannot
    // walk back into the reel they have just left, and the timeline keeps
    // the scroll it had. The stat rides back on the pop, because an offset
    // is not a row: the badge that pushed this reel is waiting for it and
    // brings that row into view (`game_screen.dart` `_scrollToStat`). A
    // profile keeps its tab and its offset; the TILE rides back, so a grid
    // that re-read itself meanwhile can still bring it into view
    // (`highlights_grid.dart`).
    if (context.canPop()) {
      if (game != null) {
        context.pop(_fromStat);
      } else {
        context.pop(widget.id);
      }
      return;
    }
    // A visitor who opened a reel link straight from outside: a match page
    // needs an account in the app, so the end of the reel is the guest Home,
    // not a sign-in wall nobody asked for.
    if (ref.read(highlightVisitorProvider)) {
      context.go('/home');
      return;
    }
    if (game == null) {
      // A profile tile's reel with nothing underneath: the profile itself.
      _goToProfile(player!);
      return;
    }
    // Nothing underneath (a link that opened straight into a reel): the
    // match itself, at that row, replacing this page for the same reason.
    // `?stat=` is the web's own parameter for it (`gameStatHref`), read here
    // by `/games/:id` in the router.
    final stat = _fromStat;
    context.go(stat == null ? '/games/$game' : '/games/$game?stat=$stat');
  }

  /// A player's profile, in place of this page: your own is the dock's
  /// Profile tab, anyone else's `/players/<id>`. A guest has no profiles to
  /// open: signing in comes back to it.
  void _goToProfile(String player) {
    if (ref.read(highlightVisitorProvider)) {
      context.push(highlightSignInHref('/players/$player'));
      return;
    }
    final me = ref.read(authControllerProvider).valueOrNull?.user?.id;
    if (me != null && me.toLowerCase() == player) {
      ref.read(homeTabIndexProvider.notifier).state = HomeTab.profile;
      context.go('/home');
      return;
    }
    context.go('/players/$player');
  }

  /// "Keep watching" on the end card: the Highlights tab, on Discover.
  void _keepWatching() {
    ref.read(highlightFeedMemoryProvider).tab = 1;
    // ...and one that is already built switches to it.
    highlightShowDiscover.value++;
    ref.read(homeTabIndexProvider.notifier).state = HomeTab.highlights;
    context.go('/home');
  }

  /// The last page of a player or subject reel: whose highlights they were,
  /// and where next. Shown for a frame where the end goes back (the profile,
  /// the page underneath); it IS the end where there is nowhere to go
  /// ([_endStays]: a link opened cold).
  Widget _endCard() {
    final l = context.l10n;
    final item = _local ??
        ref.read(highlightProvider(widget.id)).valueOrNull ??
        _leadSeen;
    final player = _reelPlayer;
    final visitor = ref.read(highlightVisitorProvider);
    // Your own: said so, with no "their" (review context-reels.md LOW-3).
    final me = ref.read(authControllerProvider).valueOrNull?.user?.id;
    final mine = me != null && player != null && me.toLowerCase() == player;
    // Honest copy (review LOW-R2): "That's all from … every one" only where it
    // is true — a subject reel, which held the player's WHOLE grid. A profile
    // reel ran from the tapped post down to the oldest: a neutral line, and no
    // name, so it can't name anyone but the reel's player (View profile).
    final whole = _fromPlayer == null;
    return HighlightMessage(
      icon: Icons.movie_filter_outlined,
      title: !whole
          ? l.highlights_reelEndNoMore
          : mine
              ? l.highlights_reelEndTitleMine
              : l.highlights_reelEndTitle(item?.subject.displayName ?? ''),
      body: whole && !mine ? l.highlights_reelEndText : null,
      actionLabel: player == null
          ? null
          : visitor
              ? l.highlights_appReelEndSignIn
              : l.common_viewProfile,
      onAction: player == null ? null : () => _goToProfile(player),
      secondaryLabel: l.highlights_reelEndKeepWatching,
      onSecondary: _keepWatching,
    );
  }

  /// A like, a comment count, a link change, a fresher copy — of the tapped
  /// post, or of any other post in the reel.
  void _patch(HighlightItem changed) {
    if (changed.id == widget.id) {
      setState(() => _local = changed);
      return;
    }
    final i = _reel.indexWhere((x) => x.id == changed.id);
    if (i >= 0) setState(() => _reel[i] = changed);
  }

  /// Take a post that has gone out of the reel (removed, or no longer this
  /// viewer's to see).
  ///
  /// The reel SHRANK — they did not scroll off its end — so the page they
  /// are on has to stay a post. Without that the count falls below their
  /// index, which is exactly the way-back condition, and a reel that loses a
  /// post throws the viewer out mid-post with no scroll at all
  /// (reviews/highlights-t6.md MED-3). They may still be on the page after
  /// the last post, where nothing happens without a page change: ask for the
  /// next page — or, with none left, go back.
  void _drop(String id) {
    setState(() {
      final was = _postCount;
      _reel.removeWhere((x) => x.id == id);
      // `_index == was` is the page after the reel: that one still goes
      // back, because they really did scroll onto it.
      if (_index >= _postCount && _index < was) _index = _postCount - 1;
    });
    if (_reelEnd) {
      _snapBack();
    } else {
      _loadReel();
    }
  }

  /// The page after the last post. Without an origin there is none at all —
  /// one post, where scrolling does nothing, exactly as before.
  Widget? _reelTrailing() {
    if (!_isReel) return null;
    final l = context.l10n;
    final failed = _reelError;
    if (failed != null) {
      return HighlightMessage(
        icon: Icons.wifi_off_rounded,
        title: l.highlights_couldntLoadMore,
        body: failed,
        actionLabel: l.common_retry,
        onAction: _loadReel,
      );
    }
    if (_reelStalled && !_reelLoading) {
      return HighlightMessage(
        icon: Icons.travel_explore_rounded,
        title: l.highlights_noneFoundSoFar,
        actionLabel: l.highlights_keepLooking,
        onAction: _loadReel,
      );
    }
    if (!_reelEnd) return const HighlightMessage(busy: true);
    // A player's reel or a subject's: who it was, and where next.
    if (_fromGame == null) return _endCard();
    // The reel has ended. This page is the way back to the match, and
    // reaching it is what takes them there ([_snapBack]) — so it says where
    // they are going rather than pretending there is more to come.
    return HighlightMessage(
      icon: Icons.timeline_rounded,
      title: l.highlights_statOpenMatch,
    );
  }

  /// Every deliberate way out: the back button, a deleted post, one that is
  /// gone. From a reel that is the match, at the stat it started from — the
  /// same place running off the end lands, so there is one way out.
  void _back() {
    if (_leavesByHand) {
      _leaveReel();
      return;
    }
    // Once: a subject reel's end and its back control (or a post going away
    // inside the exit) can both reach here, and a second pop would take the
    // page underneath off too.
    if (_left) return;
    _left = true;
    _closeOverlays();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // A fresh read replaces what this screen changed locally.
    ref.listen<AsyncValue<HighlightItem>>(highlightProvider(widget.id),
        (_, next) {
      final fresh = next.valueOrNull;
      if (fresh != null && !next.isLoading && _local != null) {
        setState(() => _local = null);
      }
      // A re-read saying item 0 is gone, on a reel it was already shown in:
      // it leaves the reel, the rest stays (LOW-5).
      final gone = next.error;
      if (_isReel &&
          _leadSeen != null &&
          !next.isLoading &&
          gone is ApiException &&
          (gone.statusCode == 404 || gone.statusCode == 400)) {
        _dropLead();
      }
    });
    final fetched = ref.watch(highlightProvider(widget.id));
    final visitor = ref.watch(highlightVisitorProvider);
    final item = _local ?? fetched.valueOrNull;
    if (item != null) _leadSeen = item;
    final padding = MediaQuery.paddingOf(context);
    // "Not found" is the server's answer for a post that doesn't exist AND
    // for one this viewer may not see; a malformed id in a link (400 from an
    // older server) is no different to the person. It also wins over a copy
    // read earlier: a later read saying so means the post is gone.
    final e = fetched.error;
    final notFound = !fetched.isLoading &&
        e is ApiException &&
        (e.statusCode == 404 || e.statusCode == 400);

    // The pager's own hooks, one set for both lists below.
    HighlightPager pager(List<HighlightItem> items) => HighlightPager(
          items: items,
          trailing: _reelTrailing(),
          onNearEnd: _isReel ? _loadReel : null,
          onIndexChanged: (i) {
            _index = i;
            _snapBack();
          },
          onChanged: _patch,
          visitorReturnReel: _visitorReel,
          openCommentsFirst: widget.openComments && !_leadGone,
          onRemoved: (id) {
            if (id != widget.id) {
              _drop(id);
              return;
            }
            // Item 0 deleted here: on a reel it leaves and the rest plays on
            // (as on the web); the one-post screen says it is deleted.
            if (_isReel) {
              _dropLead();
              return;
            }
            setState(() => _deleted = true);
            _back();
          },
          onGone: (id) {
            // Nobody asked for this one to go, and the reel would otherwise
            // just slide on to the next post: say so, as the feed does.
            if (id != widget.id || _isReel) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l.highlights_goneToast)));
            }
            if (id != widget.id) {
              _drop(id);
              return;
            }
            if (_isReel) {
              _dropLead();
              return;
            }
            // On the one-post screen the card stays and its own Back button
            // is the way out, as before.
            setState(() => _gone = true);
          },
          bottomInset: padding.bottom,
        );

    final Widget body;
    if (_isReel && (_leadGone || (_leadSeen != null && notFound))) {
      // Item 0 has gone from a reel it headed: the rest of the reel, or —
      // with nothing left — the page after it (the end card, the way back,
      // or what is still loading).
      body = _reel.isEmpty
          ? (_reelTrailing() ?? const HighlightMessage(busy: true))
          : pager(_reel);
    } else if (_deleted) {
      body = HighlightMessage(
        icon: Icons.delete_outline_rounded,
        title: l.highlights_deleted,
        actionLabel: l.common_back,
        onAction: _back,
      );
    } else if ((_gone || notFound) && visitor) {
      // Signed out, "not found" may well be "not for visitors": say so, and
      // offer the way in, back to this same address.
      body = HighlightMessage(
        icon: Icons.visibility_off_outlined,
        title: l.highlights_cantShowTitle,
        body: l.highlights_notFoundVisitorText,
        actionLabel: l.highlights_visitorSignIn,
        onAction: () => context.push(highlightSignInHref(
            highlightVisitorReturnTo(widget.id, reel: _visitorReel))),
      );
    } else if (_gone || notFound) {
      body = HighlightMessage(
        icon: Icons.visibility_off_outlined,
        title: l.highlights_cantShowTitle,
        body: l.highlights_cantShowBody,
        actionLabel: l.common_back,
        onAction: _back,
      );
    } else if (item != null) {
      // The tapped post, then the reel. Item 0 stays this screen's own read:
      // the contract leaves a `firstId` this viewer may not see out of the
      // reel instead of failing, because the client already has that post.
      body = pager(_isReel ? [item, ..._reel] : [item]);
    } else if (fetched.hasError) {
      body = HighlightMessage(
        icon: Icons.wifi_off_rounded,
        title: l.highlights_couldntLoadOne,
        body: e is ApiException ? e.message : null,
        actionLabel: l.common_retry,
        onAction: () => ref.invalidate(highlightProvider(widget.id)),
      );
    } else {
      body = const HighlightMessage(busy: true);
    }

    return PopScope(
      // The ANDROID SYSTEM back was the one exit from a reel that did not go
      // through [_leaveReel]: it popped with no result, so the badge's
      // `await` got null and the timeline restored its OFFSET without
      // re-finding the row (T8 review LOW-E). It is held here — and sent
      // through the same one way out as the screen's own back control, a
      // deleted post and the snap back — only where it has NOWHERE TO GO: a
      // reel with no route underneath it, which goes to the match instead.
      // A reel PUSHED from a timeline pops as any page does, because a route
      // that says `doNotPop` is exactly what the iOS back-swipe is refused
      // on (`ModalRoute.popGestureEnabled`; a MaterialApp draws this route
      // with `CupertinoPageTransitionsBuilder` on iOS) — holding it there
      // switched the platform way out of a reel off altogether, and Android's
      // predictive-back preview with it (T10 review MED-1). Nothing is lost
      // by letting it pop: the stat it was held for is the row the badge
      // pushed with, and the badge falls back to that row when the pop
      // carries nothing (`game_screen.dart`). `canPop` is left alone off a
      // reel, where there is nothing to hand back. (`_leaveReel`'s own
      // `context.pop` is explicit, which `canPop` does not stand in the way
      // of.)
      // (A subject reel pops like the one-post screen it grew out of: its way
      // out IS the page underneath, so there is nothing to hold.)
      canPop: !_leavesByHand || context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        // It popped without [_leaveReel] — the iOS swipe, predictive back,
        // the system back where the line above lets it through. The way out
        // has still been taken, and saying so matters: the pager's own
        // re-read can answer 404 inside the exit animation, and [_back] would
        // then pop a second time and take the timeline off the stack too.
        if (didPop) {
          _left = true;
          return;
        }
        _leaveReel();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(children: [
            Positioned.fill(child: body),
            Positioned(
              top: padding.top + 6,
              left: 10,
              child: Tooltip(
                message: l.common_back,
                child: Material(
                  color: const Color(0x66000000),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _back,
                    child: const SizedBox(
                      width: 42,
                      height: 42,
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
