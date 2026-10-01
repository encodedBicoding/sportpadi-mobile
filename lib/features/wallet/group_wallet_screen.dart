import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/data/billing/iap_repository.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/wallet/wallet_models.dart';
import 'package:sportpadi_mobile/data/wallet/wallet_repository.dart';
import 'package:sportpadi_mobile/features/wallet/fee_bearer_card.dart';
import 'package:sportpadi_mobile/features/wallet/wallet_tips.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/info_tip.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart'
    show groupProvider;
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// Group wallet for admins — mirrors the web wallet page: balance hero
/// (withdrawable for Stripe, settled-to-bank for auto-settling providers),
/// withdraw, multi-admin approvals, settlement bank, and the activity ledger.
/// Bank onboarding itself opens in the browser (the provider's hosted form,
/// or our web form for Paystack/Flutterwave).
class GroupWalletScreen extends ConsumerStatefulWidget {
  const GroupWalletScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupWalletScreen> createState() => _GroupWalletScreenState();
}

class _GroupWalletScreenState extends ConsumerState<GroupWalletScreen> {
  bool _busy = false;
  bool _planEmailFired = false;

  /// Where a plan-locked feature sends an admin.
  ///
  /// On iOS the plan is bought in the app through the App Store, so the honest
  /// thing — and what Apple asks for — is a plain button that opens it.
  /// Elsewhere there is no in-app purchase to offer, so we keep the old quiet
  /// behaviour: state the fact and have the server email the admin the details
  /// out of band, with no CTA and no link-out.
  bool get _canBuyInApp => IapRepository.supportedPlatform;

  void _maybeEmailPlanInfo() {
    if (_canBuyInApp || _planEmailFired) return;
    _planEmailFired = true;
    Future.microtask(() =>
        ref.read(walletRepositoryProvider).requestPlanEmail(widget.groupId));
  }

  /// The upgrade button, on platforms where we can actually sell a plan.
  Widget? _planCta(String label) => _canBuyInApp
      ? SpButton(
          label: label,
          icon: Icons.workspace_premium_outlined,
          onTap: () => context.push('/groups/${widget.groupId}/plan'),
        )
      : null;

  void _refetch() {
    ref.invalidate(walletOverviewProvider(widget.groupId));
    ref.invalidate(feeSettingProvider(widget.groupId));
    ref.invalidate(walletWithdrawalsProvider(widget.groupId));
    ref.invalidate(walletLedgerProvider(widget.groupId));
  }

