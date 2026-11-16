import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/data/highlights/highlight_models.dart';
import 'package:sportpadi_mobile/data/highlights/highlights_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/highlights/highlight_actions.dart';
import 'package:sportpadi_mobile/features/highlights/highlight_comments_sheet.dart';
import 'package:sportpadi_mobile/features/highlights/highlight_stat_picker.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/crest.dart';
import 'package:sportpadi_mobile/shared/widgets/player_link.dart';

/// The showcase: one highlight per screen, swiped vertically — the same
/// viewer for the feed, a single post (`/highlights/:id`) and anything else
/// that shows posts full-screen.
///
/// Playback rules (workspace `docs/wiki/highlights.md`): only the post on
/// screen plays; it starts muted, loops, and a tap pauses it. A player
/// exists for the current post and the next one only — everything else is
/// disposed. Playback stops when [active] turns false (the tab was left),
/// when another page is pushed on top, and when the app goes to the
/// background.
///
/// The list itself belongs to the parent: likes, comment counts, link
/// changes, a fresher copy of a post and deletions come back through
/// [onChanged] / [onRemoved] / [onGone].
class HighlightPager extends ConsumerStatefulWidget {
  const HighlightPager({
    super.key,
    required this.items,
    required this.onChanged,
    required this.onRemoved,
    this.onGone,
    this.active = true,
    this.trailing,
    this.onNearEnd,
    this.initialIndex = 0,
    this.onIndexChanged,
    this.bottomInset = 0,
  });

  final List<HighlightItem> items;
  final ValueChanged<HighlightItem> onChanged;

  /// The viewer deleted this post here.
  final ValueChanged<String> onRemoved;

  /// The post turned out to be gone — deleted elsewhere, or no longer
  /// visible to this viewer (the server doesn't say which). Without it,
  /// [onRemoved] is called.
  final ValueChanged<String>? onGone;

  /// False = nothing may play (the parent isn't the visible tab).
  final bool active;

  /// One more page after the last post: "loading more", or a retry.
  final Widget? trailing;

  /// Called as the viewer gets within a few posts of the end.
  final VoidCallback? onNearEnd;
  final int initialIndex;
  final ValueChanged<int>? onIndexChanged;

  /// Room the parent's own chrome takes at the bottom of each page.
  final double bottomInset;

  @override
  ConsumerState<HighlightPager> createState() => _HighlightPagerState();
}

