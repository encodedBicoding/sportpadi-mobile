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

final _stamp = DateFormat('d MMM, HH:mm');

const _kEventLabels = <String, String>{
  'requested': 'Requested',
  'approved': 'Approved',
  'auto_approved': 'Auto-approved (sole admin)',
  'rejected': 'Rejected',
  'ledger_posted': 'Wallet debited',
  'payout_initiated': 'Payout initiated',
  'paid': 'Paid',
  'failed': 'Failed',
  'cancelled': 'Cancelled',
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
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: Text(approve ? 'Approve' : 'Reject'),
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
        _snack('Approved — processing the payout.');
      } else {
        await repo.reject(widget.groupId, w.id, note: note);
        _snack('Withdrawal rejected.');
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
            TipText('Withdrawals',
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
                child: SpBadge('$pendingCount pending', tone: p.amber),
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
                    child: Text('No withdrawals yet.',
                        style: TextStyle(color: p.muted, fontSize: 13)),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Every request will show up here with who asked, who decided, and when the payout reached the bank.',
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
      'pending_approval' => 'Awaiting approval',
      'processing' => 'Processing',
      'paid' => 'Paid out',
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      'failed' => 'Failed',
      'cancelled' => 'Cancelled',
      _ => w.status,
    };
    final approvedBy = w.approvals
        .where((a) => a.decision == 'approved')
        .map((a) => a.approver?.name ?? 'an admin')
        .toList();
    final rejectedBy = w.approvals
        .where((a) => a.decision == 'rejected')
        .map((a) => a.approver?.name ?? 'an admin')
        .toList();
    final at = w.resolvedAt != null ? ' · ${_stamp.format(w.resolvedAt!)}' : '';
    final (String line, Color lineColor) = switch (w.status) {
      'pending_approval' => (
          'Awaiting approval — the ${formatMoney(w.amount, w.currency, w.currencyExponent)} is locked and can\'t be spent or re-requested until an admin decides.',
          p.amber
        ),
      'paid' => (
          'Paid out to the bank$at${approvedBy.isNotEmpty ? ' · approved by ${approvedBy.first}' : ''}.',
          p.accent
        ),
      'processing' || 'approved' => (
          '${approvedBy.isNotEmpty ? 'Approved by ${approvedBy.first}' : 'Approved'}$at — sent to the bank, settling now.',
          sky
        ),
      'rejected' => (
          'Denied by ${rejectedBy.isNotEmpty ? rejectedBy.first : 'an admin'}$at — the money is back in the withdrawable balance.',
          p.danger
        ),
      'failed' => (
          'The bank payout failed — contact support; the audit trail below has the details.',
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
                '${w.requestedBy != null ? 'Requested by ${mine ? 'you' : w.requestedBy!.name}' : 'Requested'}'
                '${w.createdAt != null ? ' · ${timeAgo(w.createdAt)}' : ''}',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
              if (w.reference.isNotEmpty)
                Text('Ref ${w.reference}',
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
                    'You requested this — another admin must approve it.',
                    style: TextStyle(color: p.muted, fontSize: 12)),
              ),
            ])
          else if (alreadyDecided)
            Text('You have already responded.',
                style: TextStyle(color: p.muted, fontSize: 12))
          else
            Row(children: [
              Expanded(
                child: SpButton(
                  label: busy ? 'Working…' : 'Approve',
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
                  label: const Text('Reject'),
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
              Text('Audit trail (${w.events.length})',
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
                        '${ev.actor?.name ?? 'System'}'
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
            Text('DECISIONS',
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
                              ? 'Approved'
                              : 'Rejected',
                          style: TextStyle(
                              color: a.decision == 'approved'
                                  ? p.accent
                                  : p.danger,
                              fontWeight: FontWeight.w700)),
                      TextSpan(text: ' by ${a.approver?.name ?? 'Unknown'}'),
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
