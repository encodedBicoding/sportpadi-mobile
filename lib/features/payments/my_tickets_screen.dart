import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/payments/payments_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';

/// My purchases — paid tickets, each opening its gate QR.
class MyTicketsScreen extends ConsumerWidget {
  const MyTicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tickets = ref.watch(myTicketsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
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
            // Groups the holder neither belongs to nor follows → nudge a
            // follow so their events stay on the home page.
            final unfollowed = <String, String>{};
            for (final t in list) {
              if (t.groupRelation == 'none' &&
                  t.groupId != null &&
                  t.groupName != null) {
                unfollowed[t.groupId!] = t.groupName!;
              }
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final e in unfollowed.entries) ...[
                  _FollowNudge(groupId: e.key, groupName: e.value),
                  const SizedBox(height: 10),
                ],
                for (final t in list) ...[
                  _TicketRow(ticket: t),
                  const SizedBox(height: 10),
                ],
              ],
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
                  if (t.giftedByName != null) '🎁 paid for by ${t.giftedByName}',
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
    final t = ticket;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _LiveTicketSheet(ticket: t),
    );
  }

}

/// "Follow this group so its events show on your home page" — shown when the
/// holder has a ticket from a group they neither belong to nor follow.

class _FollowNudge extends ConsumerStatefulWidget {
  const _FollowNudge({required this.groupId, required this.groupName});
  final String groupId;
  final String groupName;

  @override
  ConsumerState<_FollowNudge> createState() => _FollowNudgeState();
}

class _FollowNudgeState extends ConsumerState<_FollowNudge> {
  bool _busy = false;
  bool _done = false;

  Future<void> _follow() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(eventsRepositoryProvider)
          .setFollow(widget.groupId, true);
      if (mounted) {
        setState(() => _done = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                "Following — their events now show on your home page.")));
      }
      ref.invalidate(myTicketsProvider);
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
    if (_done) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color.fromRGBO(23, 166, 94, 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color.fromRGBO(23, 166, 94, 0.30)),
      ),
      child: Row(children: [
        Expanded(
          child: Text(
            'You have tickets from ${widget.groupName} but don\'t follow them — follow so their events always show on your home page when you log in.',
            style: TextStyle(color: p.ink, fontSize: 12, height: 1.4),
          ),
        ),
        const SizedBox(width: 8),
        SpButton(
          label: 'Follow',
          icon: Icons.favorite_rounded,
          onTap: _busy ? null : _follow,
        ),
      ]),
    );
  }
}

/// The gate QR + full receipt for one ticket. While the ticket is unused this
/// sheet polls, so the moment an organizer scans it the QR flips to a clear
/// "Checked in" state — no refresh needed.
class _LiveTicketSheet extends ConsumerStatefulWidget {
  const _LiveTicketSheet({required this.ticket});
  final MyTicket ticket;

  @override
  ConsumerState<_LiveTicketSheet> createState() => _LiveTicketSheetState();
}

class _LiveTicketSheetState extends ConsumerState<_LiveTicketSheet> {
  late MyTicket _t;
  Timer? _poll;
  bool _justScanned = false;

  @override
  void initState() {
    super.initState();
    _t = widget.ticket;
    if (_t.redeemedAt == null) {
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final all = await ref.read(paymentsRepositoryProvider).myTickets();
      final fresh = all.where((x) => x.code == _t.code).toList();
      if (fresh.isEmpty || !mounted) return;
      if (fresh.first.redeemedAt != null && _t.redeemedAt == null) {
        _poll?.cancel();
        HapticFeedback.heavyImpact();
        setState(() {
          _t = fresh.first;
          _justScanned = true;
        });
        ref.invalidate(myTicketsProvider);
      }
    } catch (_) {
      // Transient network error — keep polling quietly.
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = _t;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(t.title,
            style: TextStyle(
                color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(t.redeemedAt != null ? 'This ticket has been used' : 'Show this at the gate',
            style: TextStyle(color: p.muted, fontSize: 12)),
        const SizedBox(height: 14),
        if (t.redeemedAt != null)
          // Checked in — replaces the QR with unmistakable feedback.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 26),
            decoration: BoxDecoration(
              color: p.accent.withAlpha(26),
              border: Border.all(color: p.accent, width: 2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(children: [
              Icon(Icons.check_circle_rounded, size: 52, color: p.accent),
              const SizedBox(height: 8),
              Text(_justScanned ? 'Checked in — enjoy! 🎉' : 'Checked in',
                  style: TextStyle(
                      color: p.accent,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('Scanned ${timeAgo(t.redeemedAt)}',
                  style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          )
        else
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
        InkWell(
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: t.code));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Receipt code copied')));
            }
          },
          child: Text('${t.code}  ⧉',
              style: TextStyle(
                  color: p.muted, fontSize: 11, fontFamily: 'monospace')),
        ),
        const SizedBox(height: 14),
        // Full receipt: what was actually paid, and for what.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            _kv(p, 'Ticket',
                formatMoney(t.amountMinor, t.currency, t.currencyExponent)),
            if (t.feeMinor > 0)
              _kv(p, 'Fees',
                  formatMoney(t.feeMinor, t.currency, t.currencyExponent)),
            _kv(p, 'Total paid',
                formatMoney(t.totalMinor, t.currency, t.currencyExponent),
                bold: true),
            if (t.groupName != null) _kv(p, 'Group', t.groupName!),
            if (t.eventTitle != null) _kv(p, 'Event', t.eventTitle!),
            if (t.eventDate != null) _kv(p, 'Date', formatDayYear(t.eventDate)),
            if (t.paidAt != null) _kv(p, 'Paid', formatDayYear(t.paidAt)),
            if (t.giftedByName != null)
              _kv(p, 'Paid for by', '🎁 ${t.giftedByName}'),
            if (t.redeemedAt != null)
              _kv(p, 'Used', '✓ ${formatDayYear(t.redeemedAt)}'),
          ]),
        ),
      ])),
    );
  }

  Widget _kv(AppPalette p, String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(k, style: TextStyle(color: p.muted, fontSize: 12))),
          Flexible(
            child: Text(v,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: p.ink,
                    fontSize: 12,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ),
        ]),
      );
}