class _HighlightPagerState extends ConsumerState<HighlightPager>
    with WidgetsBindingObserver {
  late final PageController _pages;
  late int _index;

  /// Players by highlight id — at most the current post's and the next's.
  final Map<String, VideoPlayerController> _players = {};

  /// The address each post's player (or failed try) was for.
  final Map<String, String> _urls = {};
  final Set<String> _failed = {};

  /// Posts already re-read once after their video wouldn't play.
  final Set<String> _refetched = {};
  final Set<String> _liking = {};

  bool _foreground = true;
  bool _routeCurrent = true;

  /// Sheets this viewer opened itself (comments, more). They cover the page
  /// without leaving it, so the video keeps playing behind them.
  int _sheets = 0;
  bool _userPaused = false;

  /// The post the page index points at — a tap-to-pause belongs to it, not
  /// to whatever slides into its place.
  String? _shownId;

  String? _idAt(int i) =>
      i >= 0 && i < widget.items.length ? widget.items[i].id : null;

  int get _pageCount => widget.items.length + (widget.trailing != null ? 1 : 0);

  @override
  void initState() {
    super.initState();
    final last = widget.items.isEmpty ? 0 : widget.items.length - 1;
    final start = widget.initialIndex;
    _index = start < 0 ? 0 : (start > last ? last : start);
    _pages = PageController(initialPage: _index);
    _shownId = _idAt(_index);
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _syncPlayers();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // False while another route sits on top of ours — a pushed page, or a
    // sheet (ours are let through by [_sheets]).
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (current != _routeCurrent) {
      _routeCurrent = current;
      _applyPlayback();
    }
  }

  @override
  void didUpdateWidget(HighlightPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A post was removed from under us, or the trailing page went away.
    final count = _pageCount;
    if (_index >= count) _index = count > 0 ? count - 1 : 0;
    // The list shrank under a viewer who was on a POST: left where it is,
    // the page they are on is now the TRAILING one — "back to the match" at
    // the end of a reel, "loading more" in the feed — which they never
    // scrolled onto. Keep them on the last post instead
    // (reviews/highlights-t6.md MED-3), and tell whoever owns the list where
    // they ended up: `jumpToPage` alone reports nothing, since the index it
    // lands on is the one already set here.
    if (_index >= widget.items.length &&
        _index < oldWidget.items.length &&
        widget.items.isNotEmpty) {
      _index = widget.items.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pages.hasClients) _pages.jumpToPage(_index);
        widget.onIndexChanged?.call(_index);
      });
    }
    final shown = _idAt(_index);
    if (shown != _shownId) {
      _shownId = shown;
      _userPaused = false;
    }
    _syncPlayers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyPlayback();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _applyPlayback();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // The pages (and their VideoPlayer widgets) are gone by now.
    for (final c in _players.values) {
      // ignore: discarded_futures
      c.dispose();
    }
    _players.clear();
    _pages.dispose();
    super.dispose();
  }

  String _absolute(String url) => url.startsWith('/')
      ? '${ref.read(appConfigProvider).apiBaseUrl}$url'
      : url;

  /// Make the set of players match the page on screen: one for it, one for
  /// the page after it, none for anything else.
  void _syncPlayers() {
    final items = widget.items;
    final wanted = <String, String>{};
    for (final i in [_index, _index + 1]) {
      if (i < 0 || i >= items.length) continue;
      final item = items[i];
      final url = item.video?.url;
      if (!item.isReady || url == null) continue;
      // The server may move a clip to a new address shortly after it was
      // posted (docs/wiki/highlights.md): the player made for the old one —
      // or its failure — says nothing about the new file.
      final known = _urls[item.id];
      if (known != null && known != url) {
        _failed.remove(item.id);
        _retire(_players.remove(item.id));
      }
      _urls[item.id] = url;
      if (!_failed.contains(item.id)) wanted[item.id] = url;
    }
    final stale = [
      for (final id in _players.keys)
        if (!wanted.containsKey(id)) id
    ];
    for (final id in stale) {
      _retire(_players.remove(id));
    }
    final muted = ref.read(highlightsMutedProvider);
    wanted.forEach((id, url) {
      if (_players.containsKey(id)) return;
      final uri = Uri.tryParse(_absolute(url));
      if (uri == null || !uri.hasScheme) {
        _failed.add(id);
        return;
      }
      final c = VideoPlayerController.networkUrl(
        uri,
        // Muted autoplay shouldn't cut off music the person is listening to.
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _players[id] = c;
      _watch(id, c);
      // Applied by the player once it is ready.
      // ignore: discarded_futures
      c.setLooping(true);
      // ignore: discarded_futures
      c.setVolume(muted ? 0.0 : 1.0);
      // ignore: discarded_futures
      c.initialize().then((_) {
        if (!mounted || _players[id] != c) return;
        setState(() {});
        _applyPlayback();
      }).catchError((Object _) {
        _playFailed(id, c);
      });
    });
  }

  /// A player can also fail AFTER it started — the connection dropped, the
  /// file was removed while it played. It then reports an error and stops
  /// being "initialized", which the page would otherwise draw as a spinner
  /// for ever.
  void _watch(String id, VideoPlayerController c) {
    void onValue() {
      if (!c.value.hasError) return;
      c.removeListener(onValue);
      _playFailed(id, c);
    }

    c.addListener(onValue);
  }

  /// [c] gave up on post [id]: show "can't be played / Retry" there.
  void _playFailed(String id, VideoPlayerController c) {
    if (!mounted || _players[id] != c) return;
    setState(() {
      _failed.add(id);
      _retire(_players.remove(id));
    });
    // The file may have moved or the post may be gone: ask once by
    // ourselves (Retry asks again).
    if (_refetched.add(id)) unawaited(_reread(id));
  }

  /// Read post [id] again. A newer copy goes to the parent (a new address
  /// for its video then gets a new player); "not found" — which is also the
  /// server's answer for a post this viewer may no longer see — takes it
  /// out of the list and is answered TRUE, so a caller that already has the
  /// server's "not found" doesn't say it a second time. Any other trouble
  /// leaves things as they are.
  ///
  /// A video SportPadi's own check took down is NOT gone: while its files
  /// are kept the server answers it to anyone who may report it (`failed`
  /// with `canReport` — docs/wiki/highlights.md, H2), and it stays on
  /// screen so it still can be.
  Future<bool> _reread(String id) async {
    try {
      final fresh = await ref.read(highlightsRepositoryProvider).get(id);
      if (mounted) widget.onChanged(fresh);
    } on ApiException catch (e) {
      if (e.statusCode == 404 && mounted) {
        (widget.onGone ?? widget.onRemoved)(id);
        return true;
      }
    } catch (_) {/* stays as it is */}
    return false;
  }

  void _retire(VideoPlayerController? c) {
    if (c == null) return;
    // Silence it now; dispose after this frame, when the page that was
    // showing it has been rebuilt without it.
    // ignore: discarded_futures
    c.pause();
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Play the current post's video when everything allows it; pause the rest.
  void _applyPlayback() {
    final currentId = _idAt(_index);
    final play = widget.active &&
        _foreground &&
        (_routeCurrent || _sheets > 0) &&
        !_userPaused;
    _players.forEach((id, c) {
      if (!c.value.isInitialized) return;
      if (id == currentId && play) {
        if (!c.value.isPlaying) {
          // ignore: discarded_futures
          c.play();
        }
      } else if (c.value.isPlaying) {
        // ignore: discarded_futures
        c.pause();
      }
    });
  }

  void _onPage(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _shownId = _idAt(i);
      _userPaused = false;
      _syncPlayers();
    });
    _applyPlayback();
    widget.onIndexChanged?.call(i);
    if (i >= widget.items.length - 3) widget.onNearEnd?.call();
  }

  void _togglePause() {
    setState(() => _userPaused = !_userPaused);
    _applyPlayback();
  }

  void _toggleMute() {
    final notifier = ref.read(highlightsMutedProvider.notifier);
    notifier.state = !notifier.state;
  }

  void _retryVideo(String id) {
    setState(() {
      _failed.remove(id);
      _syncPlayers();
    });
    _applyPlayback();
    // Trying the same address again only helps when the trouble was the
    // connection; when the file moved, the fresh copy brings the new one.
    unawaited(_reread(id));
  }

  HighlightItem? _latest(String id) {
    for (final i in widget.items) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// Optimistic: the heart flips at once, then follows the server's answer
  /// (or flips back, with the reason, when the server says no).
  Future<void> _like(HighlightItem item) async {
    if (!item.isReady || _liking.contains(item.id)) return;
    _liking.add(item.id);
    final liked = !item.likedByMe;
    final guess = item.likeCount + (liked ? 1 : -1);
    widget.onChanged(
        item.copyWith(likedByMe: liked, likeCount: guess < 0 ? 0 : guess));
    try {
      final r =
          await ref.read(highlightsRepositoryProvider).like(item.id, liked);
      if (!mounted) return;
      final now = _latest(item.id);
      if (now != null) {
        widget.onChanged(
            now.copyWith(likedByMe: r.liked, likeCount: r.likeCount));
      }
    } catch (e) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final now = _latest(item.id);
      if (now != null) {
        widget.onChanged(now.copyWith(
            likedByMe: item.likedByMe, likeCount: item.likeCount));
      }
      // A remembered feed can be minutes old: the post may be gone — and a
      // post that is gone is announced by the re-read itself, so the
      // server's sentence as well would be two toasts about one thing. The
      // heart has flipped back either way.
      final gone = e is ApiException &&
          e.statusCode == 404 &&
          await _reread(item.id);
      if (!gone) messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      _liking.remove(item.id);
    }
  }

  Future<T> _whileSheetOpen<T>(Future<T> Function() open) async {
    _sheets++;
    try {
      return await open();
    } finally {
      _sheets--;
      // Not at once: this page only counts as "on top" again after the next
      // build, so applying now would pause the clip for one frame and start
      // it again.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyPlayback();
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  Future<void> _comments(HighlightItem item) {
    return _whileSheetOpen(() => showHighlightComments(
          context,
          item: item,
          onCount: (n) {
            if (!mounted) return;
            final now = _latest(item.id);
            if (now != null && now.commentCount != n) {
              widget.onChanged(now.copyWith(commentCount: n));
            }
          },
          onNotFound: () {
            if (mounted) unawaited(_reread(item.id));
          },
        ));
  }

  /// Report a post from its own card. The way in is the H2 state below: a
  /// video the check took down has no picture to tap and no menu worth
  /// opening, and its files are only kept for 72 h — so the one thing left
  /// to do with it is offered where the person is already looking.
  Future<void> _report(HighlightItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    await _whileSheetOpen(() async {
      final sent = await showHighlightReport(context, highlightId: item.id);
      if (sent) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.highlights_reportSent)));
      }
    });
  }

  Future<void> _more(HighlightItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(highlightsRepositoryProvider);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    await _whileSheetOpen(() async {
      final action = await showHighlightMore(context, item);
      if (action == null || !mounted) return;
      try {
        switch (action) {
          case HighlightMoreAction.copyLink:
            shareHighlight(context, ref, item);
          case HighlightMoreAction.report:
            final sent =
                await showHighlightReport(context, highlightId: item.id);
            if (sent) say(l10n.highlights_reportSent);
          case HighlightMoreAction.delete:
            // `canDelete` is also true for a guardian of the ward a post is
            // about; what deleting costs is only the author's business.
            final me = ref.read(authControllerProvider).valueOrNull?.user?.id;
            final ok = await confirmDeleteHighlight(context, item,
                byAuthor: me != null && me == item.author.userId);
            if (!ok) return;
            await repo.remove(item.id);
            highlightsChanged.value++;
            say(l10n.highlights_deleted);
            if (mounted) widget.onRemoved(item.id);
          case HighlightMoreAction.link:
            final pick = await showHighlightStatPicker(context,
                currentHighlightId: item.id);
            if (pick == null || !mounted) return;
            final subject = pick.subject.userId;
            // A ward's stat (or back to my own): the post changes hands.
            if (subject.isNotEmpty && subject != item.subject.userId) {
              final sure = await confirmSubjectChange(context,
                  from: item.subject.displayName,
                  to: pick.subject.displayName);
              if (!sure) return;
            }
            final linked = await repo.setLink(
                item.id,
                HighlightLink(
                    activityId: pick.stat.activityId,
                    subjectUserId: subject.isEmpty ? null : subject));
            highlightsChanged.value++;
            say(l10n.highlights_linkSaved);
            if (mounted) widget.onChanged(linked);
          case HighlightMoreAction.unlink:
            // Without a link a post is about its author again.
            if (item.aboutSomeoneElse) {
              final sure = await confirmSubjectChange(context,
                  from: item.subject.displayName,
                  to: item.author.displayName);
              if (!sure) return;
            }
            final unlinked = await repo.setLink(item.id, null);
            highlightsChanged.value++;
            say(l10n.highlights_linkRemoved);
            if (mounted) widget.onChanged(unlinked);
        }
      } catch (e) {
        // "Not found" may be about the post itself (deleted meanwhile) or
        // about the stat that was picked: reading the post again tells. When
        // it is the post, the re-read says so (onGone) — the server's
        // sentence on top of that is the second toast about one thing; when
        // the post is still there, this is the only word about it.
        final gone = e is ApiException &&
            e.statusCode == 404 &&
            mounted &&
            await _reread(item.id);
        if (!gone) say('$e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(highlightsMutedProvider, (_, muted) {
      for (final c in _players.values) {
        // ignore: discarded_futures
        c.setVolume(muted ? 0.0 : 1.0);
      }
    });
    final muted = ref.watch(highlightsMutedProvider);
    final items = widget.items;
    final trailing = widget.trailing;
    return PageView.builder(
      controller: _pages,
      scrollDirection: Axis.vertical,
      // Always scrollable, so a pull-to-refresh above works on one post too.
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _pageCount,
      onPageChanged: _onPage,
      itemBuilder: (context, i) {
        if (i >= items.length) {
          // The page after the last post — "loading more", a retry, or a
          // reel's way back — is as much a page as any other: keep it out
          // from under whatever the parent holds at the bottom (the system
          // inset on a pushed reel; the Highlights tab ends above the dock
          // by itself and passes nothing).
          final last = trailing;
          return last == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: EdgeInsets.only(bottom: widget.bottomInset),
                  child: last,
                );
        }
        final item = items[i];
        return _HighlightPage(
          key: ValueKey(item.id),
          item: item,
          player: _players[item.id],
          playFailed: _failed.contains(item.id),
          current: i == _index,
          paused: i == _index && _userPaused,
          muted: muted,
          bottomInset: widget.bottomInset,
          onTapVideo: _togglePause,
          onRetryVideo: () => _retryVideo(item.id),
          onToggleMute: _toggleMute,
          onLike: () => _like(item),
          onComments: () => _comments(item),
          onShare: () => shareHighlight(context, ref, item),
          onReport: () => _report(item),
          onMore: () => _more(item),
        );
      },
    );
  }
}

