import 'package:sportpadi_mobile/shared/format/parse.dart';

/// A ticket as the organizer manages it (all fields, incl. hidden ones).
class ManagedTicket {
  const ManagedTicket({
    required this.id,
    required this.groupId,
    required this.kind,
    required this.title,
    required this.priceMinor,
    required this.currency,
    required this.currencyExponent,
    required this.blocksCheckin,
    required this.requiresValidation,
    required this.recurrence,
    required this.isActive,
    required this.soldCount,
    this.eventId,
    this.eventTitle,
    this.eventDate,
    this.description,
    this.flierUrl,
    this.salesStartAt,
    this.salesEndAt,
    this.capacity,
    this.createdAt,
    this.validFrom,
    this.validUntil,
    this.cycleNo = 1,
  });
  final String id;
  final String groupId;
  final String kind; // general | event | tournament
  final String title;
  final int priceMinor;
  final String currency;
  final int currencyExponent;
  final bool blocksCheckin;
  final bool requiresValidation;
  final String recurrence; // one_time | weekly | monthly | quarterly | yearly
  final bool isActive;
  final int soldCount;
  final String? eventId;
  final String? eventTitle;
  final DateTime? eventDate;
  final String? description;
  final String? flierUrl;
  final DateTime? salesStartAt;
  final DateTime? salesEndAt;
  final int? capacity;
  final DateTime? createdAt;

  /// VALIDITY of a recurring ticket's cycle — how long a purchase admits you
  /// (start of the first day → end of the last day). Set by SportPadi at
  /// creation and never edited; null for one-time tickets. Not the sales
  /// window ([salesStartAt]/[salesEndAt]), which is only when it can be bought.
  final DateTime? validFrom;
  final DateTime? validUntil;

  /// Which cycle of the series this row is (1 = the first).
  final int cycleNo;

  bool get isRecurring => recurrence != 'one_time';

  /// The next cycle, already on sale before it starts.
  bool get isNextCycle {
    final from = validFrom;
    return isRecurring && from != null && from.isAfter(DateTime.now());
  }

  /// An old cycle: once its last day is over the server switches it off and a
  /// fresh ticket row runs the next cycle.
  bool get isEndedCycle {
    final until = validUntil;
    return !isActive &&
        isRecurring &&
        until != null &&
        until.isBefore(DateTime.now());
  }

  bool get soldOut => capacity != null && soldCount >= capacity!;
  String get soldLabel => capacity == null
      ? '$soldCount sold'
      : soldOut
          ? '$capacity/$capacity sold out'
          : '$soldCount/$capacity sold';

  factory ManagedTicket.fromJson(Map<String, dynamic> j) {
    final ev =
        j['event'] is Map ? Map<String, dynamic>.from(j['event'] as Map) : null;
    final count = j['_count'] is Map
        ? Map<String, dynamic>.from(j['_count'] as Map)
        : null;
    return ManagedTicket(
      id: (j['id'] ?? '') as String,
      groupId: (j['groupId'] ?? '') as String,
      kind: parseStr(j['kind']) ?? 'general',
      title: (j['title'] ?? 'Ticket') as String,
      priceMinor: parseInt(j['price']) ?? 0,
      currency: parseStr(j['currency']) ?? '',
      currencyExponent: parseInt(j['currencyExponent']) ?? 2,
      blocksCheckin: j['blocksCheckin'] == true,
      requiresValidation: j['requiresValidation'] == true,
      recurrence: parseStr(j['recurrence']) ?? 'one_time',
      isActive: j['isActive'] != false,
      soldCount: parseInt(count?['payments']) ?? 0,
      eventId: parseStr(j['eventId']),
      eventTitle: ev != null ? parseStr(ev['title']) : null,
      eventDate: ev != null ? parseDate(ev['eventDate']) : null,
      description: parseStr(j['description']),
      flierUrl: parseStr(j['flierUrl']),
      salesStartAt: parseDate(j['salesStartAt']),
      salesEndAt: parseDate(j['salesEndAt']),
      capacity: parseInt(j['capacity']),
      createdAt: parseDate(j['createdAt']),
      validFrom: parseDate(j['validFrom']),
      validUntil: parseDate(j['validUntil']),
      cycleNo: parseInt(j['cycleNo']) ?? 1,
    );
  }
}

/// One purchase of a ticket, for the organizer's sales list.
class TicketSale {
  const TicketSale({
    required this.id,
    required this.buyerName,
    required this.amount,
    required this.currency,
    required this.status,
    required this.code,
    this.buyerUsername,
    this.buyerAvatarUrl,
    this.periodKey,
    this.paidAt,
    this.redeemedAt,
    this.reconciled = false,
    this.groupShare,
    this.feeBearer = 'buyer',
    this.platformFee,
    this.provider,
    this.canRefund = false,
    this.refundBlocked,
    this.expiredAt,
    this.refundFailReason,
    this.refundedMinor = 0,
    int? refundableMinor,
  }) : _refundableMinor = refundableMinor;
  final String id;
  final String buyerName;
  final String? buyerUsername;
  final String? buyerAvatarUrl;
  final int amount;
  final String currency;
  final String status; // pending | paid | failed | refunded | cancelled
  final String code;
  final String? periodKey;
  final DateTime? paidAt;
  final DateTime? redeemedAt;

  /// An admin has put this payment right against the provider at least once.
  final bool reconciled;

