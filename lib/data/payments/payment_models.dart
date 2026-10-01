import '../../shared/format/parse.dart';

/// Money formatting: minor units + exponent + ISO code → "NGN 1,500.00".
String formatMoney(int minor, String currency, int exponent) {
  final major = minor / (exponent == 0 ? 1 : _pow10(exponent));
  final s = major.toStringAsFixed(exponent);
  // Thousands separators.
  final parts = s.split('.');
  final buf = StringBuffer();
  final whole = parts[0];
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  final frac = parts.length > 1 ? '.${parts[1]}' : '';
  return '$currency $buf$frac';
}

int _pow10(int e) {
  var v = 1;
  for (var i = 0; i < e; i++) {
    v *= 10;
  }
  return v;
}

/// One of MY wards a ticket or fine belongs to (Wards 3): the guardian pays,
/// the ward holds. Null on rows that are the viewer's own.
class PaymentWardRef {
  const PaymentWardRef({required this.userId, required this.displayName});
  final String userId;
  final String displayName;

  String get firstName {
    final parts = displayName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? displayName : parts.first;
  }

  static PaymentWardRef? fromJson(dynamic v) {
    if (v is! Map) return null;
    final id = parseStr(v['userId']);
    if (id == null) return null;
    return PaymentWardRef(
      userId: id,
      displayName: parseStr(v['displayName']) ?? 'Your ward',
    );
  }
}

/// A ticket the viewer still owes a group.
class OutstandingTicket {
  const OutstandingTicket({
    required this.id,
    required this.title,
    required this.priceMinor,
    required this.feeMinor,
    this.mandatory = false,
    this.recurrence = 'once',
    this.eventTitle,
    this.validFrom,
    this.validUntil,
  });
  final String id;
  final String title;
  final int priceMinor;
  final int feeMinor;
  final bool mandatory;
  final String recurrence;
  final String? eventTitle;

  /// A recurring ticket's cycle (how long a purchase admits you). A NEXT
  /// cycle already on presale has [validFrom] in the future.
  final DateTime? validFrom;
  final DateTime? validUntil;

  factory OutstandingTicket.fromJson(Map<String, dynamic> j) {
    final ev = j['event'];
    return OutstandingTicket(
      id: (j['id'] ?? '') as String,
      title: (j['title'] ?? 'Ticket') as String,
      priceMinor: parseInt(j['price']) ?? 0,
      feeMinor: parseInt(j['fee']) ?? 0,
      mandatory: j['mandatory'] == true,
      recurrence: parseStr(j['recurrence']) ?? 'once',
      eventTitle: ev is Map ? parseStr(ev['title']) : null,
      validFrom: parseDate(j['validFrom']),
      validUntil: parseDate(j['validUntil']),
    );
  }
}

class OutstandingSummary {
  const OutstandingSummary({
    required this.currency,
    required this.currencyExponent,
    required this.outstanding,
    required this.mandatoryTotalMinor,
  });
  final String currency;
  final int currencyExponent;
  final List<OutstandingTicket> outstanding;
  final int mandatoryTotalMinor;

  bool get isEmpty => outstanding.isEmpty;
  List<OutstandingTicket> get mandatory =>
      outstanding.where((t) => t.mandatory).toList();

  factory OutstandingSummary.fromJson(Map<String, dynamic> j) =>
      OutstandingSummary(
        currency: parseStr(j['currency']) ?? '',
        currencyExponent: parseInt(j['currencyExponent']) ?? 2,
        mandatoryTotalMinor: parseInt(j['mandatoryTotalMinor']) ?? 0,
        outstanding: j['outstanding'] is List
            ? [
                for (final t in j['outstanding'] as List)
                  OutstandingTicket.fromJson(
                      Map<String, dynamic>.from(t as Map))
              ]
            : const [],
      );
}

/// A paid ticket — the receipt with its gate QR code.
class MyTicket {
  const MyTicket({
    required this.id,
    required this.code,
    required this.amountMinor,
    required this.currency,
    this.currencyExponent = 2,
    this.title = 'Ticket',
    this.groupName,
    this.eventTitle,
    this.eventDate,
    this.paidAt,
    this.giftedByName,
    this.groupId,
    this.groupRelation,
    this.feeMinor = 0,
    this.redeemedAt,
    this.forWard,
    this.canPresent = true,
    this.holderName,
    this.status = 'paid',
    this.expiredAt,
    this.validFrom,
    this.validUntil,
    this.refundedMinor = 0,
  });
  final String id;
  final String code;
  final int amountMinor;
  final String currency;
  final int currencyExponent;
  final String title;
  final String? groupName;
  final String? eventTitle;
  final DateTime? eventDate;
  final DateTime? paidAt;
  /// Set when someone else paid for this ticket (gift purchase).
  final String? giftedByName;
  final String? groupId;
  /// member | follower | none — powers the "follow this group" nudge.
  final String? groupRelation;
  /// Platform fee paid on top of [amountMinor].
  final int feeMinor;
  /// Given back so far. A partly refunded ticket is still 'paid' and valid.
  final int refundedMinor;
  final DateTime? redeemedAt;

