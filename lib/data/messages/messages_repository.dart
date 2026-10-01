import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/messages/message_models.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Messages REST bridge (`/api/mobile/messages`, Messaging 2). Errors carry
/// the server's readable message (reach rules, closed threads, rate limits)
/// — callers show `'$e'` in a snackbar.
class MessagesRepository {
  MessagesRepository(this._dio);
  final Dio _dio;

  static const _path = '/api/mobile/messages';

  Future<dynamic> _get(Map<String, dynamic> query, String fallback,
      {String path = _path}) async {
    try {
      final res = await _dio.get(path, queryParameters: query);
      return res.data;
    } catch (e) {
      throw apiError(e, fallback: fallback);
    }
  }

  Future<Map<String, dynamic>> _post(
      Map<String, dynamic> body, String fallback,
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

  static Map<String, dynamic> _asMap(dynamic d) =>
      d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  static List<Map<String, dynamic>> _asList(dynamic d) => d is List
      ? [
          for (final e in d)
            if (e is Map) Map<String, dynamic>.from(e)
        ]
      : const [];

  String _conversationId(Map<String, dynamic> r) {
    final id = parseStr(r['conversationId']);
    if (id == null) {
      throw ApiException("Couldn't start the conversation. Try again.");
    }
    return id;
  }

  // ── reads ────────────────────────────────────────────────────────────────

  /// My conversations, newest activity first. [cursor] is the previous
  /// page's `nextCursor`.
  Future<ConversationPage> list(
      {String? cursor, String? groupId, bool unreadOnly = false}) async {
    final d = await _get({
      if (cursor != null) 'cursor': cursor,
      if (groupId != null) 'groupId': groupId,
      if (unreadOnly) 'unread': '1',
    }, "Couldn't load your messages.");
    return ConversationPage.fromJson(_asMap(d));
  }

  /// Unread conversations (muted ones don't count). Never throws — a failed
  /// count is just no badge.
  Future<int> unreadCount() async {
    try {
      final res =
          await _dio.get(_path, queryParameters: {'view': 'unread-count'});
      return parseInt(_asMap(res.data)['messages']) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// One conversation with its newest page of messages (or the page before
  /// [before]). Fetching the newest page marks it read.
  Future<ConversationThread> thread(String id, {String? before}) async {
    final d = await _get({
      if (before != null) 'before': before,
    }, "Couldn't load this conversation.", path: '$_path/$id');
    if (d is! Map) {
      throw ApiException('This conversation is no longer available.',
          statusCode: 404);
    }
    return ConversationThread.fromJson(Map<String, dynamic>.from(d));
  }

  /// What I can start in [groupId].
  Future<StartOptions> startOptions(String groupId) async {
    final d = await _get({'view': 'start-options', 'groupId': groupId},
        "Couldn't load who you can message.");
    return StartOptions.fromJson(_asMap(d));
  }

  /// Staff: members I can message, optionally filtered by name.
  Future<List<ReachablePerson>> reachable(String groupId, {String? q}) async {
    final d = await _get({
      'view': 'reachable',
      'groupId': groupId,
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    }, "Couldn't load members.");
    return [
      for (final p in _asList(d)) ReachablePerson.fromJson(p)
    ].where((p) => p.userId.isNotEmpty).toList();
  }

  /// Admins: every conversation in the group (read-only oversight).
  Future<ConversationPage> groupConversations(String groupId,
      {String? cursor}) async {
    final d = await _get({
      'view': 'group',
      'groupId': groupId,
      if (cursor != null) 'cursor': cursor,
    }, "Couldn't load the group's conversations.");
    return ConversationPage.fromJson(_asMap(d));
  }

  /// Admins: reports in the group. [status] is `open`, `reviewed`,
  /// `dismissed` or `all`.
  Future<List<MessageReport>> reports(String groupId,
      {String status = 'open'}) async {
    final d = await _get(
        {'view': 'reports', 'groupId': groupId, 'status': status},
        "Couldn't load reports.");
    return [for (final r in _asList(d)) MessageReport.fromJson(r)]
        .where((r) => r.id.isNotEmpty)
        .toList();
  }

  // ── starting ─────────────────────────────────────────────────────────────

  List<Map<String, dynamic>>? _attachments(List<MessageAttachment> a) =>
      a.isEmpty ? null : [for (final x in a) x.toJson()];

  /// Staff → a member (a ward: their guardians). Reuses an open thread.
  Future<String> startAsStaff({
    required String groupId,
    required String memberId,
    required String body,
    List<MessageAttachment> attachments = const [],
  }) async {
    final att = _attachments(attachments);
    final r = await _post({
      'action': 'start-staff',
      'groupId': groupId,
      'memberId': memberId,
      'body': body,
      if (att != null) 'attachments': att,
    }, "Couldn't send your message.");
    return _conversationId(r);
  }

  /// Me (or a ward of mine) → all the group's admins, one shared thread.
  Future<String> contactAdmins({
    required String groupId,
    String? aboutWardId,
    required String body,
    List<MessageAttachment> attachments = const [],
  }) async {
    final att = _attachments(attachments);
    final r = await _post({
      'action': 'contact-admins',
      'groupId': groupId,
      if (aboutWardId != null) 'aboutWardId': aboutWardId,
      'body': body,
      if (att != null) 'attachments': att,
    }, "Couldn't send your message.");
    return _conversationId(r);
  }

  /// Me (or a ward of mine) → a coach of our team.
  Future<String> messageCoach({
    required String groupId,
    required String coachId,
    String? aboutWardId,
    required String body,
    List<MessageAttachment> attachments = const [],
  }) async {
    final att = _attachments(attachments);
    final r = await _post({
      'action': 'message-coach',
      'groupId': groupId,
      'coachId': coachId,
      if (aboutWardId != null) 'aboutWardId': aboutWardId,
      'body': body,
      if (att != null) 'attachments': att,
    }, "Couldn't send your message.");
    return _conversationId(r);
  }

  // ── in a thread ──────────────────────────────────────────────────────────

  Future<void> send(
    String conversationId, {
    required String body,
    List<MessageAttachment> attachments = const [],
    String? replyToId,
  }) async {
    final att = _attachments(attachments);
    await _post({
      'action': 'send',
      'body': body,
      if (att != null) 'attachments': att,
      if (replyToId != null) 'replyToId': replyToId,
    }, "Couldn't send your message.", path: '$_path/$conversationId');
  }

  Future<void> markRead(String conversationId) async {
    await _post({'action': 'read'}, "Couldn't update.",
        path: '$_path/$conversationId');
  }

  Future<void> close(String conversationId) async {
    await _post({'action': 'close'}, "Couldn't close the conversation.",
        path: '$_path/$conversationId');
  }

  Future<void> deleteMessage(String conversationId, String messageId) async {
    await _post({'action': 'delete', 'messageId': messageId},
        "Couldn't delete the message.",
        path: '$_path/$conversationId');
  }

  /// Mute pushes for [hours], or [forever]; neither unmutes.
  Future<void> mute(String conversationId,
      {int? hours, bool forever = false}) async {
    await _post({
      'action': 'mute',
      if (hours != null) 'hours': hours,
      if (forever) 'forever': true,
    }, "Couldn't change the setting.", path: '$_path/$conversationId');
  }

  // ── moderation ───────────────────────────────────────────────────────────

  /// Report a message or an announcement. Returns true when I had already
  /// reported it (and it's still open).
  Future<bool> report({
    String? messageId,
    String? announcementId,
    required String reason,
    String? details,
  }) async {
    final r = await _post({
      'action': 'report',
      if (messageId != null) 'messageId': messageId,
      if (announcementId != null) 'announcementId': announcementId,
      'reason': reason,
      if (details != null && details.trim().isNotEmpty)
        'details': details.trim(),
    }, "Couldn't send the report.");
    return r['alreadyReported'] == true;
  }

  /// Admins: mark a report `reviewed` or `dismissed`.
  Future<void> resolveReport(String id, String status) async {
    await _post({'action': 'resolve-report', 'id': id, 'status': status},
        "Couldn't update the report.");
  }
}

final messagesRepositoryProvider = Provider<MessagesRepository>(
    (ref) => MessagesRepository(ref.watch(dioProvider)));

/// Messages tab badge. Polled while something watches it (the Inbox button),
/// and invalidated on message pushes, app resume, tab switches and whenever a
/// conversation is opened.
final messagesUnreadProvider = FutureProvider.autoDispose<int>((ref) {
  final timer = Timer(const Duration(seconds: 45), () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);
  return ref.watch(messagesRepositoryProvider).unreadCount();
});

/// My conversations, paged. The family arg is "unread only". Invalidate the
/// whole family (`ref.invalidate(messagesListProvider)`) to refresh both.
class MessagesListController
    extends AutoDisposeFamilyAsyncNotifier<ConversationPage, bool> {
  bool _loadingMore = false;

  @override
  Future<ConversationPage> build(bool arg) {
    _loadingMore = false;
    return ref.watch(messagesRepositoryProvider).list(unreadOnly: arg);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final next = await ref
          .read(messagesRepositoryProvider)
          .list(cursor: cursor, unreadOnly: arg);
      final latest = state.valueOrNull;
      // A refresh landed meanwhile: its first page wins.
      if (latest == null || latest.nextCursor != cursor) return;
      final seen = {for (final c in latest.items) c.id};
      state = AsyncData(ConversationPage(
        items: [
          ...latest.items,
          for (final c in next.items)
            if (!seen.contains(c.id)) c
        ],
        nextCursor: next.nextCursor,
      ));
    } catch (_) {
      // Keep what's on screen; the next scroll retries.
    } finally {
      _loadingMore = false;
    }
  }

  /// Opening a conversation reads it: drop its unread mark right away.
  void markRead(String id) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(ConversationPage(
      items: [
        for (final c in current.items)
          if (c.id == id && c.unread) c.copyWith(unread: false) else c
      ],
      nextCursor: current.nextCursor,
    ));
  }
}

final messagesListProvider = AsyncNotifierProvider.autoDispose
    .family<MessagesListController, ConversationPage, bool>(
        MessagesListController.new);

/// One conversation. [ConversationController.refreshLatest] merges the
/// newest page into what's on screen (polling, pushes, after sending);
/// [ConversationController.loadEarlier] prepends the page before it.
class ConversationController
    extends AutoDisposeFamilyAsyncNotifier<ConversationThread, String> {
  bool _loadingEarlier = false;
  bool _refreshing = false;

  bool get loadingEarlier => _loadingEarlier;

  @override
  Future<ConversationThread> build(String arg) {
    _loadingEarlier = false;
    _refreshing = false;
    return ref.watch(messagesRepositoryProvider).thread(arg);
  }

  /// Fetch the newest page (which marks it read) and merge it in, keeping
  /// any earlier pages already loaded. Returns true when something new
  /// arrived. Never throws — the next poll retries.
  Future<bool> refreshLatest() async {
    final current = state.valueOrNull;
    if (current == null || _refreshing) return false;
    _refreshing = true;
    try {
      final latest = await ref.read(messagesRepositoryProvider).thread(arg);
      final now = state.valueOrNull;
      if (now == null) return false;
      final latestIds = {for (final m in latest.messages) m.id};
      final overlaps = now.messages.any((m) => latestIds.contains(m.id));
      final List<ChatMessage> merged;
      final String? nextBefore;
      if (!overlaps && latest.hasEarlier) {
        // A gap between the two windows: start again from the newest page.
        merged = latest.messages;
        nextBefore = latest.nextBefore;
      } else {
        final firstAt = latest.messages.isEmpty
            ? null
            : latest.messages.first.createdAt;
        final older = [
          for (final m in now.messages)
            if (!latestIds.contains(m.id) &&
                (firstAt == null ||
                    (m.createdAt != null && m.createdAt!.isBefore(firstAt))))
              m
        ];
        merged = [...older, ...latest.messages];
        nextBefore = older.isEmpty ? latest.nextBefore : now.nextBefore;
      }
      final nowIds = {for (final m in now.messages) m.id};
      final changed = merged.length != now.messages.length ||
          merged.any((m) => !nowIds.contains(m.id));
      state = AsyncData(ConversationThread(
        conversation: latest.conversation,
        messages: merged,
        nextBefore: nextBefore,
      ));
      return changed;
    } catch (_) {
      return false;
    } finally {
      _refreshing = false;
    }
  }

  Future<void> loadEarlier() async {
    final current = state.valueOrNull;
    final before = current?.nextBefore;
    if (current == null || before == null || _loadingEarlier) return;
    _loadingEarlier = true;
    try {
      final page = await ref
          .read(messagesRepositoryProvider)
          .thread(arg, before: before);
      final latest = state.valueOrNull;
      if (latest == null || latest.nextBefore != before) return;
      final seen = {for (final m in latest.messages) m.id};
      state = AsyncData(ConversationThread(
        conversation: latest.conversation,
        messages: [
          for (final m in page.messages)
            if (!seen.contains(m.id)) m,
          ...latest.messages,
        ],
        nextBefore: page.nextBefore,
      ));
    } finally {
      _loadingEarlier = false;
    }
  }

  /// Show a message as deleted without waiting for the next poll.
  void markDeleted(String messageId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(messages: [
      for (final m in current.messages)
        if (m.id == messageId) m.asDeleted() else m
    ]));
  }
}

