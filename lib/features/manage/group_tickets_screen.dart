import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart' show formatMoney;
import 'package:sportpadi_mobile/data/tickets/ticket_models.dart';
import 'package:sportpadi_mobile/data/tickets/tickets_repository.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/data/wallet/wallet_models.dart' show FeeQuote;
import 'package:sportpadi_mobile/data/wallet/wallet_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart' show viewerTimezone;
import 'package:sportpadi_mobile/shared/format/ticket_validity.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

const _recurrenceLabel = {
  'one_time': 'One-time',
  'weekly': 'Weekly',
  'monthly': 'Monthly',
  'quarterly': 'Quarterly',
  'yearly': 'Yearly',
};

/// Ticket setup for group admins — the web page (`/groups/:id/tickets`),
/// screen for screen.
///
/// The shape is the web's: a plain list of tickets, each opening a DETAIL
/// sheet with the config summary, an Active switch, View / Edit / Delete,
/// and the full payment history. The editor asks the same questions in the
/// same order as the web form — title, description, flier, price, "is this
/// for a specific event?", the check-in and scan switches, "does it repeat?",
/// sales window, capacity, active — and a flier can be added, replaced or
/// removed from the app, not just the site. The old General / Event /
/// Tournament segmented control up top is gone: the kind is a question in
/// the form, as on the web, not a mode you pick before you start.
class GroupTicketsScreen extends ConsumerStatefulWidget {
  const GroupTicketsScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupTicketsScreen> createState() => _GroupTicketsScreenState();
}

class _GroupTicketsScreenState extends ConsumerState<GroupTicketsScreen> {
  bool _busy = false;

  void _refetch() => ref.invalidate(managedTicketsProvider(widget.groupId));

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEditor({ManagedTicket? existing}) async {
    final wallet = ref.read(groupWalletProvider(widget.groupId)).valueOrNull;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _TicketEditor(
        groupId: widget.groupId,
        existing: existing,
        currency: existing?.currency ?? wallet?.currency ?? '',
        exponent: existing?.currencyExponent ?? wallet?.exponent ?? 2,
      ),
    ));
    if (saved == true) _refetch();
  }

  /// The web's detail dialog: summary, quick actions, payments.
  Future<void> _openDetail(ManagedTicket t) async {
    await showSpSheet<void>(
      context,
      scrollable: false,
      padding: EdgeInsets.zero,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, controller) => _TicketDetailSheet(
          groupId: widget.groupId,
          ticketId: t.id,
          controller: controller,
          onEdit: (tk) {
            Navigator.pop(ctx);
            _openEditor(existing: tk);
          },
          onDelete: (tk) {
            Navigator.pop(ctx);
            _confirmDelete(tk);
          },
          onToggleActive: (tk, v) => _run(() async {
            await ref.read(ticketsRepositoryProvider).setActive(widget.groupId, tk.id, v);
            _refetch();
          }),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(ManagedTicket t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete this ticket?'),
        content: const Text(
            'This can\'t be undone. Tickets that already have purchases can\'t be '
            'deleted — deactivate them instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.palette.danger),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() async {
        await ref.read(ticketsRepositoryProvider).remove(widget.groupId, t.id);
        _refetch();
        _snack('Ticket deleted');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tickets = ref.watch(managedTicketsProvider(widget.groupId));
    final wallet = ref.watch(groupWalletProvider(widget.groupId)).valueOrNull;
    final walletOk = wallet?.active ?? false;
    final groupName = ref.watch(groupProvider(widget.groupId)).valueOrNull?.name ?? 'Group';
    final activeCount = tickets.valueOrNull?.where((t) => t.isActive).length;

    final all = tickets.valueOrNull ?? const <ManagedTicket>[];
    final soldTotal = all.fold<int>(0, (a, t) => a + t.soldCount);
    // Ended cycles of recurring tickets stay listed (they hold the receipts)
    // but out of the way, below the tickets that matter now.
    final ended = all.where((t) => t.isEndedCycle).toList();
    final current = all.where((t) => !t.isEndedCycle).toList();

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: SpHeader(
              title: 'Tickets',
              subtitle: groupName,
              actions: [
                // Gate validation: scan holders' ticket QRs.
                SpRoundButton(
                  icon: Icons.qr_code_scanner_rounded,
                  tooltip: 'Scan tickets',
                  onTap: () => context.push('/scan'),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<ManagedTicket>>(
              value: tickets,
              onRetry: _refetch,
              data: (list) => RefreshIndicator(
                onRefresh: () async => _refetch(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  children: [
                    // Summary + the one action that matters here.
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: p.hero,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              _heroStat(p, '${activeCount ?? 0}', 'Active'),
                              const SizedBox(width: 8),
                              _heroStat(
                                  p,
                                  '${current.length - (activeCount ?? 0)}',
                                  'Hidden'),
                              const SizedBox(width: 8),
                              _heroStat(p, '$soldTotal', 'Sold', mint: true),
                            ]),
                            const SizedBox(height: 14),
                            Material(
                              color: walletOk && !_busy
                                  ? Colors.white
                                  : p.onHero.withAlpha(30),
                              shape: const StadiumBorder(),
                              child: InkWell(
                                customBorder: const StadiumBorder(),
                                onTap: walletOk && !_busy
                                    ? () => _openEditor()
                                    : null,
                                child: SizedBox(
                                  height: 50,
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_rounded,
                                            size: 19,
                                            color: walletOk
                                                ? const Color(0xFF0E1411)
                                                : p.heroMuted),
                                        const SizedBox(width: 6),
                                        Text('New ticket',
                                            style: TextStyle(
                                                color: walletOk
                                                    ? const Color(0xFF0E1411)
                                                    : p.heroMuted,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700)),
                                      ]),
                                ),
                              ),
                            ),
                          ]),
                    ),
                    const SizedBox(height: 14),
                    if (wallet != null && !walletOk)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: p.orangeTint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SpIconTile(Icons.shield_outlined,
                                    bg: p.surface, fg: p.orangeInk, size: 38),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            'Activate your wallet to sell tickets',
                                            style: TextStyle(
                                                color: p.ink,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        Text(
                                            'Ticket prices use your wallet\'s settlement currency, so you '
                                            'need a wallet before creating tickets.',
                                            style: TextStyle(
                                                color: p.orangeInk,
                                                fontSize: 12,
                                                height: 1.4)),
                                        const SizedBox(height: 10),
                                        SpButton(
                                          label: 'Go to wallet',
                                          icon: Icons
                                              .account_balance_wallet_outlined,
                                          onTap: () => context.push(
                                              '/groups/${widget.groupId}/wallet'),
                                        ),
                                      ]),
                                ),
                              ]),
                        ),
                      ),
                    if (list.isEmpty)
                      GlassCard(
                        padding: const EdgeInsets.all(26),
                        child: Column(children: [
                          SpIconTile(Icons.confirmation_num_outlined,
                              bg: p.accentTint,
                              fg: p.greenText,
                              size: 56,
                              iconSize: 26),
                          const SizedBox(height: 12),
                          Text('No tickets yet',
                              style: TextStyle(
                                  color: p.ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(
                              'Create a paid ticket for an event, dues, or a one-off like a BBQ.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: p.muted, fontSize: 13, height: 1.4)),
                        ]),
                      )
                    else ...[
                      SpSectionTitle('Your tickets', count: current.length),
                      if (current.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SpListCard(children: [
                          for (final t in current)
                            _TicketRow(ticket: t, onTap: () => _openDetail(t)),
                        ]),
                      ],
                      if (ended.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        SpSectionTitle('Ended cycles', count: ended.length),
                        const SizedBox(height: 10),
                        SpListCard(children: [
                          for (final t in ended)
                            _TicketRow(ticket: t, onTap: () => _openDetail(t)),
                        ]),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _heroStat(AppPalette p, String value, String label,
          {bool mint = false}) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: p.onHero.withAlpha(18),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    color: mint ? const Color(0xFF6EDC9E) : p.onHero,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(color: p.heroMuted, fontSize: 11.5)),
          ]),
        ),
      );
}