  /// Held by one of my wards — I show its QR at the gate for them.
  final PaymentWardRef? forWard;

  /// This viewer may show the gate QR (the holder, or the holder's guardian).
  /// Always true for "My purchases" rows; a receipt opened by a gift buyer is
  /// false.
  final bool canPresent;

  /// Who holds the ticket (receipts only).
  final String? holderName;

  /// paid | pending | failed… (receipts; list rows are always paid).
  final String status;

  /// Set when a recurring ticket's cycle ended: the purchase is used up — it
  /// no longer admits anyone and can't be refunded.
  final DateTime? expiredAt;

  /// The cycle this purchase covers (recurring tickets only).
  final DateTime? validFrom;
  final DateTime? validUntil;

  int get totalMinor => amountMinor + feeMinor;

  /// Its cycle ended before it was scanned.
  bool get usedUp => expiredAt != null && redeemedAt == null;

  /// Show the QR: presentable, paid, and not used up.
  bool get showsQr => canPresent && status == 'paid' && expiredAt == null;

  /// `GET /api/mobile/payments?view=tickets` rows, and `view=receipt` (same
  /// keys, plus `canPresent`, `holder`, `status` and a top-level exponent).
  factory MyTicket.fromJson(Map<String, dynamic> j) {
    final t = j['ticket'];
    final tm = t is Map ? t : const {};
    final grp = tm['group'];
    final ev = tm['event'];
    return MyTicket(
      id: parseStr(j['id']) ?? '',
      code: parseStr(j['code']) ?? '',
      amountMinor: parseInt(j['amount']) ?? 0,
      currency: parseStr(j['currency']) ?? parseStr(tm['currency']) ?? '',
      currencyExponent: parseInt(tm['currencyExponent']) ??
          parseInt(j['currencyExponent']) ??
          2,
      title: parseStr(tm['title']) ?? 'Ticket',
      groupName: grp is Map ? parseStr(grp['name']) : null,
      eventTitle: ev is Map ? parseStr(ev['title']) : null,
      eventDate: ev is Map ? parseDate(ev['eventDate']) : null,
      paidAt: parseDate(j['paidAt']),
      giftedByName: j['giftedBy'] is Map
          ? parseStr((j['giftedBy'] as Map)['displayName'])
          : null,
      groupId: grp is Map ? parseStr(grp['id']) : null,
      groupRelation: parseStr(j['groupRelation']),
      feeMinor: parseInt(j['platformFee']) ?? 0,
      redeemedAt: parseDate(j['redeemedAt']),
      forWard: PaymentWardRef.fromJson(j['forWard']),
      canPresent: j['canPresent'] is bool ? j['canPresent'] as bool : true,
      holderName: j['holder'] is Map
          ? parseStr((j['holder'] as Map)['displayName'])
          : null,
      status: parseStr(j['status']) ?? 'paid',
      expiredAt: parseDate(j['expiredAt']),
      // Top level on `view=tickets` rows, under `ticket` on receipts.
      validFrom: parseDate(j['validFrom']) ?? parseDate(tm['validFrom']),
      validUntil: parseDate(j['validUntil']) ?? parseDate(tm['validUntil']),
      refundedMinor: parseInt(j['refundedMinor']) ?? 0,
    );
  }
}

/// A fine issued to the viewer.
class Fine {
  const Fine({
    required this.id,
    required this.title,
    required this.amountMinor,
    required this.currency,
    this.currencyExponent = 2,
    required this.status, // active | pardoned | paid
    this.groupName,
    this.createdAt,
    this.forWard,
  });
  final String id;
  final String title;
  final int amountMinor;
  final String currency;
  final int currencyExponent;
  final String status;
  final String? groupName;
  final DateTime? createdAt;

  /// Issued to one of my wards — any of their guardians may pay it.
  final PaymentWardRef? forWard;

  bool get isActive => status == 'active';

  factory Fine.fromJson(Map<String, dynamic> j) {
    final grp = j['group'];
    return Fine(
      id: (j['id'] ?? '') as String,
      title: (j['title'] ?? 'Fine') as String,
      amountMinor: parseInt(j['amountMinor']) ?? 0,
      currency: parseStr(j['currency']) ?? '',
      currencyExponent: parseInt(j['currencyExponent']) ?? 2,
      status: parseStr(j['status']) ?? 'active',
      groupName: grp is Map ? parseStr(grp['name']) : null,
      createdAt: parseDate(j['createdAt']),
      forWard: PaymentWardRef.fromJson(j['forWard']),
    );
  }
}

