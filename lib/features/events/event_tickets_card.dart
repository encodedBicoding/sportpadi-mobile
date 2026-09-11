import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/payments/payments_repository.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/features/payments/checkout_flow.dart';
import 'package:sportpadi_mobile/features/payments/recipient_sheet.dart';
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

  /// Single ticket: ask who it's for (self and/or others), then check out.
  Future<void> _paySingle(EventTicket t) async {
    final recipients = await showRecipientSheet(
      context,
      priceMinor: t.priceMinor,
      feeMinor: t.feeMinor,
      currency: t.currency,
      exponent: t.currencyExponent,
      maxTotal: t.remaining,
      selfPaid: t.paid,
    );
    if (recipients == null || recipients.isEmpty) return;
    await _checkout(() => ref
        .read(paymentsRepositoryProvider)
        .startCheckout(t.id, recipientIds: recipients));
  }

  Future<void> _pay(List<String> ids) async {
    await _checkout(() {
      final repo = ref.read(paymentsRepositoryProvider);
      return ids.length == 1
          ? repo.startCheckout(ids.first)
          : repo.startBulkCheckout(ids);
    });
  }

  Future<void> _follow(String groupId) async {
    setState(() => _busy = true);
    try {
      await ref.read(eventsRepositoryProvider).setFollow(groupId, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                "Following — this group's events now show on your home page.")));
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

  Future<void> _checkout(
      Future<({String url, String code})> Function() start) async {
    setState(() => _busy = true);
    try {
      final co = await start();
      if (!mounted) return;
      final done = await runHostedCheckout(context, co.url);
      if (done && co.code.isNotEmpty) {
        final status =
            await ref.read(paymentsRepositoryProvider).verify(co.code);
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
    // Price sum only — the fees line shows on the provider's checkout page.
    final payAllPrice =
        payableRequired.fold<int>(0, (a, t) => a + t.priceMinor);

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
                onPay: () => _paySingle(t),
              ),
              const SizedBox(height: 8),
            ],
            // Holder outside the group → urge a follow so this event stays
            // on their home page.
            if (data.viewerRelation == 'none' &&
                data.groupId != null &&
                data.tickets.any((t) => t.paid)) ...[
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: const Color.fromRGBO(23, 166, 94, 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: const Color.fromRGBO(23, 166, 94, 0.30)),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      "You've got a ticket here 🎟 Follow ${data.groupName ?? 'this group'} so this event always shows on your home page.",
                      style: TextStyle(color: p.ink, fontSize: 12, height: 1.4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SpButton(
                    label: 'Follow',
                    icon: Icons.favorite_rounded,
                    onTap: _busy ? null : () => _follow(data.groupId!),
                  ),
                ]),
              ),
            ],
            if (payableRequired.length > 1)
              SpButton(
                label:
                    'Pay all required · ${formatMoney(payAllPrice, data.currency, data.currencyExponent)} + fees',
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
                    // Ticket price only — fees appear at the payment step.
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
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  InkWell(
                    onTap: () => context.push('/tickets'),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle_rounded,
                          size: 15, color: p.accent),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text('Paid · view your ticket',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                  // Already covered — but they can still buy for someone else.
                  if (!t.soldOut && !t.closed && !t.notOpenYet) ...[
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: busy ? null : onPay,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: p.line),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.card_giftcard_rounded,
                                  size: 15, color: p.ink),
                              const SizedBox(width: 6),
                              Text('Buy for someone else',
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ])
              else if (t.canBuy)
                SpButton(
                  label: 'Buy ticket',
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
    // Ticket PRICE only — fees show up at the payment step, not here.
    int? cheapest;
    for (final t in data.tickets) {
      if (cheapest == null || t.priceMinor < cheapest) cheapest = t.priceMinor;
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
