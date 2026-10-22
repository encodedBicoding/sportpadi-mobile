// The Free plan's "Try Pro features for free" offer (web
// components/groups/ProOfferCard.tsx; docs/design/2026-redesign.md row 173).
// A promo code flagged as the offer (e.g. WELCOME) that the group's OWNER
// switches on by accepting the Pro Features Offer Terms. Android only: on
// iOS, unlocking features outside in-app purchase is off-limits (App Store
// 3.1.1), same as promo codes — iOS owners can accept it on the web.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/billing/iap_repository.dart';
import 'package:sportpadi_mobile/data/groups/group_admin_repository.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

const _mint = Color(0xFF6EDC9E);

String _day(DateTime d) => DateFormat('d MMM yyyy').format(d.toLocal());

/// Whether this build may show the offer at all (not on iOS).
bool get proOfferAllowedHere => !IapRepository.supportedPlatform;

/// Everything that depends on the group's features, after a change.
void _refresh(WidgetRef ref, String groupId) {
  ref.invalidate(freeOfferProvider(groupId));
  ref.invalidate(groupPromosProvider(groupId));
  ref.invalidate(groupOverviewProvider(groupId));
  ref.invalidate(groupProvider(groupId));
}

/// The offer card: the pitch (Free plan), its state once on (renews …, opt
/// out) or after opting out. Renders nothing when there's no offer for the
/// group, or on iOS.
class ProOfferCard extends ConsumerWidget {
  const ProOfferCard({super.key, required this.groupId, required this.groupName});
  final String groupId;
  final String groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!proOfferAllowedHere) return const SizedBox.shrink();
    final o = ref.watch(freeOfferProvider(groupId)).valueOrNull;
    if (o == null) return const SizedBox.shrink();
    final p = context.palette;
    final on = o.isOn;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D3B2A), Color(0xFF0F5A3C), Color(0xFF1B7A4F)]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.auto_awesome_rounded, size: 13, color: _mint),
              const SizedBox(width: 4),
              Text(on ? 'PRO FEATURES · FREE' : 'FREE PLAN OFFER',
                  style: const TextStyle(
                      color: _mint, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
              const Spacer(),
              if (on && (o.renewsOn != null || o.endsAt != null))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white.withAlpha(26), borderRadius: BorderRadius.circular(99)),
                  child: Text(
                      o.renewsOn != null ? 'Renews ${_day(o.renewsOn!)}' : 'Until ${_day(o.endsAt!)}',
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
            ]),
            const SizedBox(height: 6),
            Text(
                on
                    ? 'Pro features are on for your group'
                    : o.status == 'opted_out'
                        ? 'Want Pro features back?'
                        : 'Try Pro features for free',
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, height: 1.15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
                on
                    ? 'It renews automatically while SportPadi runs the offer — it can end at any time.'
                    : o.description ??
                        'Unlock Pro features for your group at no subscription cost — for as long as SportPadi runs the offer.',
                style: TextStyle(color: Colors.white.withAlpha(190), fontSize: 12.5, height: 1.4)),
            if (o.features.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in o.features)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.white.withAlpha(26), borderRadius: BorderRadius.circular(99)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.check_rounded, size: 12, color: _mint),
                      const SizedBox(width: 3),
                      Text(f.name,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ]),
                  ),
              ]),
            ],
          ]),
        ),
        Container(
          color: p.surface,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text.rich(TextSpan(style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4), children: [
              TextSpan(text: 'Fees still apply. ', style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
              TextSpan(text: "Payments your group collects pay the ${o.feeTierName ?? o.planName} plan's fee — "),
              TextSpan(text: o.feePhrase, style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
              const TextSpan(text: '.'),
            ])),
            const SizedBox(height: 12),
            if (on)
              o.isOwner
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => _confirmOptOut(context, ref, groupId, groupName, o),
                        style: TextButton.styleFrom(foregroundColor: p.danger, padding: EdgeInsets.zero),
                        child: const Text('Opt out of the offer'),
                      ),
                    )
                  : Text("Only the group's owner can opt out.",
                      style: TextStyle(color: p.muted, fontSize: 12))
            else if (o.isOwner)
              SpButton(
                expand: true,
                tone: SpButtonTone.brand,
                icon: Icons.auto_awesome_rounded,
                label: o.status == 'opted_out' ? 'Review terms & switch back on' : 'Review terms & switch on',
                onTap: () => showProOfferTermsSheet(context, groupId: groupId, groupName: groupName, offer: o),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(14)),
                child: Text(
                    "Only the group's owner can accept the offer terms — ask them to switch it on.",
                    style: TextStyle(color: p.ink, fontSize: 12.5)),
              ),
          ]),
        ),
      ]),
    );
  }
}

