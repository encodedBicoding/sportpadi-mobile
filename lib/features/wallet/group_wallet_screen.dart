import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/wallet/wallet_models.dart';
import 'package:sportpadi_mobile/data/wallet/wallet_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

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

  void _refetch() {
    ref.invalidate(walletOverviewProvider(widget.groupId));
    ref.invalidate(walletWithdrawalsProvider(widget.groupId));
    ref.invalidate(walletLedgerProvider(widget.groupId));
  }

  Future<void> _openWeb(String path) async {
    final base = ref.read(appConfigProvider).apiBaseUrl;
    await launchUrl(Uri.parse('$base$path'), mode: LaunchMode.externalApplication);
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
        final url = await ref.read(walletRepositoryProvider).resumeOnboarding(widget.groupId);
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
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
        _refetch();
      });

  Future<void> _refreshStatus() => _run(() async {
        final r = await ref.read(walletRepositoryProvider).refreshStatus(widget.groupId);
        _refetch();
        if (r.walletStatus == 'active') {
          _snack('Wallet activated 🎉');
        } else if (r.actionNeeded) {
          final what = r.due.isNotEmpty ? r.due.first.label.toLowerCase() : 'the next step';
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
    final amountMinor = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WithdrawSheet(policy: policy, currency: ov.currency, exponent: ov.currencyExponent),
    );
    if (amountMinor == null) return;
    await _run(() async {
      await ref.read(walletRepositoryProvider).requestWithdrawal(widget.groupId,
          paymentAccountId: acct.id, amountMinor: amountMinor);
      _snack('Withdrawal requested');
      _refetch();
    });
  }

  Future<void> _decide(Withdrawal w, bool approve) async {
    final note = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text(approve ? 'Approve withdrawal' : 'Reject withdrawal'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              '${formatMoney(w.amount, w.currency, w.currencyExponent)} to the group\'s bank'
              '${w.requestedBy != null ? ', requested by ${w.requestedBy!.name}' : ''}.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              maxLength: 280,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: Text(approve ? 'Approve' : 'Reject'),
            ),
          ],
        );
      },
    );
    if (note == null) return;
    await _run(() async {
      final repo = ref.read(walletRepositoryProvider);
      if (approve) {
        await repo.approve(widget.groupId, w.id, note: note);
        _snack('Approved — payout is on its way.');
      } else {
        await repo.reject(widget.groupId, w.id, note: note);
        _snack('Withdrawal rejected.');
      }
      _refetch();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ov = ref.watch(walletOverviewProvider(widget.groupId));
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        title: const Text('Group wallet'),
        actions: [
          if (ov.valueOrNull != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(child: _statusBadge(ov.valueOrNull!, p)),
            ),
        ],
      ),
      body: AsyncView<WalletOverview>(
        value: ov,
        onRetry: _refetch,
        data: (o) => RefreshIndicator(
          onRefresh: () async => _refetch(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: _body(o, p),
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(WalletOverview o, AppPalette p) {
    if (!o.exists) return const SizedBox.shrink();
    final s = o.status ?? '';
    final tone = switch (s) {
      'active' => p.accent,
      'frozen' => p.amber,
      _ => p.muted,
    };
    return SpBadge(s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}', tone: tone);
  }

  List<Widget> _body(WalletOverview o, AppPalette p) {
    // No wallet + plan doesn't include it → upsell.
    if (o.planGated && !o.viewable) {
      return [
        _centered(
          p,
          icon: Icons.workspace_premium_rounded,
          tone: p.amber,
          title: 'The wallet is a paid feature',
          body:
              "Your group's current plan doesn't include the group wallet. Upgrade to sell tickets and collect payments.",
          cta: SpButton(
            label: 'See plans',
            icon: Icons.open_in_new_rounded,
            onTap: () => _openWeb('/groups/${widget.groupId}/upgrade'),
          ),
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
              onTap: () => _openWeb('/groups/${widget.groupId}/wallet/activate'),
            ),
            footnote: 'Bank details are entered on a secure web form. Come back here when done.',
          ),
        ];
      }
      return [_onboardingCard(o, acct, p)];
    }

    final policy = o.policy;
    final acct = o.settlementAccount;
    final pausedByPlan = o.planGated && o.viewable;
    return [
      if (o.testMode)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SpBadge('🧪 Test mode — no real money moves', tone: p.amber),
        ),
      if (o.isFrozen || pausedByPlan)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _notice(
            p,
            pausedByPlan
                ? 'Your plan no longer includes the wallet. Records stay visible; sales and withdrawals are paused until you upgrade.'
                : 'This wallet is paused. Records stay visible; sales and withdrawals are on hold.',
            action: pausedByPlan ? 'See plans' : null,
            onAction: pausedByPlan ? () => _openWeb('/groups/${widget.groupId}/upgrade') : null,
          ),
        ),
      _balanceCard(o, policy, acct, p),
      const SizedBox(height: 14),
      _sectionTitle('Settlement account', p,
          trailing: !o.paused
              ? TextButton(
                  onPressed: () => _openWeb('/groups/${widget.groupId}/wallet/activate'),
                  child: const Text('Replace'),
                )
              : null),
      if (acct == null)
        GlassCard(
          child: Column(children: [
            Text('No bank connected yet.', style: TextStyle(color: p.muted, fontSize: 13)),
            const SizedBox(height: 10),
            SpButton(
              label: 'Connect bank',
              icon: Icons.account_balance_rounded,
              onTap: () => _openWeb('/groups/${widget.groupId}/wallet/activate'),
            ),
          ]),
        )
      else
        _accountCard(acct, o.currency, p),
      const SizedBox(height: 14),
      _withdrawalsSection(p),
      const SizedBox(height: 14),
      _sectionTitle('Activity', p),
      _ledgerSection(o, p),
    ];
  }

  // ── pieces ────────────────────────────────────────────────────────────

  Widget _centered(AppPalette p,
      {required IconData icon,
      required Color tone,
      required String title,
      required String body,
      required Widget cta,
      String? footnote}) {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: tone.withAlpha(38),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: tone, size: 28),
        ),
        const SizedBox(height: 14),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(body,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.45)),
        const SizedBox(height: 16),
        cta,
        if (footnote != null) ...[
          const SizedBox(height: 10),
          Text(footnote,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 11)),
        ],
      ]),
    );
  }

  Widget _notice(AppPalette p, String text, {String? action, VoidCallback? onAction}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(245, 167, 10, 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(245, 167, 10, 0.35)),
      ),
      child: Row(children: [
        Icon(Icons.pause_circle_outline_rounded, size: 18, color: p.amber),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: p.ink, fontSize: 12.5))),
        if (action != null) TextButton(onPressed: onAction, child: Text(action)),
      ]),
    );
  }

  Widget _sectionTitle(String t, AppPalette p, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Text(t.toUpperCase(),
              style: TextStyle(
                  color: p.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ),
        if (trailing != null) trailing,
      ]),
    );
  }

  Widget _onboardingCard(WalletOverview o, PaymentAccount acct, AppPalette p) {
    final prog = o.progress;
    final step = prog?.step ?? (acct.status == 'verifying' ? 'under_review' : 'provide_details');
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
      _ => "You started setup but didn't finish $provider's form. Pick up where you left off — nothing needs re-entering.",
    };
    final steps = <(String, String)>[
      ('Account details', step == 'provide_details' ? 'now' : 'done'),
      (
        'Identity check',
        step == 'verify_identity' ? 'now' : step == 'provide_details' ? 'todo' : 'done'
      ),
      ('$provider review', step == 'under_review' ? 'now' : step == 'ready' ? 'done' : 'todo'),
      ('Payouts on', step == 'ready' ? 'done' : 'todo'),
    ];

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: p.accent.withAlpha(38), shape: BoxShape.circle),
            child: Icon(Icons.account_balance_rounded, color: p.accent, size: 28),
          ),
        ),
        const SizedBox(height: 12),
        Text(headline,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
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
                      fontWeight: s.$2 == 'now' ? FontWeight.w700 : FontWeight.w500)),
            ]),
          ),
        if (due.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('$provider still needs:',
              style: TextStyle(color: p.ink, fontSize: 12.5, fontWeight: FontWeight.w700)),
          for (final d in due)
            Text('• ${d.label}', style: TextStyle(color: p.amber, fontSize: 12.5)),
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
        OutlinedButton.icon(
          onPressed: _busy ? null : _refreshStatus,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh status'),
        ),
      ]),
    );
  }

  Widget _balanceCard(
      WalletOverview o, WithdrawalPolicy? policy, PaymentAccount? acct, AppPalette p) {
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

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(appControlled ? 'AVAILABLE TO WITHDRAW' : 'COLLECTED',
            style: TextStyle(
                color: p.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const SizedBox(height: 4),
        Text(formatMoney(appControlled ? withdrawable : o.collectedMinor, cur, exp),
            style: TextStyle(color: p.ink, fontSize: 30, fontWeight: FontWeight.w900)),
        if (appControlled) ...[
          const SizedBox(height: 10),
          if (policy != null && policy.dayBlocked && policy.nextPayoutDate != null)
            Text('Withdrawals open on ${formatDayYear(policy.nextPayoutDate)}.',
                style: TextStyle(color: p.amber, fontSize: 12))
          else if (policy != null && !policy.withdrawalsEnabled)
            Text('Withdrawals are paused for this group.',
                style: TextStyle(color: p.amber, fontSize: 12)),
          const SizedBox(height: 8),
          SpButton(
            label: 'Withdraw to bank',
            icon: Icons.arrow_outward_rounded,
            expand: true,
            onTap: canWithdraw && !_busy ? () => _withdraw(o) : null,
          ),
        ],
        const SizedBox(height: 14),
        Container(height: 1, color: p.line),
        const SizedBox(height: 12),
        Row(children: [
          _stat('Settled to bank', formatMoney(settled, cur, exp), p),
          _stat('Maturing', formatMoney(held, cur, exp), p, muted: held <= 0),
          _stat('Collected', formatMoney(o.collectedMinor, cur, exp), p),
        ]),
        const SizedBox(height: 10),
        Text(
          appControlled
              ? 'Ticket revenue collects in your wallet at the full price you set — buyers pay the fees on top, and card-processing costs come out of those fees, never out of your balance.'
                  '${policy != null && policy.maturationDays > 0 ? ' Recent revenue matures over ${policy.maturationDays} days so refunds stay covered.' : ''}'
              : "Ticket money settles straight to your connected bank on the provider's schedule — buyers pay a small fee at checkout and SportPadi never holds your funds.",
          style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.45),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Icon(Icons.receipt_long_rounded, size: 14, color: p.muted),
          const SizedBox(width: 6),
          Text('${o.ticketCount} ticket payment${o.ticketCount == 1 ? '' : 's'} to date',
              style: TextStyle(color: p.muted, fontSize: 12)),
        ]),
      ]),
    );
  }

  Widget _stat(String label, String value, AppPalette p, {bool muted = false}) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: muted ? p.muted : p.ink, fontSize: 13.5, fontWeight: FontWeight.w800)),
        Text(label, style: TextStyle(color: p.muted, fontSize: 10.5)),
      ]),
    );
  }

  Widget _accountCard(PaymentAccount a, String currency, AppPalette p) {
    return GlassCard(
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: p.accent.withAlpha(38), borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.account_balance_rounded, color: p.accent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${a.providerLabel}${a.bankName != null ? ' · ${a.bankName}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
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
      ]),
    );
  }

  Widget _withdrawalsSection(AppPalette p) {
    final page = ref.watch(walletWithdrawalsProvider(widget.groupId)).valueOrNull;
    final list = page?.withdrawals ?? const <Withdrawal>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final pending = page!.pending;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionTitle(
          pending.isNotEmpty ? 'Withdrawals · ${pending.length} awaiting approval' : 'Withdrawals',
          p),
      for (final w in list.take(10)) ...[
        _withdrawalCard(w, page.viewerId, p),
        const SizedBox(height: 8),
      ],
    ]);
  }

  Widget _withdrawalCard(Withdrawal w, String? viewerId, AppPalette p) {
    final mine = viewerId != null && w.requestedById == viewerId;
    final alreadyDecided =
        viewerId != null && w.approvals.any((a) => a.approverId == viewerId);
    final tone = switch (w.status) {
      'paid' => p.accent,
      'approved' || 'processing' => const Color(0xFF0EA5E9),
      'pending_approval' => p.amber,
      'rejected' || 'failed' || 'cancelled' => p.danger,
      _ => p.muted,
    };
    final label = switch (w.status) {
      'pending_approval' => 'Awaiting approval',
      'processing' => 'Processing',
      'paid' => 'Paid out',
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      'failed' => 'Failed',
      'cancelled' => 'Cancelled',
      _ => w.status,
    };
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(formatMoney(w.amount, w.currency, w.currencyExponent),
                style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          SpBadge(label, tone: tone),
        ]),
        const SizedBox(height: 2),
        Text(
          '${w.requestedBy != null ? 'Requested by ${mine ? 'you' : w.requestedBy!.name}' : 'Requested'}'
          '${w.createdAt != null ? ' · ${timeAgo(w.createdAt)}' : ''}'
          '${w.reason != null ? '\n"${w.reason}"' : ''}',
          style: TextStyle(color: p.muted, fontSize: 12),
        ),
        if (w.approvals.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final a in w.approvals)
            Text(
              '${a.decision == 'approved' ? '✓ Approved' : '✕ Rejected'} by ${a.approver?.name ?? 'an admin'}'
              '${a.note != null ? ' — "${a.note}"' : ''}',
              style: TextStyle(
                  color: a.decision == 'approved' ? p.accent : p.danger, fontSize: 11.5),
            ),
        ],
        if (w.pendingApproval) ...[
          const SizedBox(height: 10),
          if (mine)
            Text('You requested this — another admin must approve it.',
                style: TextStyle(color: p.muted, fontSize: 12))
          else if (alreadyDecided)
            Text('You have already responded.',
                style: TextStyle(color: p.muted, fontSize: 12))
          else
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _decide(w, false),
                  style: OutlinedButton.styleFrom(foregroundColor: p.danger),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SpButton(
                  label: 'Approve',
                  icon: Icons.check_rounded,
                  expand: true,
                  onTap: _busy ? null : () => _decide(w, true),
                ),
              ),
            ]),
        ],
      ]),
    );
  }

  Widget _ledgerSection(WalletOverview o, AppPalette p) {
    final led = ref.watch(walletLedgerProvider(widget.groupId));
    return led.when(
      loading: () => GlassCard(
          child: Center(
              child: Text('Loading activity…', style: TextStyle(color: p.muted, fontSize: 13)))),
      error: (e, _) => GlassCard(
          child: Center(child: Text('$e', style: TextStyle(color: p.muted, fontSize: 13)))),
      data: (entries) {
        if (entries.isEmpty) {
          return GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text('No activity yet.', style: TextStyle(color: p.muted, fontSize: 13)),
              const SizedBox(height: 2),
              Text('Ticket payments will appear here as they settle.',
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          );
        }
        return Column(children: [
          for (final e in entries) ...[
            GlassCard(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: e.isCredit
                        ? const Color.fromRGBO(16, 185, 129, 0.15)
                        : const Color.fromRGBO(239, 68, 68, 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    e.isCredit ? Icons.south_west_rounded : Icons.north_east_rounded,
                    size: 16,
                    color: e.isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      e.description ?? e.type?.replaceAll('_', ' ') ?? 'Transaction',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    if (e.createdAt != null)
                      Text(timeAgo(e.createdAt), style: TextStyle(color: p.muted, fontSize: 11.5)),
                  ]),
                ),
                Text(
                  '${e.isCredit ? '+' : '−'}${formatMoney(e.amount, o.currency, o.currencyExponent)}',
                  style: TextStyle(
                      color: e.isCredit ? const Color(0xFF10B981) : p.ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700),
                ),
              ]),
            ),
            const SizedBox(height: 6),
          ],
        ]);
      },
    );
  }
}