/// One row of the list — thumbnail, title, price · sold · recurrence.
class _TicketRow extends StatelessWidget {
  const _TicketRow({required this.ticket, required this.onTap});
  final ManagedTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = ticket;
    final valid = t.isRecurring ? validityRange(t.validFrom, t.validUntil) : null;
    final sub = [
      formatMoney(t.priceMinor, t.currency, t.currencyExponent),
      t.soldLabel,
      if (t.recurrence != 'one_time') _recurrenceLabel[t.recurrence] ?? t.recurrence,
      if (valid != null) 'Valid $valid',
    ].join(' · ');

    Widget kindPill(IconData icon, String label, Color bg, Color fg) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                    color: fg, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ]),
        );

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Opacity(
        opacity: t.isActive ? 1 : 0.6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(children: [
            _Thumb(url: t.flierUrl, size: 50),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 1),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12)),
                if (t.kind == 'event' ||
                    t.kind == 'tournament' ||
                    !t.isActive ||
                    t.isNextCycle) ...[
                  const SizedBox(height: 5),
                  Wrap(spacing: 5, runSpacing: 4, children: [
                    if (t.kind == 'event')
                      kindPill(Icons.calendar_month_rounded, 'Event',
                          p.accentTint, p.greenText),
                    if (t.kind == 'tournament')
                      kindPill(Icons.emoji_events_outlined, 'Tournament',
                          p.orangeTint, p.orangeInk),
                    if (t.isNextCycle)
                      kindPill(Icons.repeat_rounded, 'Next cycle · on sale',
                          p.accentTint, p.greenText),
                    if (t.isEndedCycle)
                      kindPill(Icons.repeat_rounded, 'Ended cycle', p.surface2,
                          p.muted)
                    else if (!t.isActive)
                      kindPill(Icons.visibility_off_outlined, 'Hidden',
                          p.surface2, p.muted),
                  ]),
                ],
              ]),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: p.muted, size: 20),
          ]),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.size});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: SizedBox(
        width: size,
        height: size,
        child: url != null
            ? Image.network(url!, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(p))
            : _placeholder(p),
      ),
    );
  }

  Widget _placeholder(AppPalette p) => Container(
        color: p.accentTint,
        child: Icon(Icons.confirmation_num_outlined,
            size: size * 0.45, color: p.greenText),
      );
}

/// The web's TicketDetailDialog.
class _TicketDetailSheet extends ConsumerWidget {
  const _TicketDetailSheet({
    required this.groupId,
    required this.ticketId,
    required this.controller,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });
  final String groupId;
  final String ticketId;
  final ScrollController controller;
  final void Function(ManagedTicket) onEdit;
  final void Function(ManagedTicket) onDelete;
  final void Function(ManagedTicket, bool) onToggleActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    // Read live so the Active switch reflects the toggle without closing.
    ManagedTicket? ticket;
    for (final t in ref.watch(managedTicketsProvider(groupId)).valueOrNull ?? const <ManagedTicket>[]) {
      if (t.id == ticketId) {
        ticket = t;
        break;
      }
    }
    if (ticket == null) return const SizedBox(height: 120);
    final t = ticket;
    final sales = ref.watch(ticketSalesProvider((groupId: groupId, ticketId: t.id)));
    final base = ref.read(appConfigProvider).apiBaseUrl;
    final fmt = DateFormat('d MMM yyyy, h:mm a');
    final fmtDay = DateFormat('d MMM yyyy');
    final validity =
        t.isRecurring ? validityRange(t.validFrom, t.validUntil) : null;

