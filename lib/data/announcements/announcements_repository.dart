import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/announcements/announcement_models.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// Announcements REST bridge (`/api/mobile/announcements`, Messaging 1).
/// Errors carry the server's readable message (quota and rate limits
/// included) — callers show `'$e'` in a snackbar.
class AnnouncementsRepository {
  AnnouncementsRepository(this._dio);
  final Dio _dio;

  static const _path = '/api/mobile/announcements';

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
      Map<String, dynamic> body, String fallback) async {
    try {
      final res = await _dio.post(_path, data: body);
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

  // ── reads ────────────────────────────────────────────────────────────────

  /// My inbox, newest first. [cursor] is the previous page's `nextCursor`.
  Future<AnnouncementPage> inbox({String? cursor, String? groupId}) async {
    final d = await _get({
      if (cursor != null) 'cursor': cursor,
      if (groupId != null) 'groupId': groupId,
    }, "Couldn't load announcements.");
    return AnnouncementPage.fromJson(_asMap(d));
  }

  /// The Inbox badge. Never throws — a failed count is just no badge.
  Future<AnnouncementUnread> unreadCount() async {
    try {
      final res =
          await _dio.get(_path, queryParameters: {'view': 'unread-count'});
      return AnnouncementUnread.fromJson(_asMap(res.data));
    } catch (_) {
      return AnnouncementUnread.zero;
    }
  }

  /// One announcement (opening it marks it seen). Staff also get receipts.
  Future<AnnouncementDetail> get(String id) async {
    final d = await _get(const {}, "Couldn't load this announcement.",
        path: '$_path/$id');
    if (d is! Map) {
      throw ApiException('This announcement was removed.', statusCode: 404);
    }
    return AnnouncementDetail.fromJson(Map<String, dynamic>.from(d));
  }

  /// What I can send in [groupId]. Throws (403) for non-staff.
  Future<ComposerInfo> composer(String groupId) async {
    final d = await _get({'view': 'composer', 'groupId': groupId},
        "Couldn't load the composer.");
    return ComposerInfo.fromJson(_asMap(d));
  }

  /// Members I can hand-pick, optionally filtered by name.
  Future<List<PickablePerson>> pickable(String groupId, {String? q}) async {
    final d = await _get({
      'view': 'pickable',
      'groupId': groupId,
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
    }, "Couldn't load members.");
    return [for (final p in _asList(d)) PickablePerson.fromJson(p)];
  }

  /// Announcements sent in a group, with seen / "Got it" counts (staff).
  Future<SentPage> sent(String groupId, {String? cursor}) async {
    final d = await _get({
      'view': 'sent',
      'groupId': groupId,
      if (cursor != null) 'cursor': cursor,
    }, "Couldn't load sent announcements.");
    return SentPage.fromJson(_asMap(d));
  }

  /// Pinned announcements for the top of a group (or team) page.
  Future<List<AnnouncementItem>> pinned(String groupId,
      {String? teamId}) async {
    final d = await _get({
      'view': 'pinned',
      'groupId': groupId,
      if (teamId != null) 'teamId': teamId,
    }, "Couldn't load pinned announcements.");
    return [for (final a in _asList(d)) AnnouncementItem.fromJson(a)];
  }

  /// Groups whose announcements I've muted.
  Future<Set<String>> mutedGroups() async {
    final d = await _get({'view': 'muted'}, "Couldn't load your settings.");
    return parseStrList(d).toSet();
  }

  /// Push / email per category.
  Future<List<NotificationPreference>> preferences() async {
    final d =
        await _get({'view': 'preferences'}, "Couldn't load your settings.");
    return [for (final p in _asList(d)) NotificationPreference.fromJson(p)];
  }

  // ── writes ───────────────────────────────────────────────────────────────

  /// How many people [audience] reaches.
  Future<AudiencePreview> preview(
      String groupId, AnnouncementAudience audience) async {
    final r = await _post({
      'action': 'preview',
      'groupId': groupId,
      'audience': audience.toJson(),
    }, "Couldn't count the audience.");
    return AudiencePreview.fromJson(r);
  }

  /// Send an announcement. Returns its id, the people it reached (a ward
  /// counts once) and the deliveries it made (a guardian counts once however
  /// many wards).
  Future<({String id, int recipientCount, int deliveries})> send({
    required String groupId,
    required AnnouncementAudience audience,
    required String title,
    required String body,
    bool urgent = false,
    DateTime? pinnedUntil,
    DateTime? expiresAt,
    ({String type, String id})? link,
    List<AnnouncementAttachment> attachments = const [],
  }) async {
    final r = await _post({
      'action': 'send',
      'groupId': groupId,
      'audience': audience.toJson(),
      'title': title,
      'body': body,
      'priority': urgent ? 'urgent' : 'normal',
      if (pinnedUntil != null)
        'pinnedUntil': pinnedUntil.toUtc().toIso8601String(),
      if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
      if (link != null) 'link': {'type': link.type, 'id': link.id},
      if (attachments.isNotEmpty)
        'attachments': [for (final a in attachments) a.toJson()],
    }, "Couldn't send the announcement.");
    return (
      id: parseStr(r['id']) ?? '',
      recipientCount: parseInt(r['recipientCount']) ?? 0,
      deliveries: parseInt(r['deliveries']) ?? 0,
    );
  }

  Future<void> markSeen(List<String> ids) async {
    if (ids.isEmpty) return;
    await _post({'action': 'seen', 'ids': ids}, "Couldn't update.");
  }

  Future<void> markAllSeen() async {
    await _post({'action': 'seen-all'}, "Couldn't mark them read.");
  }

  /// "Got it".
  Future<void> ack(String id) async {
    await _post({'action': 'ack', 'id': id}, "Couldn't send your Got it.");
  }

  Future<void> delete(String id) async {
    await _post(
        {'action': 'delete', 'id': id}, "Couldn't delete the announcement.");
  }

  Future<void> unpin(String id) async {
    await _post({'action': 'unpin', 'id': id}, "Couldn't unpin it.");
  }

  Future<void> setMuted(String groupId, bool muted) async {
    await _post({'action': 'mute', 'groupId': groupId, 'muted': muted},
        "Couldn't change the setting.");
  }

  Future<void> setPreference(String category,
      {bool? push, bool? email}) async {
    await _post({
      'action': 'preference',
      'category': category,
      if (push != null) 'push': push,
      if (email != null) 'email': email,
    }, "Couldn't save the setting.");
  }
}

final announcementsRepositoryProvider = Provider<AnnouncementsRepository>(
    (ref) => AnnouncementsRepository(ref.watch(dioProvider)));

/// Inbox badge. Polled while something watches it (the Inbox button next to
/// the bell), like the bell's count; also invalidated on foreground push, app
/// resume, tab switches and whenever an announcement is opened or read.
final announcementsUnreadProvider =
    FutureProvider.autoDispose<AnnouncementUnread>((ref) {
  final timer = Timer(const Duration(seconds: 45), () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);
  return ref.watch(announcementsRepositoryProvider).unreadCount();
});

/// The inbox, paged. [AnnouncementsInboxController.loadMore] appends the
/// next page; invalidating starts again from the top.
class AnnouncementsInboxController
    extends AutoDisposeAsyncNotifier<AnnouncementPage> {
  bool _loadingMore = false;

  bool get loadingMore => _loadingMore;

  @override
  Future<AnnouncementPage> build() {
    _loadingMore = false;
    return ref.watch(announcementsRepositoryProvider).inbox();
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final next =
          await ref.read(announcementsRepositoryProvider).inbox(cursor: cursor);
      final latest = state.valueOrNull;
      // A refresh landed meanwhile: its first page wins.
      if (latest == null || latest.nextCursor != cursor) return;
      final seen = {for (final a in latest.items) a.id};
      state = AsyncData(AnnouncementPage(
        items: [
          ...latest.items,
          for (final a in next.items)
            if (!seen.contains(a.id)) a
        ],
        nextCursor: next.nextCursor,
      ));
    } catch (_) {
      // Keep what's on screen; the next scroll retries.
    } finally {
      _loadingMore = false;
    }
  }

  /// Mark everything read (server first, then the list on screen).
  Future<void> markAllSeen() async {
    await ref.read(announcementsRepositoryProvider).markAllSeen();
    final current = state.valueOrNull;
    if (current == null) return;
    final now = DateTime.now();
    state = AsyncData(AnnouncementPage(
      items: [
        for (final a in current.items)
          a.isUnread ? a.copyWith(seenAt: now) : a
      ],
      nextCursor: current.nextCursor,
    ));
  }
}

