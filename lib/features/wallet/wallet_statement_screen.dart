import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart'
    show formatMoney;
import 'package:sportpadi_mobile/data/wallet/fee_terms.dart';
import 'package:sportpadi_mobile/data/wallet/wallet_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_page_bits.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Monthly statement (web twin: groups/[id]/wallet/statement): every payment
/// the group took that month with the fee it was charged under — gross,
/// SportPadi's net, card processing, what the group received. Read-only;
/// the CSV download lives on the web.
class WalletStatementScreen extends ConsumerStatefulWidget {
  const WalletStatementScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<WalletStatementScreen> createState() => _WalletStatementScreenState();
}

class _WalletStatementScreenState extends ConsumerState<WalletStatementScreen> {
  String? _month;

  static const _kind = {
    'ticket': 'Ticket',
    'fine': 'Fine',
    'tournament_fee': 'Tournament entry',
    'league_fee': 'League entry',
  };

  StatementKey get _key => (groupId: widget.groupId, month: _month);

  Future<void> _refresh() {
    ref.invalidate(walletStatementProvider(_key));
    return settleAll([ref.read(walletStatementProvider(_key).future)]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final group = ref.watch(groupProvider(widget.groupId)).valueOrNull;
    final q = ref.watch(walletStatementProvider(_key));

    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Statement', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (group != null) Text(group.name, style: TextStyle(color: p.muted, fontSize: 11.5)),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: AsyncView(
          value: q,
          onRetry: () => ref.invalidate(walletStatementProvider(_key)),
          data: (s) {
            String money(int v, [int? e, String? c]) => formatMoney(v, c ?? s.currency ?? 'USD', e ?? s.exponent);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // Month picker
                Row(children: [
                  Text('MONTH', style: TextStyle(color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  const SizedBox(width: 10),
                  DropdownButton<String>(
                    value: s.months.contains(s.month) ? s.month : (s.months.isNotEmpty ? s.months.first : null),
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final m in s.months)
                        DropdownMenuItem(value: m, child: Text(statementMonthLabel(m), style: TextStyle(color: p.ink, fontWeight: FontWeight.w700, fontSize: 13.5))),
                    ],
                    onChanged: (m) => setState(() => _month = m),
                  ),
                ]),
                const SizedBox(height: 8),

                // Totals
                GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(statementMonthLabel(s.month).toUpperCase(),
                        style: TextStyle(color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _stat('Collected', money(s.grossMinor), p)),
                      Expanded(child: _stat('SportPadi net', money(s.netMinor), p)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _stat('Card processing', money(s.processorMinor), p)),
                      Expanded(child: _stat('You received', money(s.groupMinor), p, strong: true)),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      '${s.count} payment${s.count == 1 ? '' : 's'} · fees ${money(s.feeMinor)} in total'
                      '${s.unrecorded > 0 ? ' · ${s.unrecorded} from before fee breakdowns were recorded show the whole fee without the split' : ''}.',
                      style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
                    ),
                    for (final c in s.rateChanges) ...[
                      const SizedBox(height: 6),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: p.orangeInk),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Your rate changed on ${fmtEffectiveDay(c.at)}: ${c.fromBps == null ? 'platform rate' : fmtBps(c.fromBps!)} → ${c.toBps == null ? 'platform rate' : fmtBps(c.toBps!)}. Each payment below shows the rate it was charged.',
                            style: TextStyle(color: p.orangeInk, fontSize: 12, height: 1.35),
                          ),
                        ),
                      ]),
                    ],
                  ]),
                ),
                const SizedBox(height: 12),

                if (s.lines.isEmpty)
                  const SpEmpty(
                    icon: Icons.receipt_long_rounded,
                    title: 'No payments this month',
                    text: 'Payments you collect show up here with the fee on each one.',
                  )
                else
                  for (final l in s.lines) ...[
                    Opacity(
                      opacity: l.refunded ? 0.6 : 1,
                      child: GlassCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(l.description, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(
                                  '${_day(l.at)} · ${_kind[l.kind] ?? l.kind}'
                                  '${l.payerName != null ? ' · ${l.payerName}' : ''}'
                                  '${l.reference != null ? ' · ${l.reference}' : ''}',
                                  style: TextStyle(color: p.muted, fontSize: 12),
                                ),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(money(l.groupMinor, l.exponent, l.currency),
                                  style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
                              Text('you received', style: TextStyle(color: p.muted, fontSize: 11)),
                            ]),
                          ]),
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            SpBadge('price ${money(l.priceMinor, l.exponent, l.currency)}'),
                            SpBadge('fee ${money(l.feeMinor, l.exponent, l.currency)} · paid by ${l.bearer == 'group' ? 'you' : 'buyer'}'),
                            if (l.netMinor != null && l.processorMinor != null)
                              SpBadge(
                                'SportPadi ${money(l.netMinor!, l.exponent, l.currency)} · processing ${money(l.processorMinor!, l.exponent, l.currency)}'
                                '${l.rateBps != null ? ' · ${fmtBps(l.rateBps!)}${l.rateSource == 'default' ? ' platform rate' : l.tierName != null ? ' ${l.tierName} rate' : ''}' : ''}',
                                tone: p.accent,
                              )
                            else
                              const SpBadge('breakdown not recorded'),
                            if (l.refunded) SpBadge('refunded', tone: p.amber),
                          ]),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stat(String label, String value, AppPalette p, {bool strong = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: TextStyle(color: p.ink, fontSize: strong ? 18 : 16, fontWeight: FontWeight.w800)),
      Text(label, style: TextStyle(color: p.muted, fontSize: 11.5)),
    ]);
  }

  static String _day(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final l = d.toLocal();
    return '${m[l.month - 1]} ${l.day}';
  }
}
