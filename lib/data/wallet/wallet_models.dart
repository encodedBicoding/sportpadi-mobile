import 'package:sportpadi_mobile/shared/format/parse.dart';

/// A group's settlement (bank) account at a payment provider.
class PaymentAccount {
  const PaymentAccount({
    required this.id,
    required this.provider,
    required this.status,
    required this.payoutEnabled,
    required this.detailsSubmitted,
    required this.isDefault,
    required this.hasProviderAccount,
    this.country,
    this.currency,
    this.holderName,
    this.bankName,
    this.accountLast4,
  });
  final String id;
  final String provider; // stripe | paystack | flutterwave
  final String status;
  final bool payoutEnabled;
  final bool detailsSubmitted;
  final bool isDefault;
  final bool hasProviderAccount;
  final String? country;
  final String? currency;
  final String? holderName;
  final String? bankName;
  final String? accountLast4;

  bool get isStripe => provider == 'stripe';
  String get providerLabel => switch (provider) {
        'stripe' => 'Stripe',
        'paystack' => 'Paystack',
        'flutterwave' => 'Flutterwave',
        _ => provider,
      };

  factory PaymentAccount.fromJson(Map<String, dynamic> j) => PaymentAccount(
        id: (j['id'] ?? '') as String,
        provider: parseStr(j['provider']) ?? '',
        status: parseStr(j['status']) ?? '',
        payoutEnabled: j['payoutEnabled'] == true,
        detailsSubmitted: j['detailsSubmitted'] == true,
        isDefault: j['isDefault'] == true,
        hasProviderAccount: j['hasProviderAccount'] == true,
        country: parseStr(j['country']),
        currency: parseStr(j['currency']),
        holderName: parseStr(j['holderName']),
        bankName: parseStr(j['bankName']),
        accountLast4: parseStr(j['accountLast4']),
      );
}

/// A single onboarding requirement the provider is waiting on ("Photo ID").
class OnboardingItem {
  const OnboardingItem({required this.key, required this.label});
  final String key;
  final String label;
  factory OnboardingItem.fromJson(Map<String, dynamic> j) => OnboardingItem(
        key: parseStr(j['key']) ?? '',
        label: parseStr(j['label']) ?? '',
      );
}

/// Where the organizer is in provider onboarding.
class OnboardingProgress {
  const OnboardingProgress({
    required this.step,
    required this.actionNeeded,
    required this.due,
    required this.pending,
    this.disabledReason,
    this.onboardingUrl,
    this.walletStatus,
  });
  final String step; // provide_details | verify_identity | under_review | ready | rejected
  final bool actionNeeded;
  final List<OnboardingItem> due;
  final List<OnboardingItem> pending;
  final String? disabledReason;
  final String? onboardingUrl;
  final String? walletStatus;

  factory OnboardingProgress.fromJson(Map<String, dynamic> j) {
    final prog = j['progress'] is Map
        ? Map<String, dynamic>.from(j['progress'] as Map)
        : <String, dynamic>{};
    List<OnboardingItem> items(dynamic v) => v is List
        ? [
            for (final x in v)
              OnboardingItem.fromJson(Map<String, dynamic>.from(x as Map)),
          ]
        : const [];
    return OnboardingProgress(
      step: parseStr(prog['step']) ?? 'provide_details',
      actionNeeded: prog['actionNeeded'] == true,
      due: items(prog['due']),
      pending: items(prog['pending']),
      disabledReason: parseStr(prog['disabledReason']),
      onboardingUrl: parseStr(j['onboardingUrl']),
      walletStatus: parseStr(j['walletStatus']),
    );
  }
}

