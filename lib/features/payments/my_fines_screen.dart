import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/payments/payments_repository.dart';
import 'package:sportpadi_mobile/features/payments/checkout_flow.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';

/// My fines (2026) — what's owed up top, then the list by state; active
/// ones are settled via hosted checkout. My wards' fines are listed too
/// ("Ward · Tobi"): any of their guardians may pay them (Wards 3).
class MyFinesScreen extends ConsumerStatefulWidget {
  const MyFinesScreen({super.key});

  @override
  ConsumerState<MyFinesScreen> createState() => _MyFinesScreenState();
}

class _MyFinesScreenState extends ConsumerState<MyFinesScreen> {
  String _filter = 'active'; // active | paid | pardoned

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fines = ref.watch(myFinesProvider);
    final all = fines.valueOrNull ?? const <Fine>[];
    final open = all.where((f) => f.isActive).toList();
    int count(String s) => all.where((f) => f.status == s).length;
    // One currency is the norm; if fines span several, don't sum across them.
    final currencies = open.map((f) => f.currency).toSet();
    final owed = currencies.length == 1
        ? formatMoney(open.fold<int>(0, (a, f) => a + f.amountMinor),
            open.first.currency, open.first.currencyExponent)
        : null;

    Widget chip(String key, String label, int n) {
      final active = _filter == key;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: active ? p.hero : p.surface,
          shape: StadiumBorder(
              side: active ? BorderSide.none : BorderSide(color: p.line)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => setState(() => _filter = key),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(n > 0 ? '$label · $n' : label,
                  style: TextStyle(
                      color: active ? p.onHero : p.ink,
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600)),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(title: 'My fines'),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.refresh(myFinesProvider.future),
              child: AsyncView(
                value: fines,
                onRetry: () => ref.invalidate(myFinesProvider),
                data: (list) {
                  final shown = list.where((f) => f.status == _filter).toList();
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
                    children: [
                      // What you owe right now.
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: open.isEmpty ? p.accentTint : p.hero,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Row(children: [
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(open.isEmpty ? 'All clear' : 'You owe',
                                      style: TextStyle(
                                          color: open.isEmpty
                                              ? p.greenText
                                              : p.heroMuted,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(
                                      open.isEmpty
                                          ? 'No unpaid fines'
                                          : owed ??
                                              '${open.length} unpaid fines',
                                      style: TextStyle(
                                          color:
                                              open.isEmpty ? p.ink : p.onHero,
                                          fontSize: open.isEmpty ? 20 : 30,
                                          letterSpacing: -0.5,
                                          fontWeight: FontWeight.w800)),
                                  if (open.isNotEmpty)
                                    Text(
                                        '${open.length} unpaid fine${open.length == 1 ? '' : 's'}',
                                        style: const TextStyle(
                                            color: Color(0xFFFFB57D),
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600)),
                                  if (open.isEmpty)
                                    Text('Keep it that way.',
                                        style: TextStyle(
                                            color: p.muted, fontSize: 12.5)),
                                ]),
                          ),
                          SpIconTile(
                            open.isEmpty
                                ? Icons.verified_rounded
                                : Icons.error_outline_rounded,
                            bg: open.isEmpty
                                ? p.surface
                                : p.onHero.withAlpha(24),
                            fg: open.isEmpty
                                ? p.greenText
                                : const Color(0xFFFFB57D),
                            size: 52,
                            iconSize: 26,
                          ),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 38,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            chip('active', 'Unpaid', count('active')),
                            chip('paid', 'Paid', count('paid')),
                            chip('pardoned', 'Pardoned', count('pardoned')),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (shown.isEmpty)
                        GlassCard(
                          padding: const EdgeInsets.all(22),
                          child: Column(children: [
                            const SpIconTile(Icons.inbox_outlined,
                                size: 50, iconSize: 24),
                            const SizedBox(height: 10),
                            Text(
                                _filter == 'active'
                                    ? 'Nothing to pay.'
                                    : _filter == 'paid'
                                        ? 'No paid fines yet.'
                                        : 'No pardoned fines.',
                                style: TextStyle(color: p.muted, fontSize: 13)),
                          ]),
                        )
                      else
                        for (final f in shown) ...[
                          _FineRow(fine: f),
                          const SizedBox(height: 12),
                        ],
                    ],
                  );
                },
              ),
            ),
          ),
        ]),
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
    final sub = [
      if (f.groupName != null) f.groupName!,
      if (f.createdAt != null) 'issued ${timeAgo(f.createdAt)}',
    ].join(' · ');
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          SpIconTile(
            f.isActive ? Icons.error_outline_rounded : Icons.check_rounded,
            bg: f.isActive
                ? p.orangeTint
                : f.status == 'paid'
                    ? p.accentTint
                    : p.surface2,
            fg: f.isActive
                ? p.orangeInk
                : f.status == 'paid'
                    ? p.greenText
                    : p.muted,
            size: 46,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
                if (sub.isNotEmpty)
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 12)),
                if (f.forWard case final ward?) ...[
                  const SizedBox(height: 6),
                  WardForChip(ward.firstName),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(formatMoney(f.amountMinor, f.currency, f.currencyExponent),
                style: TextStyle(
                    color: p.ink, fontWeight: FontWeight.w800, fontSize: 15)),
            if (!f.isActive)
              Text(f.status == 'paid' ? 'PAID' : 'PARDONED',
                  style: TextStyle(
                      color: f.status == 'paid' ? p.greenText : p.muted,
                      fontSize: 10.5,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w800)),
          ]),
        ]),
        if (f.isActive) ...[
          const SizedBox(height: 14),
          SpButton(
            label: _busy
                ? 'Opening checkout…'
                : f.forWard == null
                    ? 'Pay fine'
                    : 'Pay for ${f.forWard!.firstName}',
            icon: Icons.lock_outline_rounded,
            expand: true,
            onTap: _busy ? null : _pay,
          ),
        ],
      ]),
    );
  }
}
