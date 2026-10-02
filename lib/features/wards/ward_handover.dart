import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/wards/ward_models.dart';
import 'package:sportpadi_mobile/data/wards/wards_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Wards 3 (A11): "Hand over this account" on a ward's page. A guardian
/// sends a link to the ward's own email; the ward chooses a password and the
/// account becomes theirs. Opens at 15. Under 18 the guardians stay on as
/// supervising guardians until the 18th birthday.
class WardHandoverCard extends ConsumerStatefulWidget {
  const WardHandoverCard({super.key, required this.detail});
  final WardDetail detail;

  @override
  ConsumerState<WardHandoverCard> createState() => _WardHandoverCardState();
}

class _WardHandoverCardState extends ConsumerState<WardHandoverCard> {
  bool _busy = false;

  Ward get _ward => widget.detail.ward;

  void _refresh() {
    ref.invalidate(wardDetailProvider(_ward.userId));
    ref.invalidate(myWardsProvider);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _start() async {
    final email = await showSpSheet<String>(
      context,
      builder: (_) => _HandoverSheet(ward: _ward),
    );
    if (email == null || !mounted) return;
    _toast('Link sent to $email.');
    _refresh();
  }

  Future<void> _resend(String email) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(wardsRepositoryProvider).startClaim(_ward.userId, email);
      _toast('A new link went to $email.');
      if (mounted) _refresh();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    final first = _ward.firstName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel the link?'),
        content:
            Text("The link stops working and $first's account stays with you. "
                'You can send a new one any time.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Cancel link',
                  style: TextStyle(color: ctx.palette.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(wardsRepositoryProvider).cancelClaim(_ward.userId);
      _toast('Link cancelled.');
      if (mounted) _refresh();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = widget.detail;
    final first = _ward.firstName;
    final claim = d.claim;

    Widget header(String sub, {Color? subColor}) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SpIconTile(Icons.key_rounded,
                bg: d.claimable ? p.wardTint : p.surface2,
                fg: d.claimable ? p.wardInk : p.muted,
                size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hand over this account',
                        style: TextStyle(
                            color: d.claimable ? p.ink : p.muted,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: TextStyle(
                            color: subColor ?? p.muted,
                            fontSize: 12.5,
                            height: 1.4)),
                  ]),
            ),
          ],
        );

    // Too young (or no date of birth): a quiet line saying when.
    if (!d.claimable && claim == null) {
      final opens = formatYmd(d.claimOpensOn);
      final reason =
          d.claimBlockedReason ?? 'Handing over opens when they turn 15.';
      return GlassCard(
        child: header(opens.isEmpty ? reason : '$reason Opens on $opens.'),
      );
    }

    // No link out yet.
    if (claim == null) {
      return GlassCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header('Give $first their own login. Everything stays — their '
              'games, stats, badges, teams and tickets.'),
          const SizedBox(height: 14),
          SpButton(
            label: 'Hand over this account',
            icon: Icons.send_rounded,
            expand: true,
            onTap: _busy ? null : _start,
          ),
        ]),
      );
    }

    // A link is out (or has lapsed).
    final status = claim.expired
        ? 'Link expired — it went to ${claim.email}.'
        : 'Link sent to ${claim.email}'
            '${claim.expiresAt == null ? '' : ' · expires ${fmtInstant(claim.expiresAt)}'}';
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header(status, subColor: claim.expired ? p.orangeInk : null),
        if (!claim.expired) ...[
          const SizedBox(height: 8),
          Text(
            'Waiting for $first to open it and choose a password.',
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: SpButton(
              label: _busy ? 'Working…' : 'Send again',
              icon: Icons.refresh_rounded,
              expand: true,
              onTap: _busy || !d.claimable ? null : () => _resend(claim.email),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: p.surface2,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: _busy ? null : _cancel,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Text('Cancel',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: p.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// The hand-over sheet: what happens, their email, send.
// ---------------------------------------------------------------------------

final _longDate = DateFormat('MMM d, y', 'en_US');

class _HandoverSheet extends ConsumerStatefulWidget {
  const _HandoverSheet({required this.ward});
  final Ward ward;

  @override
  ConsumerState<_HandoverSheet> createState() => _HandoverSheetState();
}

class _HandoverSheetState extends ConsumerState<_HandoverSheet> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  bool get _valid =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim());

  Future<void> _send() async {
    if (_busy || !_valid) return;
    final email = _email.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final claim = await ref
          .read(wardsRepositoryProvider)
          .startClaim(widget.ward.userId, email);
      if (mounted) Navigator.of(context).pop(claim?.email ?? email);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final w = widget.ward;
    final first = w.firstName;
    final age = w.age;
    final dob = w.dob;
    // Their 18th birthday — a calendar date (29 Feb rolls to 1 Mar, as on
    // the server).
    final adult =
        dob == null ? null : DateTime(dob.year + 18, dob.month, dob.day);
    final minor = age != null && age < 18;

    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: p.wardInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: p.ink, fontSize: 13, height: 1.4)),
            ),
          ]),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.key_rounded,
          iconBg: p.wardTint,
          iconFg: p.wardInk,
          title: 'Hand over $first\'s account',
          subtitle: "We'll email $first a link to choose a password.",
        ),
        point(
            Icons.login_rounded,
            '$first gets their own login — they sign in with this email and '
            'the password they choose.'),
        point(Icons.inventory_2_outlined,
            'Everything stays: their games, stats, badges, teams and tickets.'),
        if (minor)
          point(
              Icons.supervisor_account_rounded,
              'Until their 18th birthday'
              '${adult == null ? '' : ' (${_longDate.format(adult)})'}, you '
              'stay on as their supervising guardian. You still get messages '
              "from their groups' admins and coaches about $first and copies "
              'of announcements, but you '
              "can't act for them any more.")
        else
          point(
              Icons.person_off_outlined,
              "You'll no longer manage $first — they'll run everything "
              'themselves.'),
        point(
            Icons.timer_outlined, 'The link works once and expires in 7 days.'),
        const SizedBox(height: 4),
        TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.send,
          decoration: InputDecoration(
            labelText: "$first's own email",
            helperText: "Must be an address that isn't on SportPadi yet.",
          ),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _send(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
        ],
        const SizedBox(height: 16),
        SpButton(
          label: _busy ? 'Sending…' : 'Send link',
          icon: Icons.send_rounded,
          tone: SpButtonTone.brand,
          expand: true,
          onTap: _busy || !_valid ? null : _send,
        ),
      ],
    );
  }
}
