import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/links/web_handoff.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/billing/iap_repository.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart'
    show groupOverviewProvider;
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/pull_refresh.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// A group's plan, bought through the App Store.
///
/// Everything a group pays for that happens in the real world — match tickets,
/// tournament entry fees, fines — is a real-world service and stays on the
/// web checkout. This screen is only the plan itself, which unlocks features
/// inside the app, and Apple requires that to be an in-app purchase.
///
/// Each plan shows its features and how to pay — no prices up front. "Pay
/// with Apple" opens a sheet with StoreKit's own prices (read from the
/// device, in the user's currency, tax included — never a number of ours
/// next to an Apple buy button). On the United States storefront only, "Pay
/// with card" opens a sheet with the web prices and hands over to the web
/// checkout (Stripe); App Review Guideline 3.1.1(a) allows that there and
/// nowhere else, so other storefronts see Apple only
/// ([storefrontAllowsWebCheckout]).
class GroupPlanScreen extends ConsumerStatefulWidget {
  const GroupPlanScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupPlanScreen> createState() => _GroupPlanScreenState();
}

class _GroupPlanScreenState extends ConsumerState<GroupPlanScreen>
    with WidgetsBindingObserver {
  StreamSubscription<List<PurchaseDetails>>? _purchases;
  String? _busyProductId;

  /// Sent to the web checkout: refresh the plan when they come back.
  bool _awayAtCheckout = false;
  bool _restoring = false;

  /// Product ids we've already handed to the server this session, so a
  /// re-delivered StoreKit event doesn't redeem twice.
  final Set<String> _seen = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // StoreKit delivers purchases asynchronously, including ones made on
    // another device or interrupted mid-flight — so the listener, not the
    // buy() call, is what completes a purchase.
    _purchases = ref
        .read(iapRepositoryProvider)
        .purchaseStream
        .listen(_onPurchases, onError: (_) {});
    // Anything left pending from a previous session gets picked up too.
    unawaited(ref.read(iapRepositoryProvider).refresh(widget.groupId));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _purchases?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from paying on the web: the webhook may already have switched the
    // plan on, so show what the group has now.
    if (state == AppLifecycleState.resumed && _awayAtCheckout) {
      _awayAtCheckout = false;
      ref.invalidate(iapCatalogueProvider(widget.groupId));
      ref.invalidate(groupOverviewProvider(widget.groupId));
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    final repo = ref.read(iapRepositoryProvider);
    for (final purchase in list) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          if (mounted) setState(() => _busyProductId = purchase.productID);
          continue;
        case PurchaseStatus.error:
          await repo.complete(purchase);
          if (mounted) {
            setState(() => _busyProductId = null);
            _say(purchase.error?.message ?? 'The purchase didn\'t go through.');
          }
          continue;
        case PurchaseStatus.canceled:
          await repo.complete(purchase);
          if (mounted) setState(() => _busyProductId = null);
          continue;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          break;
      }

      final txId = purchase.purchaseID;
      if (txId == null || _seen.contains(txId)) {
        await repo.complete(purchase);
        continue;
      }
      _seen.add(txId);
      try {
        final entitled = await repo.redeem(widget.groupId, txId);
        // Only tell StoreKit we're done once the server has the purchase.
        // Completing early would lose it if the network dropped here.
        await repo.complete(purchase);
        if (!mounted) continue;
        setState(() => _busyProductId = null);
        ref.invalidate(iapCatalogueProvider(widget.groupId));
        ref.invalidate(groupOverviewProvider(widget.groupId));
        _say(entitled
            ? 'Your plan is active. The features are unlocked now.'
            : purchase.status == PurchaseStatus.restored
                ? 'Nothing to restore for this group.'
                : 'Purchase received — it will activate shortly.');
      } catch (e) {
        // Leave it uncompleted: StoreKit re-delivers on next launch, so a
        // failure here delays the unlock rather than losing the purchase.
        if (!mounted) continue;
        setState(() => _busyProductId = null);
        _say('$e');
      }
    }
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _buy(ProductDetails product) async {
    final productId = product.id;
    // The server can't confirm purchases until its App Store credentials are
    // in place. Rather than take a payment we can't honour, stop here — the
    // paywall itself stays visible so the flow can be seen and screenshotted.
    final cat = ref.read(iapCatalogueProvider(widget.groupId)).valueOrNull;
    if (cat != null && !cat.available) {
      _say('Purchases aren\'t switched on yet. Please try again soon.');
      return;
    }
    setState(() => _busyProductId = productId);
    try {
      await ref
          .read(iapRepositoryProvider)
          .buy(product: product, groupId: widget.groupId);
    } catch (e) {
      if (mounted) setState(() => _busyProductId = null);
      _say('$e');
    }
  }

  /// "Pay with Apple": the plan's App Store prices, then buy.
  Future<void> _payWithApple(IapPlan plan) async {
    final product = await showSpSheet<ProductDetails>(
      context,
      builder: (_) => _ApplePricesSheet(plan: plan),
    );
    if (product != null && mounted) await _buy(product);
  }

  /// "Pay with card" (US storefront only): the plan's web prices, then the
  /// web checkout (Stripe) for that plan and cadence.
  Future<void> _payWithCard(IapPlan plan) async {
    final interval = await showSpSheet<String>(
      context,
      builder: (_) => _CardPricesSheet(plan: plan),
    );
    if (interval == null || !mounted) return;
    // Signed in already (one-tap hand-off): straight to the plan's checkout.
    final path = Uri(
        path: '/groups/${widget.groupId}/upgrade',
        queryParameters: {
          'tier': plan.tierId,
          'interval': interval
        }).toString();
    final url = await signedInWebUriFor(ref, path);
    if (!mounted) return;
    _awayAtCheckout = true;
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) {
      _awayAtCheckout = false;
      _say('Couldn\'t open the checkout. Please try again.');
    }
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    try {
      final n = await ref.read(iapRepositoryProvider).restore();
      ref.invalidate(iapCatalogueProvider(widget.groupId));
      ref.invalidate(groupOverviewProvider(widget.groupId));
      _say(n > 0
          ? 'Restored $n subscription${n == 1 ? '' : 's'}.'
          : 'Nothing to restore.');
    } catch (e) {
      _say('$e');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// Pull to refresh: pick up purchases still pending, then refetch the
  /// plans and the storefront (which decides "Pay with card").
  Future<void> _refresh() async {
    await ref.read(iapRepositoryProvider).refresh(widget.groupId);
    if (!mounted) return;
    ref.invalidate(iapCatalogueProvider(widget.groupId));
    ref.invalidate(appStoreCountryProvider);
    ref.invalidate(groupOverviewProvider(widget.groupId));
    await settleAll([
      ref.read(iapCatalogueProvider(widget.groupId).future),
      ref.read(appStoreCountryProvider.future),
    ]);
  }

  /// [child] as is when [value] renders its data branch, else wrapped so the
  /// loader / error can still be pulled.
  Widget _pullable(AsyncValue<Object?> value, Widget child) => value.maybeWhen(
        data: (_) => child,
        orElse: () => PullableState(child: child),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cat = ref.watch(iapCatalogueProvider(widget.groupId));

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Group plan',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        // Every state is pullable: loading / error via _pullable, the
        // notices via _notice, the plans list via its physics.
        child: _pullable(
          cat,
          AsyncView(
            value: cat,
            onRetry: () => ref.invalidate(iapCatalogueProvider(widget.groupId)),
            data: (c) {
              if (!IapRepository.supportedPlatform) {
                return _notice(
                  p,
                  icon: Icons.workspace_premium_outlined,
                  title: 'Plans aren\'t available here',
                  body: 'This group\'s plan can\'t be changed from this device.',
                );
              }
              // `available` (the server holding App Store credentials) gates the
              // PURCHASE, not the page: prices come from StoreKit on the device,
              // so the paywall renders in full without it — which is what makes
              // it possible to take Apple's review screenshot, and to run the
              // screen against a local StoreKit configuration, before a single
              // product is approved. _buy() is where the gate lives.
              if (c.plans.isEmpty) {
                return _notice(
                  p,
                  icon: Icons.workspace_premium_outlined,
                  title: 'No plans on the App Store yet',
                  body: 'The plans haven\'t been set up for in-app purchase. '
                      'Check back soon.',
                );
              }
              if (c.managedElsewhere) {
                // Deliberately no link and no instructions: saying where to go
                // would be steering, and charging them twice would be worse.
                return _notice(
                  p,
                  icon: Icons.verified_outlined,
                  title: 'This group already has a plan',
                  body: 'Its billing is handled outside the App Store, so there\'s '
                      'nothing to buy here. The features it includes are already on.',
                );
              }

              // Paying on the web is offered on the US storefront only, and never
              // to a group already paying through Apple (it would bill twice).
              final cardAllowed = !c.viaApple &&
                  storefrontAllowsWebCheckout(
                      ref.watch(appStoreCountryProvider).valueOrNull);
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  if (c.viaApple && c.renewsAt != null)
                    GlassCard(
                      child: Row(children: [
                        Icon(Icons.autorenew_rounded, size: 18, color: p.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c.cancelAtPeriodEnd
                                ? 'Your plan ends on ${_date(c.renewsAt!)}.'
                                : 'Renews on ${_date(c.renewsAt!)}.',
                            style: TextStyle(color: p.ink, fontSize: 12.5),
                          ),
                        ),
                      ]),
                    ),
                  if (c.viaApple && c.renewsAt != null)
                    const SizedBox(height: 12),
                  for (final plan in c.plans) ...[
                    _PlanCard(
                      plan: plan,
                      busy: _busyProductId != null &&
                          plan.products.values.contains(_busyProductId),
                      cardAllowed: cardAllowed && plan.webPrices.isNotEmpty,
                      onApple: () => _payWithApple(plan),
                      onCard: () => _payWithCard(plan),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 6),
                  // Offer codes: Apple's sheet, then the purchase stream
                  // delivers the subscription and _onPurchases redeems it.
                  Center(
                    child: TextButton.icon(
                      onPressed: () =>
                          ref.read(iapRepositoryProvider).presentOfferCodeSheet(),
                      icon: Icon(Icons.confirmation_number_outlined,
                          size: 16, color: p.accent),
                      label: Text('Redeem a code',
                          style: TextStyle(
                              color: p.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: _restoring ? null : _restore,
                      child: Text(_restoring ? 'Restoring…' : 'Restore purchases',
                          style: TextStyle(
                              color: p.accent,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (c.viaApple)
                    Center(
                      child: TextButton(
                        onPressed: () => ref
                            .read(iapRepositoryProvider)
                            .openAppleSubscriptionSettings(),
                        child: Text('Manage subscription',
                            style: TextStyle(color: p.muted, fontSize: 12.5)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    '${cardAllowed ? 'With Apple, prices' : 'Prices'} are set and billed by Apple in your App Store '
                    'country\'s currency — not the group\'s wallet currency. '
                    'Plans renew automatically until cancelled. You can cancel any '
                    'time in your Apple subscription settings; cancelling stops the '
                    'next renewal and the plan runs to the end of the period you '
                    'have paid for.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: p.muted, fontSize: 11, height: 1.4),
                  ),
                  // App Store 3.1.2: a subscription paywall must link to the
                  // Terms of Use (EULA) and Privacy Policy, in the binary too,
                  // not only in the store listing.
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _legalLink(p, 'Terms of Use', '/terms'),
                    Text(' · ', style: TextStyle(color: p.muted, fontSize: 11)),
                    _legalLink(p, 'Privacy Policy', '/privacy'),
                  ]),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _legalLink(AppPalette p, String label, String path) {
    final base = ref.read(appConfigProvider).apiBaseUrl;
    return InkWell(
      onTap: () =>
          launchUrl(Uri.parse('$base$path'), mode: LaunchMode.inAppBrowserView),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Text(label,
            style: TextStyle(
                color: p.accent,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: p.accent)),
      ),
    );
  }

  Widget _notice(AppPalette p,
      {required IconData icon, required String title, required String body}) {
    // Pullable: it's the RefreshIndicator's child.
    return PullableState(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 34, color: p.muted),
          const SizedBox(height: 10),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: p.ink, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.4)),
        ]),
      ),
    );
  }

  String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month}/${l.year}';
  }
}

/// One plan: name, pitch and features, then how to pay — "Pay with Apple"
/// and, where allowed, "Pay with card". Prices come in the sheet each opens.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.busy,
    required this.cardAllowed,
    required this.onApple,
    required this.onCard,
  });

  final IapPlan plan;
  final bool busy;
  final bool cardAllowed;
  final VoidCallback onApple;
  final VoidCallback onCard;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final apple = SpButton(
      label: busy ? 'Working…' : 'Pay with Apple',
      icon: Icons.apple,
      expand: true,
      onTap: busy || plan.products.isEmpty ? null : onApple,
    );
    return GlassCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: Text(plan.name,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              ),
              if (plan.isCurrent) SpBadge('Current plan', tone: p.accent),
            ]),
            if (plan.description != null) ...[
              const SizedBox(height: 4),
              Text(plan.description!,
                  style:
                      TextStyle(color: p.muted, fontSize: 12.5, height: 1.35)),
            ],
            if (plan.features.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final f in plan.features)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    Icon(Icons.check_rounded, size: 14, color: p.accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(f,
                          style: TextStyle(color: p.ink, fontSize: 12.5)),
                    ),
                  ]),
                ),
            ],
            if (!plan.isCurrent) ...[
              const SizedBox(height: 12),
              if (!cardAllowed)
                apple
              else
                Row(children: [
                  Expanded(child: apple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Material(
                      color: p.surface,
                      shape: StadiumBorder(side: BorderSide(color: p.line)),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: busy ? null : onCard,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.credit_card_rounded,
                                    size: 18, color: p.ink),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text('Pay with card',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: p.ink,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ]),
                        ),
                      ),
                    ),
                  ),
                ]),
            ],
          ]),
    );
  }
}

