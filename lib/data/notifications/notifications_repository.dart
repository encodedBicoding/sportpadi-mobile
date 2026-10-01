import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/notifications/notification_models.dart';

class NotificationsRepository {
  NotificationsRepository(this._dio);
  final Dio _dio;

  Future<NotificationFeed> feed({int limit = 20}) async {
    try {
      final res = await _dio
          .get('/api/mobile/notifications', queryParameters: {'limit': limit});
      return NotificationFeed.fromJson(
          Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load notifications.');
    }
  }

  Future<int> unreadCount() async {
    try {
      final res = await _dio.get('/api/mobile/notifications/unread-count');
      final d = res.data;
      if (d is int) return d;
      if (d is num) return d.toInt();
      if (d is Map && d['count'] is num) return (d['count'] as num).toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markRead(List<String> ids) async {
    try {
      await _dio.post('/api/mobile/notifications',
          data: {'action': 'read', 'ids': ids});
    } catch (_) {
      // Best-effort — the tap should still navigate.
    }
  }

  Future<void> markAllRead() async {
    try {
      await _dio.post('/api/mobile/notifications/read-all');
    } catch (e) {
      throw apiError(e);
    }
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
    (ref) => NotificationsRepository(ref.watch(dioProvider)));

final notificationsFeedProvider = FutureProvider.autoDispose<NotificationFeed>(
    (ref) => ref.watch(notificationsRepositoryProvider).feed());

/// Unread badge count. Polled while something watches it (the app bar bell),
/// matching the web's 45s refetch; also invalidated on foreground push, app
/// resume, tab switches and when the feed is read.
final unreadCountProvider = FutureProvider.autoDispose<int>((ref) {
  final timer = Timer(const Duration(seconds: 45), () => ref.invalidateSelf());
  ref.onDispose(timer.cancel);
  return ref.watch(notificationsRepositoryProvider).unreadCount();
});
