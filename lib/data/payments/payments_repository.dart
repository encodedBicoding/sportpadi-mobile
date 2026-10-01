import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';

/// Tickets + fines over the REST bridge. Checkout is the provider's hosted
/// page (Stripe / Paystack / Flutterwave) opened in the browser; afterwards
/// the app verifies by reference.
class PaymentsRepository {
  PaymentsRepository(this._dio);
  final Dio _dio;

  /// What I — or, with [forPlayerId], one of my wards — still owe a group.
  Future<OutstandingSummary> outstanding(String groupId,
      {String? forPlayerId}) async {
    try {
      final res = await _dio.get('/api/mobile/payments', queryParameters: {
        'view': 'outstanding',
        'groupId': groupId,
        if (forPlayerId != null) 'forPlayerId': forPlayerId,
      });
      return OutstandingSummary.fromJson(
          Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load tickets.');
    }
  }

  /// The tickets tied to an event (+ the group's check-in passes that gate
  /// it), with prices and the viewer's paid state.
  Future<EventTickets> forEvent(String eventId) async {
    try {
      final res = await _dio.get('/api/mobile/payments',
          queryParameters: {'view': 'event', 'eventId': eventId});
      return EventTickets.fromJson(
          Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load tickets.');
    }
  }

  Future<List<MyTicket>> myTickets() async {
    try {
      final res = await _dio
          .get('/api/mobile/payments', queryParameters: {'view': 'tickets'});
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final t in list)
          MyTicket.fromJson(Map<String, dynamic>.from(t as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load your tickets.');
    }
  }

  /// One receipt by its code — mine, one I paid for, or one of my wards'
  /// (`canPresent` says whether I may show its QR).
  Future<MyTicket> receipt(String code) async {
    try {
      final res = await _dio.get('/api/mobile/payments',
          queryParameters: {'view': 'receipt', 'code': code});
      if (res.data is! Map) {
        throw ApiException('Receipt not found.', statusCode: 404);
      }
      return MyTicket.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load this receipt.');
    }
  }

  Future<List<Fine>> myFines() async {
    try {
      final res = await _dio
          .get('/api/mobile/payments', queryParameters: {'view': 'fines'});
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final f in list)
          Fine.fromJson(Map<String, dynamic>.from(f as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not load your fines.');
    }
  }

  /// Start a hosted checkout for one ticket → (url, code to verify with).
  /// `recipientIds` says who each ticket is FOR (multi-person / gift buys) —
  /// omitted means "just me".
  Future<({String url, String code})> startCheckout(String ticketId,
      {List<String>? recipientIds}) async {
    try {
      final res = await _dio.post('/api/mobile/payments', data: {
        'action': 'checkout',
        'ticketId': ticketId,
        if (recipientIds != null) 'recipientIds': recipientIds,
      });
      final d = Map<String, dynamic>.from(res.data as Map);
      return (url: d['url'] as String, code: (d['code'] ?? '') as String);
    } catch (e) {
      throw apiError(e, fallback: 'Could not start checkout.');
    }
  }

  /// Find people to attach tickets to — username/display-name substring, or
  /// an exact email address.
  Future<List<RecipientUser>> searchRecipients(String q) async {
    try {
      final res = await _dio
          .get('/api/mobile/users/search', queryParameters: {'q': q});
      final list = res.data is List ? res.data as List : const [];
      return [
        for (final u in list)
          RecipientUser.fromJson(Map<String, dynamic>.from(u as Map)),
      ];
    } catch (e) {
      throw apiError(e, fallback: 'Could not search.');
    }
  }

  /// Pay several of one group's tickets at once → (url, batchRef). With
  /// [forPlayerId] I pay for one of my wards: the ward holds the tickets.
  Future<({String url, String code})> startBulkCheckout(List<String> ticketIds,
      {String? forPlayerId}) async {
    try {
      final res = await _dio.post('/api/mobile/payments', data: {
        'action': 'checkout-bulk',
        'ticketIds': ticketIds,
        if (forPlayerId != null) 'forPlayerId': forPlayerId,
      });
      final d = Map<String, dynamic>.from(res.data as Map);
      return (url: d['url'] as String, code: (d['batchRef'] ?? '') as String);
    } catch (e) {
      throw apiError(e, fallback: 'Could not start checkout.');
    }
  }

  /// Verify a ticket payment by its code/batchRef → "paid" | "pending" | "failed".
  Future<String> verify(String code) async {
    try {
      final res = await _dio.post('/api/mobile/payments',
          data: {'action': 'verify', 'code': code});
      final d = res.data is Map ? res.data as Map : const {};
      return (d['status'] ?? 'pending') as String;
    } catch (e) {
      throw apiError(e, fallback: 'Could not verify the payment.');
    }
  }

  /// Start a hosted checkout to settle a fine → url. (Fines settle via the
  /// provider webhook; re-fetch [myFines] after paying.)
  Future<String> startFineCheckout(String fineId) async {
    try {
      final res = await _dio.post('/api/mobile/payments',
          data: {'action': 'fine-checkout', 'fineId': fineId});
      final d = Map<String, dynamic>.from(res.data as Map);
      return d['url'] as String;
    } catch (e) {
      throw apiError(e, fallback: 'Could not start checkout.');
    }
  }
}

final paymentsRepositoryProvider = Provider<PaymentsRepository>(
    (ref) => PaymentsRepository(ref.watch(dioProvider)));

/// Whose outstanding tickets in which group (`forPlayerId` null = mine).
typedef OutstandingKey = ({String groupId, String? forPlayerId});

final outstandingTicketsProvider = FutureProvider.autoDispose
    .family<OutstandingSummary, OutstandingKey>((ref, k) => ref
        .watch(paymentsRepositoryProvider)
        .outstanding(k.groupId, forPlayerId: k.forPlayerId));

final eventTicketsProvider = FutureProvider.autoDispose
    .family<EventTickets, String>((ref, eventId) =>
        ref.watch(paymentsRepositoryProvider).forEvent(eventId));

final myTicketsProvider = FutureProvider.autoDispose<List<MyTicket>>(
    (ref) => ref.watch(paymentsRepositoryProvider).myTickets());

final myFinesProvider = FutureProvider.autoDispose<List<Fine>>(
    (ref) => ref.watch(paymentsRepositoryProvider).myFines());
