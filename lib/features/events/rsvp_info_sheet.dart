import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/payments/payment_models.dart';
import 'package:sportpadi_mobile/data/payments/payments_repository.dart';
import 'package:sportpadi_mobile/features/payments/checkout_flow.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Shown right after an RSVP.
///
/// Open events: it tells the organiser you're planning to come, but doesn't
/// hold a place — checking in at the venue does. Then why showing up pays.
///
/// "RSVP required" events with a required ticket: the RSVP holds a spot, but
/// an unpaid one goes first when an organiser needs room. Paying puts you
/// first; if a paid spot ever has to be released the ticket price is refunded
/// at once, and a paid no-show is refunded after the event (fees aren't).
/// That version can't be dismissed for good; money is involved.
class RsvpInfoSheet extends ConsumerStatefulWidget {
  const RsvpInfoSheet({
    super.key,
    required this.eventId,
    required this.rsvpRequired,
    this.unpaidRequired = const [],
  });
  final String eventId;
  final bool rsvpRequired;

  /// Required tickets the viewer still has to pay for (paid-spot version).
  final List<EventTicket> unpaidRequired;

  static const _storage = FlutterSecureStorage();
  static const _key = 'sp_rsvp_info_dismissed';
  static bool? _dismissed;

  /// Show it: always for a paid spot still unpaid, otherwise unless the
  /// player asked not to see it again.
  static Future<void> maybeShow(
    BuildContext context,
    WidgetRef ref, {
    required String eventId,
    required bool rsvpRequired,
  }) async {
    var unpaid = const <EventTicket>[];
    if (rsvpRequired) {
      try {
        final data = await ref.read(eventTicketsProvider(eventId).future);
        if (data.ticketed) {
          unpaid = data.tickets
              .where((t) => t.required && !t.paid && t.canBuy)
              .toList();
        }
      } catch (_) {}
    }
    if (unpaid.isEmpty) {
      _dismissed ??=
          (await _storage.read(key: _key).catchError((_) => null)) == '1';
      if (_dismissed == true) return;
    }
    if (!context.mounted) return;
    await showSpSheet<void>(
      context,
      builder: (_) => RsvpInfoSheet(
        eventId: eventId,
        rsvpRequired: rsvpRequired,
        unpaidRequired: unpaid,
      ),
    );
  }

  @override
  ConsumerState<RsvpInfoSheet> createState() => _RsvpInfoSheetState();
}

class _RsvpInfoSheetState extends ConsumerState<RsvpInfoSheet> {
  bool _dontShow = false;
  bool _busy = false;

  bool get _paidVariant => widget.unpaidRequired.isNotEmpty;

  Future<void> _close() async {
    if (_dontShow && !_paidVariant) {
      RsvpInfoSheet._dismissed = true;
      try {
        await RsvpInfoSheet._storage.write(key: RsvpInfoSheet._key, value: '1');
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _payNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(paymentsRepositoryProvider);
      final ids = widget.unpaidRequired.map((t) => t.id).toList();
      final co = ids.length == 1
          ? await repo.startCheckout(ids.first)
          : await repo.startBulkCheckout(ids);
      if (!mounted) return;
      final done = await runHostedCheckout(context, co.url);
      if (done && co.code.isNotEmpty) {
        final status = await repo.verify(co.code);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(status == 'paid'
                ? l10n.event_paidYourSpotIsLocked
                : l10n.event_paymentPullToRefreshIn(status))));
      }
      ref.invalidate(eventTicketsProvider(widget.eventId));
      if (mounted) Navigator.of(context).pop();
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
    Widget row(IconData icon, Widget text, [String? xp]) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: p.accent.withAlpha(26), shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: p.accent),
            ),
            const SizedBox(width: 10),
            Expanded(child: text),
            if (xp != null)
              Text(xp,
                  style: TextStyle(
                      color: p.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800)),
          ]),
        );
    Widget plain(String s) =>
        Text(s, style: TextStyle(color: p.ink, fontSize: 13.5));
    Widget rich(String bold, String rest) => Text.rich(TextSpan(children: [
          TextSpan(
              text: bold,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          TextSpan(text: rest),
        ]), style: TextStyle(color: p.ink, fontSize: 13.5, height: 1.35));

    if (_paidVariant) {
      final first = widget.unpaidRequired.first;
      final total =
          widget.unpaidRequired.fold<int>(0, (a, t) => a + t.priceMinor);
      final label = formatMoney(total, first.currency, first.currencyExponent);
      return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpSheetHeader(
              icon: Icons.event_available_rounded,
              title: context.l10n.event_youreHoldingASpot,
              subtitle:
                  context.l10n.event_thisEventNeedsAPaid2,
            ),
            const SizedBox(height: 10),
            row(
                Icons.verified_user_outlined,
                rich(context.l10n.event_payingPutsYouFirst,
                    context.l10n.event_whenTheOrganiserNeedsRoom)),
            row(
                Icons.undo_rounded,
                rich(context.l10n.event_cantMakeItAfterPaying,
                    context.l10n.event_theTicketPriceIsRefunded)),
            row(Icons.lock_outline,
                plain(context.l10n.event_noTicketAtTheGate)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _payNow,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_outline, size: 18),
              label: Text(context.l10n.event_payAndSecureIt(label)),
            ),
            const SizedBox(height: 6),
            OutlinedButton(
                onPressed: _busy ? null : _close,
                child: Text(context.l10n.event_payLater)),
            const SizedBox(height: 6),
            Text(
                context.l10n.event_untilYouPayAnOrganiser2,
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 11.5)),
          ]);
    }

    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSheetHeader(
            icon: Icons.event_available_rounded,
            title: context.l10n.event_youveRSVPd,
            subtitle: widget.rsvpRequired
                ? context.l10n.event_yourSpotIsHeldIf2
                : context.l10n.event_thisLetsTheOrganiserKnow2,
          ),
          const SizedBox(height: 14),
          Text(context.l10n.event_showUpAndEarn2,
              style: TextStyle(
                  color: p.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1)),
          const SizedBox(height: 4),
          row(Icons.auto_awesome_rounded, plain(context.l10n.event_forYourRsvp), '+10 XP'),
          row(Icons.qr_code_scanner_rounded, plain(context.l10n.event_checkInAtTheVenue),
              '+25 XP'),
          row(Icons.timer_outlined,
              plain(context.l10n.event_checkIn10MinutesBefore), '+10 XP'),
          row(Icons.local_fire_department_rounded,
              plain(context.l10n.event_keepYourWeeklyStreakGoing), '🔥'),
          const SizedBox(height: 6),
          Text(
              context.l10n.event_rSVPdWithin24HoursOf,
              style: TextStyle(color: p.muted, fontSize: 11.5)),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: _dontShow,
            onChanged: (v) => setState(() => _dontShow = v ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(context.l10n.event_dontShowThisAgain,
                style: TextStyle(color: p.muted, fontSize: 12.5)),
          ),
          const SizedBox(height: 4),
          FilledButton(onPressed: _close, child: Text(context.l10n.event_gotIt)),
        ]);
  }
}