/// Withdrawal rules + what's withdrawable right now.
class WithdrawalPolicy {
  const WithdrawalPolicy({
    required this.maturationDays,
    required this.heldMinor,
    this.pendingApprovalMinor = 0,
    required this.withdrawableMinor,
    required this.payoutDays,
    required this.payoutDayAllowedToday,
    required this.periodDays,
    required this.periodCapMinor,
    required this.periodUsedMinor,
    required this.withdrawalsEnabled,
    required this.availableBalance,
    required this.settledToBankMinor,
    this.nextPayoutDate,
    this.periodRemainingMinor,
    this.providerName,
    this.providerAvailableMinor,
    this.payableNowMinor,
    this.settlingAtProviderMinor = 0,
  });
  final int maturationDays;
  final int heldMinor;
  /// Locked by requests still awaiting approval (not yet debited).
  final int pendingApprovalMinor;
  final int withdrawableMinor;
  final List<int> payoutDays;
  final bool payoutDayAllowedToday;
  final DateTime? nextPayoutDate;
  final int periodDays;
  final int periodCapMinor;
  final int periodUsedMinor;
  final int? periodRemainingMinor;
  final bool withdrawalsEnabled;
  final int availableBalance;
  final int settledToBankMinor;

  /// Payment provider powering this wallet (`stripe`, `paystack`, `flutterwave`).
  final String? providerName;
  /// What the provider reports as settled and payable right now (null = unknown).
  final int? providerAvailableMinor;
  /// min(withdrawable on SportPadi, provider-available). Null when the server
  /// didn't send it (older API) — falls back to [withdrawableMinor].
  final int? payableNowMinor;
  /// Matured on SportPadi but still settling with the provider.
  final int settlingAtProviderMinor;

  bool get hasProviderFigure => providerAvailableMinor != null;

  String get providerLabel {
    switch (providerName) {
      case 'stripe':
        return 'Stripe';
      case 'paystack':
        return 'Paystack';
      case 'flutterwave':
        return 'Flutterwave';
      default:
        return 'your payment provider';
    }
  }

  /// Payable right now: matured on SportPadi, capped by what the provider has settled.
  int get payableNow => payableNowMinor ?? withdrawableMinor;

  /// Withdrawable after the per-period cap and the provider's settled balance.
  int get cappedWithdrawable {
    final r = periodRemainingMinor;
    final base = payableNow;
    return r != null && r < base ? r : base;
  }

  bool get dayBlocked => !payoutDayAllowedToday && payoutDays.isNotEmpty;

  factory WithdrawalPolicy.fromJson(Map<String, dynamic> j) => WithdrawalPolicy(
        maturationDays: parseInt(j['maturationDays']) ?? 0,
        heldMinor: parseInt(j['heldMinor']) ?? 0,
        pendingApprovalMinor: parseInt(j['pendingApprovalMinor']) ?? 0,
        withdrawableMinor: parseInt(j['withdrawableMinor']) ?? 0,
        payoutDays: j['payoutDays'] is List
            ? [for (final d in j['payoutDays'] as List) parseInt(d) ?? 0]
            : const [],
        payoutDayAllowedToday: j['payoutDayAllowedToday'] != false,
        nextPayoutDate: parseDate(j['nextPayoutDate']),
        periodDays: parseInt(j['periodDays']) ?? 0,
        periodCapMinor: parseInt(j['periodCapMinor']) ?? 0,
        periodUsedMinor: parseInt(j['periodUsedMinor']) ?? 0,
        periodRemainingMinor: parseInt(j['periodRemainingMinor']),
        withdrawalsEnabled: j['withdrawalsEnabled'] != false,
        availableBalance: parseInt(j['availableBalance']) ?? 0,
        settledToBankMinor: parseInt(j['settledToBankMinor']) ?? 0,
        providerName: parseStr(j['providerName']),
        providerAvailableMinor: parseInt(j['providerAvailableMinor']),
        payableNowMinor: parseInt(j['payableNowMinor']),
        settlingAtProviderMinor: parseInt(j['settlingAtProviderMinor']) ?? 0,
      );
}

