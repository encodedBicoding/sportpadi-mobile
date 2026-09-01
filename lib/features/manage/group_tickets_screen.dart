import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/manage/manage_repository.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/tickets/ticket_models.dart';
import 'package:sportpadi_mobile/data/tickets/tickets_repository.dart';
import 'package:sportpadi_mobile/data/tournaments/tournaments_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

const _recurrenceLabel = {
  'one_time': 'One-time',
  'weekly': 'Weekly',
  'monthly': 'Monthly',
  'quarterly': 'Quarterly',
  'yearly': 'Yearly',
};

/// Ticket setup for group admins — create/edit/hide/delete tickets, see sales.
/// Mirrors the web group tickets page.
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

  Future<void> _actions(ManagedTicket t) async {
    final p = context.palette;
    final base = ref.read(appConfigProvider).apiBaseUrl;
    final link = '$base/t/${t.id}';
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(t.title, style: TextStyle(color: p.ink, fontWeight: FontWeight.w800)),
            subtitle: Text(
                '${formatMoney(t.priceMinor, t.currency, t.currencyExponent)} · ${t.soldLabel}',
                style: TextStyle(color: p.muted)),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('Edit'),
            onTap: () {
              Navigator.pop(ctx);
              _openEditor(existing: t);
            },
          ),
          ListTile(
            leading: const Icon(Icons.people_alt_rounded),
            title: Text('Sales (${t.soldCount})'),
            onTap: () {
              Navigator.pop(ctx);
              _showSales(t);
            },
          ),
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('Copy payment link'),
            subtitle: Text(link, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (ctx.mounted) Navigator.pop(ctx);
              _snack('Link copied');
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_rounded),
            title: const Text('Share…'),
            onTap: () {
              Navigator.pop(ctx);
              launchUrl(
                  Uri.parse(
                      'https://wa.me/?text=${Uri.encodeComponent('${t.title} — pay securely on SportPadi $link')}'),
                  mode: LaunchMode.externalApplication);
            },
          ),
          ListTile(
            leading: Icon(t.isActive ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            title: Text(t.isActive ? 'Hide from players' : 'Show to players'),
            onTap: () {
              Navigator.pop(ctx);
              _run(() async {
                await ref
                    .read(ticketsRepositoryProvider)
                    .setActive(widget.groupId, t.id, !t.isActive);
                _refetch();
              });
            },
          ),
          if (t.soldCount == 0)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: p.danger),
              title: Text('Delete', style: TextStyle(color: p.danger)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Delete this ticket?'),
                    content: const Text('This can\'t be undone.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                    ],
                  ),
                );
                if (ok == true) {
                  _run(() async {
                    await ref.read(ticketsRepositoryProvider).remove(widget.groupId, t.id);
                    _refetch();
                  });
                }
              },
            )
          else
            const ListTile(
              enabled: false,
              leading: Icon(Icons.delete_outline_rounded),
              title: Text('Delete'),
              subtitle: Text('Has sales — hide it instead'),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _showSales(ManagedTicket t) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (ctx, controller) => _SalesSheet(
            groupId: widget.groupId, ticket: t, controller: controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tickets = ref.watch(managedTicketsProvider(widget.groupId));
    final wallet = ref.watch(groupWalletProvider(widget.groupId)).valueOrNull;
    final walletOk = wallet?.active ?? false;
    return Scaffold(
      appBar: AppBar(backgroundColor: p.bg, title: const Text('Tickets')),
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
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Activate your group wallet first',
                          style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                          'Tickets are sold in your wallet\'s currency and settle to its bank. Set it up, then come back here.',
                          style: TextStyle(color: p.muted, fontSize: 12.5)),
                      const SizedBox(height: 10),
                      SpButton(
                        label: 'Open wallet',
                        icon: Icons.account_balance_wallet_outlined,
                        onTap: () => context.push('/groups/${widget.groupId}/wallet'),
                      ),
                    ]),
                  ),
                ),
              if (list.isEmpty)
                GlassCard(
                  padding: const EdgeInsets.all(28),
                  child: Column(children: [
                    Icon(Icons.confirmation_num_outlined, size: 36, color: p.muted),
                    const SizedBox(height: 8),
                    Text('No tickets yet',
                        style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                        'Create a general pass (dues), an event ticket that\'s required to check in, or a tournament entry ticket.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.muted, fontSize: 12.5)),
                  ]),
                )
              else
                for (final t in list) ...[
                  _TicketCard(ticket: t, onTap: () => _actions(t)),
                  const SizedBox(height: 8),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onTap});
  final ManagedTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = ticket;
    final kindLabel = switch (t.kind) {
      'event' => 'Event',
      'tournament' => 'Tournament',
      _ => 'General pass',
    };
    final meta = <String>[
      t.soldLabel,
      if (t.recurrence != 'one_time') _recurrenceLabel[t.recurrence] ?? t.recurrence,
      if (t.eventTitle != null) t.eventTitle!,
      if (t.salesStartAt != null) 'from ${formatDayYear(t.salesStartAt)}',
      if (t.salesEndAt != null) 'until ${formatDayYear(t.salesEndAt)}',
    ];
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Opacity(
        opacity: t.isActive ? 1 : 0.6,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color.fromRGBO(14, 165, 233, 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.confirmation_num_rounded, size: 20, color: Color(0xFF0EA5E9)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w800)),
                ),
                Text(formatMoney(t.priceMinor, t.currency, t.currencyExponent),
                    style: TextStyle(color: p.ink, fontSize: 14, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                SpBadge(kindLabel, tone: p.muted),
                if (t.blocksCheckin) SpBadge('🔒 Required to check in', tone: p.amber),
                if (t.requiresValidation) SpBadge('Scan at gate', tone: p.muted),
                if (!t.isActive) SpBadge('Hidden', tone: p.muted),
                if (t.soldOut) SpBadge('Sold out', tone: p.danger),
              ]),
              const SizedBox(height: 4),
              Text(meta.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 11.5)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Create / edit form.
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
  late String _kind;
  String? _eventId;
  late bool _blocksCheckin;
  late bool _requiresValidation;
  late String _recurrence;
  DateTime? _salesStart;
  DateTime? _salesEnd;
  bool _busy = false;
  String? _error;

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
        text: t != null ? (t.priceMinor / _pow10(t.currencyExponent)).toStringAsFixed(t.currencyExponent) : '');
    _capacity = TextEditingController(text: t?.capacity?.toString() ?? '');
    _kind = t?.kind ?? 'general';
    _eventId = t?.eventId;
    _blocksCheckin = t?.blocksCheckin ?? false;
    _requiresValidation = t?.requiresValidation ?? false;
    _recurrence = t?.recurrence ?? 'one_time';
    _salesStart = t?.salesStartAt;
    _salesEnd = t?.salesEndAt;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    if ((_kind == 'event' || _kind == 'tournament') && _eventId == null) {
      setState(() => _error = 'Pick the ${_kind == 'event' ? 'event' : 'tournament'} this ticket is for.');
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
      'price': (price * _pow10(widget.exponent)).round(),
      'kind': _kind,
      'eventId': _kind == 'general' ? null : _eventId,
      'blocksCheckin': _kind == 'event' ? true : _kind == 'tournament' ? false : _blocksCheckin,
      'requiresValidation': _requiresValidation,
      'recurrence': _kind == 'general' ? _recurrence : 'one_time',
      'salesStartAt': _salesStart?.toUtc().toIso8601String(),
      'salesEndAt': _salesEnd?.toUtc().toIso8601String(),
      'capacity': _capacity.text.trim().isEmpty ? null : int.tryParse(_capacity.text.trim()),
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
    if (d == null) return;
    if (!mounted) return;
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
    final events = ref.watch(groupEventsProvider(widget.groupId)).valueOrNull ?? const [];
    final tournaments =
        ref.watch(groupTournamentsProvider(widget.groupId)).valueOrNull ?? const [];
    final fmt = DateFormat('EEE d MMM, HH:mm');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        title: Text(editing ? 'Edit ticket' : 'New ticket'),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Kind
            Text('What is this ticket for?', style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'general', label: Text('General')),
                ButtonSegment(value: 'event', label: Text('Event')),
                ButtonSegment(value: 'tournament', label: Text('Tournament')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _eventId = null;
              }),
            ),
            const SizedBox(height: 6),
            Text(
              switch (_kind) {
                'event' => 'Tied to one event and required to check in there.',
                'tournament' => 'Entry ticket for a tournament you host.',
                _ => 'A group pass — dues, membership, or a season fee. Can be required to check in to every event.',
              },
              style: TextStyle(color: p.muted, fontSize: 11.5),
            ),
            if (_kind == 'event') ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                // initialValue is only read once — re-key when the list arrives
                // so an existing ticket's event shows up once events have loaded.
                key: ValueKey('event-${events.length}-$_eventId'),
                initialValue: events.any((e) => e.id == _eventId) ? _eventId : null,
                decoration: const InputDecoration(labelText: 'Event'),
                items: [
                  for (final e in events.where((e) => !e.isTournament))
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
              if (events.where((e) => !e.isTournament).isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('No upcoming events — create one first.',
                      style: TextStyle(color: p.amber, fontSize: 11.5)),
                ),
            ],
            if (_kind == 'tournament') ...[
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                key: ValueKey('tournament-${tournaments.length}-$_eventId'),
                initialValue: tournaments.any((t) => t.eventId == _eventId) ? _eventId : null,
                decoration: const InputDecoration(labelText: 'Tournament'),
                items: [
                  for (final t in tournaments)
                    DropdownMenuItem(
                        value: t.eventId,
                        child: Text(t.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _eventId = v),
              ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              maxLength: 120,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Add a title' : null,
            ),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              maxLines: 3,
              maxLength: 2000,
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Price',
                prefixText: '${widget.currency} ',
                helperText: 'You receive this in full — buyers pay fees on top.',
              ),
              validator: (v) {
                final d = double.tryParse((v ?? '').trim());
                return d == null || d <= 0 ? 'Enter a price above 0' : null;
              },
            ),
            const SizedBox(height: 14),
            if (_kind == 'general') ...[
              DropdownButtonFormField<String>(
                initialValue: _recurrence,
                decoration: const InputDecoration(labelText: 'Recurrence'),
                items: [
                  for (final e in _recurrenceLabel.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _recurrence = v ?? 'one_time'),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _blocksCheckin,
                onChanged: (v) => setState(() => _blocksCheckin = v),
                title: const Text('Required to check in'),
                subtitle: const Text('Unpaid players can\'t check in to any of your events.'),
              ),
            ],
            if (_kind == 'event')
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_rounded, color: p.amber),
                title: const Text('Required to check in'),
                subtitle: const Text('Always on for event tickets — pay before scanning in.'),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _requiresValidation,
              onChanged: (v) => setState(() => _requiresValidation = v),
              title: const Text('Scan-verify at the gate'),
              subtitle: const Text('Organizers scan the buyer\'s receipt QR to redeem it.'),
            ),
            const SizedBox(height: 8),
            Text('Sales window (optional)', style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: _PickerTile(
                  label: 'Opens',
                  value: _salesStart == null ? 'Now' : fmt.format(_salesStart!),
                  onTap: () => _pickDate(true),
                  onClear: _salesStart == null ? null : () => setState(() => _salesStart = null),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PickerTile(
                  label: 'Closes',
                  value: _salesEnd == null ? 'Never' : fmt.format(_salesEnd!),
                  onTap: () => _pickDate(false),
                  onClear: _salesEnd == null ? null : () => setState(() => _salesEnd = null),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            TextFormField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Limit (optional)',
                helperText: 'How many can buy. Buyers see "3/10 sold"; at the limit it\'s sold out.',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null;
                final n = int.tryParse(v.trim());
                return n == null || n <= 0 ? 'Enter a whole number above 0' : null;
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: p.danger, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(editing ? 'Save changes' : 'Create ticket'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({required this.label, required this.value, required this.onTap, this.onClear});
  final String label;
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: p.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: p.muted, fontSize: 11)),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (onClear != null)
            InkWell(
              onTap: onClear,
              child: Icon(Icons.close_rounded, size: 16, color: p.muted),
            ),
        ]),
      ),
    );
  }
}

