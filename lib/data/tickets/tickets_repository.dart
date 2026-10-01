import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/tickets/ticket_models.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

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

  /// Check one payment with its payment provider (group admins).
  Future<PaymentCheck> checkPayment(String paymentId) async {
    try {
      final res = await _dio.get('/api/mobile/ticket-payments',
          queryParameters: {'paymentId': paymentId});
      return PaymentCheck.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not check this payment.');
    }
  }

  /// Apply what [checkPayment] found. The server re-checks first and only
  /// applies [action] if it's still the right one.
  Future<({String? applied, List<String> warnings, PaymentCheck? check})> reconcilePayment(
      String paymentId, String action) async {
    try {
      final res = await _dio.post('/api/mobile/ticket-payments',
          data: {'paymentId': paymentId, 'action': action});
      final m = Map<String, dynamic>.from(res.data as Map);
      return (
        applied: m['applied'] as String?,
        warnings: m['warnings'] is List
            ? [for (final w in m['warnings'] as List) if (w is String) w]
            : const <String>[],
        check: m['check'] is Map
            ? PaymentCheck.fromJson(Map<String, dynamic>.from(m['check'] as Map))
            : null,
      );
    } catch (e) {
      throw apiError(e, fallback: 'Could not reconcile this payment.');
    }
  }

  /// Refund ONE purchase through the provider it was paid with (group
  /// admins): the ticket price goes back to the buyer; SportPadi's fee isn't
  /// refunded; on a pay-all charge only this ticket is. Returns the amount
  /// refunded, in minor units. 409 when a refund is already in progress.
  /// [amountMinor] refunds only part of the price (the ticket stays valid);
  /// omit it to refund everything still refundable.
  Future<int> refundPayment(String groupId, String paymentId,
      {String? reason, int? amountMinor}) async {
    try {
      final r = reason?.trim();
      final res = await _dio.post(_path(groupId), data: {
        'action': 'refund',
        'paymentId': paymentId,
        if (r != null && r.isNotEmpty) 'reason': r,
        if (amountMinor != null && amountMinor > 0) 'amountMinor': amountMinor,
      });
      final m = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : const <String, dynamic>{};
      return parseInt(m['refundedMinor']) ?? 0;
    } catch (e) {
      throw apiError(e, fallback: 'Could not refund this payment.');
    }
  }

  /// `body` uses the API's field names (title, price in minor units, kind,
  /// eventId, description, blocksCheckin, requiresValidation, recurrence,
  /// salesStartAt/salesEndAt as ISO strings, capacity; recurring tickets
  /// also validFromDate "YYYY-MM-DD" + timezone, from which SportPadi sets the
  /// validity). Recurrence can't change on [update] — don't send it there.
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

  /// Organizer scans a holder's ticket QR at the gate. Returns
  /// {ok, reason?, ticketTitle, redeemedAt?, expiredAt?}; reason is
  /// unpaid | already | expired (a recurring ticket whose cycle ended). The
  /// server checks group admin.
  Future<Map<String, dynamic>> redeem(String code) async {
    try {
      final res = await _dio
          .post('/api/mobile/tickets/redeem', data: {'code': code});
      return res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
    } catch (e) {
      throw apiError(e, fallback: 'Could not verify that ticket.');
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
