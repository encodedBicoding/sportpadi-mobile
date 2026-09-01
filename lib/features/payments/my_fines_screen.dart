import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/payments/payments_repository.dart';
import 'package:sportpadi_mobile/features/payments/checkout_flow.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// My fines — active ones can be settled via hosted checkout.
class MyFinesScreen extends ConsumerWidget {
  const MyFinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final fines = ref.watch(myFinesProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('My fines',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(myFinesProvider.future),
        child: AsyncView(
          value: fines,
          onRetry: () => ref.invalidate(myFinesProvider),
          data: (list) {
            if (list.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 120),
                Center(
                  child: Text('No fines. Keep it that way 🤝',
                      style: TextStyle(color: p.muted)),
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _FineRow(fine: list[i]),
            );
          },
        ),
      ),
    );
  }
}

class _FineRow extends ConsumerStatefulWidget {
  const _FineRow({required this.fine});
  final Fine fine;

  @override
  ConsumerState<_FineRow> createState() => _FineRowState();
}

class _FineRowState extends ConsumerState<_FineRow> {
  bool _busy = false;

  Future<void> _pay() async {
    setState(() => _busy = true);
    try {
      final url = await ref
          .read(paymentsRepositoryProvider)
          .startFineCheckout(widget.fine.id);
      if (!mounted) return;
      final done = await runHostedCheckout(context, url);
      if (done) ref.invalidate(myFinesProvider);
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
    final f = widget.fine;
    final tone = f.status == 'paid'
        ? p.accent
        : f.status == 'pardoned'
            ? p.muted
            : p.danger;
    return GlassCard(
      child: Row(children: [
        Icon(Icons.gavel_rounded, color: tone),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(f.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              Text(
                [
                  if (f.groupName != null) f.groupName!,
                  formatMoney(f.amountMinor, f.currency, f.currencyExponent),
                  if (f.createdAt != null) timeAgo(f.createdAt),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (f.isActive)
          _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : SpButton(label: 'Pay', onTap: _pay)
        else
          SpBadge(f.status.toUpperCase(), tone: tone),
      ]),
    );
  }
}