/// One ticket as shown on an event page — price + fees, sales state, and
/// whether the viewer has already paid for the current period.
class EventTicket {
  const EventTicket({
    required this.id,
    required this.title,
    required this.priceMinor,
    required this.feeMinor,
    required this.currency,
    required this.currencyExponent,
    required this.required,
    required this.eventSpecific,
    required this.recurrence,
    required this.paid,
    required this.canBuy,
    required this.soldOut,
    required this.notOpenYet,
    required this.closed,
    this.description,
    this.flierUrl,
    this.capacity,
    this.sold = 0,
    this.remaining,
    this.salesStartAt,
    this.salesEndAt,
    this.paymentCode,
    this.validFrom,
    this.validUntil,
  });
  final String id;
  final String title;
  final String? description;
  final String? flierUrl;
  final int priceMinor;
  final int feeMinor;
  final String currency;
  final int currencyExponent;
  final bool required;
  final bool eventSpecific;
  final String recurrence;
  final bool paid;
  final bool canBuy;
  final bool soldOut;
  final bool notOpenYet;
  final bool closed;
  final int? capacity;
  final int sold;
  final int? remaining;
  final DateTime? salesStartAt;
  final DateTime? salesEndAt;
  final String? paymentCode;

  /// A recurring ticket's current cycle — how long a purchase admits you.
  final DateTime? validFrom;
  final DateTime? validUntil;

  int get totalMinor => priceMinor + feeMinor;

  /// "3/10 sold" · "10/10 sold out" · null when unlimited.
  String? get soldLabel {
    final cap = capacity;
    if (cap == null) return null;
    return soldOut ? '$cap/$cap sold out' : '$sold/$cap sold';
  }

  /// Down to the last ~10% of seats.
  bool get lowStock {
    final cap = capacity;
    if (cap == null || soldOut) return false;
    final left = remaining ?? (cap - sold);
    return left <= (cap * 0.1).ceil().clamp(1, cap);
  }

  factory EventTicket.fromJson(Map<String, dynamic> j) => EventTicket(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? 'Ticket') as String,
        description: parseStr(j['description']),
        flierUrl: parseStr(j['flierUrl']),
        priceMinor: parseInt(j['price']) ?? 0,
        feeMinor: parseInt(j['fee']) ?? 0,
        currency: parseStr(j['currency']) ?? '',
        currencyExponent: parseInt(j['currencyExponent']) ?? 2,
        required: j['required'] == true,
        eventSpecific: j['eventSpecific'] == true,
        recurrence: parseStr(j['recurrence']) ?? 'one_time',
        paid: j['paid'] == true,
        canBuy: j['canBuy'] == true,
        soldOut: j['soldOut'] == true,
        notOpenYet: j['notOpenYet'] == true,
        closed: j['closed'] == true,
        capacity: parseInt(j['capacity']),
        sold: parseInt(j['sold']) ?? 0,
        remaining: parseInt(j['remaining']),
        salesStartAt: parseDate(j['salesStartAt']),
        salesEndAt: parseDate(j['salesEndAt']),
        paymentCode: parseStr(j['paymentCode']),
        validFrom: parseDate(j['validFrom']),
        validUntil: parseDate(j['validUntil']),
      );
}

/// The event page's ticket block.
class EventTickets {
  const EventTickets({
    required this.ticketed,
    required this.currency,
    required this.currencyExponent,
    required this.tickets,
    required this.unpaidRequiredIds,
    required this.unpaidRequiredTotalMinor,
    this.groupId,
    this.groupName,
    this.viewerRelation,
  });
  final bool ticketed;
  final String currency;
  final int currencyExponent;
  final List<EventTicket> tickets;
  final List<String> unpaidRequiredIds;
  final int unpaidRequiredTotalMinor;
  final String? groupId;
  final String? groupName;
  /// member | follower | none (null = signed out).
  final String? viewerRelation;

  bool get anyRequired => tickets.any((t) => t.required);
  bool get allRequiredPaid => anyRequired && unpaidRequiredIds.isEmpty;

  factory EventTickets.fromJson(Map<String, dynamic> j) {
    final list = j['tickets'] is List ? j['tickets'] as List : const [];
    final ids = j['unpaidRequiredIds'] is List
        ? (j['unpaidRequiredIds'] as List).map((e) => '$e').toList()
        : <String>[];
    final grp = j['group'] is Map ? Map<String, dynamic>.from(j['group'] as Map) : null;
    return EventTickets(
      ticketed: j['ticketed'] == true,
      groupId: grp != null ? parseStr(grp['id']) : null,
      groupName: grp != null ? parseStr(grp['name']) : null,
      viewerRelation: parseStr(j['viewerRelation']),
      currency: parseStr(j['currency']) ?? '',
      currencyExponent: parseInt(j['currencyExponent']) ?? 2,
      tickets: [
        for (final t in list)
          EventTicket.fromJson(Map<String, dynamic>.from(t as Map)),
      ],
      unpaidRequiredIds: ids,
      unpaidRequiredTotalMinor: parseInt(j['unpaidRequiredTotal']) ?? 0,
    );
  }
}

/// Someone a ticket can be bought FOR (found by username or exact email).
class RecipientUser {
  const RecipientUser({
    required this.userId,
    required this.displayName,
    required this.username,
    this.avatarUrl,
  });
  final String userId;
  final String displayName;
  final String username;
  final String? avatarUrl;

  factory RecipientUser.fromJson(Map<String, dynamic> j) => RecipientUser(
        userId: parseStr(j['userId']) ?? '',
        displayName: parseStr(j['displayName']) ?? 'Player',
        username: parseStr(j['username']) ?? '',
        avatarUrl: parseStr(j['avatarUrl']),
      );
}