class _SalesSheet extends ConsumerWidget {
  const _SalesSheet({required this.groupId, required this.ticket, required this.controller});
  final String groupId;
  final ManagedTicket ticket;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final sales = ref.watch(ticketSalesProvider((groupId: groupId, ticketId: ticket.id)));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(children: [
          Expanded(
            child: Text('${ticket.title} · ${ticket.soldLabel}',
                style: TextStyle(color: p.ink, fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: AsyncView<TicketSales>(
          value: sales,
          data: (s) {
            final rows = s.sales.where((x) => x.status == 'paid' || x.status == 'refunded').toList();
            if (rows.isEmpty) {
              return Center(
                  child: Text('No sales yet.', style: TextStyle(color: p.muted)));
            }
            return ListView.builder(
              controller: controller,
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage:
                        r.buyerAvatarUrl != null ? NetworkImage(r.buyerAvatarUrl!) : null,
                    child: r.buyerAvatarUrl == null
                        ? Text(r.buyerName.isNotEmpty ? r.buyerName[0].toUpperCase() : '?')
                        : null,
                  ),
                  title: Text(r.buyerName),
                  subtitle: Text([
                    if (r.buyerUsername != null) '@${r.buyerUsername}',
                    if (r.paidAt != null) timeAgo(r.paidAt),
                    if (r.periodKey != null) r.periodKey!,
                    if (r.redeemedAt != null) 'redeemed',
                  ].join(' · ')),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(formatMoney(r.amount, r.currency, s.currencyExponent),
                          style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
                      if (r.status == 'refunded')
                        Text('refunded', style: TextStyle(color: p.amber, fontSize: 11)),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