final conversationProvider = AsyncNotifierProvider.autoDispose
    .family<ConversationController, ConversationThread, String>(
        ConversationController.new);

/// What I can start in a group. An error means "not for you": entry points
/// watch `.valueOrNull` and hide themselves.
final messageStartOptionsProvider = FutureProvider.autoDispose
    .family<StartOptions, String>((ref, groupId) =>
        ref.watch(messagesRepositoryProvider).startOptions(groupId));

typedef ReachableKey = ({String groupId, String q});

/// Staff: members I can message in a group, filtered by name.
final messageReachableProvider = FutureProvider.autoDispose
    .family<List<ReachablePerson>, ReachableKey>((ref, k) => ref
        .watch(messagesRepositoryProvider)
        .reachable(k.groupId, q: k.q));

/// Staff: the ids of everyone I can message in a group (for per-row Message
/// buttons). Empty for non-staff, and on any error.
final messageReachableIdsProvider =
    FutureProvider.autoDispose.family<Set<String>, String>((ref, groupId) async {
  try {
    final options =
        await ref.watch(messageStartOptionsProvider(groupId).future);
    if (!options.isStaff) return const <String>{};
    final people = await ref
        .watch(messageReachableProvider((groupId: groupId, q: '')).future);
    return {for (final p in people) p.userId};
  } catch (_) {
    return const <String>{};
  }
});