  /// What the group receives — the price, or the price less the fees when the
  /// group paid them. Null from older servers (use [amount]).
  final int? groupShare;

  /// Who covered the fees on this sale: 'buyer' | 'group'.
  final String feeBearer;

  /// SportPadi's processing fee on this sale (non-refundable).
  final int? platformFee;

  /// Who took the money: stripe | paystack | flutterwave — null when the
  /// ticket was issued outside SportPadi.
  final String? provider;

  /// The admin can refund this purchase from here (paid, provider-paid, not
  /// used up). [refundBlocked] says why not.
  final bool canRefund;
  final String? refundBlocked;

  /// When a recurring purchase was used up (its cycle ended).
  final DateTime? expiredAt;

  /// Why the last refund attempt failed, if it did (the sale is still paid).
  final String? refundFailReason;

  /// Partial refunds: how much of the price has been given back so far. A
  /// partly refunded sale is still 'paid' and its ticket still valid.
  final int refundedMinor;
  final int? _refundableMinor;

  /// What can still be refunded (the price less what's been refunded; the fee
  /// never is). Older servers don't send it — fall back to the whole price.
  int get refundableMinor =>
      _refundableMinor ?? (status == 'paid' ? amount - refundedMinor : 0);

  /// The provider's name for people: Stripe, Paystack, Flutterwave.
  String? get providerLabel => switch (provider) {
        'stripe' => 'Stripe',
        'paystack' => 'Paystack',
        'flutterwave' => 'Flutterwave',
        final String other => other[0].toUpperCase() + other.substring(1),
        null => null,
      };

  /// What this sale is worth to the group.
  int get received => groupShare ?? amount;

  factory TicketSale.fromJson(Map<String, dynamic> j) => TicketSale(
        id: (j['id'] ?? '') as String,
        buyerName: (j['buyerName'] ?? 'Unknown') as String,
        buyerUsername: parseStr(j['buyerUsername']),
        buyerAvatarUrl: parseStr(j['buyerAvatarUrl']),
        amount: parseInt(j['amount']) ?? 0,
        currency: parseStr(j['currency']) ?? '',
        status: parseStr(j['status']) ?? '',
        code: parseStr(j['code']) ?? '',
        periodKey: parseStr(j['periodKey']),
        paidAt: parseDate(j['paidAt']),
        redeemedAt: parseDate(j['redeemedAt']),
        reconciled: j['reconciled'] == true,
        groupShare: parseInt(j['groupShare']),
        feeBearer: parseStr(j['feeBearer']) ?? 'buyer',
        platformFee: parseInt(j['platformFee']),
        provider: parseStr(j['provider']),
        canRefund: j['canRefund'] == true,
        refundBlocked: parseStr(j['refundBlocked']),
        expiredAt: parseDate(j['expiredAt']),
        refundFailReason: parseStr(j['refundFailReason']),
        refundedMinor: parseInt(j['refundedMinor']) ?? 0,
        refundableMinor: parseInt(j['refundableMinor']),
      );
}

/// One payment checked against its payment provider (tickets.checkPayment):
/// what the provider says, in plain words, and the reconcile action when
/// SportPadi is out of step.
class PaymentCheck {
  const PaymentCheck({
    required this.paymentId,
    required this.code,
    required this.ourStatus,
    required this.verdict,
    required this.headline,
    this.details = const [],
    this.providerLabel,
    this.providerStatus,
    this.action,
    this.actionLabel,
    this.actionHint,
    this.coveredCodes = const [],
  });
  final String paymentId;
  final String code;
  final String ourStatus;

  /// in_sync | out_of_sync | needs_attention | no_provider | error
  final String verdict;
  final String headline;
  final List<String> details;
  final String? providerLabel;
  final String? providerStatus;

  /// mark_refunded | mark_paid | mark_failed — null when nothing to apply.
  final String? action;
  final String? actionLabel;
  final String? actionHint;
  final List<String> coveredCodes;

  factory PaymentCheck.fromJson(Map<String, dynamic> j) {
    final insp = j['inspection'] is Map
        ? Map<String, dynamic>.from(j['inspection'] as Map)
        : null;
    List<String> strs(dynamic v) => v is List
        ? [
            for (final x in v)
              if (x is String) x
          ]
        : const <String>[];
    return PaymentCheck(
      paymentId: parseStr(j['paymentId']) ?? '',
      code: parseStr(j['code']) ?? '',
      ourStatus: parseStr(j['ourStatus']) ?? '',
      verdict: parseStr(j['verdict']) ?? 'error',
      headline: parseStr(j['headline']) ?? '',
      details: strs(j['details']),
      providerLabel: parseStr(j['providerLabel']),
      providerStatus: insp == null ? null : parseStr(insp['providerStatus']),
      action: parseStr(j['action']),
      actionLabel: parseStr(j['actionLabel']),
      actionHint: parseStr(j['actionHint']),
      coveredCodes: strs(j['coveredCodes']),
    );
  }
}

class TicketSales {
  const TicketSales({required this.currencyExponent, required this.sales});
  final int currencyExponent;
  final List<TicketSale> sales;
  factory TicketSales.fromJson(Map<String, dynamic> j) => TicketSales(
        currencyExponent: parseInt(j['currencyExponent']) ?? 2,
        sales: j['payments'] is List
            ? [
                for (final p in j['payments'] as List)
                  TicketSale.fromJson(Map<String, dynamic>.from(p as Map)),
              ]
            : const [],
      );
}
