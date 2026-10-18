import 'package:sportpadi_mobile/shared/format/parse.dart';

/// The one way SportPadi's fee is said to groups, matching the web
/// (packages/lib feeWording.ts): always "X% + card processing", never the
/// combined number alone; always say where the rate comes from; facts only —
/// nothing here is a reason to buy (App Store 3.1.1).

String fmtBps(int bps) {
  final p = bps / 100;
  return '${p == p.roundToDouble() ? p.toInt() : p.toStringAsFixed(2)}%';
}

/// "6% + card processing" / "No SportPadi fee — card processing only".
String feePhrase(int netBps) => netBps == 0
    ? 'No SportPadi fee — card processing only'
    : '${fmtBps(netBps)} + card processing';

/// "Pro plan rate" / "platform rate".
String feeSourcePhrase(String source, String? tierName) =>
    source == 'tier' && tierName != null ? '$tierName plan rate' : 'platform rate';

String fmtEffectiveDay(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final u = d.toUtc();
  return '${m[u.month - 1]} ${u.day}, ${u.year}';
}

/// A scheduled change to a rate: "becomes 7% + card processing on Nov 1, 2026".
class PendingFee {
  const PendingFee({required this.newBps, required this.effectiveAt});
  final int newBps;
  final DateTime effectiveAt;

  static PendingFee? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = parseDate(j['effectiveAt']);
    final bps = parseInt(j['newBps']);
    if (at == null || bps == null) return null;
    return PendingFee(newBps: bps, effectiveAt: at);
  }

  String get phrase => 'becomes ${feePhrase(newBps)} on ${fmtEffectiveDay(effectiveAt)}';
}

/// A plan's fee, as `/api/mobile/iap` describes it per tier.
class PlanFee {
  const PlanFee({required this.bps, required this.source, required this.hasWallet, this.pending});
  final int bps;
  final String source; // tier | default
  final bool hasWallet;
  final PendingFee? pending;

  static PlanFee? fromJson(Object? j) {
    if (j is! Map) return null;
    final bps = parseInt(j['bps']);
    if (bps == null) return null;
    return PlanFee(
      bps: bps,
      source: parseStr(j['source']) ?? 'default',
      hasWallet: j['hasWallet'] == true,
      pending: PendingFee.fromJson(j['pending']),
    );
  }

  /// Label + value + note for a plan card.
  ({String label, String value, String? note}) get line {
    final notes = <String>[
      if (source == 'default') 'platform rate',
      if (pending != null) pending!.phrase,
    ];
    final note = notes.isEmpty ? null : notes.join(' · ');
    return hasWallet
        ? (label: 'Fee on payments you collect', value: feePhrase(bps), note: note)
        : (label: 'Collecting payments', value: 'By promo code only · ${feePhrase(bps)}', note: note);
  }
}

/// What a group pays SportPadi, in full (`wallet?view=fee-terms`).
class GroupFeeTerms {
  const GroupFeeTerms({
    required this.tierName,
    required this.netBps,
    required this.source,
    required this.bearer,
    required this.walletVia,
    required this.currency,
    required this.exponent,
    required this.processorProvider,
    required this.processorBps,
    required this.processorFixedMinor,
    required this.maxFeeBps,
    required this.examplePrice,
    required this.exampleBuyerPays,
    required this.exampleGroupReceives,
    required this.exampleFee,
    required this.exampleProcessor,
    required this.exampleNet,
    required this.pending,
  });

  final String? tierName;
  final int netBps;
  final String source;
  final String bearer; // buyer | group
  final String? walletVia; // tier | promo | null
  final String? currency;
  final int exponent;
  final String? processorProvider;
  final int processorBps;
  final int processorFixedMinor;
  final int maxFeeBps;
  final int examplePrice;
  final int exampleBuyerPays;
  final int exampleGroupReceives;
  final int exampleFee;
  final int exampleProcessor;
  final int exampleNet;
  final PendingFee? pending;

  factory GroupFeeTerms.fromJson(Map<String, dynamic> j) {
    final tier = j['tier'] is Map ? j['tier'] as Map : null;
    final proc = j['processor'] is Map ? j['processor'] as Map : null;
    final ex = j['example'] is Map ? j['example'] as Map : const {};
    return GroupFeeTerms(
      tierName: tier == null ? null : parseStr(tier['name']),
      netBps: parseInt(j['netBps']) ?? 0,
      source: parseStr(j['source']) ?? 'default',
      bearer: parseStr(j['bearer']) ?? 'buyer',
      walletVia: parseStr(j['walletVia']),
      currency: parseStr(j['currency']),
      exponent: parseInt(j['currencyExponent']) ?? 2,
      processorProvider: proc == null ? null : parseStr(proc['provider']),
      processorBps: proc == null ? 0 : parseInt(proc['bps']) ?? 0,
      processorFixedMinor: proc == null ? 0 : parseInt(proc['fixedMinor']) ?? 0,
      maxFeeBps: parseInt(j['maxFeeBps']) ?? 0,
      examplePrice: parseInt(ex['priceMinor']) ?? 0,
      exampleBuyerPays: parseInt(ex['buyerPaysMinor']) ?? 0,
      exampleGroupReceives: parseInt(ex['groupReceivesMinor']) ?? 0,
      exampleFee: parseInt(ex['feeMinor']) ?? 0,
      exampleProcessor: parseInt(ex['processorMinor']) ?? 0,
      exampleNet: parseInt(ex['netMinor']) ?? 0,
      pending: PendingFee.fromJson(j['pending']),
    );
  }
}