/// "1.2K" for the rail; plain below a thousand.
String _compact(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final k = n / 1000;
    return '${k.toStringAsFixed(k < 10 ? 1 : 0)}K';
  }
  final m = n / 1000000;
  return '${m.toStringAsFixed(m < 10 ? 1 : 0)}M';
}

const _textShadow = [Shadow(color: Color(0x99000000), blurRadius: 6)];

class _HighlightPage extends ConsumerStatefulWidget {
  const _HighlightPage({
    super.key,
    required this.item,
    required this.player,
    required this.playFailed,
    required this.current,
    required this.paused,
    required this.muted,
    required this.bottomInset,
    required this.onTapVideo,
    required this.onRetryVideo,
    required this.onToggleMute,
    required this.onLike,
    required this.onComments,
    required this.onShare,
    required this.onReport,
    required this.onMore,
  });

  final HighlightItem item;
  final VideoPlayerController? player;
  final bool playFailed;
  final bool current;
  final bool paused;
  final bool muted;
  final double bottomInset;
  final VoidCallback onTapVideo;
  final VoidCallback onRetryVideo;
  final VoidCallback onToggleMute;
  final VoidCallback onLike;
  final VoidCallback onComments;
  final VoidCallback onShare;

  /// Report this post — from the state on a video the check took down (H2).
  final VoidCallback onReport;
  final VoidCallback onMore;

