import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/highlights/highlight_add.dart';
import 'package:sportpadi_mobile/data/highlights/highlight_media.dart';
import 'package:sportpadi_mobile/data/highlights/highlight_models.dart';
import 'package:sportpadi_mobile/data/highlights/highlights_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/highlights/highlight_stat_picker.dart';
import 'package:sportpadi_mobile/features/highlights/highlight_text_limit.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// `?gameId=` / `?activityId=` count only as uuids (the web's `isUuid`).
final _wantUuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);

/// One file on its way to storage.
class _Upload {
  const _Upload(this.file, this.kind, this.bytes);
  final File file;

  /// `video` | `image` | `poster`.
  final String kind;
  final int bytes;

  String get contentType => kind == 'video' ? 'video/mp4' : 'image/jpeg';
}

/// Composers that need the screen kept on right now (a link can open a
/// second composer over the first; the lock is one for the whole app).
int _awakeHolds = 0;

/// Keeping the screen on is best-effort, as in `officiate_screen.dart`.
Future<void> _setWakelock(bool on) async {
  try {
    if (on) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  } catch (_) {/* the job runs either way */}
}

/// A video Android handed back after it had closed the app behind the
/// camera ([_HighlightCreateScreenState._recoverLostVideo]), waiting for the
/// person to say what should happen to it. Kept outside the screen: the
/// picker hands a lost video over only once, so leaving the composer without
/// answering must not lose it.
String? _lostVideo;

/// Post a highlight (`/highlights/new`): ONE video (≤ 60 s, from the gallery
/// or the camera) or 1–10 photos, a caption, and optionally the stat it
/// shows.
///
/// Everything is made ready on the phone first (`highlight_media.dart`):
/// the video is compressed to 720p with its poster, photos are re-encoded
/// without EXIF. Then each file goes to its own presigned slot and the post
/// is published with the slots' keys. Pops with the new [HighlightItem].
class HighlightCreateScreen extends ConsumerStatefulWidget {
  const HighlightCreateScreen(
      {super.key, this.fromGameId, this.fromActivityId});

  /// `?gameId=&activityId=` — a match row's "+" (`game_screen.dart`): start
  /// with that stat picked, if it can still take a highlight from this
  /// person (`_preselect`). Each counts only as a uuid, the web's rule
  /// (`isUuid`). Both null when the Highlights tab opens the composer.
  final String? fromGameId;
  final String? fromActivityId;

  @override
  ConsumerState<HighlightCreateScreen> createState() =>
      _HighlightCreateScreenState();
}

