/// Plain-language explanations for wallet terms — the Dart twin of
/// `packages/lib/src/walletTips.ts` on the web. Keep the copy in step.
class WalletTips {
  WalletTips({String? provider, int maturationDays = 0, int periodDays = 0})
      : prov = (provider == null || provider.isEmpty)
            ? 'your payout provider'
            : provider,
        hold = maturationDays > 0 ? '$maturationDays-day ' : '',
        period = periodDays > 0 ? '$periodDays-day ' : '';

  final String prov;
  final String hold;
  final String period;

  String get availableAtProvider =>
      'What $prov has finished settling and can actually pay to your bank today. Card payments take a few business days to settle, so this can lag behind what has matured on SportPadi.';
  String get availableToWithdraw =>
      'Ticket money that has cleared the ${hold}hold and can be sent to your bank.';
  String get maturedOnSportPadi =>
      'Ticket revenue that has cleared the ${hold}hold on SportPadi. You can withdraw it once $prov has settled it too.';
  String get settlingAtProvider =>
      "Matured on SportPadi, but $prov hasn't finished settling it yet. It joins the available amount automatically — usually within a few business days.";
  String get settledToBank =>
      'Everything already paid out to your bank through approved withdrawals.';
  String get maturing =>
      "Recent ticket revenue still inside the ${hold}hold. It's held so refunds stay covered and becomes withdrawable automatically.";
  String get collected =>
      'Everything buyers have paid for your events, at the price you set. Buyers pay processing fees on top, so this is what your group keeps.';
  String get lockedByApproval =>
      "A withdrawal request is waiting for another admin's decision. The amount stays locked until it's approved (paid out) or rejected (returned to the balance).";
  String get leftThisPeriod =>
      "Withdrawals for this group are capped per ${period}period. This is what's left before the cap resets.";
  String get payoutDays =>
      'Withdrawals for this group are only sent on these days of the month. Requests made on other days wait for the next payout day.';
  String get testMode =>
      'This wallet is connected in $prov test mode — payments and payouts are simulated and no real money moves.';
  String get settlementAccount =>
      "The bank account withdrawals are paid to. There is exactly one per group; replacing it re-runs $prov's verification before payouts resume.";
  String get activity =>
      'Every movement in the wallet: ticket credits, refunds, fees and withdrawal debits — the full ledger.';
  String get withdrawalRequests =>
      'The approval log. Every withdrawal needs another admin\'s approval (sole admins are auto-approved), and each request records who asked, who decided, and when the bank received it.';
  String get withdrawAmount =>
      "You can withdraw up to the smallest of: what $prov has settled, what has matured on SportPadi, and what's left in this period.";
  String get settledDirect =>
      "Ticket money settles straight to your connected bank on $prov's schedule — SportPadi never holds it.";

  String? walletStatus(String? s) => switch (s) {
        'active' => 'Live — sales and withdrawals are on.',
        'pending' =>
          'Set up but not live yet — $prov is still verifying the account.',
        'frozen' ||
        'paused' =>
          'Paused — records stay visible; sales and withdrawals are on hold.',
        'inactive' =>
          'Not activated yet — connect a bank account to start collecting.',
        _ => null,
      };

  String? withdrawalStatus(String s) => switch (s) {
        'pending_approval' =>
          'Waiting for another admin to approve or reject. The amount is locked meanwhile.',
        'approved' => 'Approved — the payout is being sent to $prov.',
        'processing' => '$prov has the payout and is moving it to the bank.',
        'paid' => 'The money reached the bank account.',
        'rejected' =>
          'An admin declined it; the amount went back to the withdrawable balance.',
        'failed' =>
          'The bank payout failed — the amount is back in the wallet. Check the audit trail and contact support.',
        'cancelled' => 'Cancelled before it was processed.',
        _ => null,
      };

  String accountStatus({required bool payoutEnabled, required String status}) {
    if (payoutEnabled) return 'Verified by $prov and able to receive payouts.';
    if (status == 'pending') {
      return 'Details submitted but not yet verified — finish any remaining $prov steps and payouts unlock once $prov approves.';
    }
    return "$prov is reviewing the details — payouts start once it's done.";
  }
}
