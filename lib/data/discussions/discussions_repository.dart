import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/discussions/discussion_models.dart';
import 'package:sportpadi_mobile/data/messages/message_models.dart'
    show MessageAttachment;
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Discussions REST bridge (`/api/mobile/discussions`). Errors carry the
/// server's readable message (locked threads, rate limits, who may post) —
/// callers show `'$e'` in a snackbar.
class DiscussionsRepository {
  DiscussionsRepository(this._dio);
  final Dio _dio;

  static const _path = '/api/mobile/discussions';

  Future<Map<String, dynamic>> _get(Map<String, dynamic> query, String fallback,
      {String path = _path}) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      return res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
    } catch (e) {
      throw apiError(e, fallback: fallback);
    }
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body, String fallback,
      {String path = _path}) async {
    try {
      final res = await _dio.post(path, data: body);
      return res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
    } catch (e) {
      throw apiError(e, fallback: fallback);
    }
  }

  Future<Map<String, dynamic>> _act(
          String id, Map<String, dynamic> body, String fallback) =>
      _post(body, fallback, path: '$_path/$id');

  // ── reads ────────────────────────────────────────────────────────────────

  /// Where I can read and post in [groupId].
  Future<DiscussionSpaces> spaces(String groupId) async {
    final d = await _get(
        {'view': 'spaces', 'groupId': groupId}, "Couldn't load discussions.");
    return DiscussionSpaces.fromJson(d);
  }

  /// Discussions in a group. [space]: empty = everything I can see,
  /// `group` = group-wide only, otherwise a team id. [sort]: `hot` · `new` ·
  /// `top`. [cursor] is the previous page's `nextCursor`.
  Future<DiscussionPage> list({
    required String groupId,
    String space = '',
    String sort = 'hot',
    String? flair,
    String? status,
    int? cursor,
  }) async {
    final d = await _get({
      'groupId': groupId,
      if (space.isNotEmpty) 'teamId': space,
      'sort': sort,
      if (flair != null) 'flair': flair,
      if (status != null) 'status': status,
      if (cursor != null && cursor > 0) 'cursor': '$cursor',
    }, "Couldn't load discussions.");
    return DiscussionPage.fromJson(d);
  }

  /// Every discussion I can see, across all my groups and teams, newest
  /// activity first — each with its group, [DiscussionItem.unseen] and
  /// [DiscussionItem.newComments]. [unreadOnly]: only those with something
  /// new for me. [cursor] is the previous page's `nextCursor`.
  Future<DiscussionPage> mine({bool unreadOnly = false, int? cursor}) async {
    final d = await _get({
      'view': 'mine',
      if (unreadOnly) 'unread': '1',
      if (cursor != null && cursor > 0) 'cursor': '$cursor',
    }, "Couldn't load your discussions.");
    return DiscussionPage.fromJson(d);
  }

  /// One discussion with its comments. [sort]: `best` · `new` · `old`.
  Future<DiscussionThread> thread(String id, {String sort = 'best'}) async {
    final d = await _get({'sort': sort}, "Couldn't load this discussion.",
        path: '$_path/$id');
    final t = DiscussionThread.fromJson(d);
    if (t.discussion.id.isEmpty) {
      throw ApiException('This discussion is no longer available.',
          statusCode: 404);
    }
    return t;
  }

  // ── posting ──────────────────────────────────────────────────────────────

  /// Start a discussion; returns its id. [teamId] null = group-wide.
  Future<String> create({
    required String groupId,
    String? teamId,
    required String title,
    String body = '',
    String flair = 'general',
    List<MessageAttachment> attachments = const [],
    String? viaWardId,
  }) async {
    final r = await _post({
      'action': 'create',
      'groupId': groupId,
      if (teamId != null) 'teamId': teamId,
      'title': title,
      'body': body,
      'flair': flair,
      if (attachments.isNotEmpty)
        'attachments': [for (final a in attachments) a.toJson()],
      if (viaWardId != null) 'viaWardId': viaWardId,
    }, "Couldn't post your discussion.");
    final id = parseStr(r['id']);
    if (id == null) {
      throw ApiException("Couldn't post your discussion. Try again.");
    }
    return id;
  }

  /// Comment on a discussion, or reply to [parentId]; returns its id.
  Future<String> comment(String discussionId,
      {required String body, String? parentId, String? viaWardId}) async {
    final r = await _act(
        discussionId,
        {
          'action': 'comment',
          'body': body,
          if (parentId != null) 'parentId': parentId,
          if (viaWardId != null) 'viaWardId': viaWardId,
        },
        "Couldn't post your comment.");
    return parseStr(r['id']) ?? '';
  }

  // ── the discussion ───────────────────────────────────────────────────────

  /// OP: edit the title, body or flair.
  Future<void> update(String id,
      {String? title, String? body, String? flair}) async {
    await _act(
        id,
        {
          'action': 'update',
          if (title != null) 'title': title,
          if (body != null) 'body': body,
          if (flair != null) 'flair': flair,
        },
        "Couldn't save your changes.");
  }

  /// OP or a moderator: remove it.
  Future<void> delete(String id) async {
    await _act(id, {'action': 'delete'}, "Couldn't remove the discussion.");
  }

  /// OP or a moderator: `open` or `resolved`.
  Future<void> setStatus(String id, String status) async {
    await _act(id, {'action': 'status', 'status': status},
        "Couldn't update the discussion.");
  }

  /// Moderators: pin and / or lock.
  Future<void> moderate(String id, {bool? pinned, bool? locked}) async {
    await _act(
        id,
        {
          'action': 'moderate',
          if (pinned != null) 'pinned': pinned,
          if (locked != null) 'locked': locked,
        },
        "Couldn't update the discussion.");
  }

  /// Upvote (1) or clear (0) my vote on the discussion, or on one of
  /// its comments ([commentId]). Returns the new score and my vote.
  Future<({int score, int myVote})> vote(String discussionId,
      {String? commentId, required int value}) async {
    final r = await _act(
        discussionId,
        {
          'action': 'vote',
          'type': commentId == null ? 'discussion' : 'comment',
          if (commentId != null) 'targetId': commentId,
          'value': value,
        },
        "Couldn't save your vote.");
    return (
      score: parseInt(r['score']) ?? 0,
      myVote: (parseInt(r['myVote']) ?? value).clamp(-1, 1),
    );
  }

  // ── comments ─────────────────────────────────────────────────────────────

  Future<void> editComment(String discussionId, String commentId,
      {required String body}) async {
    await _act(
        discussionId,
        {'action': 'edit-comment', 'commentId': commentId, 'body': body},
        "Couldn't save your comment.");
  }

  Future<void> deleteComment(String discussionId, String commentId) async {
    await _act(
        discussionId,
        {'action': 'delete-comment', 'commentId': commentId},
        "Couldn't remove the comment.");
  }

  /// Report the discussion, or one of its comments ([commentId]). Returns
  /// true when I had already reported it (and it's still open).
  Future<bool> report(String discussionId,
      {String? commentId, required String reason, String? details}) async {
    final r = await _act(
        discussionId,
        {
          'action': 'report',
          if (commentId != null) 'commentId': commentId,
          'reason': reason,
          if (details != null && details.trim().isNotEmpty)
            'details': details.trim(),
        },
        "Couldn't send the report.");
    return r['alreadyReported'] == true;
  }
}

