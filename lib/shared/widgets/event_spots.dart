import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/events/event_models.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// The "Spots" block of the create / edit event forms: a cap on players and
/// the RSVP rule. Web twin: components/events/SpotsSettings.tsx.
class EventSpotsPicker extends StatelessWidget {
  const EventSpotsPicker({
    super.key,
    required this.maxPlayers,
    required this.rsvpPolicy,
    required this.onMaxPlayers,
    required this.onRsvpPolicy,
    this.enabled = true,
  });

  final TextEditingController maxPlayers;
  final String rsvpPolicy; // open | required
  final ValueChanged<String> onMaxPlayers;
  final ValueChanged<String> onRsvpPolicy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cap = int.tryParse(maxPlayers.text.trim());
    final required = rsvpPolicy == 'required';
    final hint = cap == null
        ? context.l10n.common_noCapAnyoneCanCheck
        : required
            ? '$cap spots. RSVPs hold them; the page shows what\'s left.'
            : context.l10n.common_checkInsStopAt(cap);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.group_outlined, size: 16, color: p.ink),
                const SizedBox(width: 6),
                Text(context.l10n.common_maxPlayers,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: p.ink)),
              ]),
              const SizedBox(height: 2),
              Text(hint, style: TextStyle(color: p.muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: TextField(
              controller: maxPlayers,
              enabled: enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.right,
              onChanged: onMaxPlayers,
              decoration: const InputDecoration(hintText: '∞', isDense: true),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text(context.l10n.common_rsvp, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: p.ink)),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: _PolicyTile(
              on: !required,
              label: context.l10n.common_justInterest,
              hint: context.l10n.common_anyoneCanShowUpAnd,
              onTap: enabled ? () => onRsvpPolicy('open') : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _PolicyTile(
              on: required,
              icon: Icons.lock_outline,
              label: context.l10n.common_requiredToCheckIn,
              hint: context.l10n.common_anRsvpHoldsASpot,
              onTap: enabled ? () => onRsvpPolicy('required') : null,
            ),
          ),
        ]),
      ]),
    );
  }
}

class _PolicyTile extends StatelessWidget {
  const _PolicyTile({
    required this.on,
    required this.label,
    required this.hint,
    this.icon,
    this.onTap,
  });
  final bool on;
  final String label;
  final String hint;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = on ? p.bg : p.ink;
    return Material(
      color: on ? p.ink : p.surface2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(label,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: fg)),
              ),
            ]),
            const SizedBox(height: 2),
            Text(hint,
                style: TextStyle(
                    fontSize: 11.5, height: 1.3, color: on ? fg.withAlpha(204) : p.muted)),
          ]),
        ),
      ),
    );
  }
}

/// The event's spots at a glance on the event page: the "RSVP required" rule,
/// the cap and what's left ("2 of 12 spots left", "Full"). Nothing for an
/// open, uncapped event. Web twin: components/events/SpotsBanner.tsx.
class SpotsBanner extends StatelessWidget {
  const SpotsBanner({super.key, required this.capacity, this.myInterested = false});
  final EventCapacity capacity;
  final bool myInterested;

  @override
  Widget build(BuildContext context) {
    final c = capacity;
    if (!c.shows) return const SizedBox.shrink();
    final p = context.palette;
    final required = c.rsvpRequired;
    final full = c.full;
    final Color bg;
    final Color fg;
    if (full && !myInterested) {
      bg = p.liveTint;
      fg = p.danger;
    } else if (full) {
      bg = p.accentTint;
      fg = p.greenText;
    } else {
      bg = p.surface2;
      fg = p.ink;
    }
    final headline = required
        ? full
            ? (myInterested ? context.l10n.common_fullYourSpotIsHeld : context.l10n.common_fullEverySpotIsTaken)
            : c.capped
                ? context.l10n.common_rsvpToHoldASpot(c.line ?? '')
                : context.l10n.common_rsvpRequiredToCheckIn
        : full
            ? context.l10n.common_fullPlayersCheckedIn(c.maxPlayers ?? '')
            : '${c.line} · ${c.checkedInCount} checked in';
    final detail = required
        ? context.l10n.common_noRsvpNoCheckIn
        : context.l10n.common_checkInsCloseWhenThe;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(required ? Icons.lock_outline : Icons.group_outlined, size: 16, color: fg),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(headline, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: fg)),
            const SizedBox(height: 2),
            Text(detail, style: TextStyle(fontSize: 12, color: fg.withAlpha(204))),
          ]),
        ),
      ]),
    );
  }
}