class _HighlightCreateScreenState extends ConsumerState<HighlightCreateScreen>
    with WidgetsBindingObserver {
  final _caption = TextEditingController();

  /// The box stops where the server does (it counts code points).
  final _captionLimit = HighlightTextLimit(HighlightLimits.captionMax);

  /// The post's id for the server. Every retry with the SAME files sends
  /// the same one, so a lost answer can't make the server publish it twice;
  /// it only changes when the files do after an attempt ([_mediaChanged]).
  String _clientId = newHighlightClientId();

  /// `create` went out with [_clientId] and no post came back: the server
  /// may or may not have made one.
  bool _createTried = false;

  PreparedVideo? _video;
  final List<PreparedImage> _photos = [];
  LinkableStat? _link;

  /// The person has picked a stat, or taken one off, themselves: the stat
  /// the "+" asked for no longer applies (the web's `picked !== undefined`).
  bool _linkTouched = false;

  /// The "+" asked for a stat that has no free place for this person (taken
  /// since, voided, not theirs — or the list could not be had): the link
  /// card says so until they choose (the web's `preselectMissed`).
  bool _preselectMissed = false;

  /// Compressing the video / re-encoding photos.
  bool _preparing = false;
  bool _preparingVideo = false;
  double _prepareProgress = 0;

  bool _posting = false;

  /// The files are up and `create` is on its way: from here the post exists
  /// (or is about to), so the screen stays until the answer is in.
  bool _publishing = false;

  /// The person stopped the upload themselves — not an error to explain.
  bool _uploadStopped = false;
  double _uploadProgress = 0;
  CancelToken? _cancel;
  String? _error;

  /// Files already in storage (path → slot key): a retry doesn't send them
  /// again.
  final Map<String, String> _uploaded = {};

  /// 400s from `create` in a row (see the end of [_post]).
  int _refusals = 0;

  /// This screen is holding the screen on ([_holdAwake]).
  bool _awake = false;

  /// The app left the foreground while the job now running (or the last one
  /// that ran) was under way. iOS stops a video export and stalls an upload
  /// of an app that isn't on screen — a failure is then explained by that,
  /// not blamed on the video or the connection.
  bool _wentAway = false;

  /// A video whose preparation was stopped that way: "Try again" starts it
  /// once more.
  String? _retryVideo;

  /// Set while "Discard this highlight?" is on screen; completes with the
  /// answer.
  Future<bool>? _leaveAsk;

  bool get _busy => _preparing || _posting;
  bool get _hasMedia => _video != null || _photos.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    highlightComposerOpened();
    unawaited(_recoverLostVideo());
    unawaited(_preselect());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseAwake();
    _cancel?.cancel();
    if (_preparingVideo) unawaited(cancelHighlightVideo());
    // The prepared copies have served their purpose (or were abandoned).
    unawaited(highlightComposerClosed());
    _caption.dispose();
    super.dispose();
  }

  // ── staying awake ─────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` alone (a call coming in, the notification shade) doesn't
    // count: the app is still running then.
    if (_busy &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden)) {
      _wentAway = true;
    }
    // Coming back with the job still running: the system may have let the
    // lock go while the app was away, so take it again (`officiate_screen`
    // does the same) — otherwise the phone locks itself mid-upload.
    if (state == AppLifecycleState.resumed && _awake) {
      unawaited(_setWakelock(true));
    }
  }

  /// A job starts (compressing, re-encoding, uploading). Compressing takes
  /// up to a minute and an upload can take several; an iPhone locks itself
  /// after 30 seconds without a touch, and iOS then stops both. So the
  /// screen is kept on while a job runs — and only then: every way out of a
  /// job, and [dispose], calls [_releaseAwake].
  void _holdAwake() {
    _wentAway = false;
    if (_awake) return;
    _awake = true;
    if (_awakeHolds++ == 0) unawaited(_setWakelock(true));
  }

  void _releaseAwake() {
    if (!_awake) return;
    _awake = false;
    if (--_awakeHolds == 0) unawaited(_setWakelock(false));
  }

  // ── leaving ───────────────────────────────────────────────────────────────

  void _leave() => context.canPop() ? context.pop() : context.go('/home');

  /// True when the person chose to throw the post away.
  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.highlights_appDiscardTitle),
        content: Text(ctx.l10n.highlights_appDiscardBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10n.highlights_appDiscardKeep)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.l10n.highlights_appDiscardConfirm)),
        ],
      ),
    );
    return ok == true;
  }

  /// Back — the header's button, the system's, the edge swipe. With nothing
  /// prepared it just leaves. Otherwise it asks first: leaving stops the
  /// compression or the upload and deletes what was prepared.
  Future<void> _close() async {
    // While the post is being published the screen stays (a second or two):
    // leaving then would hide the new post from the feed that opened us.
    if (_publishing || _leaveAsk != null) return;
    if (!_busy && !_hasMedia) {
      _leave();
      return;
    }
    final ask = _confirmDiscard();
    _leaveAsk = ask;
    final leave = await ask;
    _leaveAsk = null;
    if (!leave || !mounted || _publishing) return;
    _leave();
  }

  // ── picking ───────────────────────────────────────────────────────────────

  /// The files of this post are about to change. If a `create` already
  /// went out with the old ones, what follows is a different post and needs
  /// its own id — otherwise the server would answer with the FIRST post and
  /// this screen would close as if the new files had been posted.
  void _mediaChanged() {
    _refusals = 0;
    if (!_createTried) return;
    _clientId = newHighlightClientId();
    _createTried = false;
  }

  Future<void> _pickVideo(ImageSource source) async {
    if (_busy) return;
    final XFile? picked;
    try {
      picked = await ImagePicker().pickVideo(
        source: source,
        maxDuration: const Duration(seconds: HighlightLimits.videoMaxSeconds),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = l10n.highlights_pickFailed;
          _retryVideo = null;
        });
      }
      return;
    }
    if (picked == null || !mounted) return;
    await _prepareVideo(picked.path);
  }

  /// Android may close the app behind the camera while a video is being
  /// filmed (a minute of recording on a phone short of memory). The
  /// recording isn't lost: the picker hands it over the next time it is
  /// asked. Only a VIDEO is taken — this is the one screen that picks
  /// videos, so it is ours; a lost photo could be another screen's.
  ///
  /// The app restarts on Home after that, so this may run days later: the
  /// video is OFFERED ([_lostVideoCard]), never prepared unasked — and not
  /// at all when its file has been cleared away meanwhile.
  Future<void> _recoverLostVideo() async {
    if (!Platform.isAndroid) return;
    try {
      final response = await ImagePicker().retrieveLostData();
      final file = response.isEmpty || response.type != RetrieveType.video
          ? null
          : response.file;
      if (file != null) _lostVideo = file.path;
    } catch (_) {
      // Nothing new to hand over; one from an earlier visit may still wait.
    }
    final path = _lostVideo;
    if (path == null) return;
    var there = false;
    try {
      there = await File(path).exists();
    } catch (_) {/* counts as gone */}
    if (!there) {
      if (_lostVideo == path) _lostVideo = null;
      return;
    }
    if (mounted) setState(() {});
  }

  void _useLostVideo(String path) {
    if (_busy) return;
    _lostVideo = null;
    unawaited(_prepareVideo(path));
  }

  /// "Discard" only puts the offer away. It used to delete the file too —
  /// but a recording the camera made for the picker is in the app's cache
  /// and NOT in the gallery, so that was the one copy of it, and a button
  /// saying no more than "Discard" must not destroy a person's video. The
  /// picker hands a lost recording over once, so the offer doesn't come
  /// back; the phone clears its own cache.
  void _discardLostVideo() {
    setState(() => _lostVideo = null);
  }

  Future<void> _prepareVideo(String path) async {
    if (_busy) return;
    _mediaChanged();
    _holdAwake();
    setState(() {
      _photos.clear();
      _video = null;
      _preparing = true;
      _preparingVideo = true;
      _prepareProgress = 0;
      _error = null;
      _retryVideo = null;
    });
    PreparedVideo? video;
    String? error;
    String? retry;
    try {
      video = await prepareHighlightVideo(
        path,
        onProgress: (f) {
          if (mounted) setState(() => _prepareProgress = f);
        },
      );
    } on HighlightMediaCancelled {
      // Their own choice: back to the start, nothing to explain.
    } on HighlightMediaException catch (e) {
      if (e.unexplained && _wentAway) {
        // The phone was locked, or another app was looked at, while the
        // encoder ran: that is what stopped it, not the video ("Try another
        // one" would be wrong — every video would end the same way).
        error = l10n.highlights_appKeepOpen;
        retry = path;
      } else {
        error = e.message;
      }
    } catch (e) {
      error = '$e';
    } finally {
      _releaseAwake();
    }
    if (!mounted) return;
    final prepared = video;
    final failed = error;
    final again = retry;
    setState(() {
      _video = prepared;
      _preparing = false;
      _preparingVideo = false;
      _error = failed;
      _retryVideo = again;
    });
  }

  Future<void> _pickPhotos({bool camera = false}) async {
    if (_busy) return;
    final room = HighlightLimits.maxPhotos - _photos.length;
    if (room <= 0) return;
    final picked = <XFile>[];
    try {
      final picker = ImagePicker();
      // requestFullMetadata: false — we don't want the photo's location,
      // and iOS then needs no photo-library permission at all.
      if (camera) {
        final one = await picker.pickImage(
            source: ImageSource.camera, requestFullMetadata: false);
        if (one != null) picked.add(one);
      } else if (room == 1) {
        // The multi-picker refuses a limit below two.
        final one = await picker.pickImage(
            source: ImageSource.gallery, requestFullMetadata: false);
        if (one != null) picked.add(one);
      } else {
        picked.addAll(await picker.pickMultiImage(
            limit: room, requestFullMetadata: false));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = l10n.highlights_pickFailed;
          _retryVideo = null;
        });
      }
      return;
    }
    if (picked.isEmpty || !mounted) return;
    _mediaChanged();
    _holdAwake();
    setState(() {
      _video = null;
      _preparing = true;
      _preparingVideo = false;
      _error = null;
      _retryVideo = null;
    });
    String? error;
    try {
      // Not every platform enforces the picker's limit.
      for (final x in picked.take(room)) {
        try {
          final photo = await prepareHighlightPhoto(x.path);
          if (!mounted) return;
          setState(() => _photos.add(photo));
        } catch (e) {
          // Keep the ones that worked; say why one is missing.
          error = '$e';
        }
      }
    } finally {
      _releaseAwake();
    }
    if (!mounted) return;
    final failed = error;
    setState(() {
      _preparing = false;
      _error = failed;
    });
  }

  Future<void> _pickStat() async {
    if (_posting) return;
    final pick = await showHighlightStatPicker(context);
    if (pick == null || !mounted) return;
    setState(() {
      _link = pick;
      _linkTouched = true;
      _preselectMissed = false;
    });
  }

  /// Opened from a match row's "+": start with that stat picked, as the
  /// web's composer does (`NewHighlightClient.tsx` `preselected`) — of the
  /// match's FREE places on that stat, this person's own first, else the
  /// first (a ward's; `highlightPreselect`). The places are the match's
  /// `linkable` list, in pages of 50, stopping at the page that holds the
  /// stat (a stat's entries are listed together) and after four at most.
  /// Nothing free there — or no answer — and nothing is picked; the card
  /// then says so (`highlights_statPreselectMissed`), as the web's does. A
  /// choice the person made meanwhile wins — and so does tapping Post: the
  /// pick never changes the link once a post has begun (kmdock review LOW-1;
  /// the web still has that race, `link = picked ?? preselected` at submit).
  Future<void> _preselect() async {
    final gameId = widget.fromGameId;
    final activityId = widget.fromActivityId;
    if (gameId == null ||
        activityId == null ||
        !_wantUuid.hasMatch(gameId) ||
        !_wantUuid.hasMatch(activityId)) {
      return;
    }
    final repo = ref.read(highlightsRepositoryProvider);
    final me = ref.read(authControllerProvider).valueOrNull?.user?.id;
    LinkableStat? found;
    try {
      final listed = <LinkableStat>[];
      String? cursor;
      for (var page = 0; page < 4; page++) {
        final res =
            await repo.linkable(gameId: gameId, cursor: cursor, limit: 50);
        listed.addAll(res.items);
        cursor = res.nextCursor;
        if (cursor == null ||
            res.items.any((s) => s.stat.activityId == activityId)) {
          break;
        }
      }
      found = highlightPreselect(listed, activityId: activityId, me: me);
    } catch (_) {
      found = null;
    }
    // `_linkTouched` also covers a Post tapped meanwhile (`_post` sets it),
    // and `_posting` says the same while that post is in flight.
    if (!mounted || _linkTouched || _posting || _link != null) return;
    final pick = found;
    setState(() {
      if (pick != null) {
        _link = pick;
      } else {
        _preselectMissed = true;
      }
    });
  }

  // ── posting ───────────────────────────────────────────────────────────────

  Future<void> _post() async {
    if (_busy || !_hasMedia) return;
    // Whatever stat this goes out with (or none) is now the person's own
    // choice: a pre-pick still on its way must not change the link under a
    // post in flight, nor slip onto the retry of one that failed.
    _linkTouched = true;
    final repo = ref.read(highlightsRepositoryProvider);
    final video = _video;
    final photos = List<PreparedImage>.of(_photos);
    final caption = _caption.text.trim();
    final link = _link;

    final files = <_Upload>[
      if (video != null) ...[
        _Upload(video.file, 'video', video.bytes),
        _Upload(video.poster.file, 'poster', video.poster.bytes),
      ] else
        for (final photo in photos) _Upload(photo.file, 'image', photo.bytes),
    ];
    var total = 0;
    for (final f in files) {
      total += f.bytes;
    }
    if (total <= 0) total = 1;

    final cancel = CancelToken();
    _cancel = cancel;
    _uploadStopped = false;
    _holdAwake();
    setState(() {
      _posting = true;
      _publishing = false;
      _uploadProgress = 0;
      _error = null;
    });
    try {
      var done = 0;
      for (final f in files) {
        if (cancel.isCancelled) break;
        if (_uploaded[f.file.path] == null) {
          final slot = await repo.createUpload(
              kind: f.kind, contentType: f.contentType, bytes: f.bytes);
          final before = done;
          await repo.putFile(
            slot,
            f.file,
            contentType: f.contentType,
            cancelToken: cancel,
            onProgress: (sent, _) {
              if (!mounted) return;
              final fraction = (before + sent) / total;
              setState(
                  () => _uploadProgress = fraction > 1.0 ? 1.0 : fraction);
            },
          );
          _uploaded[f.file.path] = slot.key;
        }
        done += f.bytes;
        if (!mounted) return;
        final overall = done / total;
        setState(() => _uploadProgress = overall > 1.0 ? 1.0 : overall);
      }

      // "Discard this highlight?" is on screen: its answer comes first —
      // past this point the post is published.
      final ask = _leaveAsk;
      if (ask != null && await ask) return;
      if (!mounted) return;
      // Stopped between two files, where no request was there to fail.
      if (cancel.isCancelled) {
        setState(() => _posting = false);
        return;
      }
      setState(() => _publishing = true);
      _createTried = true;

      final media = <Map<String, dynamic>>[
        if (video != null)
          {
            'key': _uploaded[video.file.path],
            'posterKey': _uploaded[video.poster.file.path],
            // The video's size as it is shown (highlight_media.dart works
            // it out; the poster can be smaller than the video).
            'width': video.width,
            'height': video.height,
            if (video.durationMs != null) 'durationMs': video.durationMs,
          }
        else
          for (final photo in photos)
            {
              'key': _uploaded[photo.file.path],
              'width': photo.width,
              'height': photo.height,
            },
      ];
      final subject = link?.subject.userId ?? '';
      final item = await repo.create(
        clientId: _clientId,
        kind: video != null ? 'video' : 'photos',
        caption: caption.isEmpty ? null : caption,
        media: media,
        link: link == null
            ? null
            : HighlightLink(
                activityId: link.stat.activityId,
                subjectUserId: subject.isEmpty ? null : subject),
      );
      // Grids and timelines elsewhere in the app re-read.
      highlightsChanged.value++;
      if (!mounted) return;
      // The composer is normally pushed over the page that opened it; were
      // it ever the only page, popping would throw — and the post is made.
      if (context.canPop()) {
        context.pop(item);
      } else {
        context.go('/home');
      }
    } catch (e) {
      var message = '$e';
      var statGone = false;

      // The stat is gone, but taking the link off would move the post to
      // its author: it is left on the form for the person to change.
      var keepLink = false;
      if (e is ApiException && e.statusCode == 400) {
        // Only an answer about the FILES ("We couldn't find one of your
        // uploads") should make the next try send them again — same post
        // id, so never a duplicate. The server words its refusals for
        // people, not for code, so: a 400 with no stat linked is about the
        // files. With one it may be about the stat ("Removed stats … can't
        // take a highlight"), and 40 MB shouldn't go up again for that — so
        // the match is asked whether the stat can still take a highlight
        // (as the web does): gone → the uploads are kept and the person is
        // told so, and what became of the link; still there → it was the
        // files. When that can't be found out, the uploads are kept unless
        // it happens twice in a row.
        final gone = link != null && _publishing
            ? await _statGone(repo, link)
            : null;
        if (link != null && gone == true) {
          statGone = true;
          // Dropping the link quietly would hand the post over: a ward's
          // highlight, seen by no more people than the ward's profile is,
          // would go out as the guardian's own — as public as the
          // guardian's profile. So a ward's link STAYS on the form, with
          // its name, and they choose (another of the ward's stats, or the
          // link off themselves). Only a post about me is unlinked here.
          keepLink = link.forWard;
          message = keepLink
              ? l10n.highlights_appStatGoneWardKept
              // Not the web's `statGoneKept`: it says "tap Try again", and
              // the only button here is "Post".
              : l10n.highlights_appStatGoneKept;
        } else if (link == null || gone == false || ++_refusals > 1) {
          _uploaded.clear();
          _refusals = 0;
        }
      } else if (_wentAway && (e is! ApiException || e.statusCode == null)) {
        // No answer at all (a stall, a dropped connection), and the app
        // was off screen meanwhile: that is what an upload doesn't survive.
        // "Post" is still there to try again.
        message = l10n.highlights_appKeepOpen;
      }
      if (!mounted) return;
      setState(() {
        _posting = false;
        _publishing = false;
        // The stat is gone, so the next try goes without it — unless the
        // link is what makes this post the ward's (keepLink above).
        if (statGone && !keepLink && identical(_link, link)) _link = null;
        // Stopping the upload was their own choice: nothing to explain.
        _error = _uploadStopped ? null : message;
      });
    } finally {
      _releaseAwake();
    }
  }

  /// Has the stat picked for this post gone from its match since (voided,
  /// or no longer the person's)? Null when that couldn't be found out.
  ///
  /// Gone from the LIST, which is not the same as taken. A stat another
  /// guardian linked a post to between the two taps is still listed (with
  /// `highlightId`), and the server answers 409 for that one — never the
  /// 400 this question is asked about, which `resolveLink` sends for a stat
  /// that can't take a highlight at all and `linkable` leaves out. Counting
  /// a taken stat as gone would tell the person a stat was removed when it
  /// wasn't, and keep uploads the server has just said it can't find. The
  /// web asks the same question the same way (`statStillListed`).
  Future<bool?> _statGone(HighlightsRepository repo, LinkableStat link) async {
    final gameId = link.stat.gameId;
    if (gameId.isEmpty) return null;
    try {
      String? cursor;
      // One person's stats in one match: a page or two.
      for (var hops = 0; hops < 4; hops++) {
        final page = await repo.linkable(gameId: gameId, cursor: cursor);
        for (final s in page.items) {
          if (s.stat.activityId == link.stat.activityId &&
              s.subject.userId == link.subject.userId) {
            return false;
          }
        }
        cursor = page.nextCursor;
        if (cursor == null) return true;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// "Cancel" next to the upload bar. What is already in storage stays
  /// there for another try.
  void _stopUpload() {
    if (!_posting || _publishing) return;
    _uploadStopped = true;
    _cancel?.cancel();
  }

  // ── screen ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final quota = ref.watch(highlightQuotaProvider);
    return PopScope(
      // With nothing prepared, back simply leaves; otherwise [_close] asks.
      canPop: !_busy && !_hasMedia,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: _header(p),
            ),
            Expanded(
              child: AsyncView<HighlightQuota>(
                value: quota,
                onRetry: () => ref.invalidate(highlightQuotaProvider),
                // Once a post is under way a refreshed allowance must not
                // take the composer away from under it.
                data: (q) => q.canPost || _hasMedia || _busy
                    ? _composer(p, q)
                    : _blocked(p, q),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// [SpHeader]'s look, with a back button that goes through [_close] (the
  /// shared header pops at once, which would throw a post away unasked).
  Widget _header(AppPalette p) {
    final l = context.l10n;
    return Row(children: [
      SpRoundButton(
        icon: Icons.arrow_back_ios_new_rounded,
        tooltip: l.common_back,
        iconSize: 18,
        onTap: () => unawaited(_close()),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(l.highlights_newPost,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: p.ink,
                fontSize: 20,
                height: 1.2,
                fontWeight: FontWeight.w800)),
      ),
    ]);
  }

  /// Why no VIDEO can be posted right now (`Quota.video`), or null when one
  /// can. Photos are never affected. `blockedBy` is an open set: a reason
  /// we don't know still means "no video for now".
  String? _videoBlockedText(HighlightQuota q) {
    final video = q.video;
    final reason = video?.blockedBy;
    if (video == null || reason == null) return null;
    final l = context.l10n;
    final String why;
    switch (reason) {
      case 'daily':
        final next = video.nextSlotAt;
        why = next == null
            ? l.highlights_appVideoDailyLimit
            : l.highlights_appVideoDailyLimitUntil(fmtInstant(next));
      case 'processing':
        why = l.highlights_appVideoWaitProcessing;
      default:
        why = l.highlights_appVideoUnavailable;
    }
    return '$why ${l.highlights_appPhotosStillOk}';
  }

  /// The allowance says no: why, in plain words, and nothing to fill in.
  Widget _blocked(AppPalette p, HighlightQuota q) {
    final l = context.l10n;
    final String title;
    final String body;
    // `blockedBy` is an open set: anything we don't know gets the generic
    // message rather than a wrong reason.
    switch (q.blockedBy) {
      case 'paused':
        title = l.highlights_pausedTitle;
        body = l.highlights_pausedBody;
      case 'limit':
        title = l.highlights_limitTitle;
        final next = q.nextSlotAt;
        final rule = l.highlights_limitBody(q.limit, q.windowDays);
        body = next == null
            ? rule
            : '$rule ${l.highlights_limitNext(fmtInstant(next))}';
      default:
        title = l.highlights_blockedTitle;
        body = l.highlights_blockedBody;
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SpIconTile(Icons.hourglass_empty_rounded,
              size: 56, iconSize: 26),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.45)),
          const SizedBox(height: 16),
          SpButton(label: l.common_back, onTap: _leave),
        ]),
      ),
    );
  }

  Widget _composer(AppPalette p, HighlightQuota q) {
    final l = context.l10n;
    final error = _error;
    // Videos have limits of their own; with one reached the two video
    // choices are greyed out and the reason is given above them.
    final noVideo = _videoBlockedText(q);
    final lost = _lostVideo;
    final retry = _retryVideo;
    final captionLength = highlightTextLength(_caption.text);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Text(l.highlights_allowance(q.remaining, q.limit, q.windowDays),
            style: TextStyle(color: p.muted, fontSize: 12.5)),
        const SizedBox(height: 14),
        if (_preparing)
          _preparingCard(p)
        else if (!_hasMedia) ...[
          if (noVideo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(noVideo,
                  style:
                      TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
            ),
          if (lost != null && noVideo == null) _lostVideoCard(p, lost),
          _option(
            p,
            Icons.video_library_outlined,
            l.highlights_chooseVideo,
            l.highlights_videoHint(HighlightLimits.videoMaxSeconds),
            noVideo != null ? null : () => _pickVideo(ImageSource.gallery),
          ),
          _option(
            p,
            Icons.videocam_outlined,
            l.highlights_recordVideo,
            l.highlights_videoHint(HighlightLimits.videoMaxSeconds),
            noVideo != null ? null : () => _pickVideo(ImageSource.camera),
          ),
          _option(
            p,
            Icons.photo_library_outlined,
            l.highlights_choosePhotos,
            l.highlights_photosHint(HighlightLimits.maxPhotos),
            _pickPhotos,
          ),
          _option(
            p,
            Icons.photo_camera_outlined,
            l.manage_takeAPhoto,
            l.highlights_photosHint(HighlightLimits.maxPhotos),
            () => _pickPhotos(camera: true),
          ),
        ],
        if (_photos.isNotEmpty) _photoStrip(p),
        if (_video != null && !_preparing) _videoCard(p, _video!),
        if (_hasMedia) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _caption,
            enabled: !_posting,
            minLines: 2,
            maxLines: 5,
            // Not `maxLength`: that counts a flag or a tone-marked letter as
            // one character, the server as several — the counter and the
            // limit here are the server's.
            inputFormatters: [_captionLimit],
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: l.highlights_captionHint,
              counterText: '$captionLength/${HighlightLimits.captionMax}',
            ),
          ),
          const SizedBox(height: 8),
          _linkCard(p),
        ],
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error,
              style: TextStyle(color: p.danger, fontSize: 13, height: 1.4)),
          // The video itself was fine (the app left the screen while it
          // was being prepared): one tap starts it again.
          if (retry != null && noVideo == null && !_busy && !_hasMedia)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => unawaited(_prepareVideo(retry)),
                child: Text(l.common_tryAgain),
              ),
            ),
        ],
        if (_posting) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                // The files are up; the post itself is being made.
                value: _publishing ? null : _uploadProgress,
                minHeight: 6,
                color: p.accent),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(
                  _publishing
                      ? l.inbox_posting
                      : l.highlights_uploading((_uploadProgress * 100).round()),
                  style: TextStyle(color: p.muted, fontSize: 12.5)),
            ),
            // A way out of a slow upload that doesn't cost the post.
            if (!_publishing)
              TextButton(
                onPressed: _stopUpload,
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(l.common_cancel),
              ),
          ]),
        ],
        if (_hasMedia && !_preparing) ...[
          const SizedBox(height: 18),
          SpButton(
            label: _posting ? l.inbox_posting : l.highlights_post,
            icon: Icons.send_rounded,
            expand: true,
            tone: SpButtonTone.brand,
            onTap: _posting ? null : _post,
          ),
        ],
      ],
    );
  }

  /// "Use the video from earlier?" — see [_recoverLostVideo].
  Widget _lostVideoCard(AppPalette p, String path) {
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.highlights_appLostVideoTitle,
                style: TextStyle(
                    color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(l.highlights_appLostVideoBody,
                style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: _discardLostVideo,
                child: Text(l.highlights_appDiscardConfirm),
              ),
              TextButton(
                onPressed: () => _useLostVideo(path),
                child: Text(l.highlights_appLostVideoUse),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  /// [onTap] null = it can't be chosen right now: shown greyed out.
  Widget _option(AppPalette p, IconData icon, String title, String subtitle,
      VoidCallback? onTap) {
    final card = GlassCard(
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Row(children: [
          SpIconTile(icon, bg: p.accentTint, fg: p.greenText),
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
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ]),
      );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: onTap == null ? Opacity(opacity: 0.45, child: card) : card,
    );
  }

  Widget _preparingCard(AppPalette p) {
    final l = context.l10n;
    final known = _preparingVideo && _prepareProgress > 0;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              _preparingVideo
                  ? l.highlights_preparingVideo
                  : l.highlights_preparingPhotos,
              style: TextStyle(
                  color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(l.highlights_preparingNote,
              style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: known ? _prepareProgress : null,
                minHeight: 6,
                color: p.accent),
          ),
          if (_preparingVideo)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => unawaited(cancelHighlightVideo()),
                child: Text(l.common_cancel),
              ),
            ),
        ],
      ),
    );
  }

  String _clock(int ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _megabytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  Widget _videoCard(AppPalette p, PreparedVideo video) {
    final l = context.l10n;
    final ms = video.durationMs;
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(video.poster.file,
              width: 84, height: 112, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.highlights_videoReady,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                  ms == null
                      ? _megabytes(video.bytes)
                      : '${_clock(ms)} · ${_megabytes(video.bytes)}',
                  style: TextStyle(color: p.muted, fontSize: 12.5)),
              if (!_posting)
                TextButton(
                  onPressed: () {
                    _mediaChanged();
                    setState(() => _video = null);
                  },
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  child: Text(l.highlights_chooseAnother),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _photoStrip(AppPalette p) {
    final canAdd = _photos.length < HighlightLimits.maxPhotos && !_busy;
    return SizedBox(
      height: 124,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < _photos.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(_photos[i].file,
                      width: 93, height: 124, fit: BoxFit.cover),
                ),
                if (!_busy)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Material(
                      color: const Color(0x99000000),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          _mediaChanged();
                          setState(() => _photos.removeAt(i));
                        },
                        child: const SizedBox(
                          width: 26,
                          height: 26,
                          child: Icon(Icons.close_rounded,
                              size: 15, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          if (canAdd)
            Material(
              color: p.surface2,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _pickPhotos,
                child: SizedBox(
                  width: 93,
                  height: 124,
                  child: Icon(Icons.add_photo_alternate_outlined,
                      color: p.muted, size: 26),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The stat this highlight shows — optional, and changeable after posting.
  Widget _linkCard(AppPalette p) {
    final l = context.l10n;
    final link = _link;
    final where = link == null
        ? (_preselectMissed
            ? l.highlights_statPreselectMissed
            : l.highlights_linkHint)
        : [
            if (link.subject.displayName.isNotEmpty) link.subject.displayName,
            if (link.stat.eventTitle != null) link.stat.eventTitle!,
          ].join(' · ');
    return GlassCard(
      padding: const EdgeInsets.all(12),
      onTap: _posting ? null : _pickStat,
      child: Row(children: [
        SpIconTile(Icons.add_link_rounded, bg: p.accentTint, fg: p.greenText),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  link == null
                      ? l.highlights_linkToStat
                      : highlightStatLabel(link.stat),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              if (where.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(where,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
              ],
            ],
          ),
        ),
        if (link != null && !_posting)
          IconButton(
            tooltip: l.highlights_removeStat,
            onPressed: () => setState(() {
              _link = null;
              _linkTouched = true;
            }),
            icon: Icon(Icons.close_rounded, color: p.muted, size: 20),
          )
        else
          Icon(Icons.chevron_right_rounded, color: p.muted),
      ]),
    );
  }
}