/// Amount entry for a withdrawal request. Pops with the amount in MINOR units.
class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet({required this.policy, required this.currency, required this.exponent});
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
    if (minor > widget.policy.cappedWithdrawable) {
      return setState(() => _error = 'Amount exceeds what you can withdraw right now');
    }
    Navigator.pop(context, minor);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pol = widget.policy;
    final cur = widget.currency;
    final exp = widget.exponent;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Withdraw to bank',
            style: TextStyle(color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: p.surface2, borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            _kv('Available now', formatMoney(pol.withdrawableMinor, cur, exp), p),
            if (pol.heldMinor > 0)
              _kv('Maturing (${pol.maturationDays} days)', formatMoney(pol.heldMinor, cur, exp), p),
            if (pol.periodRemainingMinor != null)
              _kv('Left this ${pol.periodDays}-day period',
                  formatMoney(pol.periodRemainingMinor!, cur, exp), p),
          ]),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Amount',
            prefixText: '$cur ',
            errorText: _error,
            suffixIcon: TextButton(
              onPressed: () => setState(() {
                _amount.text =
                    (pol.cappedWithdrawable / _pow10(exp)).toStringAsFixed(exp);
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
        SpButton(label: 'Request withdrawal', icon: Icons.arrow_outward_rounded, expand: true, onTap: _submit),
      ]),
    );
  }

  Widget _kv(String k, String v, AppPalette p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: p.muted, fontSize: 12))),
          Text(v, style: TextStyle(color: p.ink, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
}
