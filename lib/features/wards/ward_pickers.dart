import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/data/events/events_repository.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart'
    show formatMoney;
import 'package:sportpadi_mobile/data/payments/payments_repository.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/data/wards/ward_models.dart';
import 'package:sportpadi_mobile/features/payments/checkout_flow.dart';
import 'package:sportpadi_mobile/features/wards/ward_widgets.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Acting for a ward (A5, A8): the "Who's going?" RSVP sheet on an event,
/// the "Who's checking in?" picker after an event QR is scanned, and the
/// per-person check-in results.

// ---------------------------------------------------------------------------
// Who's going? — RSVP me and/or my wards. Each switch saves on its own.
// ---------------------------------------------------------------------------

/// Pops true when anyone was newly RSVP'd (the caller may explain what an
/// RSVP means), false or null otherwise. The caller should refresh the event
/// either way.
Future<bool?> showWhoIsGoingSheet(BuildContext context,
        {required EventDetail event}) =>
    showSpSheet<bool>(context, builder: (_) => _WhoIsGoingSheet(event: event));

class _WhoIsGoingSheet extends ConsumerStatefulWidget {
  const _WhoIsGoingSheet({required this.event});
  final EventDetail event;

  @override
  ConsumerState<_WhoIsGoingSheet> createState() => _WhoIsGoingSheetState();
}

class _WhoIsGoingSheetState extends ConsumerState<_WhoIsGoingSheet> {
  late bool _me = widget.event.myInterested;
  late final Map<String, bool> _wards = {
    for (final w in widget.event.myWards) w.userId: w.interested,
  };
  final Set<String> _busy = {}; // '' is me
  bool _joined = false;
  String? _error;

  Future<void> _toggle(String? playerId) async {
    final key = playerId ?? '';
    if (_busy.contains(key)) return;
    setState(() {
      _busy.add(key);
      _error = null;
    });
    try {
      final going = await ref
          .read(eventsRepositoryProvider)
          .toggleInterest(widget.event.id, forPlayerId: playerId);
      if (!mounted) return;
      setState(() {
        if (playerId == null) {
          _me = going;
        } else {
          _wards[playerId] = going;
        }
        if (going) _joined = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = widget.event;
    final me = ref.watch(meProvider).valueOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SpSheetHeader(
          icon: Icons.how_to_reg_rounded,
          title: "Who's going?",
          subtitle:
              'RSVP for yourself and your wards. It tells the organiser who '
              'to expect — check-in still happens at the venue.',
        ),
        SpListCard(children: [
          _PersonSwitchRow(
            name: 'Me',
            sub: e.myCheckedIn ? 'Checked in' : (_me ? 'Going' : 'Not going'),
            avatarUrl: me?.avatarUrl,
            avatarName: me?.displayName ?? 'Me',
            value: _me,
            busy: _busy.contains(''),
            checkedIn: e.myCheckedIn,
            onChanged: () => _toggle(null),
          ),
          for (final w in e.myWards)
            _PersonSwitchRow(
              name: w.displayName,
              sub: [
                if (w.age != null) 'Age ${w.age}',
                'Ward',
                if (w.checkedIn)
                  'Checked in'
                else
                  (_wards[w.userId] ?? false) ? 'Going' : 'Not going',
              ].join(' · '),
              avatarUrl: w.avatarUrl,
              avatarName: w.displayName,
              value: _wards[w.userId] ?? false,
              busy: _busy.contains(w.userId),
              checkedIn: w.checkedIn,
              onChanged: () => _toggle(w.userId),
            ),
        ]),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
        ],
        const SizedBox(height: 16),
        SpButton(
          label: 'Done',
          icon: Icons.check_rounded,
          expand: true,
          onTap: () => Navigator.of(context).pop(_joined),
        ),
      ],
    );
  }
}

class _PersonSwitchRow extends StatelessWidget {
  const _PersonSwitchRow({
    required this.name,
    required this.sub,
    required this.avatarName,
    required this.value,
    required this.busy,
    required this.checkedIn,
    required this.onChanged,
    this.avatarUrl,
  });
  final String name;
  final String sub;
  final String? avatarUrl;
  final String avatarName;
  final bool value;
  final bool busy;
  final bool checkedIn;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final Widget trailing;
    if (checkedIn) {
      trailing = SpBadge('Checked in',
          icon: Icons.check_circle_rounded, tone: p.greenText);
    } else if (busy) {
      trailing = const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14),
        child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else {
      trailing = Switch(value: value, onChanged: (_) => onChanged());
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: [
        WardAvatar(name: avatarName, url: avatarUrl, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: p.ink, fontSize: 14.5, fontWeight: FontWeight.w700)),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: value || checkedIn ? p.greenText : p.muted,
                    fontSize: 12)),
          ]),
        ),
        const SizedBox(width: 8),
        trailing,
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Who's checking in? — after an event QR is read, for guardians.
// ---------------------------------------------------------------------------