/// Longest commitment first — a year reads as the better deal.
List<String> _byCommitment(Iterable<String> intervals) {
  const order = ['year', 'month', 'week', 'day'];
  int rank(String i) {
    final r = order.indexOf(i);
    return r < 0 ? order.length : r;
  }

  return intervals.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
}

/// "Pay with Apple": StoreKit's prices for this plan, fetched when the sheet
/// opens, one button per cadence. Pops with the chosen product.
class _ApplePricesSheet extends ConsumerStatefulWidget {
  const _ApplePricesSheet({required this.plan});
  final IapPlan plan;

  @override
  ConsumerState<_ApplePricesSheet> createState() => _ApplePricesSheetState();
}

class _ApplePricesSheetState extends ConsumerState<_ApplePricesSheet> {
  IapPriceResult? _res;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ref
        .read(iapRepositoryProvider)
        .productDetails(widget.plan.products.values.toSet());
    if (!mounted) return;
    if (kDebugMode && res.notFound.isNotEmpty) {
      // The single most useful line when a plan says "not available": the
      // exact ids the store rejected, to compare against App Store Connect or
      // the local .storekit file.
      debugPrint('[iap] StoreKit does not know: ${res.notFound.join(', ')}'
          '${res.error != null ? ' (error: ${res.error})' : ''}');
    }
    setState(() {
      _res = res;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final plan = widget.plan;
    final res = _res;
    final intervals = _byCommitment(plan.products.keys);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.apple,
          title: '${plan.name} · Apple',
          subtitle: 'Billed by Apple to your Apple ID.',
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (res != null && res.error != null)
          _PriceNotice(
            icon: Icons.wifi_off_rounded,
            text: 'Couldn\'t reach the App Store for prices. ${res.error!}',
            action: 'Try again',
            onAction: _load,
          )
        else ...[
          for (final interval in intervals)
            Builder(builder: (_) {
              final d = res?.found[plan.products[interval]];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SpButton(
                  // Apple's own localized price string — never one of ours.
                  label: d != null
                      ? '${d.price} / $interval'
                      : 'Not available yet · $interval',
                  expand: true,
                  onTap: d == null ? null : () => Navigator.pop(context, d),
                ),
              );
            }),
          if (res != null && res.notFound.isNotEmpty)
            _PriceNotice(
              icon: Icons.storefront_outlined,
              text: 'Some options aren\'t on the App Store yet, so they can\'t '
                  'be bought here for now.'
                  '${kDebugMode ? '\n\nUnknown to StoreKit: ${res.notFound.join(', ')}' : ''}',
            ),
        ],
        const SizedBox(height: 4),
        Text(
            'Renews automatically until cancelled in your Apple subscription '
            'settings.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.4)),
      ],
    );
  }
}

