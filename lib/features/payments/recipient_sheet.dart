import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/payments/payments_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// "Who is this ticket for?" — pick the people one purchase covers. The buyer
/// can include or exclude themselves; every other ticket is attached to a
/// SportPadi user found by username or exact email. Pops with the recipient
/// ids ('me' stands for the buyer; the API bridge resolves it), or null.
Future<List<String>?> showRecipientSheet(
  BuildContext context, {
  required int priceMinor,
  required int feeMinor,
  required String currency,
  required int exponent,
  int? maxTotal,
  bool selfPaid = false,
}) {
  return showSpSheet<List<String>>(
    context,
    builder: (_) => _RecipientSheet(
      priceMinor: priceMinor,
      feeMinor: feeMinor,
      currency: currency,
      exponent: exponent,
      maxTotal: maxTotal,
      selfPaid: selfPaid,
    ),
  );
}

class _RecipientSheet extends ConsumerStatefulWidget {
  const _RecipientSheet({
    required this.priceMinor,
    required this.feeMinor,
    required this.currency,
    required this.exponent,
    this.maxTotal,
    this.selfPaid = false,
  });
  final int priceMinor;
  final int feeMinor;
  final String currency;
  final int exponent;
  final int? maxTotal;
  final bool selfPaid;

  @override
  ConsumerState<_RecipientSheet> createState() => _RecipientSheetState();
}

class _RecipientSheetState extends ConsumerState<_RecipientSheet> {
  late bool _includeSelf = !widget.selfPaid;
  final List<RecipientUser> _others = [];
  final _search = TextEditingController();
  Timer? _debounce;
  List<RecipientUser> _results = const [];
  bool _searching = false;

  int get _cap {
    final m = widget.maxTotal;
    return m == null ? 20 : (m < 20 ? m : 20);
  }

  int get _count => (_includeSelf ? 1 : 0) + _others.length;
  bool get _full => _count >= _cap;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _runSearch(String q) {
    _debounce?.cancel();
    final query = q.trim();
    if (query.length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _searching = true);
      try {
        final res =
            await ref.read(paymentsRepositoryProvider).searchRecipients(query);
        if (!mounted) return;
        setState(() => _results =
            res.where((r) => !_others.any((o) => o.userId == r.userId)).toList());
      } catch (_) {
        if (mounted) setState(() => _results = const []);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final priceSum = _count * widget.priceMinor;
    final feeSum = _count * widget.feeMinor;
    final total = priceSum + feeSum;
    return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SpSheetHeader(
                icon: Icons.group_add_outlined,
                title: 'Who is this for?',
                subtitle:
                    'One purchase can cover several people — each gets their own ticket and receipt.',
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeSelf,
                onChanged: widget.selfPaid || (!_includeSelf && _full)
                    ? null
                    : (v) => setState(() => _includeSelf = v),
                title: const Text('Include myself'),
                subtitle: Text(widget.selfPaid
                    ? 'You already have this ticket.'
                    : _includeSelf
                        ? "You'll get a ticket + receipt of your own."
                        : "You're paying for others only — no receipt for you."),
              ),
              for (final r in _others)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _avatar(r),
                  title: Text(r.displayName),
                  subtitle: Text('@${r.username}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _others.remove(r)),
                  ),
                ),
              if (_full)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    widget.maxTotal != null && widget.maxTotal! < 20
                        ? 'Only ${widget.maxTotal} left — that\'s the most this purchase can cover.'
                        : 'That\'s the most one purchase can cover.',
                    style: TextStyle(color: p.amber, fontSize: 11.5),
                  ),
                )
              else ...[
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    labelText: 'Add someone — @username or exact email',
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2)))
                        : const Icon(Icons.search_rounded),
                  ),
                  onChanged: _runSearch,
                ),
                for (final r in _results)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _avatar(r),
                    title: Text(r.displayName),
                    subtitle: Text('@${r.username}'),
                    trailing: Icon(Icons.person_add_alt_rounded, color: p.accent),
                    onTap: () => setState(() {
                      _others.add(r);
                      _results = const [];
                      _search.clear();
                    }),
                  ),
                if (_search.text.trim().length >= 2 &&
                    !_searching &&
                    _results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'No one found — usernames and exact emails are the handles that work.',
                      style: TextStyle(color: p.muted, fontSize: 11.5),
                    ),
                  ),
              ],
              if (_count > 0) ...[
                const SizedBox(height: 14),
                // The payment step: ticket price and fees, spelled out.
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.palette.surface2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(children: [
                    _priceRow(
                        'Ticket${_count > 1 ? ' × $_count' : ''}',
                        formatMoney(priceSum, widget.currency, widget.exponent)),
                    if (feeSum > 0)
                      _priceRow('Fees',
                          formatMoney(feeSum, widget.currency, widget.exponent)),
                    _priceRow(
                        'Total',
                        formatMoney(total, widget.currency, widget.exponent),
                        bold: true),
                  ]),
                ),
              ],
              const SizedBox(height: 14),
              SpButton(
                label: _count == 0
                    ? 'Add at least one person'
                    : 'Pay ${formatMoney(total, widget.currency, widget.exponent)}',
                icon: Icons.confirmation_num_rounded,
                expand: true,
                onTap: _count == 0
                    ? null
                    : () => Navigator.pop(context, <String>[
                          if (_includeSelf) 'me',
                          ..._others.map((r) => r.userId),
                        ]),
              ),
            ],
          );
  }

  Widget _priceRow(String k, String v, {bool bold = false}) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(k, style: TextStyle(color: p.muted, fontSize: 12))),
        Text(v,
            style: TextStyle(
                color: p.ink,
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      ]),
    );
  }

  Widget _avatar(RecipientUser r) => CircleAvatar(
        radius: 16,
        backgroundImage: r.avatarUrl != null
            ? CachedNetworkImageProvider(r.avatarUrl!)
            : null,
        child: r.avatarUrl == null
            ? Text(r.displayName.isNotEmpty ? r.displayName[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 12))
            : null,
      );
}
