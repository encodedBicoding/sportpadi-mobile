import 'package:flutter/material.dart';
import 'package:sportpadi_mobile/core/i18n/date_locale.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/wards/ward_models.dart';
import 'package:sportpadi_mobile/data/wards/wards_repository.dart';
import 'package:sportpadi_mobile/shared/format/formatters.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

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
    _toast(l10n.ward_linkSentTo3(email));
    _refresh();
  }

  Future<void> _resend(String email) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(wardsRepositoryProvider).startClaim(_ward.userId, email);
      _toast(l10n.ward_aNewLinkWentTo(email));
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
        title: Text(l10n.ward_cancelTheLink),
        content:
            Text(l10n.ward_theLinkStopsWorkingAnd(first)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.ward_keepIt)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.ward_cancelLink,
                  style: TextStyle(color: ctx.palette.danger))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(wardsRepositoryProvider).cancelClaim(_ward.userId);
      _toast(l10n.ward_linkCancelled2);
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
                    Text(context.l10n.ward_handOverThisAccount,
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
          d.claimBlockedReason ?? context.l10n.ward_handingOverOpensWhenThey;
      return GlassCard(
        child: header(opens.isEmpty ? reason : '$reason Opens on $opens.'),
      );
    }

    // No link out yet.
    if (claim == null) {
      return GlassCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          header(context.l10n.ward_giveTheirOwnLoginEverything(first)),
          const SizedBox(height: 14),
          SpButton(
            label: context.l10n.ward_handOverThisAccount,
            icon: Icons.send_rounded,
            expand: true,
            onTap: _busy ? null : _start,
          ),
        ]),
      );
    }

    // A link is out (or has lapsed).
    final status = claim.expired
        ? context.l10n.ward_linkExpiredItWentTo(claim.email)
        : context.l10n.ward_linkSentTo4(claim.email, (claim.expiresAt == null ? '' : ' · expires ${fmtInstant(claim.expiresAt)}'));
    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header(status, subColor: claim.expired ? p.orangeInk : null),
        if (!claim.expired) ...[
          const SizedBox(height: 8),
          Text(
            context.l10n.ward_waitingForToOpenIt(first),
            style: TextStyle(color: p.muted, fontSize: 12),
          ),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: SpButton(
              label: _busy ? context.l10n.ward_working : context.l10n.ward_sendAgain,
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
                  child: Text(context.l10n.ward_cancel,
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

DateFormat get _longDate => DateFormat('MMM d, y', spDateLocale);

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
          title: context.l10n.ward_handOverSAccount(first),
          subtitle: context.l10n.ward_wellEmailALinkTo(first),
        ),
        point(
            Icons.login_rounded,
            '$first gets their own login — they sign in with this email and '
            'the password they choose.'),
        point(Icons.inventory_2_outlined,
            context.l10n.ward_everythingStaysTheirGamesStats),
        if (minor)
          point(
              Icons.supervisor_account_rounded,
              context.l10n.ward_untilTheir18thBirthdayYou((adult == null ? '' : ' (${_longDate.format(adult)})'), first))
        else
          point(
              Icons.person_off_outlined,
              context.l10n.ward_youllNoLongerManageTheyll(first)),
        point(
            Icons.timer_outlined, context.l10n.ward_theLinkWorksOnceAnd2),
        const SizedBox(height: 4),
        TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.send,
          decoration: InputDecoration(
            labelText: context.l10n.ward_sOwnEmail(first),
            helperText: context.l10n.ward_mustBeAnAddressThat,
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
          label: _busy ? context.l10n.ward_sending : context.l10n.ward_sendLink,
          icon: Icons.send_rounded,
          tone: SpButtonTone.brand,
          expand: true,
          onTap: _busy || !_valid ? null : _send,
        ),
      ],
    );
  }
}