  @override
  ConsumerState<_HighlightPage> createState() => _HighlightPageState();
}

class _HighlightPageState extends ConsumerState<_HighlightPage> {
  int _photo = 0;
  bool _expanded = false;

  String _absolute(String url) => url.startsWith('/')
      ? '${ref.read(appConfigProvider).apiBaseUrl}$url'
      : url;

  /// Upright clips fill the screen; wide ones are shown whole.
  BoxFit _fitFor(double? aspect) =>
      aspect != null && aspect < 0.8 ? BoxFit.cover : BoxFit.contain;

  List<HighlightMedia> get _photos => [
        for (final m in widget.item.media)
          if (!m.isVideo && m.url.isNotEmpty) m
      ];

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final bottom = widget.bottomInset + 14;
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Colors.black),
      if (item.isVideo) _video(item) else _photoPager(),
      // A soft shade behind the text only — never over the whole picture.
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.0, 0.2, 0.55, 1.0],
              colors: [
                Color(0x66000000),
                Color(0x00000000),
                Color(0x00000000),
                Color(0xA6000000),
              ],
            ),
          ),
        ),
      ),
      if (!item.isReady) _status(item),
      if (item.isVideo && item.isReady && widget.paused)
        const IgnorePointer(
          child: Center(
            child: Icon(Icons.play_arrow_rounded,
                size: 84, color: Color(0xCCFFFFFF), shadows: _textShadow),
          ),
        ),
      Positioned(left: 14, right: 78, bottom: bottom, child: _caption(item)),
      Positioned(right: 6, bottom: bottom, child: _rail(item)),
    ]);
  }

  // ── picture ───────────────────────────────────────────────────────────────

  Widget _poster(HighlightItem item, BoxFit fit) {
    final url = item.video?.posterUrl ?? item.thumbnailUrl;
    if (url == null) return const SizedBox.expand();
    return CachedNetworkImage(
      imageUrl: _absolute(url),
      fit: fit,
      fadeInDuration: Duration.zero,
      errorWidget: (_, __, ___) => const SizedBox.expand(),
    );
  }

  Widget _video(HighlightItem item) {
    final media = item.video;
    final posterFit = _fitFor(media?.aspectRatio);
    final c = widget.player;
    final Widget child;
    if (!item.isReady || media == null || (c == null && !widget.playFailed)) {
      child = _poster(item, posterFit);
    } else if (c == null) {
      // The player gave up on this file.
      child = Stack(fit: StackFit.expand, children: [
        _poster(item, posterFit),
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(context.l10n.highlights_cantPlay,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    shadows: _textShadow)),
            TextButton(
              onPressed: widget.onRetryVideo,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(context.l10n.common_retry),
            ),
          ]),
        ),
      ]);
    } else {
      child = ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: c,
        builder: (context, v, _) {
          final size = v.size;
          final ready = v.isInitialized && size.width > 0 && size.height > 0;
          return Stack(fit: StackFit.expand, children: [
            // Stays underneath until the first frame is drawn over it.
            _poster(item, posterFit),
            if (ready)
              FittedBox(
                fit: _fitFor(size.width / size.height),
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: VideoPlayer(c),
                ),
              )
            else if (widget.current)
              const Center(
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                ),
              ),
          ]);
        },
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: item.isReady && c != null ? widget.onTapVideo : null,
      child: child,
    );
  }

  Widget _photoPager() {
    final photos = _photos;
    if (photos.isEmpty) return const SizedBox.expand();
    return PageView.builder(
      itemCount: photos.length,
      onPageChanged: (i) => setState(() => _photo = i),
      itemBuilder: (context, i) => CachedNetworkImage(
        imageUrl: _absolute(photos[i].url),
        fit: BoxFit.contain,
        placeholder: (_, __) => const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child:
                CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
          ),
        ),
        errorWidget: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white54, size: 36),
        ),
      ),
    );
  }

  /// What is on a post that can't be watched: a web upload the server is
  /// still converting, or a video it couldn't publish — with the author's
  /// own reason in `failureMessage`.
  ///
  /// Those two are the author's alone. The third is not: a video SportPadi's
  /// check took down is also shown to a viewer who may report it, for as
  /// long as its files are kept as evidence (H2,
  /// docs/wiki/highlights.md) — the card stays where it is and says so, and
  /// the Report button is right there, because that window is the whole
  /// point of showing it.
  Widget _status(HighlightItem item) {
    final l = context.l10n;
    final failed = item.status == 'failed';
    final reportable = item.takenDownForReport;
    final card = Center(
      child: Container(
        margin: const EdgeInsets.all(36),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xB3000000),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (failed)
            const Icon(Icons.error_outline_rounded,
                color: Colors.white, size: 30)
          else
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: Colors.white),
            ),
          const SizedBox(height: 10),
          if (reportable) ...[
            Text(l.highlights_takenDownTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3)),
            const SizedBox(height: 6),
          ],
          Text(
            reportable
                ? l.highlights_takenDownText
                : failed
                    ? (item.failureMessage ?? l.highlights_failed)
                    : l.highlights_processing,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 13.5, height: 1.4),
          ),
          if (reportable)
            TextButton(
              onPressed: widget.onReport,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: Text(l.highlights_report),
            ),
        ]),
      ),
    );
    // Taps belong to the picture behind it — except where there is now
    // something to tap.
    return reportable ? card : IgnorePointer(child: card);
  }

  // ── words ─────────────────────────────────────────────────────────────────

  Widget _dots(int count) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < count; i++)
          Container(
            width: i == _photo ? 16 : 6,
            height: 6,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: i == _photo ? Colors.white : const Color(0x80FFFFFF),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ]);

  Widget _caption(HighlightItem item) {
    final l = context.l10n;
    final caption = item.caption;
    final stat = item.stat;
    final photoCount = item.isVideo ? 0 : _photos.length;
    final author = item.author.displayName.isEmpty
        ? l.common_player
        : item.author.displayName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (photoCount > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _dots(photoCount),
          ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => openPlayerProfile(context, ref, item.author.userId),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ClipOval(
              child: Crest(
                  logoUrl: item.author.avatarUrl, label: author, size: 38),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          shadows: _textShadow)),
                  if (item.createdAt != null)
                    Text(fmtRelative(item.createdAt),
                        style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 11.5,
                            shadows: _textShadow)),
                ],
              ),
            ),
          ]),
        ),
        // A guardian's post about a ward: say who it shows.
        if (item.aboutSomeoneElse)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  openPlayerProfile(context, ref, item.subject.userId),
              child: Text(l.highlights_aboutPerson(item.subject.displayName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      shadows: _textShadow)),
            ),
          ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(caption,
                  maxLines: _expanded ? 14 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      height: 1.35,
                      shadows: _textShadow)),
            ),
          ),
        if (stat != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _statChip(stat),
          ),
      ],
    );
  }

  /// The stat this highlight shows; opens the match — unless the event is
  /// private and this viewer isn't in its group: the server then sends the
  /// stat without its event, and the match page would refuse them.
  Widget _statChip(HighlightStat stat) {
    final title = stat.eventTitle;
    final label = highlightStatLabel(stat);
    final canOpen = stat.gameId.isNotEmpty && stat.eventVisible;
    return Material(
      color: const Color(0x40FFFFFF),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: canOpen ? () => context.push('/games/${stat.gameId}') : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 7, canOpen ? 8.0 : 12.0, 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(title == null ? label : '$label · $title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ),
            if (canOpen) ...[
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded,
                  size: 17, color: Colors.white),
            ],
          ]),
        ),
      ),
    );
  }

  // ── rail ──────────────────────────────────────────────────────────────────

  Widget _rail(HighlightItem item) {
    final l = context.l10n;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _RailButton(
        icon: item.likedByMe
            ? Icons.favorite_rounded
            : Icons.favorite_border_rounded,
        color: item.likedByMe ? const Color(0xFFFF4D67) : Colors.white,
        label: _compact(item.likeCount),
        tooltip: item.likedByMe ? l.highlights_unlike : l.highlights_like,
        onTap: item.isReady ? widget.onLike : null,
      ),
      // Comments and Share are gated like Like above. Nobody but the
      // author may even READ a post that isn't `ready` (the server's
      // `canSee`), so the sheet would open on "Highlight not found." beside
      // a card that is plainly still there — and the link of a post that is
      // down 404s for everyone the report window doesn't open. The web
      // greys out all three on the same card.
      _RailButton(
        icon: Icons.mode_comment_outlined,
        label: _compact(item.commentCount),
        tooltip: l.inbox_comments,
        onTap: item.isReady ? widget.onComments : null,
      ),
      _RailButton(
        icon: Icons.share_outlined,
        tooltip: l.event_share,
        onTap: item.isReady ? widget.onShare : null,
      ),
      if (item.isVideo && item.isReady)
        _RailButton(
          icon: widget.muted
              ? Icons.volume_off_rounded
              : Icons.volume_up_rounded,
          tooltip:
              widget.muted ? l.highlights_soundOn : l.highlights_soundOff,
          onTap: widget.onToggleMute,
        ),
      _RailButton(
        icon: Icons.more_horiz_rounded,
        tooltip: l.event_more,
        onTap: widget.onMore,
      ),
    ]);
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
    this.color = Colors.white,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final String? label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = label;
    final content = Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 30, color: color, shadows: _textShadow),
            if (text != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(text,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        shadows: _textShadow)),
              ),
          ]),
        ),
      ),
    );
    // Greyed, not merely inert — the web's rail does the same. The tooltip
    // stays either way, so it still says what the button is.
    //
    // Grey is for the eyes only: a screen reader would otherwise read the
    // tooltip off a thing that looks tappable and does nothing. The web
    // disables a real `<button>` there, which VoiceOver and TalkBack say
    // out loud ("dimmed" / "disabled"); this is the same thing — one node,
    // named by the tooltip, with the inert child's own semantics dropped so
    // the name isn't read twice. Dropping them drops the count under the
    // icon too, so the label carries it: a greyed Like still says how many
    // (`scope_switch.dart` names its segments the same way).
    return onTap == null
        ? Semantics(
            button: true,
            enabled: false,
            label: text == null ? tooltip : '$tooltip, $text',
            excludeSemantics: true,
            child: Opacity(opacity: 0.4, child: content),
          )
        : content;
  }
}

/// A full-screen message on the viewer's dark canvas: empty, error,
/// not-found, "loading more".
class HighlightMessage extends StatelessWidget {
  const HighlightMessage({
    super.key,
    this.icon,
    this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.busy = false,
  });

  final IconData? icon;
  final String? title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// A spinner instead of the icon.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = title;
    final b = body;
    final a = actionLabel;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (busy)
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            else if (icon != null)
              Icon(icon, color: const Color(0xB3FFFFFF), size: 42),
            if (t != null) ...[
              const SizedBox(height: 14),
              Text(t,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
            ],
            if (b != null && b.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(b,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xB3FFFFFF), fontSize: 13, height: 1.45)),
            ],
            if (a != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x80FFFFFF)),
                ),
                child: Text(a),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
