import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/tickets/ticket_models.dart';

/// Ticket SETUP for group admins — list/create/edit/hide/delete tickets and
/// see who bought them. (Buying lives in PaymentsRepository.)
class TicketsRepository {
  TicketsRepository(this._dio);
  final Dio _dio;

  String _path(String groupId) => '/api/mobile/groups/$groupId/tickets';

  Future<List<ManagedTicket>> list(String groupId) async {
    try {
      final res = await _dio.get(_path(groupId), queryParameters: {'view': 'list'});
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final t in list) ManagedTicket.fromJson(Map<String, dynamic>.from(t as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load tickets.');
    }
  }

  Future<TicketSales> sales(String groupId, String ticketId) async {
    try {
      final res = await _dio.get(_path(groupId),
          queryParameters: {'view': 'payments', 'ticketId': ticketId});
      return TicketSales.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load sales.');
    }
  }

  /// `body` uses the API's field names (title, price in minor units, kind,
  /// eventId, description, blocksCheckin, requiresValidation, recurrence,
  /// salesStartAt/salesEndAt as ISO strings, capacity).
  Future<void> create(String groupId, Map<String, dynamic> body) async {
    try {
      await _dio.post(_path(groupId), data: {'action': 'create', ...body});
    } catch (e) {
      throw apiError(e, fallback: 'Could not create the ticket.');
    }
  }

  Future<void> update(String groupId, String id, Map<String, dynamic> body) async {
    try {
      await _dio.post(_path(groupId), data: {'action': 'update', 'id': id, ...body});
    } catch (e) {
      throw apiError(e, fallback: 'Could not save the ticket.');
    }
  }

  Future<void> setActive(String groupId, String id, bool isActive) async {
    try {
      await _dio.post(_path(groupId),
          data: {'action': 'setActive', 'id': id, 'isActive': isActive});
    } catch (e) {
      throw apiError(e, fallback: 'Could not update the ticket.');
    }
  }

  Future<void> remove(String groupId, String id) async {
    try {
      await _dio.post(_path(groupId), data: {'action': 'remove', 'id': id});
    } catch (e) {
      throw apiError(e, fallback: 'Could not delete the ticket.');
    }
  }
}

final ticketsRepositoryProvider =
    Provider<TicketsRepository>((ref) => TicketsRepository(ref.watch(dioProvider)));

final managedTicketsProvider = FutureProvider.autoDispose
    .family<List<ManagedTicket>, String>(
        (ref, groupId) => ref.watch(ticketsRepositoryProvider).list(groupId));

final ticketSalesProvider = FutureProvider.autoDispose
    .family<TicketSales, ({String groupId, String ticketId})>((ref, a) =>
        ref.watch(ticketsRepositoryProvider).sales(a.groupId, a.ticketId));