Future<void> _confirmOptOut(
    BuildContext context, WidgetRef ref, String groupId, String groupName, ProOffer o) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Opt out of free Pro features?'),
      content: Text(
          "The offer's features stop for $groupName straight away; your events, members and records stay. You can switch it back on later by accepting the terms again, while SportPadi still runs the offer."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Opt out'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(groupAdminRepositoryProvider).optOutPromo(groupId, o.promoId);
    _refresh(ref, groupId);
    messenger.showSnackBar(const SnackBar(content: Text("You've opted out — Pro features are off.")));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}

/// The terms, a checkbox, and "Accept & switch on" (group owner).
Future<void> showProOfferTermsSheet(BuildContext context,
    {required String groupId, required String groupName, required ProOffer offer}) {
  return showSpSheet<void>(
    context,
    builder: (_) => _TermsSheet(groupId: groupId, groupName: groupName, offer: offer),
  );
}

class _TermsSheet extends ConsumerStatefulWidget {
  const _TermsSheet({required this.groupId, required this.groupName, required this.offer});
  final String groupId;
  final String groupName;
  final ProOffer offer;

  @override
  ConsumerState<_TermsSheet> createState() => _TermsSheetState();
}

class _TermsSheetState extends ConsumerState<_TermsSheet> {
  bool _agree = false;
  bool _busy = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await ref.read(groupAdminRepositoryProvider).acceptFreeOffer(widget.groupId, widget.offer.terms.version);
      _refresh(ref, widget.groupId);
      nav.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Pro features are on for your group 🎉')));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      // Terms changed under us: reload so the sheet shows the new version next time.
      ref.invalidate(freeOfferProvider(widget.groupId));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final o = widget.offer;
    final t = o.terms;
    final base = ref.read(appConfigProvider).apiBaseUrl;

    Widget point(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.check_rounded, size: 14, color: p.greenText),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: TextStyle(color: p.ink, fontSize: 13, height: 1.35))),
          ]),
        );

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SpSheetHeader(
        icon: Icons.auto_awesome_rounded,
        title: t.title,
        subtitle: 'Accept on behalf of ${widget.groupName} to switch on free Pro features.',
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final k in t.keyPoints) point(k),
          point("Your group's fee today: ${o.feePhrase} on each payment (${o.feeTierName ?? o.planName} plan)."),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.34),
        decoration: BoxDecoration(
            border: Border.all(color: p.line), borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.intro, style: TextStyle(color: p.ink, fontSize: 12.5, height: 1.45)),
            for (final s in t.sections) ...[
              const SizedBox(height: 10),
              Text(s.heading,
                  style: TextStyle(color: p.ink, fontSize: 13, fontWeight: FontWeight.w800)),
              for (final para in s.paragraphs) ...[
                const SizedBox(height: 4),
                Text(para, style: TextStyle(color: p.ink, fontSize: 12.5, height: 1.45)),
              ],
              for (final b in s.bullets)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 6),
                  child: Text('•  $b', style: TextStyle(color: p.ink, fontSize: 12.5, height: 1.45)),
                ),
            ],
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => launchUrl(Uri.parse('$base${t.url}'), mode: LaunchMode.inAppBrowserView),
              child: Text('Version ${t.version} · updated ${t.updated} · open on the web',
                  style: TextStyle(
                      color: p.muted, fontSize: 11, decoration: TextDecoration.underline)),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : () => setState(() => _agree = !_agree),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(
            value: _agree,
            onChanged: _busy ? null : (v) => setState(() => _agree = v == true),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                  'I own ${widget.groupName} on SportPadi and agree to the ${t.title} on its behalf — including that fees still apply and the offer can end at any time.',
                  style: TextStyle(color: p.ink, fontSize: 12.5, height: 1.4)),
            ),
          ),
        ]),
      ),
      if (_error != null) ...[
        const SizedBox(height: 6),
        Text(_error!, style: TextStyle(color: p.danger, fontSize: 12.5)),
      ],
      const SizedBox(height: 12),
      SpButton(
        expand: true,
        tone: SpButtonTone.brand,
        icon: Icons.auto_awesome_rounded,
        label: _busy ? 'Switching on…' : 'Accept & switch on',
        onTap: _agree && !_busy ? _accept : null,
      ),
    ]);
  }
}