/// "Pay with card" (US storefront): the plan's web prices, one per cadence.
/// Pops with the chosen interval; the screen opens the web checkout.
class _CardPricesSheet extends StatelessWidget {
  const _CardPricesSheet({required this.plan});
  final IapPlan plan;

  static String _money(int minor, String currency) {
    try {
      return NumberFormat.simpleCurrency(name: currency).format(minor / 100);
    } catch (_) {
      return '${(minor / 100).toStringAsFixed(2)} $currency';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final intervals = _byCommitment(plan.webPrices.keys);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSheetHeader(
          icon: Icons.credit_card_rounded,
          title: '${plan.name} · Card',
          subtitle: 'Pay securely on sportpadi.com (processed by Stripe).',
        ),
        for (final interval in intervals)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SpButton(
              label:
                  '${_money(plan.webPrices[interval]!.minor, plan.webPrices[interval]!.currency)} / $interval',
              icon: Icons.open_in_new_rounded,
              expand: true,
              onTap: () => Navigator.pop(context, interval),
            ),
          ),
        const SizedBox(height: 4),
        Text(
            'Opens the checkout in your browser — sign in there if asked. '
            'Your plan switches on here as soon as the payment goes through.',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 11.5, height: 1.4)),
      ],
    );
  }
}

class _PriceNotice extends StatelessWidget {
  const _PriceNotice({
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? action;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: p.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: p.muted, fontSize: 12, height: 1.4)),
          ),
          if (action != null && onAction != null)
            TextButton(
              onPressed: () => onAction!(),
              child: Text(action!,
                  style: TextStyle(
                      color: p.accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    );
  }
}