final discussionsRepositoryProvider = Provider<DiscussionsRepository>(
    (ref) => DiscussionsRepository(ref.watch(dioProvider)));

/// Where I can read and post in a group. An error means "not for you":
/// entry points watch `.valueOrNull` and hide themselves.
final discussionSpacesProvider = FutureProvider.autoDispose
    .family<DiscussionSpaces, String>((ref, groupId) =>
        ref.watch(discussionsRepositoryProvider).spaces(groupId));

/// The latest change made on a thread (vote, comment, status, pin, lock,
/// edit, removal). Lists on screen listen and patch their cards.
final discussionChangeProvider =
    StateProvider<DiscussionChange?>((ref) => null);

/// A list's filters. [space]: '' = everything I can see, `group` =
/// group-wide only, otherwise a team id.
typedef DiscussionListKey = ({
  String groupId,
  String space,
  String sort,
  String? flair,
  String? status,
});

/// Discussions in a group, paged, with optimistic votes. Invalidate the whole
/// family (`ref.invalidate(discussionListProvider)`) after posting.
class DiscussionListController
    extends AutoDisposeFamilyAsyncNotifier<DiscussionPage, DiscussionListKey> {
  bool _loadingMore = false;

  // Captured in build: used after awaits, when this list may be gone.
  late DiscussionsRepository _repo;
  late StateController<DiscussionChange?> _changes;

  @override
  Future<DiscussionPage> build(DiscussionListKey arg) {
    _loadingMore = false;
    _repo = ref.watch(discussionsRepositoryProvider);
    _changes = ref.read(discussionChangeProvider.notifier);
    ref.listen<DiscussionChange?>(discussionChangeProvider, (_, change) {
      if (change != null) _apply(change);
    });
    return _repo.list(
      groupId: arg.groupId,
      space: arg.space,
      sort: arg.sort,
      flair: arg.flair,
      status: arg.status,
    );
  }

  void _apply(DiscussionChange c) {
    final current = state.valueOrNull;
    if (current == null || !current.items.any((i) => i.id == c.id)) return;
    state = AsyncData(current.copyWith(items: [
      for (final i in current.items)
        if (i.id != c.id) i else if (!c.removed) c.applyTo(i)
    ]));
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final next = await _repo.list(
        groupId: arg.groupId,
        space: arg.space,
        sort: arg.sort,
        flair: arg.flair,
        status: arg.status,
        cursor: cursor,
      );
      final latest = state.valueOrNull;
      // A refresh landed meanwhile: its first page wins.
      if (latest == null || latest.nextCursor != cursor) return;
      final seen = {for (final d in latest.items) d.id};
      state = AsyncData(DiscussionPage(
        items: [
          ...latest.items,
          for (final d in next.items)
            if (!seen.contains(d.id)) d
        ],
        nextCursor: next.nextCursor,
      ));
    } catch (_) {
      // Keep what's on screen; the next scroll retries.
    } finally {
      _loadingMore = false;
    }
  }

  /// ▲ ([pressed] 1) on a card: shown at once, reconciled with
  /// the server's score, rolled back (and rethrown) on failure.
  Future<void> vote(String id, int pressed) async {
    final current = state.valueOrNull;
    DiscussionItem? item;
    for (final i in current?.items ?? const <DiscussionItem>[]) {
      if (i.id == id) item = i;
    }
    if (item == null) return;
    final before = item;
    final value = nextDiscussionVote(before.myVote, pressed);
    void put(int score, int myVote) =>
        _apply(DiscussionChange(id: id, score: score, myVote: myVote));
    put(before.score - before.myVote + value, value);
    try {
      final r = await _repo.vote(id, value: value);
      put(r.score, r.myVote);
      _broadcast(DiscussionChange(id: id, score: r.score, myVote: r.myVote));
    } catch (_) {
      put(before.score, before.myVote);
      rethrow;
    }
  }

  void _broadcast(DiscussionChange c) => _changes.state = c;
}