    Widget badge(IconData icon, String label, {Color? tone}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: tone != null ? tone.withAlpha(30) : p.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: tone ?? p.muted),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: tone ?? p.ink, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ]),
        );

    Widget action(IconData icon, String label, VoidCallback onTap,
            {bool primary = false, bool danger = false}) =>
        Expanded(
          child: Material(
            color: primary
                ? p.hero
                : danger
                    ? p.liveTint
                    : p.surface,
            shape: StadiumBorder(
                side: primary || danger
                    ? BorderSide.none
                    : BorderSide(color: p.line)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: SizedBox(
                height: 46,
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 17,
                          color: primary
                              ? p.onHero
                              : danger
                                  ? p.danger
                                  : p.ink),
                      const SizedBox(width: 6),
                      Text(label,
                          style: TextStyle(
                              color: primary
                                  ? p.onHero
                                  : danger
                                      ? p.danger
                                      : p.ink,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700)),
                    ]),
              ),
            ),
          ),
        );

    final canDelete = t.soldCount == 0;

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        // What it is, and what it costs.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Thumb(url: t.flierUrl, size: 68),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 19,
                      height: 1.25,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(formatMoney(t.priceMinor, t.currency, t.currencyExponent),
                  style: TextStyle(
                      color: p.greenText,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                badge(
                    t.isActive
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    t.isActive ? 'On sale' : 'Hidden',
                    tone: t.isActive ? p.accent : null),
                if (t.soldOut)
                  badge(Icons.block_rounded, 'Sold out', tone: p.danger),
                if (t.capacity != null)
                  badge(Icons.people_outline_rounded, 'Cap ${t.capacity}'),
              ]),
            ]),
          ),
        ]),
        if (t.description != null && t.description!.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(t.description!,
              style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.5)),
        ],

        // How it's set up.
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Setup',
                style: TextStyle(
                    color: p.ink, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (t.kind == 'event')
                badge(Icons.calendar_month_rounded, t.eventTitle ?? 'Event',
                    tone: p.accent),
              if (t.kind == 'tournament')
                badge(Icons.emoji_events_outlined, t.eventTitle ?? 'Tournament',
                    tone: p.orange),
              if (t.kind != 'event' && t.kind != 'tournament')
                badge(Icons.groups_outlined, 'Any group activity'),
              if (t.blocksCheckin)
                badge(Icons.shield_outlined, 'Required for check-in'),
              if (t.requiresValidation)
                badge(Icons.qr_code_2_rounded, 'Scanned at the gate'),
              badge(Icons.repeat_rounded,
                  _recurrenceLabel[t.recurrence] ?? t.recurrence),
              if (validity != null)
                badge(Icons.event_available_outlined,
                    'Valid $validity · cycle ${t.cycleNo}'),
              if (t.isNextCycle)
                badge(Icons.repeat_rounded, 'Next cycle · on sale',
                    tone: p.accent),
              if (t.salesStartAt != null)
                badge(Icons.play_arrow_rounded,
                    'Sales open ${fmtDay.format(t.salesStartAt!.toLocal())}'),
              if (t.salesEndAt != null)
                badge(Icons.stop_rounded,
                    'Sales close ${fmtDay.format(t.salesEndAt!.toLocal())}'),
              if (t.isEndedCycle) badge(Icons.repeat_rounded, 'Ended cycle'),
            ]),
            Divider(height: 24, color: p.surface2),
            Row(children: [
              SpIconTile(
                  t.isActive
                      ? Icons.storefront_outlined
                      : Icons.visibility_off_outlined,
                  bg: t.isActive ? p.accentTint : p.surface2,
                  fg: t.isActive ? p.greenText : p.muted,
                  size: 38,
                  iconSize: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.isActive ? 'On sale' : 'Hidden from buyers',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      Text(
                          t.isActive
                              ? 'Members can buy it now.'
                              : 'Switch on to start selling.',
                          style: TextStyle(color: p.muted, fontSize: 12)),
                    ]),
              ),
              Switch(
                value: t.isActive,
                onChanged: (v) => onToggleActive(t, v),
              ),
            ]),
          ]),
        ),

        // View / Edit / Delete — the web's action row.
        const SizedBox(height: 14),
        Row(children: [
          action(Icons.open_in_new_rounded, 'View', () {
            launchUrl(Uri.parse('$base/t/${t.id}'),
                mode: LaunchMode.inAppBrowserView);
          }),
          const SizedBox(width: 8),
          action(Icons.edit_outlined, 'Edit', () => onEdit(t), primary: true),
          if (canDelete) ...[
            const SizedBox(width: 8),
            action(Icons.delete_outline_rounded, 'Delete', () => onDelete(t),
                danger: true),
          ],
        ]),
        if (!canDelete)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                'It has sales, so it can\'t be deleted — switch it off to hide it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 12)),
          ),

        // Payments
        const SizedBox(height: 22),
        AsyncView<TicketSales>(
          value: sales,
          data: (s) {
            final rows = s.sales;
            final paid = rows.where((r) => r.status == 'paid').toList();
            final total = paid.fold<int>(0, (a, r) => a + r.received);
            final used = rows.where((r) => r.redeemedAt != null).length;
            Widget tile(String v, String l, {bool green = false}) => Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: p.hero,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(v,
                            style: TextStyle(
                                color: green
                                    ? const Color(0xFF6EDC9E)
                                    : p.onHero,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                      ),
                      Text(l,
                          style: TextStyle(color: p.heroMuted, fontSize: 11)),
                    ]),
                  ),
                );
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SpSectionTitle('Payments', count: rows.length),
              const SizedBox(height: 10),
              Row(children: [
                tile('${paid.length}', 'Paid'),
                const SizedBox(width: 8),
                tile(formatMoney(total, t.currency, s.currencyExponent),
                    'Collected',
                    green: true),
                const SizedBox(width: 8),
                tile('$used', 'Used'),
              ]),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    const SpIconTile(Icons.receipt_long_outlined,
                        size: 48, iconSize: 22),
                    const SizedBox(height: 8),
                    Text('No payments yet.',
                        style: TextStyle(color: p.muted, fontSize: 13)),
                  ]),
                )
              else
                SpListCard(children: [
                  for (final r in rows)
                    // Tap → check this payment with the payment provider
                    // (and reconcile it if SportPadi is out of step).
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _openPaymentCheck(
                          context, ref, r, t.currency, s.currencyExponent),
                      child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                      Row(children: [
                        CircleAvatar(
                          radius: 19,
                          backgroundColor: p.surface2,
                          backgroundImage: r.buyerAvatarUrl != null
                              ? NetworkImage(r.buyerAvatarUrl!)
                              : null,
                          child: r.buyerAvatarUrl == null
                              ? Text(
                                  r.buyerName.isNotEmpty
                                      ? r.buyerName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                      color: p.muted,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700))
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(r.buyerName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.ink,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700)),
                                Text(
                                  [
                                    if (r.paidAt != null)
                                      fmt.format(r.paidAt!.toLocal()),
                                    if (r.periodKey != null) r.periodKey!,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: p.muted, fontSize: 12),
                                ),
                              ]),
                        ),
                        const SizedBox(width: 8),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                  formatMoney(r.amount, r.currency,
                                      s.currencyExponent),
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(
                                (r.redeemedAt != null
                                        ? 'USED'
                                        : r.status.toUpperCase()) +
                                    (r.reconciled ? ' · RECONCILED' : ''),
                                style: TextStyle(
                                  color: r.redeemedAt != null ||
                                          r.status == 'paid'
                                      ? p.greenText
                                      : r.status == 'failed'
                                          ? p.danger
                                          : r.status == 'refunded'
                                              ? p.orangeInk
                                              : p.muted,
                                  fontSize: 10.5,
                                  letterSpacing: 0.4,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ]),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded, size: 18, color: p.muted),
                      ]),
                      // Refund: the action, why it can't be, or how it went.
                      _SaleRefundLine(
                        sale: r,
                        money: (m) => formatMoney(
                            m,
                            r.currency.isNotEmpty ? r.currency : t.currency,
                            s.currencyExponent),
                        onRefund: () => _openRefund(context, groupId, t.id,
                            r, t.currency, s.currencyExponent),
                      ),
                    ]),
                    ),
                    ),
                ]),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Tap a payment to check it with the payment provider.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 12)),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

