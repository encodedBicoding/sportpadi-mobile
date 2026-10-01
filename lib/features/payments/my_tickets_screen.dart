import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/payments/payments_repository.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/ticket_validity.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sheet_scroll.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// My purchases — paid tickets as ticket stubs (2026), each opening its
/// gate QR. Unused tickets lead; used ones — scanned, or used up when their
/// recurring cycle ended — sit under their own tab. My
/// wards' tickets are here too ("Ward · Tobi") — I show their QR at the gate.
/// [openCode] (from `/tickets/<code>`) opens that receipt straight away.
class MyTicketsScreen extends ConsumerStatefulWidget {
  const MyTicketsScreen({super.key, this.openCode});
  final String? openCode;

  @override
  ConsumerState<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

/// Not scanned yet, and its cycle (recurring tickets) hasn't ended.
bool _isReady(MyTicket t) => t.redeemedAt == null && t.expiredAt == null;

class _MyTicketsScreenState extends ConsumerState<MyTicketsScreen> {
  bool _used = false;

  @override
  void initState() {
    super.initState();
    final code = widget.openCode;
    if (code != null && code.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openReceipt(code));
    }
  }

  /// A ticket from my list when it's there (mine or my ward's), else the
  /// receipt itself (e.g. one I bought for someone else).
  Future<MyTicket> _ticketFor(String code) async {
    final list = await ref.read(myTicketsProvider.future);
    for (final t in list) {
      if (t.code == code) return t;
    }
    return ref.read(paymentsRepositoryProvider).receipt(code);
  }

