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
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        // Left-aligned two-line title. On iOS the toolbar centres the title
        // by default, and a centred two-line Column was what ended up
        // colliding with the leading button.
        centerTitle: false,
        titleSpacing: 0,
        title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tickets',
                  style: TextStyle(
                      color: p.ink, fontSize: 16, fontWeight: FontWeight.w700)),
              Text(
                '$groupName${activeCount != null ? ' · $activeCount active' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.muted, fontSize: 11),
              ),
            ]),
        actions: [
          // Gate validation: scan holders' ticket QRs.
          IconButton(
            tooltip: 'Scan tickets',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => context.push('/scan'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: walletOk
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _openEditor(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New ticket'),
            )
          : null,
      body: AsyncView<List<ManagedTicket>>(
        value: tickets,
        onRetry: _refetch,
        data: (list) => RefreshIndicator(
          onRefresh: () async => _refetch(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (wallet != null && !walletOk)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassCard(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: p.amber.withAlpha(38),
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.shield_outlined, color: p.amber, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Activate your wallet to sell tickets',
                              style: TextStyle(
                                  color: p.ink, fontSize: 14, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                              'Ticket prices use your wallet\'s settlement currency, so you '
                              'need a wallet before creating tickets.',
                              style: TextStyle(color: p.muted, fontSize: 12)),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => context.push('/groups/${widget.groupId}/wallet'),
                            child: const Text('Go to wallet'),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
              if (list.isEmpty)
                GlassCard(
                  padding: const EdgeInsets.all(28),
                  child: Column(children: [
                    Icon(Icons.confirmation_num_outlined, size: 40, color: p.muted),
                    const SizedBox(height: 10),
                    Text('No tickets yet',
                        style: TextStyle(
                            color: p.ink, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Create a paid ticket for an event, dues, or a one-off like a BBQ.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.muted, fontSize: 12.5)),
                    if (walletOk) ...[
                      const SizedBox(height: 14),
                      SpButton(
                        label: 'Create your first ticket',
                        icon: Icons.add_rounded,
                        onTap: () => _openEditor(),
                      ),
                    ],
                  ]),
                )
              else
                for (final t in list) ...[
                  _TicketRow(ticket: t, onTap: () => _openDetail(t)),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        ),
      ),
    );
  }
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
    final sub = [
      formatMoney(t.priceMinor, t.currency, t.currencyExponent),
      t.soldLabel,
      if (t.recurrence != 'one_time') _recurrenceLabel[t.recurrence] ?? t.recurrence,
    ].join(' · ');

    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: Opacity(
        opacity: t.isActive ? 1 : 0.6,
        child: Row(children: [
          _Thumb(url: t.flierUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
                if (t.kind == 'event') ...[
                  const SizedBox(width: 6),
                  Icon(Icons.calendar_month_rounded, size: 13, color: p.accent),
                ],
                if (t.kind == 'tournament') ...[
                  const SizedBox(width: 6),
                  Icon(Icons.emoji_events_outlined, size: 13, color: p.accent),
                ],
                if (!t.isActive) ...[
                  const SizedBox(width: 6),
                  SpBadge('Hidden', tone: p.muted),
                ],
              ]),
              const SizedBox(height: 2),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: p.muted, size: 20),
        ]),
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
      borderRadius: BorderRadius.circular(10),
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              p.accent.withAlpha(64),
              p.accent.withAlpha(26),
              const Color(0xFF0EA5E9).withAlpha(51),
            ],
          ),
        ),
        child: Icon(Icons.confirmation_num_rounded,
            size: size * 0.45, color: p.accent.withAlpha(128)),
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

    Widget badge(IconData icon, String label, {Color? tone}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: tone != null ? tone.withAlpha(30) : Colors.transparent,
            border: Border.all(color: tone ?? p.line),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: tone ?? p.muted),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: tone ?? p.ink, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ]),
        );

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Thumb(url: t.flierUrl, size: 56),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.title,
                  style: TextStyle(color: p.ink, fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                '${formatMoney(t.priceMinor, t.currency, t.currencyExponent)}'
                '${t.capacity != null ? ' · cap ${t.capacity}' : ''}',
                style: TextStyle(color: p.muted, fontSize: 13),
              ),
            ]),
          ),
        ]),
        if (t.description != null && t.description!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(t.description!, style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (t.kind == 'event')
            badge(Icons.calendar_month_rounded, t.eventTitle ?? 'Event', tone: p.accent),
          if (t.kind == 'tournament')
            badge(Icons.emoji_events_outlined, t.eventTitle ?? 'Tournament', tone: p.accent),
          if (t.blocksCheckin) badge(Icons.shield_outlined, 'Required for check-in'),
          if (t.requiresValidation) badge(Icons.qr_code_2_rounded, 'Scannable'),
          if (t.recurrence != 'one_time')
            badge(Icons.repeat_rounded, _recurrenceLabel[t.recurrence] ?? t.recurrence),
          if (t.salesStartAt != null)
            badge(Icons.play_arrow_rounded, 'from ${fmtDay.format(t.salesStartAt!.toLocal())}'),
          if (t.salesEndAt != null)
            badge(Icons.stop_rounded, 'until ${fmtDay.format(t.salesEndAt!.toLocal())}'),
          if (t.soldOut) badge(Icons.block_rounded, 'Sold out', tone: p.danger),
        ]),
        const SizedBox(height: 12),

        // Active switch + View / Edit / Delete — the web's action row.
        Row(children: [
          Switch(
            value: t.isActive,
            onChanged: (v) => onToggleActive(t, v),
          ),
          const SizedBox(width: 4),
          Text(t.isActive ? 'Active' : 'Hidden',
              style: TextStyle(color: p.muted, fontSize: 13)),
          const Spacer(),
          _iconAction(p, Icons.open_in_new_rounded, 'View', () {
            launchUrl(Uri.parse('$base/t/${t.id}'), mode: LaunchMode.inAppBrowserView);
          }),
          _iconAction(p, Icons.edit_outlined, 'Edit', () => onEdit(t)),
          _iconAction(p, Icons.delete_outline_rounded, 'Delete', () => onDelete(t),
              color: p.danger),
        ]),
        if (t.soldCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Has sales, so it can\'t be deleted — switch it off to hide it.',
                style: TextStyle(color: p.muted, fontSize: 11)),
          ),
        const Divider(height: 28),

        // Payments
        AsyncView<TicketSales>(
          value: sales,
          data: (s) {
            final rows = s.sales;
            final paid = rows.where((r) => r.status == 'paid').toList();
            final total = paid.fold<int>(0, (a, r) => a + r.amount);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('PAYMENTS',
                    style: TextStyle(
                        color: p.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2)),
                const Spacer(),
                Text(
                  '${paid.length} paid · ${formatMoney(total, t.currency, s.currencyExponent)}',
                  style: TextStyle(color: p.muted, fontSize: 11.5),
                ),
              ]),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                      child:
                          Text('No payments yet.', style: TextStyle(color: p.muted, fontSize: 13))),
                )
              else
                for (final r in rows)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: p.line),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: p.surface2,
                        backgroundImage:
                            r.buyerAvatarUrl != null ? NetworkImage(r.buyerAvatarUrl!) : null,
                        child: r.buyerAvatarUrl == null
                            ? Text(r.buyerName.isNotEmpty ? r.buyerName[0].toUpperCase() : '?',
                                style: TextStyle(color: p.muted, fontSize: 12))
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.buyerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w600)),
                          Text(
                            [
                              if (r.paidAt != null) fmt.format(r.paidAt!.toLocal()),
                              if (r.periodKey != null) r.periodKey!,
                            ].join(' · '),
                            style: TextStyle(color: p.muted, fontSize: 11),
                          ),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(formatMoney(r.amount, r.currency, s.currencyExponent),
                            style: TextStyle(
                                color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
                        Text(
                          r.redeemedAt != null ? '✓ used' : r.status,
                          style: TextStyle(
                            color: r.redeemedAt != null || r.status == 'paid'
                                ? p.accent
                                : r.status == 'failed'
                                    ? p.danger
                                    : r.status == 'refunded'
                                        ? p.amber
                                        : p.muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ]),
                    ]),
                  ),
            ]);
          },
        ),
      ],
    );
  }

  Widget _iconAction(AppPalette p, IconData icon, String label, VoidCallback onTap,
          {Color? color}) =>
      TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: color ?? p.ink,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12.5)),
      );
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
  bool _busy = false;
  bool _uploadingFlier = false;
  String? _error;

  bool get _isEvent => _kind == 'event';
  bool get _isTournament => _kind == 'tournament';

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
      'recurrence': _recurrence,
      'salesStartAt': _salesStart?.toUtc().toIso8601String(),
      'salesEndAt': _salesEnd?.toUtc().toIso8601String(),
      'capacity': _capacity.text.trim().isEmpty ? null : int.tryParse(_capacity.text.trim()),
      'isActive': _isActive,
    };
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
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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

            // Q4 — recurring?
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
              onChanged: (v) => setState(() => _recurrence = v ?? 'one_time'),
            ),
            if (_recurrence != 'one_time')
              hint('Players pay again each period — dues, memberships, season fees.'),
            const Divider(height: 32),

            // Robustness extras
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  label('Sales open (optional)'),
                  _PickerTile(
                    value: _salesStart == null ? 'Now' : fmt.format(_salesStart!),
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
                    value: _salesEnd == null ? 'Never' : fmt.format(_salesEnd!),
                    onTap: () => _pickDate(false),
                    onClear: _salesEnd == null ? null : () => setState(() => _salesEnd = null),
                  ),
                ]),
              ),
            ]),
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