/// Under a payment row: a Refund button when it can be refunded, a
/// "Refunded" pill once it is, why it can't be when it's paid but not
/// refundable, and the last failed attempt if there was one.
class _SaleRefundLine extends StatelessWidget {
  const _SaleRefundLine(
      {required this.sale, required this.money, required this.onRefund});
  final TicketSale sale;
  final String Function(int minor) money;
  final VoidCallback onRefund;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = sale;
    final paid = r.status == 'paid';
    final failed = paid ? r.refundFailReason : null;
    final blocked = paid && !r.canRefund ? r.refundBlocked : null;
    final canRefund = paid && r.canRefund;
    // Partly refunded: still paid, the ticket still valid.
    final partly = paid && r.refundedMinor > 0;
    // A refunded row already says REFUNDED on the right — nothing to add.
    if (!canRefund && blocked == null && failed == null && !partly) {
      return const SizedBox.shrink();
    }
    return Padding(
      // Lined up under the buyer's name (avatar 38 + gap 12).
      padding: const EdgeInsets.only(left: 50, top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (partly) ...[
          Text(
              '${money(r.refundedMinor)} of ${money(r.amount)} refunded so far · ticket still valid',
              style: TextStyle(color: p.orangeInk, fontSize: 12, height: 1.35)),
          const SizedBox(height: 6),
        ],
        if (failed != null) ...[
          Text('Last refund attempt failed: $failed',
              style: TextStyle(color: p.danger, fontSize: 12, height: 1.35)),
          const SizedBox(height: 6),
        ],
        if (canRefund)
          Material(
            color: p.liveTint,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onRefund,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.undo_rounded, size: 14, color: p.danger),
                  const SizedBox(width: 5),
                  Text(partly ? 'Refund more' : 'Refund',
                      style: TextStyle(
                          color: p.danger,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          )
        else if (blocked != null)
          Text(blocked,
              style: TextStyle(color: p.muted, fontSize: 12, height: 1.35)),
      ]),
    );
  }
}

/// Opens the refund confirmation for one payment.
void _openRefund(BuildContext context, String groupId, String ticketId,
    TicketSale sale, String currency, int exponent) {
  showSpSheet<void>(
    context,
    builder: (_) => _RefundSheet(
      groupId: groupId,
      ticketId: ticketId,
      sale: sale,
      currency: currency,
      exponent: exponent,
    ),
  );
}

/// "Refund {buyer}'s ticket?" — like refunding a charge from the Stripe
/// Dashboard: the ticket price goes back to the buyer's original payment
/// method; SportPadi's processing fee doesn't; on a pay-all checkout only
/// this ticket is refunded. The buyer (or a ward's paying guardian) is told.
class _RefundSheet extends ConsumerStatefulWidget {
  const _RefundSheet({
    required this.groupId,
    required this.ticketId,
    required this.sale,
    required this.currency,
    required this.exponent,
  });
  final String groupId;
  final String ticketId;
  final TicketSale sale;
  final String currency;
  final int exponent;

  @override
  ConsumerState<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends ConsumerState<_RefundSheet> {
  final _reason = TextEditingController();
  // How much to give back, in major units ("2.00"). Starts at everything
  // still refundable; anything less is a partial refund.
  late final TextEditingController _amount =
      TextEditingController(text: _toMajor(widget.sale.refundableMinor));
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(_onAmount);
  }

  void _onAmount() => setState(() {});

  @override
  void dispose() {
    _amount.removeListener(_onAmount);
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  int get _refundable => widget.sale.refundableMinor;

  String _toMajor(int minor) {
    var d = 1;
    for (var i = 0; i < widget.exponent; i++) {
      d *= 10;
    }
    return (minor / d).toStringAsFixed(widget.exponent);
  }

  /// The typed amount in minor units, or null when it isn't a number.
  int? get _amountMinor {
    final v = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (v == null || !v.isFinite) return null;
    var d = 1;
    for (var i = 0; i < widget.exponent; i++) {
      d *= 10;
    }
    return (v * d).round();
  }

  String? get _amountError {
    final m = _amountMinor;
    if (m == null) return 'Enter an amount';
    if (m <= 0) return 'Enter more than zero';
    if (m > _refundable) return 'You can refund up to ${_money(_refundable)}';
    return null;
  }

  bool get _isPartial =>
      _amountError == null && (_amountMinor ?? 0) < _refundable;

  String get _currency =>
      widget.sale.currency.isNotEmpty ? widget.sale.currency : widget.currency;

  String _money(int minor) => formatMoney(minor, _currency, widget.exponent);

  Future<void> _refund() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final key = (groupId: widget.groupId, ticketId: widget.ticketId);
    try {
      final asked = _amountMinor ?? _refundable;
      final refunded = await ref.read(ticketsRepositoryProvider).refundPayment(
          widget.groupId, widget.sale.id,
          reason: _reason.text,
          // Only a partial sends an amount; a full refund takes whatever is
          // left when it runs.
          amountMinor: _isPartial ? asked : null);
      if (!mounted) return;
      // Refresh the payments list (and the sold counts) before closing, so
      // the row already reads "Refunded" when the sheet goes.
      ref.invalidate(managedTicketsProvider(widget.groupId));
      ref.invalidate(ticketSalesProvider(key));
      try {
        await ref.read(ticketSalesProvider(key).future);
      } catch (_) {
        // The refund went through; the list shows its own error.
      }
      if (!mounted) return;
      nav.pop();
      messenger.showSnackBar(SnackBar(
          content: Text(
              'Refunded ${_money(refunded > 0 ? refunded : asked)}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sale = widget.sale;
    final price = _money(sale.amount);
    final fee = sale.platformFee;
    final via = sale.providerLabel;
    final error = _amountError;
    final partial = _isPartial;
    final amountLabel = error == null ? _money(_amountMinor!) : '';

    Widget line(IconData icon, String text, {Color? tone}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 17, color: tone ?? p.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: tone ?? p.ink, fontSize: 13.5, height: 1.4)),
            ),
          ]),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.undo_rounded,
          iconBg: p.liveTint,
          iconFg: p.danger,
          title: "Refund ${sale.buyerName}'s ticket?",
          subtitle: sale.refundedMinor > 0
              ? '$price · ${sale.code} · ${_money(sale.refundedMinor)} already refunded'
              : '$price · ${sale.code}',
        ),
        Text('Amount to refund ($_currency)',
            style: TextStyle(
                color: p.ink, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _amount,
              enabled: !_busy,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                errorText: error,
                helperText: partial
                    ? 'Partial refund — their ticket stays valid'
                    : null,
                helperMaxLines: 2,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: OutlinedButton(
              onPressed: _busy || (!partial && error == null)
                  ? null
                  : () => _amount.text = _toMajor(_refundable),
              child: Text('Full ${_money(_refundable)}'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            line(
                Icons.credit_card_rounded,
                via != null
                    ? 'Refund ${error == null ? amountLabel : '—'} to their $via payment'
                    : 'Refund ${error == null ? amountLabel : '—'} to their original payment'),
            line(
                Icons.receipt_long_outlined,
                fee != null && fee > 0
                    ? "SportPadi's processing fee (${_money(fee)}) isn't refunded"
                    : "SportPadi's processing fee isn't refunded"),
            line(Icons.layers_outlined,
                'If they paid several tickets in one checkout, only this one is refunded'),
            if (!partial)
              line(Icons.info_outline_rounded, 'A full refund cancels the ticket'),
            if (sale.redeemedAt != null)
              line(Icons.warning_amber_rounded,
                  "They've already used this ticket at the gate",
                  tone: p.orangeInk),
          ]),
        ),
        const SizedBox(height: 14),
        Text('Reason (optional)',
            style: TextStyle(
                color: p.ink, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          controller: _reason,
          enabled: !_busy,
          maxLength: 200,
          maxLines: 2,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'e.g. Event cancelled',
            helperText: 'Shown to them',
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: p.danger,
                foregroundColor: Colors.white,
                disabledBackgroundColor: p.danger.withAlpha(150),
                disabledForegroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _busy || error != null ? null : _refund,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                          error == null ? 'Refund $amountLabel' : 'Refund',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
            ),
          ),
        ]),
      ],
    );
  }
}

