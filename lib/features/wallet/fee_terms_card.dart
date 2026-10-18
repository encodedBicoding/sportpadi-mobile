import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart'
    show formatMoney;
import 'package:sportpadi_mobile/data/wallet/fee_terms.dart';
import 'package:sportpadi_mobile/data/wallet/wallet_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/info_tip.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// "Your fee" — what this group pays SportPadi on every payment it collects,
/// where the rate comes from (its plan, or the platform rate), card
/// processing on top, who pays it, a worked example and any scheduled change
/// (web twin: components/groups/FeeTermsCard.tsx; same numbers from
/// groupWallet.feeTerms). Links to the monthly statement.
class FeeTermsCard extends ConsumerWidget {
  const FeeTermsCard({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final d = ref.watch(feeTermsProvider(groupId)).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    String money(int v) => formatMoney(v, d.currency ?? 'USD', d.exponent);
    final via = d.walletVia == 'promo' && d.tierName != null
        ? ' — your wallet comes from a promo code, and the fee follows your ${d.tierName} plan, not the code'
        : '';
    final who = d.bearer == 'group' ? 'your group pays it' : 'buyers pay it on top';
    final example = d.processorProvider != null
        ? 'On a ${money(d.examplePrice)} payment the buyer pays ${money(d.exampleBuyerPays)} and you receive ${money(d.exampleGroupReceives)}. '
            'Of the ${money(d.exampleFee)} fee, card processing (${d.processorProvider}, ${fmtBps(d.processorBps)}'
            '${d.processorFixedMinor > 0 ? ' + ${money(d.processorFixedMinor)}' : ''}) takes about ${money(d.exampleProcessor)} and SportPadi keeps ${money(d.exampleNet)}.'
            '${d.maxFeeBps > 0 && d.bearer == 'buyer' ? " The buyer's fee is capped at ${fmtBps(d.maxFeeBps)} of the price." : ''}'
        : 'Card processing is added once your bank is connected — the exact rate depends on the provider that settles your sales.';

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SpIconTile(Icons.percent_rounded, size: 40, iconSize: 20, bg: p.accentTint, fg: p.greenText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('YOUR FEE',
                    style: TextStyle(color: p.muted, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const SizedBox(width: 4),
                // The worked example, as a tooltip.
                SpInfoTip(example, size: 13, color: p.muted),
              ]),
              const SizedBox(height: 2),
              Text(feePhrase(d.netBps),
                  style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text('${feeSourcePhrase(d.source, d.tierName)}$via · $who',
                  style: TextStyle(color: p.muted, fontSize: 12, height: 1.35)),
            ]),
          ),
          if (d.tierName != null) SpBadge(d.tierName!, tone: d.source == 'tier' ? p.accent : null),
        ]),
        if (d.pending != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: p.orangeTint, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(Icons.event_rounded, size: 14, color: p.orangeInk),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Your fee ${d.pending!.phrase}. Nothing changes before then.',
                    style: TextStyle(color: p.orangeInk, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => context.push('/groups/$groupId/wallet/statement'),
          icon: const Icon(Icons.receipt_long_rounded, size: 16),
          label: const Text('Monthly statement — every payment and its fee'),
          style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: p.greenText),
        ),
      ]),
    );
  }
}