final discussionListProvider = AsyncNotifierProvider.autoDispose
    .family<DiscussionListController, DiscussionPage, DiscussionListKey>(
        DiscussionListController.new);

/// The menu's Discussions page: every discussion I can see, paged, newest
/// activity first. The family arg is "unread only". Threads opened from it
/// clear their "new" marks through [discussionChangeProvider]; invalidate the
/// whole family (`ref.invalidate(myDiscussionsProvider)`) to refetch both.
class MyDiscussionsController
    extends AutoDisposeFamilyAsyncNotifier<DiscussionPage, bool> {
  bool _loadingMore = false;

  // Captured in build: used after awaits, when this list may be gone.
  late DiscussionsRepository _repo;

  @override
  Future<DiscussionPage> build(bool arg) {
    _loadingMore = false;
    _repo = ref.watch(discussionsRepositoryProvider);
    ref.listen<DiscussionChange?>(discussionChangeProvider, (_, change) {
      if (change != null) _apply(change);
    });
    return _repo.mine(unreadOnly: arg);
  }

  void _apply(DiscussionChange c) {
    final current = state.valueOrNull;
    if (current == null || !current.items.any((i) => i.id == c.id)) return;
    state = AsyncData(current.copyWith(items: [
      for (final i in current.items)
        if (i.id != c.id) i else if (!c.removed) c.applyTo(i)
    ]));
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final next = await _repo.mine(unreadOnly: arg, cursor: cursor);
      final latest = state.valueOrNull;
      // A refresh landed meanwhile: its first page wins.
      if (latest == null || latest.nextCursor != cursor) return;
      final seen = {for (final d in latest.items) d.id};
      state = AsyncData(DiscussionPage(
        items: [
          ...latest.items,
          for (final d in next.items)
            if (!seen.contains(d.id)) d
        ],
        nextCursor: next.nextCursor,
      ));
    } catch (_) {
      // Keep what's on screen; the next scroll retries.
    } finally {
      _loadingMore = false;
    }
  }
}