/// Opens the provider check for one payment.
void _openPaymentCheck(BuildContext context, WidgetRef ref, TicketSale sale,
    String currency, int exponent) {
  showSpSheet<void>(
    context,
    builder: (_) => _PaymentCheckSheet(sale: sale, currency: currency, exponent: exponent),
  );
}

final _paymentCheckProvider = FutureProvider.autoDispose
    .family<PaymentCheck, String>(
        (ref, id) => ref.watch(ticketsRepositoryProvider).checkPayment(id));

/// One payment, checked against the payment provider: what it says in plain
/// words and — when SportPadi is out of step (e.g. refunded in the Stripe
/// Dashboard but still counted as paid here) — a Reconcile button that puts
/// the ticket, the wallet and the payouts right. Web: PaymentCheckDialog.
class _PaymentCheckSheet extends ConsumerStatefulWidget {
  const _PaymentCheckSheet({required this.sale, required this.currency, required this.exponent});
  final TicketSale sale;
  final String currency;
  final int exponent;

  @override
  ConsumerState<_PaymentCheckSheet> createState() => _PaymentCheckSheetState();
}

class _PaymentCheckSheetState extends ConsumerState<_PaymentCheckSheet> {
  PaymentCheck? _fresh;
  bool _confirming = false;
  bool _busy = false;

  Future<void> _reconcile(PaymentCheck c) async {
    final action = c.action;
    if (action == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await ref
          .read(ticketsRepositoryProvider)
          .reconcilePayment(widget.sale.id, action);
      if (!mounted) return;
      setState(() {
        _fresh = res.check ?? _fresh;
        _confirming = false;
      });
      if (res.applied != null) {
        messenger.showSnackBar(SnackBar(
            content: Text(res.applied == 'mark_refunded'
                ? 'Reconciled — marked refunded.'
                : res.applied == 'mark_paid'
                    ? 'Reconciled — marked paid.'
                    : 'Reconciled — marked unpaid.')));
        for (final w in res.warnings) {
          messenger.showSnackBar(SnackBar(content: Text(w)));
        }
      } else {
        messenger.showSnackBar(const SnackBar(
            content: Text('Nothing applied — the payment changed. Showing the latest.')));
      }
      ref.invalidate(ticketSalesProvider);
      ref.invalidate(managedTicketsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sale = widget.sale;
    final async = ref.watch(_paymentCheckProvider(sale.id));
    final check = _fresh ?? async.valueOrNull;
    final loading = _fresh == null && async.isLoading;
    final provider = check?.providerLabel ?? 'the payment provider';
    final status = check?.ourStatus ?? sale.status;

    final (Color tileBg, Color tileFg, IconData icon) = switch (check?.verdict) {
      'in_sync' => (p.accentTint, p.greenText, Icons.check_circle_outline_rounded),
      'out_of_sync' => (p.orangeTint, p.orangeInk, Icons.error_outline_rounded),
      'error' => (p.liveTint, p.danger, Icons.error_outline_rounded),
      _ => (p.surface2, p.muted, Icons.info_outline_rounded),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.receipt_long_outlined,
          title: sale.buyerName,
          subtitle: '${formatMoney(sale.amount, sale.currency.isNotEmpty ? sale.currency : widget.currency, widget.exponent)} · ${sale.code}',
          trailing: SpBadge(status.toUpperCase(),
              tone: status == 'paid'
                  ? p.greenText
                  : status == 'refunded'
                      ? p.orangeInk
                      : p.muted),
        ),
        Eyebrow('With $provider'),
        const SizedBox(height: 8),
        if (loading)
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Checking with $provider…',
                    style: TextStyle(color: p.muted, fontSize: 13)),
              ),
            ]),
          )
        else if (check == null)
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Text(
                async.hasError ? '${async.error}' : 'Couldn\'t check this payment.',
                style: TextStyle(color: p.danger, fontSize: 13)),
          )
        else
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SpIconTile(icon, bg: tileBg, fg: tileFg, size: 40, iconSize: 19),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(check.headline,
                        style: TextStyle(
                            color: p.ink, fontSize: 15, fontWeight: FontWeight.w700, height: 1.3)),
                    for (final d in check.details) ...[
                      const SizedBox(height: 6),
                      Text(d, style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
                    ],
                    if (check.providerStatus != null) ...[
                      const SizedBox(height: 8),
                      Text('$provider status: ${check.providerStatus}',
                          style: TextStyle(color: p.muted, fontSize: 11)),
                    ],
                  ]),
                ),
              ]),
              if (check.action != null) ...[
                const SizedBox(height: 16),
                if (!_confirming)
                  SpButton(
                    expand: true,
                    icon: Icons.sync_rounded,
                    label: check.actionLabel ?? 'Reconcile',
                    onTap: () => setState(() => _confirming = true),
                  )
                else
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => setState(() => _confirming = false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: SpButton(
                        expand: true,
                        tone: SpButtonTone.brand,
                        icon: Icons.check_rounded,
                        label: _busy ? 'Reconciling…' : 'Yes, reconcile',
                        onTap: _busy ? null : () => _reconcile(check),
                      ),
                    ),
                  ]),
                if (check.actionHint != null) ...[
                  const SizedBox(height: 8),
                  Text(check.actionHint!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted, fontSize: 12, height: 1.4)),
                ],
              ],
            ]),
          ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: loading || _busy
                ? null
                : () {
                    setState(() => _fresh = null);
                    ref.invalidate(_paymentCheckProvider(sale.id));
                  },
            child: const Text('Check again'),
          ),
        ),
      ],
    );
  }
}