  Future<void> _openWeb(String path) async {
    final base = ref.read(appConfigProvider).apiBaseUrl;
    // Custom Tabs / SFSafariViewController, not a bare VIEW intent: the app is
    // a verified handler for this host, so externalApplication can be routed
    // straight back to us instead of to a browser.
    await launchUrl(Uri.parse('$base$path'), mode: LaunchMode.inAppBrowserView);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// "Continue with Stripe" — mint/resume the hosted onboarding link and open it.
  Future<void> _continueOnboarding() => _run(() async {
        final url = await ref
            .read(walletRepositoryProvider)
            .resumeOnboarding(widget.groupId);
        if (url == null) {
          _snack('Nothing left to finish.');
          _refetch();
          return;
        }
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Finish in your browser'),
            content: const Text(
                'Complete the provider\'s form, then come back here and tap Refresh status.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
        _refetch();
      });

  Future<void> _refreshStatus() => _run(() async {
        final r = await ref
            .read(walletRepositoryProvider)
            .refreshStatus(widget.groupId);
        _refetch();
        if (r.walletStatus == 'active') {
          _snack('Wallet activated 🎉');
        } else if (r.actionNeeded) {
          final what = r.due.isNotEmpty
              ? r.due.first.label.toLowerCase()
              : 'the next step';
          _snack('Not done yet — the provider still needs $what.');
        } else if (r.step == 'under_review') {
          _snack('Everything is submitted — the provider is reviewing it now.');
        } else if (r.step == 'rejected') {
          _snack('The provider declined this account. Contact support.');
        } else {
          _snack("Setup isn't finished yet — continue when you're ready.");
        }
      });

  Future<void> _withdraw(WalletOverview ov) async {
    final acct = ov.settlementAccount;
    final policy = ov.policy;
    if (acct == null || policy == null) return;
    final amountMinor = await showSpSheet<int>(
      context,
      builder: (_) => _WithdrawSheet(
          policy: policy, currency: ov.currency, exponent: ov.currencyExponent),
    );
    if (amountMinor == null) return;
    await _run(() async {
      await ref.read(walletRepositoryProvider).requestWithdrawal(widget.groupId,
          paymentAccountId: acct.id, amountMinor: amountMinor);
      _snack(
          'Withdrawal requested — every group admin has been notified. The money is locked until it\'s approved or rejected.');
      _refetch();
      if (mounted) context.push('/groups/${widget.groupId}/wallet/withdrawals');
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ov = ref.watch(walletOverviewProvider(widget.groupId));
    final groupName =
        ref.watch(groupProvider(widget.groupId)).valueOrNull?.name;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: SpHeader(
              title: 'Wallet',
              subtitle: groupName,
              actions: [
                if (ov.valueOrNull != null) _statusBadge(ov.valueOrNull!, p),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<WalletOverview>(
              value: ov,
              onRetry: _refetch,
              data: (o) => RefreshIndicator(
                onRefresh: () async => _refetch(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                  children: _body(o, p),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  WalletTips _tips(WalletOverview o) => WalletTips(
        provider: o.policy?.providerName != null
            ? o.policy!.providerLabel
            : o.settlementAccount?.providerLabel,
        maturationDays: o.policy?.maturationDays ?? 0,
        periodDays: o.policy?.periodDays ?? 0,
      );

  Widget _statusBadge(WalletOverview o, AppPalette p) {
    if (!o.exists) return const SizedBox.shrink();
    final s = o.status ?? '';
    final tone = switch (s) {
      'active' => p.accent,
      'frozen' => p.amber,
      _ => p.muted,
    };
    final tip = _tips(o).walletStatus(s);
    final badge = SpBadge(
        s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}',
        tone: tone);
    if (tip == null) return badge;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      badge,
      SpInfoTip(tip, color: tone),
    ]);
  }

  List<Widget> _body(WalletOverview o, AppPalette p) {
    // No wallet + not entitled → neutral locked state. App-store rules forbid
    // in-app upgrade CTAs, purchase link-outs or even naming the plan, so
    // (uniformly on every platform) the app states the fact and the server
    // emails the admin instead.
    if (o.planGated && !o.viewable) {
      _maybeEmailPlanInfo();
      return [
        _centered(
          p,
          icon: Icons.lock_outline_rounded,
          tone: p.muted,
          title: "The wallet isn't enabled for this group",
          body: 'Ticket sales, a group balance and withdrawals to your bank '
              "aren't switched on for this group yet.",
          cta: _planCta('See plans'),
        ),
      ];
    }

    // Not activated yet — never started, or provider onboarding in progress.
    if (!o.viewable) {
      final acct = o.settlementAccount;
      if (acct == null) {
        return [
          _centered(
            p,
            icon: Icons.account_balance_rounded,
            tone: p.accent,
            title: 'Set up payment collection',
            body:
                "Connect your group's bank once. After that, money from ticket sales settles straight into it — buyers pay a small fee at checkout and SportPadi never holds your funds.",
            cta: SpButton(
              label: 'Connect bank (opens browser)',
              icon: Icons.open_in_new_rounded,
              onTap: () =>
                  _openWeb('/groups/${widget.groupId}/wallet/activate'),
            ),
            footnote:
                'Bank details are entered on a secure web form. Come back here when done.',
          ),
        ];
      }
      return [_onboardingCard(o, acct, p)];
    }

    final policy = o.policy;
    final acct = o.settlementAccount;
    final pausedByPlan = o.planGated && o.viewable;
    if (pausedByPlan) _maybeEmailPlanInfo();
    return [
      if (o.testMode)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SpBadge('🧪 Test mode — no real money moves', tone: p.amber),
            SpInfoTip(_tips(o).testMode, color: p.amber),
          ]),
        ),
      if (o.isFrozen || pausedByPlan)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _notice(
            p,
            'This wallet is paused. Records stay visible; sales and withdrawals are on hold.',
          ),
        ),
      // (No "add a primary card for renewals" prompt here: it's subscription
      // billing, which the app must not surface — App Store 3.1.1.)
      _balanceCard(o, policy, acct, p),
      const SizedBox(height: 14),
      // One-time: who covers the fees on tickets, fines and tournament fees.
      FeeBearerCard(groupId: widget.groupId, disabled: o.paused),
      const SizedBox(height: 14),
      _sectionTitle('Settlement account', p,
          tip: _tips(o).settlementAccount,
          trailing: !o.paused
              ? TextButton(
                  onPressed: () =>
                      _openWeb('/groups/${widget.groupId}/wallet/activate'),
                  child: const Text('Replace'),
                )
              : null),
      if (acct == null)
        GlassCard(
          child: Column(children: [
            Text('No bank connected yet.',
                style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 10),
            SpButton(
              label: 'Connect bank',
              icon: Icons.account_balance_rounded,
              onTap: () =>
                  _openWeb('/groups/${widget.groupId}/wallet/activate'),
            ),
          ]),
        )
      else
        _accountCard(acct, o.currency, p),
      const SizedBox(height: 14),
      _withdrawalsSection(p),
      const SizedBox(height: 14),
      _sectionTitle('Activity', p, tip: _tips(o).activity),
      _ledgerSection(o, p),
    ];
  }

  // ── pieces ────────────────────────────────────────────────────────────

  Widget _centered(AppPalette p,
      {required IconData icon,
      required Color tone,
      required String title,
      required String body,
      Widget? cta,
      String? footnote}) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: tone.withAlpha(34),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: tone, size: 28),
        ),
        const SizedBox(height: 14),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(body,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.45)),
        if (cta != null) ...[const SizedBox(height: 16), cta],
        if (footnote != null) ...[
          const SizedBox(height: 10),
          Text(footnote,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 11)),
        ],
      ]),
    );
  }

  Widget _notice(AppPalette p, String text,
      {String? action, VoidCallback? onAction}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.orangeTint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(children: [
        SpIconTile(Icons.pause_circle_outline_rounded,
            bg: p.surface, fg: p.orangeInk, size: 36, iconSize: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text, style: TextStyle(color: p.ink, fontSize: 12.5))),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action)),
      ]),
    );
  }

  Widget _sectionTitle(String t, AppPalette p,
      {Widget? trailing, String? tip}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 0, 10),
      child: Row(children: [
        Expanded(
          child: TipText(t,
              tip: tip,
              style: TextStyle(
                  color: p.ink, fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        if (trailing != null) trailing,
      ]),
    );
  }

  Widget _onboardingCard(WalletOverview o, PaymentAccount acct, AppPalette p) {
    final prog = o.progress;
    final step = prog?.step ??
        (acct.status == 'verifying' ? 'under_review' : 'provide_details');
    final provider = acct.providerLabel;
    final actionNeeded = prog?.actionNeeded ?? acct.status != 'verifying';
    final due = prog?.due ?? const <OnboardingItem>[];
    final pending = prog?.pending ?? const <OnboardingItem>[];

    final headline = switch (step) {
      'rejected' => '$provider declined this account',
      'under_review' => '$provider is reviewing your details',
      'verify_identity' => '$provider is waiting on you — one more step',
      _ => 'Finish setting up with $provider',
    };
    final blurb = switch (step) {
      'rejected' => prog?.disabledReason != null
          ? 'Reason: ${prog!.disabledReason!.replaceFirst(RegExp(r'^rejected\.'), '').replaceAll('_', ' ')}. Contact support to sort this out.'
          : 'Contact support to sort this out.',
      'under_review' =>
        'Everything is submitted. This usually takes a few minutes, sometimes up to a day. Pull to refresh to check.',
      'verify_identity' =>
        "Your first form went through, but $provider still needs to verify who you are before it can pay out. This step isn't optional.",
      _ =>
        "You started setup but didn't finish $provider's form. Pick up where you left off — nothing needs re-entering.",
    };
    final steps = <(String, String)>[
      ('Account details', step == 'provide_details' ? 'now' : 'done'),
      (
        'Identity check',
        step == 'verify_identity'
            ? 'now'
            : step == 'provide_details'
                ? 'todo'
                : 'done'
      ),
      (
        '$provider review',
        step == 'under_review'
            ? 'now'
            : step == 'ready'
                ? 'done'
                : 'todo'
      ),
      ('Payouts on', step == 'ready' ? 'done' : 'todo'),
    ];

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: p.accentTint, borderRadius: BorderRadius.circular(20)),
            child: Icon(Icons.account_balance_rounded,
                color: p.greenText, size: 28),
          ),
        ),
        const SizedBox(height: 12),
        Text(headline,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(blurb,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.45)),
        const SizedBox(height: 14),
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Icon(
                s.$2 == 'done'
                    ? Icons.check_circle_rounded
                    : s.$2 == 'now'
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                size: 18,
                color: s.$2 == 'done'
                    ? p.accent
                    : s.$2 == 'now'
                        ? p.amber
                        : p.muted,
              ),
              const SizedBox(width: 8),
              Text(s.$1,
                  style: TextStyle(
                      color: s.$2 == 'todo' ? p.muted : p.ink,
                      fontSize: 13,
                      fontWeight:
                          s.$2 == 'now' ? FontWeight.w700 : FontWeight.w500)),
            ]),
          ),
        if (due.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('$provider still needs:',
              style: TextStyle(
                  color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
          for (final d in due)
            Text('• ${d.label}',
                style: TextStyle(color: p.amber, fontSize: 12.5)),
        ],
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Being verified: ${pending.map((x) => x.label).join(', ')}',
              style: TextStyle(color: p.muted, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        if (step != 'rejected' && actionNeeded)
          SpButton(
            label: step == 'verify_identity'
                ? 'Verify identity with $provider'
                : 'Continue with $provider',
            icon: Icons.open_in_new_rounded,
            expand: true,
            onTap: _busy ? null : _continueOnboarding,
          ),
        const SizedBox(height: 8),
        Material(
          color: p.surface,
          shape: StadiumBorder(side: BorderSide(color: p.line)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: _busy ? null : _refreshStatus,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.refresh_rounded, size: 18, color: p.ink),
                const SizedBox(width: 6),
                Text('Refresh status',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _balanceCard(WalletOverview o, WithdrawalPolicy? policy,
      PaymentAccount? acct, AppPalette p) {
    final cur = o.currency;
    final exp = o.currencyExponent;
    final appControlled = o.isStripe;
    final withdrawable = policy?.cappedWithdrawable ?? 0;
    final held = policy?.heldMinor ?? 0;
    final settled = policy?.settledToBankMinor ?? 0;
    final canWithdraw = appControlled &&
        o.isActive &&
        !o.paused &&
        acct != null &&
        acct.hasProviderAccount &&
        (policy?.withdrawalsEnabled ?? true) &&
        withdrawable > 0 &&
        !(policy?.dayBlocked ?? false);

    final providerKnown = appControlled && (policy?.hasProviderFigure ?? false);
    final providerLabel = policy?.providerLabel ?? 'your payment provider';
    final matured = policy?.withdrawableMinor ?? 0;
    final settling = policy?.settlingAtProviderMinor ?? 0;
    final eyebrow = !appControlled
        ? 'COLLECTED'
        : providerKnown
            ? 'AVAILABLE AT ${providerLabel.toUpperCase()} NOW'
            : 'AVAILABLE TO WITHDRAW';
    final tips = _tips(o);
    final eyebrowTip = !appControlled
        ? tips.settledDirect
        : providerKnown
            ? tips.availableAtProvider
            : tips.availableToWithdraw;

    const mint = Color(0xFF6EDC9E);
    const warm = Color(0xFFFFB57D);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.hero,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TipText(eyebrow,
            tip: eyebrowTip,
            style: TextStyle(
                color: providerKnown ? mint : p.heroMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
              formatMoney(
                  appControlled ? withdrawable : o.collectedMinor, cur, exp),
              style: TextStyle(
                  color: p.onHero,
                  fontSize: 36,
                  letterSpacing: -0.8,
                  fontWeight: FontWeight.w800)),
        ),
        if (appControlled && policy?.providerName != null) ...[
          const SizedBox(height: 6),
          TipText('Matured on SportPadi: ${formatMoney(matured, cur, exp)}',
              tip: tips.maturedOnSportPadi,
              style: TextStyle(
                  color: p.onHero,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          TipText(
            !providerKnown
                ? 'Couldn\'t read your $providerLabel balance just now — showing the SportPadi figure. Pull to refresh to try again.'
                : settling > 0
                    ? '${formatMoney(settling, cur, exp)} is still settling with $providerLabel and becomes payable as it clears.'
                    : 'Fully settled with $providerLabel.',
            tip: providerKnown && settling > 0 ? tips.settlingAtProvider : null,
            style: TextStyle(
                color: providerKnown && settling > 0 ? warm : p.heroMuted,
                fontSize: 12,
                height: 1.4),
          ),
        ],
        if (appControlled && (policy?.pendingApprovalMinor ?? 0) > 0) ...[
          const SizedBox(height: 6),
          TipText(
            '${formatMoney(policy!.pendingApprovalMinor, cur, exp)} is locked by a withdrawal awaiting approval — excluded from the balance above.',
            tip: tips.lockedByApproval,
            style: const TextStyle(color: warm, fontSize: 12, height: 1.4),
          ),
        ],
        if (appControlled) ...[
          const SizedBox(height: 10),
          if (policy != null &&
              policy.dayBlocked &&
              policy.nextPayoutDate != null)
            Text('Withdrawals open on ${formatDayYear(policy.nextPayoutDate)}.',
                style: const TextStyle(color: warm, fontSize: 12))
          else if (policy != null && !policy.withdrawalsEnabled)
            const Text('Withdrawals are paused for this group.',
                style: TextStyle(color: warm, fontSize: 12)),
          const SizedBox(height: 10),
          Material(
            color:
                canWithdraw && !_busy ? Colors.white : p.onHero.withAlpha(30),
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: canWithdraw && !_busy ? () => _withdraw(o) : null,
              child: SizedBox(
                height: 50,
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.arrow_outward_rounded,
                      size: 18,
                      color: canWithdraw && !_busy
                          ? const Color(0xFF0E1411)
                          : p.heroMuted),
                  const SizedBox(width: 7),
                  Text('Withdraw to bank',
                      style: TextStyle(
                          color: canWithdraw && !_busy
                              ? const Color(0xFF0E1411)
                              : p.heroMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(children: [
          _stat('Settled to bank', formatMoney(settled, cur, exp), p,
              tip: tips.settledToBank),
          const SizedBox(width: 8),
          _stat('Maturing', formatMoney(held, cur, exp), p,
              muted: held <= 0, tip: tips.maturing),
          const SizedBox(width: 8),
          _stat('Collected', formatMoney(o.collectedMinor, cur, exp), p,
              tip: tips.collected),
        ]),
        const SizedBox(height: 14),
        Text(
          appControlled
              ? 'Ticket revenue collects in your wallet at the full price you set — buyers pay the fees on top, and card-processing costs come out of those fees, never out of your balance.'
                  '${policy != null && policy.maturationDays > 0 ? ' Recent revenue matures over ${policy.maturationDays} days so refunds stay covered.' : ''}'
              : "Ticket money settles straight to your connected bank on the provider's schedule — buyers pay a small fee at checkout and SportPadi never holds your funds.",
          style: TextStyle(color: p.heroMuted, fontSize: 11.5, height: 1.5),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.receipt_long_rounded, size: 14, color: p.heroMuted),
          const SizedBox(width: 6),
          Text(
              '${o.ticketCount} ticket payment${o.ticketCount == 1 ? '' : 's'} to date',
              style: TextStyle(color: p.heroMuted, fontSize: 12)),
        ]),
      ]),
    );
  }

  /// A figure tile on the dark balance card.
  Widget _stat(String label, String value, AppPalette p,
      {bool muted = false, String? tip}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: p.onHero.withAlpha(18),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: muted ? p.heroMuted : p.onHero,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          TipText(label,
              tip: tip,
              maxLines: 1,
              style: TextStyle(color: p.heroMuted, fontSize: 10.5)),
        ]),
      ),
    );
  }

  Widget _accountCard(PaymentAccount a, String currency, AppPalette p) {
    return GlassCard(
      child: Row(children: [
        SpIconTile(Icons.account_balance_rounded,
            bg: p.accentTint, fg: p.greenText),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${a.providerLabel}${a.bankName != null ? ' · ${a.bankName}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
            Text(
              '${a.accountLast4 != null ? '•••• ${a.accountLast4}' : (a.holderName ?? '')} · ${a.country ?? ''} · $currency',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ]),
        ),
        SpBadge(a.payoutEnabled ? 'Ready' : a.status,
            tone: a.payoutEnabled ? p.accent : p.muted),
        SpInfoTip(
            WalletTips(provider: a.providerLabel).accountStatus(
                payoutEnabled: a.payoutEnabled, status: a.status),
            color: a.payoutEnabled ? p.accent : p.muted),
      ]),
    );
  }

  /// Entry to the transparent withdrawal log (its own page, like the web
  /// `/wallet/approvals`): who requested, who approved or rejected, and when
  /// each payout reached the bank.
  Widget _withdrawalsSection(AppPalette p) {
    final page =
        ref.watch(walletWithdrawalsProvider(widget.groupId)).valueOrNull;
    final pending = page?.pending.length ?? 0;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      onTap: () => context.push('/groups/${widget.groupId}/wallet/withdrawals'),
      child: Row(children: [
        SpIconTile(Icons.fact_check_outlined,
            bg: pending > 0 ? p.orangeTint : p.surface2,
            fg: pending > 0 ? p.orangeInk : p.muted),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TipText('Withdrawal requests',
                tip: WalletTips().withdrawalRequests,
                style: TextStyle(
                    color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              pending > 0
                  ? '$pending awaiting approval'
                  : 'Who requested, who approved or rejected, and when each payout reached the bank.',
              style: TextStyle(
                  color: pending > 0 ? p.orangeInk : p.muted,
                  fontSize: 11.5,
                  fontWeight: pending > 0 ? FontWeight.w700 : FontWeight.w400),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        if (pending > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: p.orange, borderRadius: BorderRadius.circular(999)),
            child: Text('$pending',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 6),
        ],
        Icon(Icons.chevron_right_rounded, color: p.muted, size: 20),
      ]),
    );
  }

  Widget _ledgerSection(WalletOverview o, AppPalette p) {
    final led = ref.watch(walletLedgerProvider(widget.groupId));
    return led.when(
      loading: () => GlassCard(
          child: Center(
              child: Text('Loading activity…',
                  style: TextStyle(color: p.muted, fontSize: 13)))),
      error: (e, _) => GlassCard(
          child: Center(
              child:
                  Text('$e', style: TextStyle(color: p.muted, fontSize: 13)))),
      data: (entries) {
        if (entries.isEmpty) {
          return GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text('No activity yet.',
                  style: TextStyle(color: p.muted, fontSize: 13)),
              const SizedBox(height: 2),
              Text('Ticket payments will appear here as they settle.',
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          );
        }
        return SpListCard(children: [
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
              child: Row(children: [
                SpIconTile(
                  e.isCredit
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  bg: e.isCredit ? p.accentTint : p.surface2,
                  fg: e.isCredit ? p.greenText : p.muted,
                  size: 38,
                  iconSize: 17,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.description ??
                              e.type?.replaceAll('_', ' ') ??
                              'Transaction',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                        if (e.createdAt != null)
                          Text(timeAgo(e.createdAt),
                              style: TextStyle(color: p.muted, fontSize: 12)),
                      ]),
                ),
                const SizedBox(width: 8),
                Text(
                  '${e.isCredit ? '+' : '−'}${formatMoney(e.amount, o.currency, o.currencyExponent)}',
                  style: TextStyle(
                      color: e.isCredit ? p.greenText : p.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800),
                ),
              ]),
            ),
        ]);
      },
    );
  }
}

