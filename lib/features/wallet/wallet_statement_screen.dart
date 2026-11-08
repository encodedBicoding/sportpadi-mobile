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
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

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

  static Map<String, String> get _kind => {
        'ticket': l10n.wallet_ticket2,
        'fine': l10n.wallet_fine,
        'tournament_fee': l10n.wallet_tournamentEntry,
        'league_fee': l10n.wallet_leagueEntry,
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
          Text(context.l10n.wallet_statement, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
                  Text(context.l10n.wallet_month2, style: TextStyle(color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
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
                      Expanded(child: _stat(context.l10n.wallet_collected, money(s.grossMinor), p)),
                      Expanded(child: _stat(context.l10n.wallet_sportPadiNet, money(s.netMinor), p)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _stat(context.l10n.wallet_cardProcessing, money(s.processorMinor), p)),
                      Expanded(child: _stat(context.l10n.wallet_youReceived, money(s.groupMinor), p, strong: true)),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      context.l10n.wallet_countPluralOnePaymentFees(s.count, money(s.feeMinor), (s.unrecorded > 0 ? ' · ${s.unrecorded} from before fee breakdowns were recorded show the whole fee without the split' : '')),
                      style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
                    ),
                    for (final c in s.rateChanges) ...[
                      const SizedBox(height: 6),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: p.orangeInk),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            context.l10n.wallet_yourRateChangedOnEach(fmtEffectiveDay(c.at), c.fromBps == null ? 'platform rate' : fmtBps(c.fromBps!), c.toBps == null ? 'platform rate' : fmtBps(c.toBps!)),
                            style: TextStyle(color: p.orangeInk, fontSize: 12, height: 1.35),
                          ),
                        ),
                      ]),
                    ],
                  ]),
                ),
                const SizedBox(height: 12),

                if (s.lines.isEmpty)
                  SpEmpty(
                    icon: Icons.receipt_long_rounded,
                    title: context.l10n.wallet_noPaymentsThisMonth,
                    text: context.l10n.wallet_paymentsYouCollectShowUp,
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
                              Text(context.l10n.wallet_youReceived2, style: TextStyle(color: p.muted, fontSize: 11)),
                            ]),
                          ]),
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            SpBadge(context.l10n.wallet_price2(money(l.priceMinor, l.exponent, l.currency))),
                            SpBadge(context.l10n.wallet_feePaidBy(money(l.feeMinor, l.exponent, l.currency), (l.bearer == 'group' ? context.l10n.wallet_you : context.l10n.wallet_buyer))),
                            if (l.netMinor != null && l.processorMinor != null)
                              SpBadge(
                                context.l10n.wallet_sportPadiProcessing(money(l.netMinor!, l.exponent, l.currency), money(l.processorMinor!, l.exponent, l.currency), (l.rateBps != null ? ' · ${fmtBps(l.rateBps!)}${l.rateSource == 'default' ? ' platform rate' : l.tierName != null ? ' ${l.tierName} rate' : ''}' : '')),
                                tone: p.accent,
                              )
                            else
                              SpBadge(context.l10n.wallet_breakdownNotRecorded),
                            if (l.refunded) SpBadge(context.l10n.wallet_refunded3, tone: p.amber),
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