/// Create / edit — the web form, question for question.
class _TicketEditor extends ConsumerStatefulWidget {
  const _TicketEditor({
    required this.groupId,
    required this.currency,
    required this.exponent,
    this.existing,
  });
  final String groupId;
  final String currency;
  final int exponent;
  final ManagedTicket? existing;

  @override
  ConsumerState<_TicketEditor> createState() => _TicketEditorState();
}

class _TicketEditorState extends ConsumerState<_TicketEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _capacity;
  late String _kind; // general | event | tournament
  String? _eventId;
  String? _flierUrl;
  late bool _blocksCheckin;
  late bool _requiresValidation;
  late String _recurrence;
  late bool _isActive;
  DateTime? _salesStart;
  DateTime? _salesEnd;
  // First day of the first cycle (recurring, create only): SportPadi sets the
  // validity from it — start of that day to the end of the cycle's last day.
  DateTime _firstDay = viewerToday();
  bool _busy = false;
  bool _uploadingFlier = false;
  String? _error;

  bool get _isEvent => _kind == 'event';
  bool get _isTournament => _kind == 'tournament';
  bool get _isRecurring => _recurrence != 'one_time';

  int _pow10(int e) {
    var v = 1;
    for (var i = 0; i < e; i++) {
      v *= 10;
    }
    return v;
  }

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _title = TextEditingController(text: t?.title ?? '');
    _description = TextEditingController(text: t?.description ?? '');
    _price = TextEditingController(
        text: t != null
            ? (t.priceMinor / _pow10(t.currencyExponent)).toStringAsFixed(t.currencyExponent)
            : '');
    _capacity = TextEditingController(text: t?.capacity?.toString() ?? '');
    _kind = t?.kind ?? 'general';
    _eventId = t?.eventId;
    _flierUrl = t?.flierUrl;
    _blocksCheckin = t?.blocksCheckin ?? false;
    _requiresValidation = t?.requiresValidation ?? false;
    _recurrence = t?.recurrence ?? 'one_time';
    _isActive = t?.isActive ?? true;
    _salesStart = t?.salesStartAt?.toLocal();
    _salesEnd = t?.salesEndAt?.toLocal();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _pickFlier() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _uploadingFlier = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await ref.read(eventsRepositoryProvider).uploadImage(
            bytes,
            picked.mimeType ?? 'image/jpeg',
            assetType: 'eventImage',
            scopeId: widget.groupId,
          );
      if (mounted) setState(() => _flierUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingFlier = false);
    }
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if ((_isEvent || _isTournament) && _eventId == null) {
      setState(() =>
          _error = 'Pick the ${_isEvent ? 'event' : 'tournament'} this ticket is for.');
      return;
    }
    if (_salesStart != null && _salesEnd != null && !_salesEnd!.isAfter(_salesStart!)) {
      setState(() => _error = 'Sales end must be after sales start.');
      return;
    }
    final price = double.tryParse(_price.text.trim()) ?? 0;
    final body = <String, dynamic>{
      'title': _title.text.trim(),
      'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      'flierUrl': _flierUrl,
      'price': (price * _pow10(widget.exponent)).round(),
      'kind': _kind,
      'eventId': _kind == 'general' ? null : _eventId,
      // Same rules as the web: event tickets always block check-in,
      // tournament tickets never do (an officiant scans them instead) and are
      // always scannable.
      'blocksCheckin': _isEvent ? true : (_isTournament ? false : _blocksCheckin),
      'requiresValidation': _isTournament ? true : _requiresValidation,
      'salesStartAt': _salesStart?.toUtc().toIso8601String(),
      'salesEndAt': _salesEnd?.toUtc().toIso8601String(),
      'capacity': _capacity.text.trim().isEmpty ? null : int.tryParse(_capacity.text.trim()),
      'isActive': _isActive,
    };
    // How often it renews is fixed once created (the server rejects a
    // change), so it's only sent on create — with the first day the validity
    // starts from, in the admin's zone.
    if (widget.existing == null) {
      body['recurrence'] = _recurrence;
      if (_isRecurring) {
        body['validFromDate'] = ymdString(_firstDay);
        final zone = viewerTimezone;
        if (zone != null) body['timezone'] = zone;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(ticketsRepositoryProvider);
      if (widget.existing == null) {
        await repo.create(widget.groupId, body);
      } else {
        await repo.update(widget.groupId, widget.existing!.id, body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFirstDay() async {
    final today = viewerToday();
    final d = await showDatePicker(
      context: context,
      initialDate: _firstDay,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 3),
    );
    if (d == null || !mounted) return;
    setState(() => _firstDay = DateTime(d.year, d.month, d.day));
  }

  Future<void> _pickDate(bool start) async {
    final now = DateTime.now();
    final initial = (start ? _salesStart : _salesEnd) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    final dt = DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
    setState(() {
      if (start) {
        _salesStart = dt;
      } else {
        _salesEnd = dt;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final editing = widget.existing != null;
    final events = (ref.watch(groupEventsProvider(widget.groupId)).valueOrNull ?? const [])
        .where((e) => !e.isTournament)
        .toList();
    final tournaments =
        ref.watch(groupTournamentsProvider(widget.groupId)).valueOrNull ?? const [];
    final fmt = DateFormat('EEE d MMM, HH:mm');
    // Creating a recurring ticket: the validity SportPadi will set, live.
    final preview = !editing && _isRecurring ? cyclePreview(_recurrence, _firstDay) : null;
    // Editing: the ticket's own validity, read-only.
    final existing = widget.existing;
    final editValidity = existing != null && _isRecurring
        ? validityRange(existing.validFrom, existing.validUntil)
        : null;
    final cycleNo = existing?.cycleNo ?? 1;

    Widget infoBox(String title, String body) => Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.surface2,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: p.ink, fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(body, style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.4)),
          ]),
        );

    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(s,
              style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
        );
    Widget hint(String s) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(s, style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.35)),
        );
    Widget switchRow({
      required String title,
      required String body,
      required bool value,
      required ValueChanged<bool>? onChanged,
    }) =>
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(
                        color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(body, style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.3)),
              ]),
            ),
            Switch(value: value, onChanged: onChanged),
          ]),
        );

    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: Text(editing ? 'Edit ticket' : 'New ticket'),
      ),
      body: Form(
        key: _form,
        // A single scroll view over one Column, not a ListView: the form is
        // fixed-size content, and a ListView's lazy layout was what left the
        // page unable to scroll back up on iOS once the bottom was reached
        // (children re-laid-out on the way down kept re-measuring the extent).
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Text('Set the price and answer a few questions so we know how this ticket behaves.',
                style: TextStyle(color: p.muted, fontSize: 12.5)),
            const SizedBox(height: 18),

            label('Title'),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(hintText: 'e.g. Saturday 5-a-side entry'),
              maxLength: 120,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Give the ticket a title' : null,
            ),
            const SizedBox(height: 10),

            label('Description (optional)'),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(hintText: 'What\'s this ticket for?'),
              maxLines: 2,
              maxLength: 2000,
            ),
            const SizedBox(height: 10),

            // Flier — promo image players see on the ticket.
            label('Flier (optional)'),
            _FlierField(
              url: _flierUrl,
              uploading: _uploadingFlier,
              onPick: _pickFlier,
              onClear: () => setState(() => _flierUrl = null),
            ),
            const SizedBox(height: 18),

            label('Price'),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: '0.00',
                prefixText: '${widget.currency} ',
              ),
              validator: (v) {
                final d = double.tryParse((v ?? '').trim());
                return d == null || d <= 0 ? 'Enter a price greater than zero' : null;
              },
            ),
            hint('Tickets are sold in your wallet\'s currency (${widget.currency}).'),
            _FeePreview(
              groupId: widget.groupId,
              price: _price,
              currency: widget.currency,
              exponent: widget.exponent,
            ),
            const Divider(height: 32),

            // Q2 — is this tied to an event or tournament?
            label('Is this ticket for a specific event?'),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _kind,
              items: const [
                DropdownMenuItem(value: 'general', child: Text('No — a general ticket')),
                DropdownMenuItem(value: 'event', child: Text('Yes — tie it to an event')),
                DropdownMenuItem(
                    value: 'tournament', child: Text('Yes — tie it to a tournament')),
              ],
              onChanged: (v) => setState(() {
                // Switching kind clears a now-irrelevant event selection.
                _kind = v ?? 'general';
                _eventId = null;
              }),
            ),
            if (_isEvent) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('event-${events.length}-$_eventId'),
                initialValue: events.any((e) => e.id == _eventId) ? _eventId : null,
                hint: const Text('Choose an event'),
                items: [
                  for (final e in events)
                    DropdownMenuItem(
                      value: e.id,
                      child: Text(
                        '${e.title}${e.eventDate != null ? ' · ${formatDay(e.eventDate)}' : ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _eventId = v),
              ),
              hint(events.isEmpty
                  ? 'No upcoming events — create one first.'
                  : 'Players must hold this ticket to check in to that event.'),
            ],
            if (_isTournament) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('tournament-${tournaments.length}-$_eventId'),
                initialValue:
                    tournaments.any((t) => t.eventId == _eventId) ? _eventId : null,
                hint: const Text('Choose a tournament'),
                items: [
                  for (final t in tournaments)
                    DropdownMenuItem(
                        value: t.eventId,
                        child: Text(t.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _eventId = v),
              ),
              hint(tournaments.isEmpty
                  ? 'No tournaments yet — create one first.'
                  : 'Buyers don\'t check in — an officiant scans the ticket\'s QR code to admit entry at the game.'),
            ],
            const SizedBox(height: 14),

            // Q1 — blocks check-in? (not for officiant-scanned tournament tickets)
            if (!_isTournament) ...[
              switchRow(
                title: 'Required to check in',
                body: 'Unpaid players can\'t check into games/events.',
                value: _isEvent ? true : _blocksCheckin,
                onChanged: _isEvent ? null : (v) => setState(() => _blocksCheckin = v),
              ),
              const SizedBox(height: 10),
            ],

            // Q3 — scannable? Tournament tickets are always officiant-scanned.
            switchRow(
              title: _isTournament ? 'Scanned by an officiant' : 'Verify with a scan',
              body: _isTournament
                  ? 'An officiant scans the ticket\'s QR code at the game to admit entry.'
                  : 'Organizers can scan a code at the gate to validate entry. Every purchase already gets its own QR receipt.',
              value: _isTournament ? true : _requiresValidation,
              onChanged:
                  _isTournament ? null : (v) => setState(() => _requiresValidation = v),
            ),
            const SizedBox(height: 14),

            // Q4 — recurring? Fixed once created: the cadence sets the validity.
            label('Does this repeat?'),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _recurrence,
              items: const [
                DropdownMenuItem(value: 'one_time', child: Text('One-time — pay once')),
                DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),
                DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
              ],
              onChanged:
                  editing ? null : (v) => setState(() => _recurrence = v ?? 'one_time'),
            ),
            if (editing)
              hint('How often a ticket renews can\'t change after it\'s created — '
                  'create a new ticket instead.')
            else if (_isRecurring)
              hint('Players pay again each period — dues, memberships, season fees.'),
            if (_isEvent && _isRecurring)
              hint('Covers every occurrence of this event during each cycle '
                  '(e.g. a monthly pass for a weekly session).'),

            // Validity — how long a purchase admits you. Set by SportPadi on
            // create, from the first day; read-only afterwards.
            if (preview != null) ...[
              const SizedBox(height: 14),
              label('First day'),
              _PickerTile(
                value: DateFormat('EEE d MMM yyyy').format(_firstDay),
                onTap: _pickFirstDay,
              ),
              infoBox(
                'Valid ${preview.current} · renews every ${cycleUnit(_recurrence)} '
                    '(next: ${preview.next})',
                'Validity is set by SportPadi from the first day and can\'t be changed '
                    'later. When a cycle\'s last day ends, a fresh ticket starts the next '
                    'cycle; last cycle\'s tickets are used up and can\'t be refunded.',
              ),
            ],
            if (editValidity != null)
              infoBox(
                'Valid $editValidity · cycle $cycleNo',
                'Set by SportPadi when the ticket was created — it can\'t be changed.',
              ),
            const Divider(height: 32),

            // Robustness extras
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  label('Sales open (optional)'),
                  _PickerTile(
                    value: _salesStart == null
                        ? (_isRecurring ? 'Cycle start' : 'Now')
                        : fmt.format(_salesStart!),
                    onTap: () => _pickDate(true),
                    onClear:
                        _salesStart == null ? null : () => setState(() => _salesStart = null),
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  label('Sales close (optional)'),
                  _PickerTile(
                    value: _salesEnd == null
                        ? (_isRecurring ? 'Cycle end' : 'Never')
                        : fmt.format(_salesEnd!),
                    onTap: () => _pickDate(false),
                    onClear: _salesEnd == null ? null : () => setState(() => _salesEnd = null),
                  ),
                ]),
              ),
            ]),
            if (_isRecurring)
              hint('When people can buy it. Leave empty to sell for the whole cycle.'),
            const SizedBox(height: 14),

            label('Capacity (optional)'),
            TextFormField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'Unlimited'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = int.tryParse(v.trim());
                return n == null || n <= 0 ? 'Enter a whole number above 0' : null;
              },
            ),
            const SizedBox(height: 14),

            switchRow(
              title: 'Active',
              body: 'Visible and on sale to players.',
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            // The app's button theme makes buttons full-width by default
            // (minimumSize: infinity), which a Row can't satisfy — so both get
            // an Expanded slot: Cancel small, Save twice as wide.
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _busy || _uploadingFlier ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(editing ? 'Save changes' : 'Create ticket'),
                ),
              ),
            ]),
          ],
          ),
        ),
      ),
    );
  }
}