/// Amount entry for a withdrawal request. Pops with the amount in MINOR units.
class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet(
      {required this.policy, required this.currency, required this.exponent});
  final WithdrawalPolicy policy;
  final String currency;
  final int exponent;

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int _pow10(int e) {
    var v = 1;
    for (var i = 0; i < e; i++) {
      v *= 10;
    }
    return v;
  }

  void _submit() {
    final v = double.tryParse(_amount.text.trim());
    if (v == null || v <= 0) return setState(() => _error = 'Enter an amount');
    final minor = (v * _pow10(widget.exponent)).round();
    final pol = widget.policy;
    if (minor > pol.cappedWithdrawable) {
      final providerCapped = pol.hasProviderFigure &&
          pol.payableNow < pol.withdrawableMinor &&
          minor <= pol.withdrawableMinor;
      return setState(() => _error = providerCapped
          ? 'Only ${formatMoney(pol.payableNow, widget.currency, widget.exponent)} has settled with ${pol.providerLabel} so far'
          : 'Amount exceeds what you can withdraw right now');
    }
    Navigator.pop(context, minor);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pol = widget.policy;
    final cur = widget.currency;
    final exp = widget.exponent;
    final tips = WalletTips(
        provider: pol.providerName != null ? pol.providerLabel : null,
        maturationDays: pol.maturationDays,
        periodDays: pol.periodDays);
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SpSheetHeader(
            icon: Icons.account_balance_outlined,
            title: 'Withdraw to bank',
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: p.surface2, borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              if (pol.hasProviderFigure) ...[
                _kv('Available at ${pol.providerLabel} now',
                    formatMoney(pol.providerAvailableMinor!, cur, exp), p,
                    tip: tips.availableAtProvider),
                _kv('Matured on SportPadi',
                    formatMoney(pol.withdrawableMinor, cur, exp), p,
                    tip: tips.maturedOnSportPadi),
                if (pol.settlingAtProviderMinor > 0)
                  _kv('Still settling with ${pol.providerLabel}',
                      formatMoney(pol.settlingAtProviderMinor, cur, exp), p,
                      tip: tips.settlingAtProvider),
              ] else
                _kv('Available now',
                    formatMoney(pol.withdrawableMinor, cur, exp), p,
                    tip: tips.availableToWithdraw),
              if (pol.heldMinor > 0)
                _kv('Maturing (${pol.maturationDays} days)',
                    formatMoney(pol.heldMinor, cur, exp), p,
                    tip: tips.maturing),
              if (pol.pendingApprovalMinor > 0)
                _kv('Locked · awaiting approval',
                    formatMoney(pol.pendingApprovalMinor, cur, exp), p,
                    tip: tips.lockedByApproval),
              if (pol.periodRemainingMinor != null)
                _kv('Left this ${pol.periodDays}-day period',
                    formatMoney(pol.periodRemainingMinor!, cur, exp), p,
                    tip: tips.leftThisPeriod),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              helperText: tips.withdrawAmount,
              helperMaxLines: 3,
              prefixText: '$cur ',
              errorText: _error,
              suffixIcon: TextButton(
                onPressed: () => setState(() {
                  _amount.text = (pol.cappedWithdrawable / _pow10(exp))
                      .toStringAsFixed(exp);
                  _error = null;
                }),
                child: const Text('Max'),
              ),
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 8),
          Text(
            'Another group admin has to approve before the payout is sent. If you are the only admin it goes through automatically.',
            style: TextStyle(color: p.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 14),
          SpButton(
              label: 'Request withdrawal',
              icon: Icons.arrow_outward_rounded,
              expand: true,
              onTap: _submit),
        ]);
  }

  Widget _kv(String k, String v, AppPalette p, {String? tip}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
              child: TipText(k,
                  tip: tip, style: TextStyle(color: p.muted, fontSize: 12))),
          Text(v,
              style: TextStyle(
                  color: p.ink, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}