/// Everything the wallet screen needs, in one call.
class WalletOverview {
  const WalletOverview({
    required this.exists,
    required this.status,
    required this.currency,
    required this.currencyExponent,
    required this.testMode,
    required this.availableBalance,
    required this.accounts,
    required this.walletAllowed,
    this.hasPrimaryCard = true,
    required this.collectedMinor,
    required this.ticketCount,
    this.policy,
    this.progress,
  });
  final bool exists;
  final String? status; // pending | active | frozen | closed …
  final String currency;
  final int currencyExponent;
  final bool testMode;
  final int availableBalance;
  final List<PaymentAccount> accounts;
  final bool walletAllowed;
  final bool hasPrimaryCard; // a primary card backs plan renewals
  final int collectedMinor;
  final int ticketCount;
  final WithdrawalPolicy? policy;
  final OnboardingProgress? progress;

  bool get isActive => status == 'active';
  bool get isFrozen => status == 'frozen';
  bool get viewable => exists && (isActive || isFrozen);
  bool get planGated => !walletAllowed;
  bool get paused => isFrozen || (planGated && viewable);

  /// The one settlement bank the group's money goes to.
  PaymentAccount? get settlementAccount {
    for (final a in accounts) {
      if (a.isDefault && a.status != 'disabled') return a;
    }
    for (final a in accounts) {
      if (a.status != 'disabled') return a;
    }
    return null;
  }

  bool get isStripe => settlementAccount?.isStripe ?? false;

  factory WalletOverview.fromJson(Map<String, dynamic> j) {
    final w = j['wallet'] is Map
        ? Map<String, dynamic>.from(j['wallet'] as Map)
        : null;
    final summary = j['summary'] is Map
        ? Map<String, dynamic>.from(j['summary'] as Map)
        : const <String, dynamic>{};
    final accts = w?['paymentAccounts'] is List
        ? [
            for (final a in w!['paymentAccounts'] as List)
              PaymentAccount.fromJson(Map<String, dynamic>.from(a as Map)),
          ]
        : <PaymentAccount>[];
    return WalletOverview(
      exists: w != null,
      status: parseStr(w?['status']),
      currency: parseStr(w?['currency']) ?? parseStr(summary['currency']) ?? '',
      currencyExponent: parseInt(w?['currencyExponent']) ??
          parseInt(summary['currencyExponent']) ??
          2,
      testMode: parseStr(w?['accountMode']) == 'test',
      availableBalance: parseInt(w?['availableBalance']) ?? 0,
      accounts: accts,
      walletAllowed: j['walletAllowed'] == true,
      hasPrimaryCard: j['hasPrimaryCard'] == true,
      collectedMinor: parseInt(summary['collected']) ?? 0,
      ticketCount: parseInt(summary['count']) ?? 0,
      policy: j['policy'] is Map
          ? WithdrawalPolicy.fromJson(Map<String, dynamic>.from(j['policy'] as Map))
          : null,
      progress: j['progress'] is Map
          ? OnboardingProgress.fromJson(
              Map<String, dynamic>.from(j['progress'] as Map))
          : null,
    );
  }
}

class Person {
  const Person({required this.id, this.displayName, this.username, this.avatarUrl});
  final String id;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  String get name => displayName ?? username ?? 'Unknown';
  static Person? fromJson(dynamic j) => j is Map
      ? Person(
          id: parseStr(j['userId']) ?? parseStr(j['id']) ?? '',
          displayName: parseStr(j['displayName']),
          username: parseStr(j['username']),
          avatarUrl: parseStr(j['avatarUrl']),
        )
      : null;
}

class WithdrawalApproval {
  const WithdrawalApproval(
      {required this.decision, required this.approverId, this.approver, this.note, this.createdAt});
  final String decision; // approved | rejected
  final String approverId;
  final Person? approver;
  final String? note;
  final DateTime? createdAt;
  factory WithdrawalApproval.fromJson(Map<String, dynamic> j) => WithdrawalApproval(
        decision: parseStr(j['decision']) ?? '',
        approverId: parseStr(j['approverId']) ?? '',
        approver: Person.fromJson(j['approver']),
        note: parseStr(j['note']),
        createdAt: parseDate(j['createdAt']),
      );
}