/// The web's flier block: a 16:9 dashed drop zone, or the image with
/// Replace / remove over it.
class _FlierField extends StatelessWidget {
  const _FlierField({
    required this.url,
    required this.uploading,
    required this.onPick,
    required this.onClear,
  });
  final String? url;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            Image.network(url!, fit: BoxFit.cover),
            Positioned(
              top: 8,
              right: 8,
              child: Row(children: [
                FilledButton.tonal(
                  onPressed: uploading ? null : onPick,
                  // Same theme trap: an explicit minimumSize keeps it from
                  // asking a Row for infinite width.
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10)),
                  child: uploading
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Replace'),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ]),
            ),
          ]),
        ),
      );
    }
    return InkWell(
      onTap: uploading ? null : onPick,
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: p.line, width: 2, strokeAlign: BorderSide.strokeAlignInside),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (uploading)
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(Icons.image_outlined, size: 26, color: p.muted),
            const SizedBox(height: 6),
            Text(uploading ? 'Uploading…' : 'Upload a flier',
                style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
            Text('Shown to players · 16:9 works best',
                style: TextStyle(color: p.muted, fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({required this.value, required this.onTap, this.onClear});
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: p.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          if (onClear != null)
            InkWell(
              onTap: onClear,
              child: Icon(Icons.close_rounded, size: 16, color: p.muted),
            )
          else
            Icon(Icons.calendar_today_rounded, size: 14, color: p.muted),
        ]),
      ),
    );
  }
}