  Future<void> _openReceipt(String code) async {
    try {
      final t = await _ticketFor(code);
      if (!mounted) return;
      await showSpSheet<void>(
        context,
        framed: false,
        builder: (_) => _LiveTicketSheet(ticket: t),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tickets = ref.watch(myTicketsProvider);
    final all = tickets.valueOrNull ?? const <MyTicket>[];
    final ready = all.where(_isReady).length;
    final used = all.length - ready;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(
              title: 'My purchases',
              subtitle: tickets.hasValue
                  ? '$ready ready to use'
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: SpSegmented(
              options: [
                ready > 0 ? 'Ready · $ready' : 'Ready',
                used > 0 ? 'Used · $used' : 'Used',
              ],
              index: _used ? 1 : 0,
              onChanged: (i) => setState(() => _used = i == 1),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.refresh(myTicketsProvider.future),
              child: AsyncView(
                value: tickets,
                onRetry: () => ref.invalidate(myTicketsProvider),
                data: (list) {
                  final shown = [
                    for (final t in list)
                      if (_isReady(t) != _used) t
                  ];
                  // Groups the holder neither belongs to nor follows → nudge
                  // a follow so their events stay on the home page.
                  final unfollowed = <String, String>{};
                  for (final t in list) {
                    if (t.groupRelation == 'none' &&
                        t.groupId != null &&
                        t.groupName != null) {
                      unfollowed[t.groupId!] = t.groupName!;
                    }
                  }
                  if (shown.isEmpty) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(32, 70, 32, 32),
                      children: [
                        Center(
                          child: SpIconTile(
                              Icons.confirmation_num_outlined,
                              bg: p.accentTint,
                              fg: p.greenText,
                              size: 60,
                              iconSize: 28),
                        ),
                        const SizedBox(height: 14),
                        Text(
                            _used
                                ? 'No used tickets yet'
                                : list.isEmpty
                                    ? 'No purchases yet'
                                    : 'Nothing waiting to be scanned',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                            _used
                                ? 'Tickets move here once they\'re scanned at the gate, or when their cycle ends.'
                                : 'Tickets you buy — or get gifted — land here, ready to show at the gate.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: p.muted, fontSize: 13, height: 1.45)),
                      ],
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
                    children: [
                      for (final e in unfollowed.entries) ...[
                        _FollowNudge(groupId: e.key, groupName: e.value),
                        const SizedBox(height: 12),
                      ],
                      for (final t in shown) ...[
                        _TicketStub(ticket: t),
                        const SizedBox(height: 14),
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

/// A ticket as a stub: what and when on top, a perforation, then the code
/// and the way in. Ready tickets are dark; used ones are quiet.
class _TicketStub extends StatelessWidget {
  const _TicketStub({required this.ticket});
  final MyTicket ticket;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = ticket;
    // Its recurring cycle ended before it was scanned: paid, but it no longer
    // admits anyone.
    final usedUp = t.usedUp;
    final ready = _isReady(t);
    final bg = ready ? p.hero : p.surface;
    final fg = ready ? p.onHero : p.ink;
    final muted = ready ? p.heroMuted : p.muted;
    final ward = t.forWard;
    final eyebrow = ward == null && t.giftedByName != null
        ? 'GIFTED BY ${t.giftedByName!.toUpperCase()}'
        : ready
            ? 'READY TO SCAN'
            : usedUp
                ? 'CYCLE ENDED'
                : 'USED ${formatDayYear(t.redeemedAt).toUpperCase()}';
    final valid = validityRange(t.validFrom, t.validUntil);
    final meta = [
      if (t.groupName != null) t.groupName!,
      if (t.eventDate != null) formatDayYear(t.eventDate),
      if (valid != null) 'Valid $valid',
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => showSpSheet<void>(
      context,
      framed: false,
      builder: (_) => _LiveTicketSheet(ticket: t),
    ),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(26),
            boxShadow: ready ? null : cardShadow(context),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(eyebrow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: ready
                                ? const Color(0xFF6EDC9E)
                                : ward == null && t.giftedByName != null
                                    ? p.orangeInk
                                    : p.muted,
                            fontSize: 11,
                            letterSpacing: 1.3,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Text(t.eventTitle ?? t.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: fg,
                                fontSize: 18,
                                height: 1.25,
                                fontWeight: FontWeight.w800)),
                      ),
                      if (usedUp) ...[
                        const SizedBox(width: 8),
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: p.surface2,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('Used up',
                              style: TextStyle(
                                  color: p.muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ]),
                    if (t.eventTitle != null)
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: fg.withAlpha(215),
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 12.5)),
                    ],
                    if (ward != null) ...[
                      const SizedBox(height: 8),
                      WardForChip(ward.firstName, onDark: ready),
                    ],
                  ]),
            ),
            TicketPerforation(
                color: ready ? p.onHero.withAlpha(46) : p.line,
                notch: p.bg),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 16),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Receipt code',
                            style: TextStyle(color: muted, fontSize: 11.5)),
                        Text(t.code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: fg,
                                fontFamily: 'monospace',
                                fontSize: 14,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w700)),
                      ]),
                ),
                const SizedBox(width: 10),
                Text(formatMoney(t.amountMinor, t.currency, t.currencyExponent),
                    style: TextStyle(
                        color: fg, fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ready ? Colors.white : p.surface2,
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(ready ? Icons.qr_code_2_rounded : Icons.receipt_long_outlined,
                        size: 16,
                        color: ready ? const Color(0xFF0E1411) : p.ink),
                    const SizedBox(width: 5),
                    Text(ready ? 'Show' : 'Receipt',
                        style: TextStyle(
                            color: ready ? const Color(0xFF0E1411) : p.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The tear line across a ticket: a dashed rule with a half-circle notch
/// bitten out of each edge (in the page colour).
class TicketPerforation extends StatelessWidget {
  const TicketPerforation({super.key, required this.color, required this.notch});
  final Color color;
  final Color notch;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: -10,
          top: 0,
          child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: notch, shape: BoxShape.circle)),
        ),
        Positioned(
          right: -10,
          top: 0,
          child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: notch, shape: BoxShape.circle)),
        ),
        Positioned.fill(
          left: 18,
          right: 18,
          child: LayoutBuilder(builder: (_, c) {
            final n = (c.maxWidth / 10).floor();
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < n; i++)
                  Container(width: 5, height: 2, color: color),
              ],
            );
          }),
        ),
      ]),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.accentTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        SpIconTile(Icons.groups_outlined,
            bg: p.surface, fg: p.greenText, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Follow ${widget.groupName} so their events always show on your home page.',
            style: TextStyle(color: p.ink, fontSize: 12.5, height: 1.4),
          ),
        ),
        const SizedBox(width: 8),
        SpButton(
          label: 'Follow',
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
    if (_t.redeemedAt == null && _t.showsQr) {
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
    final used = t.redeemedAt != null;
    // Its recurring cycle ended: paid, but no longer admits anyone.
    final usedUp = t.usedUp;
    final valid = validityRange(t.validFrom, t.validUntil);
    final ward = t.forWard;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      // Pull down from the top to close (a plain scroll view swallowed the
      // sheet's drag, so the ticket wouldn't go away), or tap the X.
      child: SheetScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 10, 20, 24 + MediaQuery.of(context).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const SizedBox(width: 44),
            Expanded(
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: p.line, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            SpRoundButton(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              onTap: () => Navigator.of(context).pop(),
            ),
          ]),
          const SizedBox(height: 12),
          // The ticket itself.
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: cardShadow(context),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  color: p.hero,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                              ward != null
                                  ? 'FOR ${ward.firstName.toUpperCase()}'
                                  : t.giftedByName != null
                                      ? 'GIFTED BY ${t.giftedByName!.toUpperCase()}'
                                      : 'MATCH TICKET',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Color(0xFF6EDC9E),
                                  fontSize: 11,
                                  letterSpacing: 1.3,
                                  fontWeight: FontWeight.w700)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: used
                                ? const Color(0x296EDC9E)
                                : p.onHero.withAlpha(30),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                              used
                                  ? 'Used'
                                  : usedUp
                                      ? 'Used up'
                                      : t.status == 'paid'
                                          ? 'Valid'
                                          : capitalizeFirst(t.status),
                              style: TextStyle(
                                  color: used
                                      ? const Color(0xFF6EDC9E)
                                      : usedUp
                                          ? p.heroMuted
                                          : p.onHero,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(t.eventTitle ?? t.title,
                          style: TextStyle(
                              color: p.onHero,
                              fontSize: 20,
                              height: 1.25,
                              fontWeight: FontWeight.w800)),
                      if (t.eventTitle != null)
                        Text(t.title,
                            style: TextStyle(
                                color: p.onHero.withAlpha(215),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                          [
                            if (t.groupName != null) t.groupName!,
                            if (t.eventDate != null) formatDayYear(t.eventDate),
                            if (valid != null) 'Valid $valid',
                          ].join(' · '),
                          style:
                              TextStyle(color: p.heroMuted, fontSize: 12.5)),
                    ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: used
                    // Checked in — replaces the QR with unmistakable feedback.
                    ? Container(
                        padding: const EdgeInsets.symmetric(vertical: 26),
                        decoration: BoxDecoration(
                          color: p.accentTint,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                                color: p.accent, shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded,
                                size: 38, color: Colors.white),
                          ),
                          const SizedBox(height: 12),
                          Text(
                              _justScanned
                                  ? "You're in — enjoy the game"
                                  : 'Checked in',
                              style: TextStyle(
                                  color: p.greenText,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text('Scanned ${timeAgo(t.redeemedAt)}',
                              style: TextStyle(
                                  color: p.muted, fontSize: 12.5)),
                        ]),
                      )
                    : usedUp
                        // Cycle ended — no QR: it would only be turned away
                        // at the gate.
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 26, horizontal: 16),
                            decoration: BoxDecoration(
                              color: p.surface2,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Column(children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                    color: p.surface, shape: BoxShape.circle),
                                child: Icon(Icons.event_busy_outlined,
                                    size: 30, color: p.muted),
                              ),
                              const SizedBox(height: 12),
                              Text('Used up',
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(
                                  'Used up — this cycle has ended'
                                  '${t.validUntil != null ? ' (last day ${shortDay(t.validUntil!)})' : ''}. '
                                  'Used-up tickets can\'t be refunded.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: p.muted,
                                      fontSize: 12.5,
                                      height: 1.45)),
                            ]),
                          )
                    : !t.showsQr
                        // Not mine to present (a ticket I bought for someone
                        // else) or not paid yet: the receipt, no QR.
                        ? Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: p.surface2,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(children: [
                              Icon(Icons.qr_code_2_rounded,
                                  size: 20, color: p.muted),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  t.status != 'paid'
                                      ? 'This payment is ${t.status} — the gate QR appears once it has gone through.'
                                      : 'The gate QR is with ${t.holderName ?? 'the ticket holder'} — they show it at the gate.',
                                  style: TextStyle(
                                      color: p.muted,
                                      fontSize: 12.5,
                                      height: 1.4),
                                ),
                              ),
                            ]),
                          )
                        : Column(children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: p.line),
                          ),
                          child: QrImageView(
                              data: t.code,
                              size: 210,
                              backgroundColor: Colors.white),
                        ),
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: p.accent, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                                ward != null
                                    ? 'Show this at the gate for ${ward.firstName}'
                                    : 'Show this at the gate — it updates when scanned',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: p.muted, fontSize: 12)),
                          ),
                        ]),
                      ]),
              ),
              TicketPerforation(color: p.line, notch: p.bg),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
                child: Material(
                  color: p.surface2,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: t.code));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Receipt code copied')));
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Receipt code',
                                    style: TextStyle(
                                        color: p.muted, fontSize: 11.5)),
                                Text(t.code,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.ink,
                                        fontFamily: 'monospace',
                                        fontSize: 15,
                                        letterSpacing: 1.5,
                                        fontWeight: FontWeight.w700)),
                              ]),
                        ),
                        Icon(Icons.copy_rounded, size: 18, color: p.muted),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          // Full receipt: what was actually paid, and for what.
          GlassCard(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: Column(children: [
              _kv(p, 'Ticket',
                  formatMoney(t.amountMinor, t.currency, t.currencyExponent)),
              if (t.feeMinor > 0)
                _kv(p, 'Fees',
                    formatMoney(t.feeMinor, t.currency, t.currencyExponent)),
              Divider(height: 14, color: p.surface2),
              _kv(p, 'Total paid',
                  formatMoney(t.totalMinor, t.currency, t.currencyExponent),
                  bold: true),
              if (t.refundedMinor > 0)
                _kv(
                    p,
                    t.status == 'refunded' ? 'Refunded' : 'Refunded so far',
                    formatMoney(
                        t.refundedMinor, t.currency, t.currencyExponent)),
              if (ward != null) _kv(p, 'For', ward.displayName),
              if (ward == null &&
                  !t.canPresent &&
                  t.holderName != null)
                _kv(p, 'For', t.holderName!),
              if (t.groupName != null) _kv(p, 'Group', t.groupName!),
              if (t.eventTitle != null) _kv(p, 'Event', t.eventTitle!),
              if (t.eventDate != null)
                _kv(p, 'Date', formatDayYear(t.eventDate)),
              if (t.paidAt != null) _kv(p, 'Paid', formatDayYear(t.paidAt)),
              if (t.giftedByName != null)
                _kv(p, 'Paid for by', t.giftedByName!),
              if (valid != null) _kv(p, 'Valid', valid),
              if (t.redeemedAt != null)
                _kv(p, 'Used', formatDayYear(t.redeemedAt)),
              // The cycle's last day (when it was closed can be the morning after).
              if (usedUp) _kv(p, 'Cycle ended', shortDay(t.validUntil ?? t.expiredAt!)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _kv(AppPalette p, String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
              child: Text(k, style: TextStyle(color: p.muted, fontSize: 13))),
          Flexible(
            child: Text(v,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: p.ink,
                    fontSize: bold ? 14 : 13,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ),
        ]),
      );
}
