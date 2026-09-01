import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/payments/payments_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// My purchases — paid tickets, each opening its gate QR.
class MyTicketsScreen extends ConsumerWidget {
  const MyTicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tickets = ref.watch(myTicketsProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('My purchases',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(myTicketsProvider.future),
        child: AsyncView(
          value: tickets,
          onRetry: () => ref.invalidate(myTicketsProvider),
          data: (list) {
            if (list.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 120),
                Center(
                  child: Text('No purchases yet.',
                      style: TextStyle(color: p.muted)),
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _TicketRow(ticket: list[i]),
            );
          },
        ),
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket});
  final MyTicket ticket;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = ticket;
    return GlassCard(
      onTap: () => _showQr(context),
      child: Row(children: [
        Icon(Icons.confirmation_number_outlined, color: p.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              Text(
                [
                  if (t.groupName != null) t.groupName!,
                  if (t.eventTitle != null) t.eventTitle!,
                  if (t.paidAt != null) 'paid ${timeAgo(t.paidAt)}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(formatMoney(t.amountMinor, t.currency, t.currencyExponent),
            style: TextStyle(
                color: p.ink, fontWeight: FontWeight.w800, fontSize: 13)),
      ]),
    );
  }

  void _showQr(BuildContext context) {
    final p = context.palette;
    final t = ticket;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: p.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t.title,
              style: TextStyle(
                  color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Show this at the gate',
              style: TextStyle(color: p.muted, fontSize: 12)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: QrImageView(
                data: t.code, size: 200, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(t.code,
              style: TextStyle(
                  color: p.muted, fontSize: 11, fontFamily: 'monospace')),
        ]),
      ),
    );
  }
}
