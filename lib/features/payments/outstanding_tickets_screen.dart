import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/payments/payments_repository.dart';
import 'package:sportpadi_mobile/features/payments/checkout_flow.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';

/// Tickets the viewer still owes one group — pay one or all (web
/// /groups/[id]/tickets/outstanding).
class OutstandingTicketsScreen extends ConsumerStatefulWidget {
  const OutstandingTicketsScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<OutstandingTicketsScreen> createState() =>
      _OutstandingTicketsScreenState();
}

class _OutstandingTicketsScreenState
    extends ConsumerState<OutstandingTicketsScreen> {
  bool _busy = false;

  Future<void> _pay(List<String> ids) async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(paymentsRepositoryProvider);
      final co = ids.length == 1
          ? await repo.startCheckout(ids.first)
          : await repo.startBulkCheckout(ids);
      if (!mounted) return;
      final done = await runHostedCheckout(context, co.url);
      if (done && co.code.isNotEmpty) {
        final status = await repo.verify(co.code);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(status == 'paid'
                ? 'Payment confirmed ✅'
                : 'Payment $status — pull to refresh in a moment.')));
        ref.invalidate(outstandingTicketsProvider(widget.groupId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sum = ref.watch(outstandingTicketsProvider(widget.groupId));
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Outstanding tickets',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.refresh(outstandingTicketsProvider(widget.groupId).future),
        child: AsyncView(
          value: sum,
          onRetry: () =>
              ref.invalidate(outstandingTicketsProvider(widget.groupId)),
          data: (s) {
            if (s.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 120),
                Center(
                  child: Text('All settled 🎉',
                      style: TextStyle(color: p.muted)),
                ),
              ]);
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final t in s.outstanding)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GlassCard(
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                              Text(
                                [
                                  formatMoney(
                                      t.priceMinor, s.currency, s.currencyExponent),
                                  if (t.mandatory)
                                    'required to check in',
                                  if (t.eventTitle != null)
                                    t.eventTitle!,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: p.muted, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SpButton(
                          label: 'Pay',
                          onTap: _busy ? null : () => _pay([t.id]),
                        ),
                      ]),
                    ),
                  ),
                if (s.outstanding.length > 1)
                  SpButton(
                    label:
                        'Pay all (${formatMoney(s.outstanding.fold<int>(0, (a, t) => a + t.priceMinor), s.currency, s.currencyExponent)} + fees)',
                    expand: true,
                    onTap: _busy
                        ? null
                        : () =>
                            _pay(s.outstanding.map((t) => t.id).toList()),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