/// A person to check in: [id] null is the signed-in user.
typedef CheckinPerson = ({String? id, String name});

/// Me (pre-selected) plus each ward, multi-select. Pops the chosen people in
/// order (me first), or null when dismissed.
Future<List<CheckinPerson>?> showWhoIsCheckingInSheet(BuildContext context,
        {required List<Ward> wards}) =>
    showSpSheet<List<CheckinPerson>>(context,
        builder: (_) => _WhoIsCheckingInSheet(wards: wards));

class _WhoIsCheckingInSheet extends ConsumerStatefulWidget {
  const _WhoIsCheckingInSheet({required this.wards});
  final List<Ward> wards;

  @override
  ConsumerState<_WhoIsCheckingInSheet> createState() =>
      _WhoIsCheckingInSheetState();
}

class _WhoIsCheckingInSheetState extends ConsumerState<_WhoIsCheckingInSheet> {
  final Set<String> _picked = {''}; // '' is me

  void _flip(String key) => setState(() {
        if (!_picked.remove(key)) _picked.add(key);
      });

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider).valueOrNull;
    final n = _picked.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SpSheetHeader(
          icon: Icons.qr_code_scanner_rounded,
          title: "Who's checking in?",
          subtitle: 'Pick everyone who is here with you.',
        ),
        SpListCard(children: [
          _PickRow(
            name: 'Me',
            sub: me?.displayName,
            avatarName: me?.displayName ?? 'Me',
            avatarUrl: me?.avatarUrl,
            selected: _picked.contains(''),
            onTap: () => _flip(''),
          ),
          for (final w in widget.wards)
            _PickRow(
              name: w.displayName,
              sub: [if (w.age != null) 'Age ${w.age}', 'Ward'].join(' · '),
              avatarName: w.displayName,
              avatarUrl: w.avatarUrl,
              selected: _picked.contains(w.userId),
              onTap: () => _flip(w.userId),
            ),
        ]),
        const SizedBox(height: 16),
        SpButton(
          label: n == 0
              ? 'Pick at least one person'
              : n == 1
                  ? 'Check in'
                  : 'Check in $n people',
          icon: Icons.how_to_reg_rounded,
          tone: SpButtonTone.brand,
          expand: true,
          onTap: n == 0
              ? null
              : () => Navigator.of(context).pop(<CheckinPerson>[
                    if (_picked.contains('')) (id: null, name: 'You'),
                    for (final w in widget.wards)
                      if (_picked.contains(w.userId))
                        (id: w.userId, name: w.firstName),
                  ]),
        ),
      ],
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.name,
    required this.avatarName,
    required this.selected,
    required this.onTap,
    this.sub,
    this.avatarUrl,
  });
  final String name;
  final String? sub;
  final String avatarName;
  final String? avatarUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(children: [
          WardAvatar(name: avatarName, url: avatarUrl, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
              if (sub != null && sub!.isNotEmpty)
                Text(sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: selected ? p.accentDeep : Colors.transparent,
              shape: BoxShape.circle,
              border: selected ? null : Border.all(color: p.line, width: 2),
            ),
            child: selected
                ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                : null,
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-person check-in results.
// ---------------------------------------------------------------------------

/// One person's check-in outcome, worded for the results list.
class CheckinOutcome {
  const CheckinOutcome({
    required this.name,
    required this.isMe,
    required this.status,
    required this.message,
    this.playerId,
    this.forWard = false,
    this.ticketIds = const [],
    this.totalMinor = 0,
    this.currency = '',
    this.currencyExponent = 2,
  });

  final String name;
  final bool isMe;

  /// The server status, or 'error' when the call itself failed.
  final String status;
  final String message;

  /// Who the check-in was for (the ward's id on a ward's row).
  final String? playerId;

  /// The row is one of my wards' (the server's `forWard`).
  final bool forWard;

  /// `payment_required`: the unpaid tickets, and what they come to.
  final List<String> ticketIds;
  final int totalMinor;
  final String currency;
  final int currencyExponent;

  bool get ok => status == 'checked_in' || status == 'already_checked_in';
  bool get isError => status == 'error';

  /// A ward's unpaid ticket(s): their guardian can pay right here (Wards 3).
  bool get canPayForWard =>
      status == 'payment_required' &&
      forWard &&
      playerId != null &&
      ticketIds.isNotEmpty;

  /// A ward's fine blocks the check-in: their guardian pays it on Fines.
  bool get wardFined => status == 'fined' && forWard;

  String get headline => switch (status) {
        'checked_in' => 'Checked in',
        'already_checked_in' => 'Already checked in',
        'payment_required' => 'Payment required',
        'limit_reached' => 'Check-ins are full',
        'fined' => 'Outstanding fine',
        'self_checkin' => 'Ask an admin to check you in',
        'error' => "Couldn't check in",
        _ => 'Not checked in',
      };

  factory CheckinOutcome.fromResult(Map<String, dynamic> res,
      {required String name, required bool isMe}) {
    final status = parseStr(res['status']) ?? '';
    final reason = parseStr(res['reason']);
    final title = parseStr(res['eventTitle']) ?? 'this event';
    // The server flags `forWard` on `payment_required` but not on `fined`;
    // any row that isn't mine is one of my wards (the caller knows).
    final forWard = res['forWard'] == true || !isMe;
    final message = switch (status) {
      'checked_in' => 'Checked in to $title.',
      'already_checked_in' => 'Already on the list for $title.',
      'payment_required' => forWard
          ? '$title needs a paid ticket for $name. Pay for them here, then '
              'scan again to check them in.'
          : 'This event needs a paid ticket before check-in. Open the event '
              'page to pay, then scan again.',
      'limit_reached' =>
        reason ?? "This group's monthly check-in limit has been reached.",
      'fined' => forWard
          ? '${reason ?? '$name has an unpaid fine with this group.'} '
              'You can pay it from Fines, then scan again.'
          : reason ??
              'There is an unpaid fine with this group — settle it to check in.',
      'self_checkin' =>
        reason ?? "Organisers can't check themselves in — ask another admin.",
      _ => 'Unexpected result: $status',
    };
    final outstanding = res['outstanding'] is List
        ? [
            for (final t in res['outstanding'] as List)
              if (t is Map && parseStr(t['id']) != null) parseStr(t['id'])!
          ]
        : const <String>[];
    return CheckinOutcome(
      name: name,
      isMe: isMe,
      status: status,
      message: message,
      playerId: parseStr(res['playerId']),
      forWard: forWard,
      ticketIds: outstanding,
      totalMinor: parseInt(res['totalMinor']) ?? 0,
      currency: parseStr(res['currency']) ?? '',
      currencyExponent: parseInt(res['currencyExponent']) ?? 2,
    );
  }

  factory CheckinOutcome.failed(
          {required String name, required bool isMe, required String message}) =>
      CheckinOutcome(
          name: name, isMe: isMe, status: 'error', message: message);
}

/// What the results sheet was closed with.
enum CheckinSheetAction { done, scanAgain, openFines }

/// Pops [CheckinSheetAction.done] for "Done", [CheckinSheetAction.scanAgain]
/// for "Scan another code" (also when dismissed), and
/// [CheckinSheetAction.openFines] from a ward's "See fines".
Future<CheckinSheetAction> showCheckinResultsSheet(BuildContext context,
    {required List<CheckinOutcome> results}) async {
  final r = await showSpSheet<CheckinSheetAction>(
    context,
    builder: (_) => _CheckinResultsSheet(results: results),
  );
  return r ?? CheckinSheetAction.scanAgain;
}

class _CheckinResultsSheet extends ConsumerStatefulWidget {
  const _CheckinResultsSheet({required this.results});
  final List<CheckinOutcome> results;

  @override
  ConsumerState<_CheckinResultsSheet> createState() =>
      _CheckinResultsSheetState();
}

class _CheckinResultsSheetState extends ConsumerState<_CheckinResultsSheet> {
  /// Rows (by index) being paid for / paid for in this sheet.
  final Set<int> _paying = {};
  final Set<int> _paid = {};

  /// "Pay for Tobi": the guardian pays, the ward holds the ticket(s).
  Future<void> _payFor(int i) async {
    final o = widget.results[i];
    final playerId = o.playerId;
    if (playerId == null || _paying.contains(i)) return;
    setState(() => _paying.add(i));
    try {
      final repo = ref.read(paymentsRepositoryProvider);
      final co =
          await repo.startBulkCheckout(o.ticketIds, forPlayerId: playerId);
      if (!mounted) return;
      final done = await runHostedCheckout(context, co.url);
      if (!done || co.code.isEmpty) return;
      final status = await repo.verify(co.code);
      if (!mounted) return;
      if (status == 'paid') {
        setState(() => _paid.add(i));
        ref.invalidate(myTicketsProvider);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == 'paid'
              ? 'Paid ✅ — scan again to check ${o.name} in.'
              : 'Payment $status — try scanning again in a moment.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _paying.remove(i));
    }
  }

  /// The fix-it button under a ward's row, if there is one.
  Widget? _rowAction(AppPalette p, int i) {
    final o = widget.results[i];
    if (o.canPayForWard) {
      if (_paid.contains(i)) {
        return Text('Paid — scan again to check ${o.name} in.',
            style: TextStyle(
                color: p.greenText,
                fontSize: 12.5,
                fontWeight: FontWeight.w700));
      }
      final busy = _paying.contains(i);
      final amount = o.currency.isEmpty || o.totalMinor <= 0
          ? ''
          : ' · ${formatMoney(o.totalMinor, o.currency, o.currencyExponent)}';
      return Align(
        alignment: Alignment.centerLeft,
        child: SpButton(
          label: busy ? 'Opening checkout…' : 'Pay for ${o.name}$amount',
          icon: Icons.lock_outline_rounded,
          tone: SpButtonTone.brand,
          onTap: busy ? null : () => _payFor(i),
        ),
      );
    }
    if (o.wardFined) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SpButton(
          label: 'See fines',
          icon: Icons.receipt_long_outlined,
          onTap: () =>
              Navigator.of(context).pop(CheckinSheetAction.openFines),
        ),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final results = widget.results;
    final allOk = results.every((r) => r.ok);
    final noneOk = !results.any((r) => r.ok);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: allOk
              ? Icons.check_rounded
              : noneOk
                  ? Icons.close_rounded
                  : Icons.priority_high_rounded,
          iconBg: allOk
              ? p.accentTint
              : noneOk
                  ? p.liveTint
                  : p.orangeTint,
          iconFg: allOk
              ? p.greenText
              : noneOk
                  ? p.danger
                  : p.orangeInk,
          title: allOk
              ? (results.length == 1 ? "You're all set" : "Everyone's in")
              : noneOk
                  ? 'Nobody was checked in'
                  : 'Some check-ins need attention',
          subtitle: allOk
              ? 'Have a great game.'
              : 'Here is how each check-in went.',
        ),
        SpListCard(children: [
          for (var i = 0; i < results.length; i++)
            _ResultRow(
              outcome: results[i],
              action: _rowAction(p, i),
            ),
        ]),
        const SizedBox(height: 16),
        SpButton(
          label: 'Done',
          icon: Icons.check_rounded,
          expand: true,
          onTap: () => Navigator.of(context).pop(CheckinSheetAction.done),
        ),
        const SizedBox(height: 8),
        Material(
          color: p.surface2,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () =>
                Navigator.of(context).pop(CheckinSheetAction.scanAgain),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner_rounded, size: 18, color: p.ink),
                    const SizedBox(width: 7),
                    Text('Scan another code',
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ]),
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.outcome, this.action});
  final CheckinOutcome outcome;

  /// A way to sort it out from here (a ward's "Pay for Tobi").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final o = outcome;
    final (bg, fg, icon) = o.ok
        ? (p.accentTint, p.greenText, Icons.check_rounded)
        : o.isError
            ? (p.liveTint, p.danger, Icons.close_rounded)
            : (p.orangeTint, p.orangeInk, Icons.priority_high_rounded);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SpIconTile(icon, bg: bg, fg: fg, size: 38, iconSize: 19),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(o.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Text(o.headline,
                  style: TextStyle(
                      color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 2),
            Text(o.message,
                style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4)),
            if (action != null) ...[
              const SizedBox(height: 8),
              action!,
            ],
          ]),
        ),
      ]),
    );
  }
}
