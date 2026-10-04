import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/payments/payments_repository.dart';
import 'package:sportpadi_mobile/data/wards/ward_models.dart';
import 'package:sportpadi_mobile/data/wards/wards_repository.dart';
import 'package:sportpadi_mobile/features/payments/checkout_flow.dart';
import 'package:sportpadi_mobile/shared/format/ticket_validity.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';

/// Tickets the viewer still owes one group — pay one or all (web
/// /groups/[id]/tickets/outstanding). A guardian can switch to one of their
/// wards ("For: Me · Tobi"): they pay, the ward holds the tickets (Wards 3).
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

  /// Whose tickets: null = mine, else one of my wards.
  String? _forPlayerId;

  OutstandingKey get _key =>
      (groupId: widget.groupId, forPlayerId: _forPlayerId);

  Future<void> _pay(List<String> ids, {String? wardName}) async {
    final forPlayerId = _forPlayerId;
    final key = _key;
    setState(() => _busy = true);
    try {
      final repo = ref.read(paymentsRepositoryProvider);
      // A ward's tickets always go through the consolidated checkout — it's
      // the call that knows who holds them.
      final co = forPlayerId != null
          ? await repo.startBulkCheckout(ids, forPlayerId: forPlayerId)
          : ids.length == 1
              ? await repo.startCheckout(ids.first)
              : await repo.startBulkCheckout(ids);
      if (!mounted) return;
      final done = await runHostedCheckout(context, co.url);
      if (done && co.code.isNotEmpty) {
        final status = await repo.verify(co.code);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(status == 'paid'
                ? (wardName == null
                    ? 'Payment confirmed ✅'
                    : 'Payment confirmed ✅ — $wardName holds the tickets.')
                : 'Payment $status — pull to refresh in a moment.')));
        ref.invalidate(outstandingTicketsProvider(key));
        ref.invalidate(myTicketsProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
        // e.g. "That cycle has ended — a new one is on sale. Reload to buy
        // it.": reload so the new cycle shows.
        ref.invalidate(outstandingTicketsProvider(key));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A recurring ticket's cycle: a NEXT cycle already on presale says when
  /// it starts; otherwise how long this cycle admits you. Null for one-time.
  ({String text, bool next})? _cycleLine(OutstandingTicket t) {
    final from = t.validFrom;
    if (from != null && isFutureInstant(from)) {
      return (text: 'Next cycle · starts ${shortDay(from)}', next: true);
    }
    final range = validityRange(t.validFrom, t.validUntil);
    return range == null ? null : (text: 'Valid $range', next: false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final wards =
        ref.watch(myWardsProvider).valueOrNull?.wards ?? const <Ward>[];
    final picked = _forPlayerId;
    Ward? ward;
    for (final w in wards) {
      if (w.userId == picked) ward = w;
    }
    final sum = ref.watch(outstandingTicketsProvider(_key));
    final wardName = ward?.firstName;
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Outstanding tickets',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        if (wards.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              Text('For',
                  style: TextStyle(
                      color: p.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: SpSegmented(
                  options: ['Me', for (final w in wards) w.firstName],
                  index: ward == null ? 0 : 1 + wards.indexOf(ward),
                  onChanged: (i) {
                    if (_busy) return;
                    setState(() =>
                        _forPlayerId = i == 0 ? null : wards[i - 1].userId);
                  },
                ),
              ),
            ]),
          ),
        Expanded(
          child: RefreshIndicator(
            // Pullable in every state; a pull refetches the tickets and the
            // wards behind the "For" switch, and the spinner stays until
            // they're back.
            onRefresh: () {
              ref.invalidate(outstandingTicketsProvider(_key));
              ref.invalidate(myWardsProvider);
              return settleAll([
                ref.read(outstandingTicketsProvider(_key).future),
                ref.read(myWardsProvider.future),
              ]);
            },
            child: sum.maybeWhen(
              orElse: () => PullableState(
                child: AsyncView(
                  value: sum,
                  onRetry: () =>
                      ref.invalidate(outstandingTicketsProvider(_key)),
                  data: (_) => const SizedBox.shrink(),
                ),
              ),
              data: (s) {
                if (s.isEmpty) {
                  return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                    const SizedBox(height: 120),
                    Center(
                      child: Text(
                          wardName == null
                              ? 'All settled 🎉'
                              : '$wardName is all settled 🎉',
                          style: TextStyle(color: p.muted)),
                    ),
                  ]);
                }
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (wardName != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          "You pay, $wardName holds the tickets — their QR "
                          'shows under your purchases.',
                          style: TextStyle(color: p.muted, fontSize: 12.5),
                        ),
                      ),
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
                                      formatMoney(t.priceMinor, s.currency,
                                          s.currencyExponent),
                                      if (t.mandatory) 'required to check in',
                                      if (t.eventTitle != null) t.eventTitle!,
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.muted, fontSize: 11.5),
                                  ),
                                  if (_cycleLine(t) case final c?)
                                    Text(
                                      c.text,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: c.next ? p.greenText : p.muted,
                                          fontSize: 11.5,
                                          fontWeight: c.next
                                              ? FontWeight.w700
                                              : FontWeight.w400),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SpButton(
                              label: 'Pay',
                              onTap: _busy
                                  ? null
                                  : () => _pay([t.id], wardName: wardName),
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
                            : () => _pay(
                                s.outstanding.map((t) => t.id).toList(),
                                wardName: wardName),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}
