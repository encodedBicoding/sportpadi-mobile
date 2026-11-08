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
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

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
        ? ' ${context.l10n.wallet_yourWalletComesFromA(d.tierName!)}'
        : '';
    final who = d.bearer == 'group'
        ? context.l10n.wallet_yourGroupPaysIt
        : context.l10n.wallet_buyersPayItOnTop;
    final example = d.processorProvider != null
        ? context.l10n.wallet_feeWorkedExample(
                money(d.examplePrice),
                money(d.exampleBuyerPays),
                money(d.exampleGroupReceives),
                money(d.exampleFee),
                d.processorProvider!,
                fmtBps(d.processorBps),
                d.processorFixedMinor > 0
                    ? ' + ${money(d.processorFixedMinor)}'
                    : '',
                money(d.exampleProcessor),
                money(d.exampleNet)) +
            (d.maxFeeBps > 0 && d.bearer == 'buyer'
                ? ' ${context.l10n.wallet_theBuyersFeeIsCappedAt(fmtBps(d.maxFeeBps))}'
                : '')
        : context.l10n.wallet_cardProcessingIsAddedOnce;

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SpIconTile(Icons.percent_rounded, size: 40, iconSize: 20, bg: p.accentTint, fg: p.greenText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(context.l10n.wallet_yourFee,
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
                child: Text(context.l10n.wallet_yourFeeNothingChangesBefore(d.pending!.phrase),
                    style: TextStyle(color: p.orangeInk, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ],
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => context.push('/groups/$groupId/wallet/statement'),
          icon: const Icon(Icons.receipt_long_rounded, size: 16),
          label: Text(context.l10n.wallet_monthlyStatementEveryPaymentAnd),
          style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: p.greenText),
        ),
      ]),
    );
  }
}