final announcementsInboxProvider = AsyncNotifierProvider.autoDispose<
    AnnouncementsInboxController,
    AnnouncementPage>(AnnouncementsInboxController.new);

/// One announcement by id (fetching it marks it seen).
final announcementDetailProvider = FutureProvider.autoDispose
    .family<AnnouncementDetail, String>(
        (ref, id) => ref.watch(announcementsRepositoryProvider).get(id));

/// What the viewer may send in a group. An error (403) means "not staff":
/// entry points watch `.valueOrNull` and hide themselves.
final announcementComposerProvider = FutureProvider.autoDispose
    .family<ComposerInfo, String>((ref, groupId) =>
        ref.watch(announcementsRepositoryProvider).composer(groupId));

/// Sent announcements in a group (staff), paged like the inbox.
class SentAnnouncementsController
    extends AutoDisposeFamilyAsyncNotifier<SentPage, String> {
  bool _loadingMore = false;

  @override
  Future<SentPage> build(String arg) {
    _loadingMore = false;
    return ref.watch(announcementsRepositoryProvider).sent(arg);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null || _loadingMore) return;
    _loadingMore = true;
    try {
      final next = await ref
          .read(announcementsRepositoryProvider)
          .sent(arg, cursor: cursor);
      final latest = state.valueOrNull;
      if (latest == null || latest.nextCursor != cursor) return;
      final seen = {for (final a in latest.items) a.id};
      state = AsyncData(SentPage(
        items: [
          ...latest.items,
          for (final a in next.items)
            if (!seen.contains(a.id)) a
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

final sentAnnouncementsProvider = AsyncNotifierProvider.autoDispose
    .family<SentAnnouncementsController, SentPage, String>(
        SentAnnouncementsController.new);

/// Pinned announcements for a group page (`teamId: null`) or a team page.
typedef PinnedKey = ({String groupId, String? teamId});

final pinnedAnnouncementsProvider = FutureProvider.autoDispose
    .family<List<AnnouncementItem>, PinnedKey>((ref, k) => ref
        .watch(announcementsRepositoryProvider)
        .pinned(k.groupId, teamId: k.teamId));

/// Groups whose announcements I've muted.
final mutedAnnouncementGroupsProvider = FutureProvider.autoDispose<Set<String>>(
    (ref) => ref.watch(announcementsRepositoryProvider).mutedGroups());

/// Push / email per category.
final notificationPreferencesProvider =
    FutureProvider.autoDispose<List<NotificationPreference>>(
        (ref) => ref.watch(announcementsRepositoryProvider).preferences());