/// One payment on the monthly statement (`wallet?view=statement`).
class StatementLine {
  const StatementLine({
    required this.kind,
    required this.id,
    required this.at,
    required this.description,
    required this.reference,
    required this.payerName,
    required this.currency,
    required this.exponent,
    required this.priceMinor,
    required this.feeMinor,
    required this.netMinor,
    required this.processorMinor,
    required this.rateBps,
    required this.rateSource,
    required this.tierName,
    required this.bearer,
    required this.groupMinor,
    required this.refunded,
  });

  final String kind;
  final String id;
  final DateTime at;
  final String description;
  final String? reference;
  final String? payerName;
  final String currency;
  final int exponent;
  final int priceMinor;
  final int feeMinor;
  final int? netMinor;
  final int? processorMinor;
  final int? rateBps;
  final String? rateSource;
  final String? tierName;
  final String bearer;
  final int groupMinor;
  final bool refunded;

  static StatementLine? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = parseDate(j['at']);
    if (at == null) return null;
    return StatementLine(
      kind: parseStr(j['kind']) ?? 'ticket',
      id: parseStr(j['id']) ?? '',
      at: at,
      description: parseStr(j['description']) ?? 'Payment',
      reference: parseStr(j['reference']),
      payerName: parseStr(j['payerName']),
      currency: parseStr(j['currency']) ?? 'USD',
      exponent: parseInt(j['exponent']) ?? 2,
      priceMinor: parseInt(j['priceMinor']) ?? 0,
      feeMinor: parseInt(j['feeMinor']) ?? 0,
      netMinor: parseInt(j['netMinor']),
      processorMinor: parseInt(j['processorMinor']),
      rateBps: parseInt(j['rateBps']),
      rateSource: parseStr(j['rateSource']),
      tierName: parseStr(j['tierName']),
      bearer: parseStr(j['bearer']) ?? 'buyer',
      groupMinor: parseInt(j['groupMinor']) ?? 0,
      refunded: j['refunded'] == true,
    );
  }
}

class GroupStatement {
  const GroupStatement({
    required this.month,
    required this.currency,
    required this.exponent,
    required this.count,
    required this.grossMinor,
    required this.feeMinor,
    required this.netMinor,
    required this.processorMinor,
    required this.groupMinor,
    required this.unrecorded,
    required this.lines,
    required this.months,
    required this.rateChanges,
  });

  final String month;
  final String? currency;
  final int exponent;
  final int count;
  final int grossMinor;
  final int feeMinor;
  final int netMinor;
  final int processorMinor;
  final int groupMinor;
  final int unrecorded;
  final List<StatementLine> lines;
  final List<String> months;
  final List<({DateTime at, int? fromBps, int? toBps})> rateChanges;

  factory GroupStatement.fromJson(Map<String, dynamic> j) {
    return GroupStatement(
      month: parseStr(j['month']) ?? '',
      currency: parseStr(j['currency']),
      exponent: parseInt(j['exponent']) ?? 2,
      count: parseInt(j['count']) ?? 0,
      grossMinor: parseInt(j['grossMinor']) ?? 0,
      feeMinor: parseInt(j['feeMinor']) ?? 0,
      netMinor: parseInt(j['netMinor']) ?? 0,
      processorMinor: parseInt(j['processorMinor']) ?? 0,
      groupMinor: parseInt(j['groupMinor']) ?? 0,
      unrecorded: parseInt(j['unrecorded']) ?? 0,
      lines: [
        for (final l in (j['lines'] is List ? j['lines'] as List : const []))
          if (StatementLine.fromJson(l) != null) StatementLine.fromJson(l)!,
      ],
      months: [
        for (final m in (j['months'] is List ? j['months'] as List : const []))
          if (parseStr(m) != null) parseStr(m)!,
      ],
      rateChanges: [
        for (final c in (j['rateChanges'] is List ? j['rateChanges'] as List : const []))
          if (c is Map && parseDate(c['at']) != null)
            (at: parseDate(c['at'])!, fromBps: parseInt(c['fromBps']), toBps: parseInt(c['toBps'])),
      ],
    );
  }
}

/// "October 2026" for a "YYYY-MM" key.
String statementMonthLabel(String key) {
  final parts = key.split('-');
  if (parts.length != 2) return key;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (y == null || m == null || m < 1 || m > 12) return key;
  const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${names[m - 1]} $y';
}
