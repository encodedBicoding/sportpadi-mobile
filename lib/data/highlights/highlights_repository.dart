import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/highlights/highlight_models.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Highlights REST bridge (`/api/mobile/highlights`, contract in the
/// workspace's `docs/wiki/highlights.md`). Errors carry the server's readable
/// message — the weekly cap, a taken stat, "still processing" — so callers
/// show `'$e'`.
class HighlightsRepository {
  HighlightsRepository(this._dio);
  final Dio _dio;

  static const _path = '/api/mobile/highlights';

  /// An upload with nothing moving for this long is taken for dead.
  static const _uploadStallAfter = Duration(seconds: 45);

  Map<String, dynamic> _body(Response<dynamic> res) => highlightMap(res.data);

  HighlightsPage<HighlightItem> _page(Map<String, dynamic> d) => HighlightsPage(
        items: [
          for (final m in highlightMaps(d['items'])) HighlightItem.fromJson(m)
        ],
        nextCursor: parseStr(d['nextCursor']),
      );

  // ── reads ────────────────────────────────────────────────────────────────

  /// The feed, newest first. [tab]: `following` | `discover`.
  Future<HighlightsPage<HighlightItem>> feed(
      {required String tab, String? cursor, int? limit}) async {
    try {
      final res = await _dio.get(_path, queryParameters: {
        'tab': tab,
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': limit,
      });
      return _page(_body(res));
    } catch (e) {
      throw apiError(e, fallback: l10n.highlights_couldntLoad);
    }
  }

  /// Posts ABOUT a player (their profile grid), newest first.
  Future<HighlightsPage<HighlightItem>> byPlayer(String userId,
      {String? cursor, int? limit}) async {
    try {
      final res = await _dio.get(_path, queryParameters: {
        'playerId': userId,
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': limit,
      });
      return _page(_body(res));
    } catch (e) {
      throw apiError(e, fallback: l10n.highlights_couldntLoad);
    }
  }

  /// The highlights linked to a match's stats (timeline badges).
  Future<List<GameHighlightRef>> byGame(String gameId) async {
    try {
      final res = await _dio.get(_path, queryParameters: {'gameId': gameId});
      return [
        for (final m in highlightMaps(_body(res)['items']))
          GameHighlightRef.fromJson(m)
      ];
    } catch (e) {
      throw apiError(e, fallback: l10n.highlights_couldntLoad);
    }
  }

  /// The match reel: every highlight pinned to a stat of the EVENT [gameId]
  /// belongs to, in the event's own order — not just that one match. The
  /// post they tapped is [firstId]: item 0 of the first page and of no
  /// other, left out without complaint when this viewer may not see it (the
  /// caller already has it from [get]).
  ///
  /// `nextCursor` null means the reel has ENDED — that is what takes the
  /// viewer back to the timeline. An unknown match, or an event with nothing
  /// pinned in it, answers an empty page that has ended
  /// (docs/wiki/highlights.md, "The match reel").
  Future<HighlightsPage<HighlightItem>> byEvent(String gameId,
      {String? firstId, String? cursor, int? limit}) async {
    try {
      final res = await _dio.get(_path, queryParameters: {
        // Its own parameter: `gameId` still means the timeline's badges.
        'eventOfGameId': gameId,
        if (firstId != null) 'firstId': firstId,
        if (cursor != null) 'cursor': cursor,
        if (limit != null) 'limit': limit,
      });
      return _page(_body(res));
    } catch (e) {
      throw apiError(e, fallback: l10n.highlights_couldntLoad);
    }
  }

  /// One post. A 404 (`ApiException.statusCode`) means it doesn't exist OR
  /// the viewer may not see it — the server doesn't say which.
  Future<HighlightItem> get(String id) async {
    try {
      final res = await _dio.get('$_path/$id');
      if (res.data is! Map) {
        throw ApiException(l10n.highlights_notFound, statusCode: 404);
      }
      return HighlightItem.fromJson(_body(res));
    } catch (e) {
      throw apiError(e, fallback: l10n.highlights_couldntLoadOne);
    }
  }

  /// May I post, how many posts are left in my rolling week, and whether a
  /// VIDEO can be posted right now (`video`, when the server sends it).
  Future<HighlightQuota> quota() async {
    try {
      final res = await _dio.get('$_path/quota');
      return HighlightQuota.fromJson(_body(res));
    } catch (e) {
      throw apiError(e, fallback: l10n.highlights_couldntLoadAllowance);
    }
  }

  /// The stat picker: my recent stats, or a ward's with [forUserId]. With
  /// [gameId]: the stats of that match — mine and my wards' — that may take
  /// a highlight.
  Future<HighlightsPage<LinkableStat>> linkable(
      {String? forUserId, String? gameId, String? cursor}) async {
    try {
      final res = await _dio.get('$_path/linkable', queryParameters: {
        if (forUserId != null) 'forUserId': forUserId,
        if (gameId != null) 'gameId': gameId,
        if (cursor != null) 'cursor': cursor,
      });
      final d = _body(res);
      return HighlightsPage(
        items: [
          for (final m in highlightMaps(d['items'])) LinkableStat.fromJson(m)
        ],
        nextCursor: parseStr(d['nextCursor']),
      );
    } catch (e) {
      throw apiError(e, fallback: l10n.highlights_couldntLoadStats);
    }
  }

  /// Comments, oldest first; [cursor] loads the ones after the page.
  Future<HighlightCommentsPage> comments(String id, {String? cursor}) async {
    try {
      final res = await _dio.get('$_path/$id/comments',
          queryParameters: {if (cursor != null) 'cursor': cursor});
      final d = _body(res);
      return HighlightCommentsPage(
        items: [
          for (final m in highlightMaps(d['items']))
            HighlightComment.fromJson(m)
        ],
        nextCursor: parseStr(d['nextCursor']),
        commentCount: parseInt(d['commentCount']),
      );
    } catch (e) {
      throw apiError(e, fallback: l10n.highlights_couldntLoadComments);
    }
  }

  // ── actions ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _act(
      String id, Map<String, dynamic> body, String fallback) async {
    try {
      final res = await _dio.post('$_path/$id', data: body);
      return _body(res);
    } catch (e) {
      throw apiError(e, fallback: fallback);
    }
  }

  /// Like or unlike (safe to repeat). Returns the server's truth.
  Future<({bool liked, int likeCount})> like(String id, bool liked) async {
    final d = await _act(id, {'action': liked ? 'like' : 'unlike'},
        l10n.highlights_couldntLike);
    return (
      liked: d['liked'] is bool ? d['liked'] as bool : liked,
      likeCount: parseInt(d['likeCount']) ?? 0,
    );
  }

  /// Pin the post to a stat, move it, or — with null — take the link off.
  Future<HighlightItem> setLink(String id, HighlightLink? link) async {
    final d = await _act(id, {'action': 'link', 'link': link?.toJson()},
        l10n.highlights_couldntChangeLink);
    return HighlightItem.fromJson(d);
  }

  /// Report the post, or one comment on it with [commentId].
  Future<void> report(String id,
      {required String reason, String? note, String? commentId}) async {
    await _act(
        id,
        {
          'action': 'report',
          'reason': reason,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          if (commentId != null) 'commentId': commentId,
        },
        l10n.common_couldntSendTheReport);
  }

  /// Delete a post — mine, or one about my ward (`permissions.canDelete`).
  /// The files go too; there is no undo.
  Future<void> remove(String id) async {
    try {
      await _dio.delete('$_path/$id');
    } catch (e) {
      throw apiError(e, fallback: l10n.highlights_couldntDelete);
    }
  }

  /// [clientId] makes a retry return the first comment instead of a second.
  Future<({HighlightComment comment, int? commentCount})> addComment(
      String id, String body,
      {String? clientId}) async {
    try {
      final res = await _dio.post('$_path/$id/comments', data: {
        'body': body,
        if (clientId != null) 'clientId': clientId,
      });
      final d = _body(res);
      return (
        comment: HighlightComment.fromJson(highlightMap(d['comment'])),
        commentCount: parseInt(d['commentCount']),
      );
    } catch (e) {
      throw apiError(e, fallback: l10n.common_couldntPostYourComment);
    }
  }

  /// Returns the post's new comment count when the server sends one.
  Future<int?> deleteComment(String id, String commentId) async {
    try {
      final res = await _dio.delete('$_path/$id/comments',
          queryParameters: {'commentId': commentId});
      return parseInt(_body(res)['commentCount']);
    } catch (e) {
      throw apiError(e, fallback: l10n.common_couldntRemoveTheComment);
    }
  }

  // ── posting ──────────────────────────────────────────────────────────────

  /// A presigned PUT for ONE file. [kind]: `video` | `image` | `poster`.
  /// A video slot can be refused (429): too many videos today.
  Future<HighlightUploadSlot> createUpload(
      {required String kind, required String contentType, int? bytes}) async {
    try {
      final res = await _dio.post('$_path/upload', data: {
        'kind': kind,
        'contentType': contentType,
        // The file was compressed on this device (video ≤ 40 MB). The server
        // remembers this with the slot and treats the post accordingly:
        // published at once, then checked.
        'source': 'app',
        if (bytes != null) 'bytes': bytes,
      });
      final slot = HighlightUploadSlot.fromJson(_body(res));
      if (slot.key.isEmpty || slot.uploadUrl.isEmpty) {
        throw ApiException(l10n.common_uploadFailed);
      }
      return slot;
    } catch (e) {
      throw apiError(e, fallback: l10n.common_uploadFailed);
    }
  }

  /// PUT [file] to its slot, streamed from disk, with progress.
  ///
  /// On a bare client: the URL points at object storage, which must never
  /// see our bearer token — and the signature covers exactly the slot's
  /// headers, so nothing else is added but the length.
  Future<void> putFile(
    HighlightUploadSlot slot,
    File file, {
    required String contentType,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final put = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      // Once every byte has been handed over: how long storage may take to
      // answer. "Handed over" means to the phone's own send buffer — on a
      // very slow link the last megabytes are still leaving it, so this is
      // generous. A dead link while bytes are moving is the watchdog's job.
      receiveTimeout: const Duration(minutes: 5),
    ));
    // A connection that dies mid-file reports nothing for minutes. While
    // bytes are still to go, no progress for [_uploadStallAfter] ends the
    // upload with a message the person can act on.
    final token = cancelToken ?? CancelToken();
    var stalled = false;
    Timer? watchdog;
    void watch() {
      watchdog?.cancel();
      watchdog = Timer(_uploadStallAfter, () {
        stalled = true;
        token.cancel();
      });
    }

    try {
      final length = await file.length();
      final Stream<Uint8List> body = file
          .openRead()
          .map((chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
      watch();
      await put.put<void>(
        slot.uploadUrl,
        data: body,
        options: Options(
          headers: {...slot.headers, 'Content-Length': length},
          contentType: slot.headers['Content-Type'] ??
              slot.headers['content-type'] ??
              contentType,
        ),
        onSendProgress: (sent, total) {
          if (total > 0 && sent >= total) {
            // All of it is on its way: the answer has its own time limit.
            watchdog?.cancel();
          } else {
            watch();
          }
          onProgress?.call(sent, total);
        },
        cancelToken: token,
      );
    } catch (e) {
      if (stalled) throw ApiException(l10n.highlights_appUploadStalled);
      throw apiError(e, fallback: l10n.common_uploadFailed);
    } finally {
      watchdog?.cancel();
      put.close();
    }
  }

  /// Publish a post from uploaded files. [clientId] is minted once per post
  /// and reused on every retry, so a retry returns the first post.
  /// [media]: `{ key, posterKey?, width?, height?, durationMs? }` per file.
  Future<HighlightItem> create({
    required String clientId,
    required String kind,
    String? caption,
    required List<Map<String, dynamic>> media,
    HighlightLink? link,
  }) async {
    try {
      // No `source`: the server reads who made the files from their upload
      // slots ([createUpload]).
      final res = await _dio.post(_path, data: {
        'clientId': clientId,
        'kind': kind,
        'caption': caption,
        'media': media,
        'link': link?.toJson(),
      });
      return HighlightItem.fromJson(_body(res));
    } catch (e) {
      throw apiError(e, fallback: l10n.highlights_couldntPost);
    }
  }
}

final highlightsRepositoryProvider = Provider<HighlightsRepository>(
    (ref) => HighlightsRepository(ref.watch(dioProvider)));

/// One post by id (the `/highlights/:id` screen).
final highlightProvider = FutureProvider.autoDispose
    .family<HighlightItem, String>(
        (ref, id) => ref.watch(highlightsRepositoryProvider).get(id));

/// A match's highlights by stat id — the timeline's play badges. A failure
/// reads as "none": the badges are a bonus, never the page.
final gameHighlightsProvider = FutureProvider.autoDispose
    .family<Map<String, List<GameHighlightRef>>, String>((ref, gameId) async {
  // A post made, deleted or re-linked anywhere in the app changes the badges
  // of a match page that is open underneath.
  void changed() => ref.invalidateSelf();
  highlightsChanged.addListener(changed);
  ref.onDispose(() => highlightsChanged.removeListener(changed));
  try {
    final list = await ref.watch(highlightsRepositoryProvider).byGame(gameId);
    final byStat = <String, List<GameHighlightRef>>{};
    for (final h in list) {
      if (h.activityId.isEmpty || h.id.isEmpty) continue;
      byStat.putIfAbsent(h.activityId, () => []).add(h);
    }
    return byStat;
  } catch (_) {
    return <String, List<GameHighlightRef>>{};
  }
});

/// The weekly allowance, for the create screen.
final highlightQuotaProvider = FutureProvider.autoDispose<HighlightQuota>(
    (ref) => ref.watch(highlightsRepositoryProvider).quota());

/// Bumped after a post is made, deleted, or its link changes, so the profile
/// grids (which page with their own state, not a provider) and the timeline
/// badges ([gameHighlightsProvider]) re-read.
final highlightsChanged = ValueNotifier<int>(0);

/// Sound in the feed: muted until the viewer turns it on, then remembered
/// for the rest of the session (every video, every screen).
final highlightsMutedProvider = StateProvider<bool>((_) => true);
