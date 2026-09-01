import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/payments/payments_repository.dart';
import 'package:sportpadi_mobile/features/payments/checkout_flow.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

const _recurrenceLabel = {
  'daily': 'per day',
  'weekly': 'per week',
  'monthly': 'per month',
  'yearly': 'per year',
};

/// "Ticketed event" — the tickets tied to an event (plus the group's general
/// check-in passes that gate it): price + fees, sales window, capacity, the
/// viewer's paid state, and a way to pay (single or all-required at once).
/// Renders nothing for an un-ticketed event. Mirrors web's <EventTickets/>.
class EventTicketsCard extends ConsumerStatefulWidget {
  const EventTicketsCard({super.key, required this.eventId});
  final String eventId;

  @override
  ConsumerState<EventTicketsCard> createState() => _EventTicketsCardState();
}

class _EventTicketsCardState extends ConsumerState<EventTicketsCard> {
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
                ? 'Payment confirmed ✅ — you can check in.'
                : 'Payment $status — pull to refresh in a moment.')));
      }
      ref.invalidate(eventTicketsProvider(widget.eventId));
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
    final async = ref.watch(eventTicketsProvider(widget.eventId));
    final data = async.valueOrNull;
    if (data == null || !data.ticketed || data.tickets.isEmpty) {
      return const SizedBox.shrink();
    }
    final required = data.tickets.where((t) => t.required).toList();
    final payableRequired =
        required.where((t) => !t.paid && t.canBuy).toList();
    final allPaid = data.allRequiredPaid;
    final payAllTotal =
        payableRequired.fold<int>(0, (a, t) => a + t.totalMinor);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(23, 166, 94, 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.confirmation_num_rounded,
                    size: 18, color: p.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Ticketed event',
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                        if (required.isNotEmpty)
                          SpBadge(
                            allPaid
                                ? "✓ You're covered"
                                : '🔒 Required to check in',
                            tone: allPaid ? p.accent : p.amber,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      required.isNotEmpty
                          ? "Pay before you scan in — the gate won't let an unpaid ticket through."
                          : 'Optional tickets for this event.',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 10),
            for (final t in data.tickets) ...[
              _TicketRow(
                ticket: t,
                busy: _busy,
                onPay: () => _pay([t.id]),
              ),
              const SizedBox(height: 8),
            ],
            if (payableRequired.length > 1)
              SpButton(
                label:
                    'Pay all required · ${formatMoney(payAllTotal, data.currency, data.currencyExponent)}',
                icon: Icons.confirmation_num_rounded,
                expand: true,
                onTap: _busy
                    ? null
                    : () => _pay(payableRequired.map((t) => t.id).toList()),
              ),
          ],
        ),
      ),
    );
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow(
      {required this.ticket, required this.busy, required this.onPay});
  final EventTicket ticket;
  final bool busy;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = ticket;
    final rec = _recurrenceLabel[t.recurrence];
    final meta = <String>[
      t.required ? 'Required to check in' : 'Optional',
      if (!t.eventSpecific) 'group pass',
      if (t.soldLabel != null) t.soldLabel!,
      if (t.lowStock) 'only ${t.remaining ?? (t.capacity! - t.sold)} left',
      if (t.notOpenYet && t.salesStartAt != null)
        'Sales open ${formatDayYear(t.salesStartAt)}',
      if (!t.notOpenYet && !t.closed && t.salesEndAt != null)
        'Until ${formatDayYear(t.salesEndAt)}',
      if (t.closed) 'Sales closed',
    ];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.paid ? const Color.fromRGBO(23, 166, 94, 0.06) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: t.paid ? const Color.fromRGBO(23, 166, 94, 0.35) : p.line),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (t.flierUrl != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(
              imageUrl: t.flierUrl!,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                      if (t.description != null)
                        Text(t.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: p.muted, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoney(t.priceMinor, t.currency, t.currencyExponent),
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800),
                    ),
                    if (rec != null)
                      Text(rec,
                          style: TextStyle(color: p.muted, fontSize: 10)),
                    if (t.feeMinor > 0)
                      Text(
                        '+ ${formatMoney(t.feeMinor, '', t.currencyExponent).trim()} fees · ${formatMoney(t.totalMinor, '', t.currencyExponent).trim()} total',
                        style: TextStyle(color: p.muted, fontSize: 10),
                      ),
                  ],
                ),
              ]),
              const SizedBox(height: 4),
              Text(meta.join(' · '),
                  style: TextStyle(
                      color: t.soldOut
                          ? const Color(0xFFDC2626)
                          : (t.required && !t.paid) || t.lowStock
                              ? p.amber
                              : p.muted,
                      fontSize: 11)),
              const SizedBox(height: 8),
              if (t.paid)
                InkWell(
                  onTap: () => context.push('/tickets'),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_rounded,
                        size: 15, color: p.accent),
                    const SizedBox(width: 5),
                    Text('Paid · view your ticket',
                        style: TextStyle(
                            color: p.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ]),
                )
              else if (t.canBuy)
                SpButton(
                  label:
                      'Pay ${formatMoney(t.totalMinor, t.currency, t.currencyExponent)}',
                  icon: Icons.confirmation_num_rounded,
                  onTap: busy ? null : onPay,
                )
              else
                Text(
                  t.soldOut
                      ? 'Sold out — all ${t.capacity} bought'
                      : t.notOpenYet
                          ? 'Not on sale yet'
                          : 'Sales closed',
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// One-line "🎟 Ticketed · from NGN 5,000 · required to check in" for the
/// info card. Shares the provider with [EventTicketsCard].
class EventTicketedLine extends ConsumerWidget {
  const EventTicketedLine({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(eventTicketsProvider(eventId)).valueOrNull;
    if (data == null || !data.ticketed || data.tickets.isEmpty) {
      return const SizedBox.shrink();
    }
    final p = context.palette;
    int? cheapest;
    for (final t in data.tickets) {
      if (cheapest == null || t.totalMinor < cheapest) cheapest = t.totalMinor;
    }
    final parts = <String>[
      'Ticketed',
      if (cheapest != null)
        '${data.tickets.length > 1 ? 'from ' : ''}${formatMoney(cheapest, data.currency, data.currencyExponent)}',
    ];
    return InfoRow(
      Icons.confirmation_num_rounded,
      parts.join(' · '),
      trailing: data.anyRequired
          ? Text(
              data.allRequiredPaid ? 'paid ✓' : 'required to check in',
              style: TextStyle(
                  color: data.allRequiredPaid ? p.accent : p.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            )
          : null,
    );
  }
}