/// Admins: every conversation in a group, paged (read-only oversight).
class GroupConversationsController
    extends AutoDisposeFamilyAsyncNotifier<ConversationPage, String> {
  bool _loadingMore = false;

  @override
  Future<ConversationPage> build(String arg) {
    _loadingMore = false;
    return ref.watch(messagesRepositoryProvider).groupConversations(arg);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final next = await ref
          .read(messagesRepositoryProvider)
          .groupConversations(arg, cursor: cursor);
      final latest = state.valueOrNull;
      if (latest == null || latest.nextCursor != cursor) return;
      final seen = {for (final c in latest.items) c.id};
      state = AsyncData(ConversationPage(
        items: [
          ...latest.items,
          for (final c in next.items)
            if (!seen.contains(c.id)) c
        ],
        nextCursor: next.nextCursor,
      ));
    } catch (_) {
      // Keep what's on screen.
    } finally {
      _loadingMore = false;
    }
  }
}

final groupConversationsProvider = AsyncNotifierProvider.autoDispose
    .family<GroupConversationsController, ConversationPage, String>(
        GroupConversationsController.new);

typedef ReportsKey = ({String groupId, String status});

/// Admins: reports in a group by status (`open`, `reviewed`, `dismissed`,
/// `all`).
final messageReportsProvider = FutureProvider.autoDispose
    .family<List<MessageReport>, ReportsKey>((ref, k) => ref
        .watch(messagesRepositoryProvider)
        .reports(k.groupId, status: k.status));
