
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Plain-language explanations for wallet terms — the Dart twin of
/// `packages/lib/src/walletTips.ts` on the web. Keep the copy in step.
class WalletTips {
  WalletTips({String? provider, int maturationDays = 0, int periodDays = 0})
      : prov = (provider == null || provider.isEmpty)
            ? l10n.wallet_yourPayoutProvider
            : provider,
        holdDays = maturationDays > 0 ? maturationDays : 0,
        periodDays = periodDays > 0 ? periodDays : 0;

  final String prov;

  /// The maturation hold in days; 0 when there is none (the copy then
  /// says just "the hold").
  final int holdDays;

  /// The withdrawal cap period in days; 0 when unknown.
  final int periodDays;

  String get availableAtProvider => l10n.wallet_tipAvailableAtProvider(prov);
  String get availableToWithdraw =>
      l10n.wallet_tipAvailableToWithdraw(holdDays);
  String get maturedOnSportPadi =>
      l10n.wallet_tipMaturedOnSportPadi(holdDays, prov);
  String get settlingAtProvider => l10n.wallet_tipSettlingAtProvider(prov);
  String get settledToBank => l10n.wallet_tipSettledToBank;
  String get maturing => l10n.wallet_tipMaturing(holdDays);
  String get collected => l10n.wallet_tipCollected;
  String get lockedByApproval => l10n.wallet_tipLockedByApproval;
  String get leftThisPeriod => l10n.wallet_tipLeftThisPeriod(periodDays);
  String get payoutDays => l10n.wallet_tipPayoutDays;
  String get testMode => l10n.wallet_tipTestMode(prov);
  String get settlementAccount => l10n.wallet_tipSettlementAccount(prov);
  String get activity => l10n.wallet_tipActivity;
  String get withdrawalRequests => l10n.wallet_tipWithdrawalRequests;
  String get withdrawAmount => l10n.wallet_tipWithdrawAmount(prov);
  String get settledDirect => l10n.wallet_tipSettledDirect(prov);

  String? walletStatus(String? s) => switch (s) {
        'active' => l10n.wallet_liveSalesAndWithdrawalsAre,
        'pending' =>
          l10n.wallet_setUpButNotLive(prov),
        'frozen' ||
        'paused' =>
          l10n.wallet_pausedRecordsStayVisibleSales,
        'inactive' =>
          l10n.wallet_notActivatedYetConnectA,
        _ => null,
      };

  String? withdrawalStatus(String s) => switch (s) {
        'pending_approval' =>
          l10n.wallet_waitingForAnotherAdminTo,
        'approved' => l10n.wallet_approvedThePayoutIsBeing(prov),
        'processing' => l10n.wallet_hasThePayoutAndIsMoving(prov),
        'paid' => l10n.wallet_theMoneyReachedTheBank,
        'rejected' =>
          l10n.wallet_anAdminDeclinedItThe,
        'failed' =>
          l10n.wallet_theBankPayoutFailedThe,
        'cancelled' => l10n.wallet_cancelledBeforeItWasProcessed,
        _ => null,
      };

  String accountStatus({required bool payoutEnabled, required String status}) {
    if (payoutEnabled) return l10n.wallet_verifiedByAndAbleTo(prov);
    if (status == 'pending') {
      return l10n.wallet_detailsSubmittedButNotYet(prov);
    }
    return l10n.wallet_isReviewingTheDetailsPayouts(prov);
  }
}
