import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart'
    show formatMoney;
import 'package:sportpadi_mobile/data/wallet/wallet_models.dart';
import 'package:sportpadi_mobile/data/wallet/wallet_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/wallet/wallet_tips.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/info_tip.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

DateFormat get _stamp => DateFormat('d MMM, HH:mm');

Map<String, String> get _kEventLabels => <String, String>{
      'requested': l10n.wallet_requested,
      'approved': l10n.wallet_approved,
      'auto_approved': l10n.wallet_autoApprovedSoleAdmin,
      'rejected': l10n.wallet_rejected,
      'ledger_posted': l10n.wallet_walletDebited,
      'payout_initiated': l10n.wallet_payoutInitiated,
      'paid': l10n.wallet_paid,
      'failed': l10n.wallet_failed,
      'cancelled': l10n.wallet_cancelled,
    };

/// The transparent withdrawal log — mirrors the web `/wallet/approvals` page:
/// every request with who asked, who approved or rejected (and their note),
/// the plain-language state, approve/reject for pending ones, and an
/// expandable audit trail. Admin-only (the server enforces it).
class WalletWithdrawalsScreen extends ConsumerStatefulWidget {
  const WalletWithdrawalsScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<WalletWithdrawalsScreen> createState() =>
      _WalletWithdrawalsScreenState();
}