/// "Buyers pay X · you receive Y" under the ticket price, split the way
/// checkout will split it for the group's fee setting (Wallet → Who pays the
/// fees?).
class _FeePreview extends ConsumerStatefulWidget {
  const _FeePreview({
    required this.groupId,
    required this.price,
    required this.currency,
    required this.exponent,
  });
  final String groupId;
  final TextEditingController price;
  final String currency;
  final int exponent;

  @override
  ConsumerState<_FeePreview> createState() => _FeePreviewState();
}

class _FeePreviewState extends ConsumerState<_FeePreview> {
  Timer? _debounce;
  FeeQuote? _quote;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    widget.price.addListener(_onChange);
    _onChange(immediate: true);
  }

  @override
  void dispose() {
    widget.price.removeListener(_onChange);
    _debounce?.cancel();
    super.dispose();
  }

  int _minor() {
    final d = double.tryParse(widget.price.text.trim()) ?? 0;
    if (d <= 0) return 0;
    var m = d;
    for (var i = 0; i < widget.exponent; i++) {
      m *= 10;
    }
    return m.round();
  }

  void _onChange({bool immediate = false}) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: immediate ? 0 : 400), () async {
      final minor = _minor();
      if (minor <= 0) {
        if (mounted) setState(() => _quote = null);
        return;
      }
      if (minor == _asked && _quote != null) return;
      _asked = minor;
      try {
        final q = await ref.read(walletRepositoryProvider).feeQuote(widget.groupId, minor);
        if (mounted && _asked == minor) setState(() => _quote = q);
      } catch (_) {
        // Preview only — checkout still validates. Don't leave the previous
        // price's split on screen.
        if (mounted && _asked == minor) {
          _asked = 0;
          setState(() => _quote = null);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    if (q == null) return const SizedBox.shrink();
    final p = context.palette;
    String money(int m) => formatMoney(m, widget.currency, widget.exponent);
    final note = q.tooLow
        ? 'This price is too low — the fees would take more than half of it. Raise the price.'
        : q.bearer == 'group'
            ? 'Your group pays the fees, so they come out of what you receive. Change this in Wallet.'
            : 'Buyers pay the fees on top of your price. Set who pays in Wallet.';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: q.tooLow ? p.orangeTint : p.surface2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(
          style: TextStyle(color: q.tooLow ? p.orangeInk : p.ink, fontSize: 12.5),
          children: [
            const TextSpan(text: 'Buyers pay '),
            TextSpan(
                text: money(q.buyerPaysMinor),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            const TextSpan(text: ' · you receive '),
            TextSpan(
                text: money(q.groupReceivesMinor),
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        )),
        const SizedBox(height: 2),
        Text(note, style: TextStyle(color: p.muted, fontSize: 11)),
      ]),
    );
  }
}