class WithdrawalEvent {
  const WithdrawalEvent({required this.type, this.actor, this.note, this.createdAt});
  final String type;
  final Person? actor;
  final String? note;
  final DateTime? createdAt;
  factory WithdrawalEvent.fromJson(Map<String, dynamic> j) => WithdrawalEvent(
        type: parseStr(j['type']) ?? '',
        actor: Person.fromJson(j['actor']),
        note: parseStr(j['note']),
        createdAt: parseDate(j['createdAt']),
      );
}

class Withdrawal {
  const Withdrawal({
    required this.id,
    required this.amount,
    required this.fees,
    required this.netAmount,
    required this.currency,
    required this.currencyExponent,
    required this.status,
    required this.reference,
    required this.requestedById,
    required this.approvals,
    required this.events,
    this.requestedBy,
    this.reason,
    this.createdAt,
    this.resolvedAt,
  });
  final String id;
  final int amount;
  final int fees;
  final int netAmount;
  final String currency;
  final int currencyExponent;
  final String status; // pending_approval | approved | rejected | processing | paid | failed | cancelled
  final String reference;
  final String requestedById;
  final Person? requestedBy;
  final String? reason;
  final List<WithdrawalApproval> approvals;
  final List<WithdrawalEvent> events;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  bool get pendingApproval => status == 'pending_approval';

  factory Withdrawal.fromJson(Map<String, dynamic> j) => Withdrawal(
        id: (j['id'] ?? '') as String,
        amount: parseInt(j['amount']) ?? 0,
        fees: parseInt(j['fees']) ?? 0,
        netAmount: parseInt(j['netAmount']) ?? 0,
        currency: parseStr(j['currency']) ?? '',
        currencyExponent: parseInt(j['currencyExponent']) ?? 2,
        status: parseStr(j['status']) ?? '',
        reference: parseStr(j['reference']) ?? '',
        requestedById: parseStr(j['requestedById']) ?? '',
        requestedBy: Person.fromJson(j['requestedBy']),
        reason: parseStr(j['reason']),
        approvals: j['approvals'] is List
            ? [
                for (final a in j['approvals'] as List)
                  WithdrawalApproval.fromJson(Map<String, dynamic>.from(a as Map)),
              ]
            : const [],
        events: j['events'] is List
            ? [
                for (final e in j['events'] as List)
                  WithdrawalEvent.fromJson(Map<String, dynamic>.from(e as Map)),
              ]
            : const [],
        createdAt: parseDate(j['createdAt']),
        resolvedAt: parseDate(j['resolvedAt']),
      );
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.direction,
    required this.amount,
    this.description,
    this.type,
    this.reference,
    this.createdAt,
  });
  final String id;
  final String direction; // credit | debit
  final int amount;
  final String? description;
  final String? type;
  final String? reference;
  final DateTime? createdAt;
  bool get isCredit => direction == 'credit';

  factory LedgerEntry.fromJson(Map<String, dynamic> j) {
    final tx = j['transaction'] is Map
        ? Map<String, dynamic>.from(j['transaction'] as Map)
        : const <String, dynamic>{};
    return LedgerEntry(
      id: (j['id'] ?? '') as String,
      direction: parseStr(j['direction']) ?? 'credit',
      amount: parseInt(j['amount']) ?? 0,
      description: parseStr(tx['description']),
      type: parseStr(tx['type']),
      reference: parseStr(tx['reference']),
      createdAt: parseDate(j['createdAt']),
    );
  }
}

/// Withdrawal list + who is looking (to tell "yours" from "approvable").
class WithdrawalsPage {
  const WithdrawalsPage({required this.viewerId, required this.withdrawals});
  final String? viewerId;
  final List<Withdrawal> withdrawals;
  List<Withdrawal> get pending => withdrawals.where((w) => w.pendingApproval).toList();

  factory WithdrawalsPage.fromJson(Map<String, dynamic> j) => WithdrawalsPage(
        viewerId: parseStr(j['viewerId']),
        withdrawals: j['withdrawals'] is List
            ? [
                for (final w in j['withdrawals'] as List)
                  Withdrawal.fromJson(Map<String, dynamic>.from(w as Map)),
              ]
            : const [],
      );
}