class _WalletWithdrawalsScreenState
    extends ConsumerState<WalletWithdrawalsScreen> {
  String? _busyId;
  final Set<String> _expanded = {};

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _refetch() {
    ref.invalidate(walletWithdrawalsProvider(widget.groupId));
    ref.invalidate(walletOverviewProvider(widget.groupId));
    ref.invalidate(walletLedgerProvider(widget.groupId));
  }

  /// Pull to refresh: the log and the group name in the app bar, holding the
  /// spinner until they're back.
  Future<void> _pullRefresh() {
    _refetch();
    ref.invalidate(groupProvider(widget.groupId));
    return settleAll([
      ref.read(walletWithdrawalsProvider(widget.groupId).future),
      ref.read(groupProvider(widget.groupId).future),
    ]);
  }

  Future<void> _decide(Withdrawal w, bool approve) async {
    final note = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text(approve ? l10n.wallet_approveWithdrawal : l10n.wallet_rejectWithdrawal),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              l10n.wallet_toTheGroupsBank(formatMoney(w.amount, w.currency, w.currencyExponent), (w.requestedBy != null ? ', requested by ${w.requestedBy!.name}' : '')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              maxLength: 280,
              decoration: InputDecoration(labelText: l10n.wallet_noteOptional),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: Text(l10n.wallet_cancel)),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: Text(approve ? l10n.wallet_approve : l10n.wallet_reject),
            ),
          ],
        );
      },
    );
    if (note == null) return;
    setState(() => _busyId = w.id);
    try {
      final repo = ref.read(walletRepositoryProvider);
      if (approve) {
        await repo.approve(widget.groupId, w.id, note: note);
        _snack(l10n.wallet_approvedProcessingThePayout);
      } else {
        await repo.reject(widget.groupId, w.id, note: note);
        _snack(l10n.wallet_withdrawalRejected);
      }
      _refetch();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final group = ref.watch(groupProvider(widget.groupId)).valueOrNull;
    final page = ref.watch(walletWithdrawalsProvider(widget.groupId));
    final pendingCount = page.valueOrNull?.pending.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TipText(context.l10n.wallet_withdrawals,
                tip: WalletTips().withdrawalRequests,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (group != null)
              Text(group.name,
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
          ],
        ),
        actions: [
          if (pendingCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: SpBadge(context.l10n.wallet_pending2(pendingCount), tone: p.amber),
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _pullRefresh,
        // Loading / error aren't scrollable on their own.
        child: _pullable(page, AsyncView(
        value: page,
        onRetry: () =>
            ref.invalidate(walletWithdrawalsProvider(widget.groupId)),
        data: (data) => data.withdrawals.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                  const SizedBox(height: 90),
                  Icon(Icons.fact_check_outlined,
                      size: 44, color: p.muted.withAlpha(120)),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(context.l10n.wallet_noWithdrawalsYet2,
                        style: TextStyle(color: p.muted, fontSize: 13)),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      context.l10n.wallet_everyRequestWillShowUp,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: p.muted.withAlpha(180), fontSize: 11.5),
                    ),
                  ),
                ])
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: data.withdrawals.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) =>
                      _card(data.withdrawals[i], data.viewerId, p),
                ),
        )),
      ),
    );
  }

  /// [child] as is when [value] renders its (scrollable) data branch, else
  /// wrapped so the loader / error can still be pulled.
  Widget _pullable(AsyncValue<Object?> value, Widget child) =>
      value.maybeWhen(
        data: (_) => child,
        orElse: () => PullableState(child: child),
      );

  Widget _card(Withdrawal w, String? viewerId, AppPalette p) {
    final mine = viewerId != null && w.requestedById == viewerId;
    final alreadyDecided =
        viewerId != null && w.approvals.any((a) => a.approverId == viewerId);
    final busy = _busyId == w.id;
    final open = _expanded.contains(w.id);
    const sky = Color(0xFF0EA5E9);
    final tone = switch (w.status) {
      'paid' => p.accent,
      'approved' || 'processing' => sky,
      'pending_approval' => p.amber,
      'rejected' || 'failed' || 'cancelled' => p.danger,
      _ => p.muted,
    };
    final label = switch (w.status) {
      'pending_approval' => context.l10n.wallet_awaitingApproval3,
      'processing' => context.l10n.wallet_processing2,
      'paid' => context.l10n.wallet_paidOut,
      'approved' => context.l10n.wallet_approved,
      'rejected' => context.l10n.wallet_rejected,
      'failed' => context.l10n.wallet_failed,
      'cancelled' => context.l10n.wallet_cancelled,
      _ => w.status,
    };
    final approvedBy = w.approvals
        .where((a) => a.decision == 'approved')
        .map((a) => a.approver?.name ?? context.l10n.wallet_anAdmin)
        .toList();
    final rejectedBy = w.approvals
        .where((a) => a.decision == 'rejected')
        .map((a) => a.approver?.name ?? context.l10n.wallet_anAdmin)
        .toList();
    final at = w.resolvedAt != null ? ' · ${_stamp.format(w.resolvedAt!)}' : '';
    final (String line, Color lineColor) = switch (w.status) {
      'pending_approval' => (
          context.l10n.wallet_awaitingApprovalTheIsLocked(
              formatMoney(w.amount, w.currency, w.currencyExponent)),
          p.amber
        ),
      'paid' => (
          approvedBy.isNotEmpty
              ? context.l10n.wallet_paidOutToTheBankApprovedBy(at, approvedBy.first)
              : context.l10n.wallet_paidOutToTheBankAt(at),
          p.accent
        ),
      'processing' || 'approved' => (
          approvedBy.isNotEmpty
              ? context.l10n.wallet_approvedBySentToTheBank(approvedBy.first, at)
              : context.l10n.wallet_approvedSentToTheBank(at),
          sky
        ),
      'rejected' => (
          context.l10n.wallet_deniedByTheMoneyIs(
              rejectedBy.isNotEmpty ? rejectedBy.first : context.l10n.wallet_anAdmin,
              at),
          p.danger
        ),
      'failed' => (
          context.l10n.wallet_theBankPayoutFailedContact,
          p.danger
        ),
      _ => ('', p.muted),
    };

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(formatMoney(w.amount, w.currency, w.currencyExponent),
                  style: TextStyle(
                      color: p.ink, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                '${w.requestedBy != null ? (mine ? context.l10n.wallet_requestedByYou : context.l10n.wallet_requestedByName(w.requestedBy!.name)) : context.l10n.wallet_requested}'
                '${w.createdAt != null ? ' · ${timeAgo(w.createdAt)}' : ''}',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
              if (w.reference.isNotEmpty)
                Text(context.l10n.wallet_ref(w.reference),
                    style: TextStyle(color: p.muted, fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            SpBadge(label, tone: tone),
            if (WalletTips().withdrawalStatus(w.status) != null)
              SpInfoTip(WalletTips().withdrawalStatus(w.status)!, color: tone),
          ]),
        ]),
        if (line.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(line,
              style: TextStyle(
                  color: lineColor, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
        if (w.reason != null && w.reason!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
                color: p.surface2, borderRadius: BorderRadius.circular(8)),
            child: Text('"${w.reason}"',
                style: TextStyle(color: p.ink, fontSize: 12.5)),
          ),
        ],
        if (w.pendingApproval) ...[
          const SizedBox(height: 10),
          if (mine)
            Row(children: [
              Icon(Icons.schedule_rounded, size: 14, color: p.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    context.l10n.wallet_youRequestedThisAnotherAdmin,
                    style: TextStyle(color: p.muted, fontSize: 12)),
              ),
            ])
          else if (alreadyDecided)
            Text(context.l10n.wallet_youHaveAlreadyResponded,
                style: TextStyle(color: p.muted, fontSize: 12))
          else
            Row(children: [
              Expanded(
                child: SpButton(
                  label: busy ? context.l10n.wallet_working : context.l10n.wallet_approve,
                  icon: Icons.check_rounded,
                  expand: true,
                  onTap: busy ? null : () => _decide(w, true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => _decide(w, false),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: p.danger,
                      side: BorderSide(color: p.danger.withAlpha(110))),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: Text(context.l10n.wallet_reject),
                ),
              ),
            ]),
        ],
        const SizedBox(height: 10),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() {
            if (!_expanded.remove(w.id)) _expanded.add(w.id);
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: p.muted),
              const SizedBox(width: 2),
              Text(context.l10n.wallet_auditTrail2(w.events.length),
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
        ),
        if (open) ...[
          const SizedBox(height: 6),
          Container(height: 1, color: p.line),
          const SizedBox(height: 10),
          for (final ev in w.events) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: p.accent, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_kEventLabels[ev.type] ?? ev.type,
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      Text(
                        '${ev.actor?.name ?? context.l10n.wallet_system}'
                        '${ev.createdAt != null ? ' · ${_stamp.format(ev.createdAt!)}' : ''}',
                        style: TextStyle(color: p.muted, fontSize: 11.5),
                      ),
                      if (ev.note != null && ev.note!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(ev.note!,
                              style: TextStyle(
                                  color: p.ink.withAlpha(180), fontSize: 11.5)),
                        ),
                    ]),
              ),
            ]),
            const SizedBox(height: 10),
          ],
          if (w.approvals.isNotEmpty) ...[
            Container(height: 1, color: p.line),
            const SizedBox(height: 8),
            Text(context.l10n.wallet_decisions2,
                style: TextStyle(
                    color: p.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1)),
            const SizedBox(height: 4),
            for (final a in w.approvals)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(color: p.muted, fontSize: 12),
                    children: [
                      TextSpan(
                          text: a.decision == 'approved'
                              ? context.l10n.wallet_approved
                              : context.l10n.wallet_rejected,
                          style: TextStyle(
                              color: a.decision == 'approved'
                                  ? p.accent
                                  : p.danger,
                              fontWeight: FontWeight.w700)),
                      TextSpan(text: context.l10n.wallet_by2(a.approver?.name ?? context.l10n.wallet_unknown)),
                      if (a.note != null && a.note!.isNotEmpty)
                        TextSpan(text: ' — "${a.note}"'),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ]),
    );
  }
}
