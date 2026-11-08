// The Free plan's "Try Pro features for free" offer (web
// components/groups/ProOfferCard.tsx; docs/design/2026-redesign.md row 173).
// A promo code flagged as the offer (e.g. WELCOME) that the group's OWNER
// switches on by accepting the Pro Features Offer Terms. The native card is
// Android only; on iPhone the group page's offer ad (ProOfferScreen) opens the
// offer on the web in the in-app browser, signed in, and the owner accepts it
// there.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/links/web_handoff.dart' show signedInWebUriFor, webPayPath;
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/billing/iap_repository.dart';
import 'package:sportpadi_mobile/data/groups/group_admin_repository.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_header.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

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
              Text(on ? context.l10n.group_proFeaturesFree2 : context.l10n.group_freePlanOffer2,
                  style: const TextStyle(
                      color: _mint, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
              const Spacer(),
              if (on && (o.renewsOn != null || o.endsAt != null))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white.withAlpha(26), borderRadius: BorderRadius.circular(99)),
                  child: Text(
                      o.renewsOn != null ? context.l10n.group_renews3(_day(o.renewsOn!)) : context.l10n.group_until2(_day(o.endsAt!)),
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
            ]),
            const SizedBox(height: 6),
            Text(
                on
                    ? context.l10n.group_proFeaturesAreOnFor2
                    : o.status == 'opted_out'
                        ? context.l10n.group_wantProFeaturesBack
                        : context.l10n.group_tryProFeaturesForFree,
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, height: 1.15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
                on
                    ? context.l10n.group_itRenewsAutomaticallyWhileSportPadi
                    : o.description ??
                        context.l10n.group_unlockProFeaturesForYour,
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
              TextSpan(text: context.l10n.group_feesStillApply, style: TextStyle(color: p.ink, fontWeight: FontWeight.w700)),
              TextSpan(text: context.l10n.group_paymentsYourGroupCollectsPay2(o.feeTierName ?? o.planName)),
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
                        child: Text(context.l10n.group_optOutOfTheOffer),
                      ),
                    )
                  : Text(context.l10n.group_onlyTheGroupsOwnerCan,
                      style: TextStyle(color: p.muted, fontSize: 12))
            else if (o.isOwner)
              SpButton(
                expand: true,
                tone: SpButtonTone.brand,
                icon: Icons.auto_awesome_rounded,
                label: o.status == 'opted_out' ? context.l10n.group_reviewTermsSwitchBackOn : context.l10n.group_reviewTermsSwitchOn,
                onTap: () => showProOfferTermsSheet(context, groupId: groupId, groupName: groupName, offer: o),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(14)),
                child: Text(
                    context.l10n.group_onlyTheGroupsOwnerCan3,
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
      title: Text(l10n.group_optOutOfFreePro),
      content: Text(
          l10n.group_theOffersFeaturesStopFor(groupName)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.group_keepIt)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.group_optOut),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(groupAdminRepositoryProvider).optOutPromo(groupId, o.promoId);
    _refresh(ref, groupId);
    messenger.showSnackBar(SnackBar(content: Text(l10n.group_youveOptedOutProFeatures)));
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
      messenger.showSnackBar(SnackBar(content: Text(l10n.group_proFeaturesAreOnFor)));
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
        subtitle: context.l10n.group_acceptOnBehalfOfTo(widget.groupName),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final k in t.keyPoints) point(k),
          point(context.l10n.group_yourGroupsFeeTodayOn(o.feePhrase, o.feeTierName ?? o.planName)),
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
              child: Text(context.l10n.group_versionUpdatedOpenOnThe(t.version, t.updated),
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
                  context.l10n.group_iOwnOnSportPadiAnd(widget.groupName, t.title),
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
        label: _busy ? context.l10n.group_switchingOn : context.l10n.group_acceptSwitchOn,
        onTap: _agree && !_busy ? _accept : null,
      ),
    ]);
  }
}


/// The offer on its own screen — where the group page's ad and offer links
/// (/groups/:id/upgrade#pro-offer, /groups/:id/pro-offer) land in the app.
/// Android: the native card (same as the manage sheet). iPhone: the offer
/// isn't drawn natively — this opens it on the web in the in-app browser,
/// already signed in (the one-tap hand-off), and steps back out of the way.
class ProOfferScreen extends ConsumerStatefulWidget {
  const ProOfferScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<ProOfferScreen> createState() => _ProOfferScreenState();
}

class _ProOfferScreenState extends ConsumerState<ProOfferScreen> {
  bool _opening = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!proOfferAllowedHere) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openOnWeb(popAfter: true));
    }
  }

  /// The upgrade page at its /pay/… address (one the app doesn't claim, so it
  /// can't bounce back here), scrolled to the offer.
  Future<void> _openOnWeb({bool popAfter = false}) async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failed = false;
    });
    var ok = false;
    try {
      final url = await signedInWebUriFor(ref, '${webPayPath(widget.groupId, 'upgrade')}#pro-offer');
      ok = await launchUrl(url, mode: LaunchMode.inAppBrowserView);
      if (!ok) ok = await launchUrl(url, mode: LaunchMode.platformDefault);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      _failed = !ok;
    });
    // Opened: this screen has done its job — back to where the ad was.
    if (ok && popAfter && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final groupId = widget.groupId;
    final group = ref.watch(groupProvider(groupId)).valueOrNull;
    final Widget body;
    if (!proOfferAllowedHere) {
      body = _failed
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _ProOfferNote(
                    title: context.l10n.group_couldntOpenTheOffer,
                    text: context.l10n.group_checkYourConnectionAndTry),
                SpButton(label: context.l10n.group_openTheOffer, onTap: () => _openOnWeb(popAfter: true)),
              ]),
            )
          : _ProOfferNote(title: context.l10n.group_openingTheOffer, text: context.l10n.group_itOpensInABrowser);
    } else {
      final offer = ref.watch(freeOfferProvider(groupId));
      if (offer.isLoading && !offer.hasValue) {
        body = const Center(child: CircularProgressIndicator());
      } else if (offer.valueOrNull == null) {
        body = _ProOfferNote(
            title: context.l10n.group_nothingToSwitchOn,
            text: context.l10n.group_thisGroupCantTakeThe);
      } else {
        body = ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [ProOfferCard(groupId: groupId, groupName: group?.name ?? 'your group')],
        );
      }
    }
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: SpHeader(title: context.l10n.group_proFeatures, subtitle: group?.name),
          ),
          Expanded(child: body),
        ]),
      ),
    );
  }
}

class _ProOfferNote extends StatelessWidget {
  const _ProOfferNote({required this.title, required this.text});
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome_outlined, color: p.muted, size: 34),
        const SizedBox(height: 10),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.ink, fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(text, textAlign: TextAlign.center, style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.4)),
      ]),
    );
  }
}
