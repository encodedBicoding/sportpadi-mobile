import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/i18n/l10n.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/share/share_models.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';

/// Sharing REST bridge (`/api/mobile/share`, contract in the workspace's
/// docs/wiki/sharing.md):
///   GET  ?view=preview&url=&viewer=   → SharePreview (works signed out)
///   GET  ?view=recipients&q=&limit=   → { items: ShareRecipient[] }
///   POST { action: preview-many, urls, viewer } → { items } in order
///   POST { action: send, url, to, note } → { url, sent, results }
/// `viewer` is who the app thinks is signed in: when the server's session is
/// someone else the answer is unavailable, never another person's view.
class ShareRepository {
  ShareRepository(this._dio);
  final Dio _dio;

  static const _path = '/api/mobile/share';

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  static List<Map<String, dynamic>> _maps(dynamic v) => [
        if (v is List)
          for (final x in v)
            if (x is Map) Map<String, dynamic>.from(x),
      ];

  Future<SharePreview> preview(String url, {required String? viewer}) async {
    try {
      final res = await _dio.get(_path, queryParameters: {
        'view': 'preview',
        'url': url,
        'viewer': viewer ?? '',
      });
      return SharePreview.fromJson(_map(res.data));
    } catch (e) {
      throw apiError(e);
    }
  }

  /// Up to 20 links in one request, answered in the same order.
  Future<List<SharePreview>> previewMany(List<String> urls,
      {required String? viewer}) async {
    try {
      final res = await _dio.post(_path, data: {
        'action': 'preview-many',
        'urls': urls,
        'viewer': viewer,
      });
      return [
        for (final m in _maps(_map(res.data)['items'])) SharePreview.fromJson(m)
      ];
    } catch (e) {
      throw apiError(e);
    }
  }

  /// My open threads first, then people I could start a profile DM with.
  Future<List<ShareRecipient>> recipients({String? q, int limit = 20}) async {
    try {
      final res = await _dio.get(_path, queryParameters: {
        'view': 'recipients',
        if (q != null && q.isNotEmpty) 'q': q,
        'limit': limit,
      });
      return [
        for (final m in _maps(_map(res.data)['items']))
          ShareRecipient.fromJson(m)
      ];
    } catch (e) {
      throw apiError(e, fallback: l10n.share_couldntLoadPeople);
    }
  }

  /// Send [url] to up to 10 recipients; one result per recipient, in order.
  Future<ShareSendOutcome> send({
    required String url,
    required List<ShareRecipient> to,
    String? note,
  }) async {
    try {
      final res = await _dio.post(_path, data: {
        'action': 'send',
        'url': url,
        'to': [for (final r in to) r.to],
        'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
      });
      final d = _map(res.data);
      final results = [
        for (final m in _maps(d['results'])) ShareSendResult.fromJson(m)
      ];
      return ShareSendOutcome(
        url: (d['url'] as String?) ?? url,
        sent: (d['sent'] as num?)?.toInt() ??
            results.where((r) => r.ok).length,
        results: results,
      );
    } catch (e) {
      throw apiError(e, fallback: l10n.share_couldntSend);
    }
  }
}

final shareRepositoryProvider =
    Provider<ShareRepository>((ref) => ShareRepository(ref.watch(dioProvider)));

/// Cards for links, batched and cached: every card a screen builds within a
/// few milliseconds goes out as ONE preview-many request (20 a request), and
/// an answer is kept per (viewer, link) — 5 minutes for a card, 30 seconds
/// for "unavailable" (which is also what a viewer the server doesn't
/// recognise yet is told, so it must not stick) — a rebuild, a new message or
/// scrolling back asks nothing again. [sharePreviewCacheProvider] is rebuilt
/// whenever the signed-in user changes, so nothing one person saw is kept
/// for the next. A request that FAILS completes its cards with an error —
/// never "unavailable" (fix round, review L1) — and is not kept.
class SharePreviewCache {
  SharePreviewCache(this._repo);
  final ShareRepository _repo;

  static const _ttl = Duration(minutes: 5);
  static const _ttlUnavailable = Duration(seconds: 30);
  static const _window = Duration(milliseconds: 30);

  final Map<String, ({SharePreview value, DateTime at})> _done = {};
  final Map<String, Completer<SharePreview>> _waiting = {};
  final Map<String, ({String? viewer, String url})> _queue = {};
  Timer? _flush;

  Future<SharePreview> get(String? viewer, String url) {
    final key = '${viewer ?? ''}|$url';
    final hit = _done[key];
    if (hit != null &&
        DateTime.now().difference(hit.at) <
            (hit.value.available ? _ttl : _ttlUnavailable)) {
      return Future.value(hit.value);
    }
    if (hit != null) _done.remove(key);
    final waiting = _waiting[key];
    if (waiting != null) return waiting.future;
    final c = Completer<SharePreview>();
    _waiting[key] = c;
    _queue[key] = (viewer: viewer, url: url);
    _flush ??= Timer(_window, _send);
    return c.future;
  }

  Future<void> _send() async {
    _flush = null;
    final batch = Map.of(_queue);
    _queue.clear();
    final byViewer = <String, List<String>>{};
    for (final e in batch.entries) {
      byViewer.putIfAbsent(e.value.viewer ?? '', () => []).add(e.key);
    }
    for (final group in byViewer.entries) {
      final keys = group.value;
      for (var i = 0; i < keys.length; i += 20) {
        final chunk = keys.sublist(i, math.min(i + 20, keys.length));
        List<SharePreview> items;
        Object? failure;
        try {
          items = await _repo.previewMany(
              [for (final k in chunk) batch[k]!.url],
              viewer: group.key.isEmpty ? null : group.key);
        } catch (e) {
          items = const [];
          failure = e;
        }
        for (var j = 0; j < chunk.length; j++) {
          final k = chunk[j];
          final c = _waiting.remove(k);
          if (failure != null || j >= items.length) {
            // Not an answer: the card says it couldn't load, and asks again.
            if (c != null && !c.isCompleted) {
              c.completeError(failure ?? StateError('no answer'));
            }
            continue;
          }
          _done[k] = (value: items[j], at: DateTime.now());
          if (c != null && !c.isCompleted) c.complete(items[j]);
        }
      }
    }
  }

  /// Another person now (or nobody): whatever was still on its way is
  /// answered with an error, so no card waits for good — the new cache asks again.
  void dispose() {
    _flush?.cancel();
    for (final c in _waiting.values) {
      if (!c.isCompleted) c.completeError(StateError('session changed'));
    }
    _waiting.clear();
    _queue.clear();
  }
}

final sharePreviewCacheProvider = Provider<SharePreviewCache>((ref) {
  // A new person signed in (or out): a new, empty cache.
  ref.watch(authControllerProvider.select((s) => s.valueOrNull?.user?.id));
  final c = SharePreviewCache(ref.watch(shareRepositoryProvider));
  ref.onDispose(c.dispose);
  return c;
});

typedef SharePreviewKey = ({String? viewer, String url});

/// One link's card for one viewer (through [SharePreviewCache]).
final sharePreviewProvider = FutureProvider.autoDispose
    .family<SharePreview, SharePreviewKey>((ref, k) =>
        ref.watch(sharePreviewCacheProvider).get(k.viewer, k.url));