final myDiscussionsProvider = AsyncNotifierProvider.autoDispose
    .family<MyDiscussionsController, DiscussionPage, bool>(
        MyDiscussionsController.new);

typedef DiscussionThreadKey = ({String id, String sort});

/// One discussion and its comments. Votes and new comments show at once and
/// are reconciled with the server; every change is broadcast through
/// [discussionChangeProvider] so lists on screen follow.
class DiscussionController extends AutoDisposeFamilyAsyncNotifier<
    DiscussionThread, DiscussionThreadKey> {
  bool _reloading = false;
  int _localSeq = 0;

  // Captured in build: used after awaits, when the thread may be closed.
  late DiscussionsRepository _repo;
  late StateController<DiscussionChange?> _changes;

  String get _id => arg.id;

  @override
  Future<DiscussionThread> build(DiscussionThreadKey arg) {
    _reloading = false;
    _repo = ref.watch(discussionsRepositoryProvider);
    _changes = ref.read(discussionChangeProvider.notifier);
    return _repo.thread(arg.id, sort: arg.sort);
  }

  void _broadcast(DiscussionChange c) => _changes.state = c;

  /// Tell lists on screen what this thread looks like now.
  void broadcastCurrent() {
    final t = state.valueOrNull;
    if (t != null) _broadcast(DiscussionChange.of(t.discussion));
  }

  void _setDiscussion(DiscussionDetail d, {bool broadcast = true}) {
    final t = state.valueOrNull;
    if (t == null) return;
    state = AsyncData(t.copyWith(discussion: d));
    if (broadcast) _broadcast(DiscussionChange.of(d));
  }

  /// Refetch in place (no loading state). Returns false when it failed.
  Future<bool> reload() async {
    if (_reloading) return false;
    _reloading = true;
    try {
      final t = await _repo.thread(_id, sort: arg.sort);
      state = AsyncData(t);
      _broadcast(DiscussionChange.of(t.discussion));
      return true;
    } catch (_) {
      return false;
    } finally {
      _reloading = false;
    }
  }

  /// ▲ / ▼ on the discussion.
  Future<void> voteDiscussion(int pressed) async {
    final d = state.valueOrNull?.discussion;
    if (d == null) return;
    final value = nextDiscussionVote(d.myVote, pressed);
    _setDiscussion(d.copyWith(score: d.score - d.myVote + value, myVote: value),
        broadcast: false);
    try {
      final r = await _repo.vote(_id, value: value);
      final now = state.valueOrNull?.discussion;
      if (now != null) {
        _setDiscussion(now.copyWith(score: r.score, myVote: r.myVote));
      }
    } catch (_) {
      final now = state.valueOrNull?.discussion;
      if (now != null) {
        _setDiscussion(now.copyWith(score: d.score, myVote: d.myVote),
            broadcast: false);
      }
      rethrow;
    }
  }

  void _patchComment(
      String id, DiscussionComment Function(DiscussionComment) f) {
    final t = state.valueOrNull;
    if (t == null) return;
    state = AsyncData(t.copyWith(
        comments: [for (final c in t.comments) c.id == id ? f(c) : c]));
  }

  /// ▲ / ▼ on a comment.
  Future<void> voteComment(String commentId, int pressed) async {
    DiscussionComment? c;
    for (final x
        in state.valueOrNull?.comments ?? const <DiscussionComment>[]) {
      if (x.id == commentId) c = x;
    }
    if (c == null || c.deleted || c.pending) return;
    final before = c;
    final value = nextDiscussionVote(before.myVote, pressed);
    _patchComment(
        commentId,
        (x) => x.copyWith(
            score: before.score - before.myVote + value, myVote: value));
    try {
      final r = await _repo.vote(_id, commentId: commentId, value: value);
      _patchComment(
          commentId, (x) => x.copyWith(score: r.score, myVote: r.myVote));
    } catch (_) {
      _patchComment(commentId,
          (x) => x.copyWith(score: before.score, myVote: before.myVote));
      rethrow;
    }
  }

  /// Post a comment (a reply when [parentId] is set). It shows at once as
  /// "Posting…", then the thread reloads with the real one. On failure the
  /// placeholder goes and the error is rethrown.
  Future<void> addComment(String body,
      {String? parentId, String? viaWardId, required String myName}) async {
    final t = state.valueOrNull;
    if (t == null) return;
    DiscussionComment? parent;
    for (final c in t.comments) {
      if (c.id == parentId) parent = c;
    }
    final localId = 'local-${++_localSeq}';
    final local = DiscussionComment(
      id: localId,
      parentId: parent == null
          ? null
          : (parent.depth >= 4 ? parent.parentId : parent.id),
      depth: parent == null ? 0 : (parent.depth >= 4 ? 4 : parent.depth + 1),
      body: body,
      author: DiscussionAuthor(id: '', name: myName),
      isOP: t.me.isOP,
      mine: true,
      createdAt: DateTime.now(),
      pending: true,
    );
    final d = t.discussion;
    state = AsyncData(t.copyWith(
      discussion: d.copyWith(commentCount: d.commentCount + 1),
      // Newest-first sorts show it on top; otherwise at the end.
      comments:
          arg.sort == 'new' ? [local, ...t.comments] : [...t.comments, local],
    ));
    try {
      await _repo.comment(_id,
          body: body, parentId: parentId, viaWardId: viaWardId);
    } catch (_) {
      final now = state.valueOrNull;
      if (now != null) {
        final nd = now.discussion;
        state = AsyncData(now.copyWith(
          discussion: nd.copyWith(
              commentCount: nd.commentCount > 0 ? nd.commentCount - 1 : 0),
          comments: [
            for (final c in now.comments)
              if (c.id != localId) c
          ],
        ));
      }
      rethrow;
    }
    final ok = await reload();
    if (!ok) {
      // Posted, but the refetch failed: keep the placeholder as posted.
      final now = state.valueOrNull;
      if (now == null) return;
      state = AsyncData(now.copyWith(comments: [
        for (final c in now.comments)
          if (c.id == localId)
            DiscussionComment(
              id: c.id,
              parentId: c.parentId,
              depth: c.depth,
              body: c.body,
              author: c.author,
              isOP: c.isOP,
              mine: true,
              createdAt: c.createdAt,
            )
          else
            c
      ]));
      _broadcast(DiscussionChange.of(now.discussion));
    }
  }

  Future<void> editComment(String commentId, String body) async {
    await _repo.editComment(_id, commentId, body: body);
    _patchComment(
        commentId, (c) => c.copyWith(body: body, editedAt: DateTime.now()));
  }

  Future<void> deleteComment(String commentId) async {
    await _repo.deleteComment(_id, commentId);
    _patchComment(commentId, (c) => c.asDeleted());
    final d = state.valueOrNull?.discussion;
    if (d != null) {
      _setDiscussion(d.copyWith(
          commentCount: d.commentCount > 0 ? d.commentCount - 1 : 0));
    }
  }

  /// OP: edit the title, body and flair. (Not `update`: that would clash
  /// with [AsyncNotifier.update].)
  Future<void> edit({
    required String title,
    required String body,
    required String flair,
  }) async {
    await _repo.update(_id, title: title, body: body, flair: flair);
    final d = state.valueOrNull?.discussion;
    if (d != null) {
      _setDiscussion(d.copyWith(
          title: title, body: body, flair: flair, editedAt: DateTime.now()));
    }
  }

  Future<void> setStatus(String status) async {
    await _repo.setStatus(_id, status);
    final d = state.valueOrNull?.discussion;
    if (d != null) _setDiscussion(d.copyWith(status: status));
  }

  Future<void> moderate({bool? pinned, bool? locked}) async {
    await _repo.moderate(_id, pinned: pinned, locked: locked);
    // Locking changes who may comment: take the server's word for it.
    if (!await reload()) {
      final d = state.valueOrNull?.discussion;
      if (d != null) _setDiscussion(d.copyWith(pinned: pinned, locked: locked));
    }
  }

  /// Remove the discussion; lists drop it.
  Future<void> delete() async {
    await _repo.delete(_id);
    _broadcast(DiscussionChange(id: _id, removed: true));
  }
}

final discussionProvider = AsyncNotifierProvider.autoDispose
    .family<DiscussionController, DiscussionThread, DiscussionThreadKey>(
        DiscussionController.new);
