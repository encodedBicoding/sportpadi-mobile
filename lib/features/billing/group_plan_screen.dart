import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/billing/iap_repository.dart';
import 'package:sportpadi_mobile/data/groups/groups_repository.dart' show groupOverviewProvider;
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// A group's plan, bought through the App Store.
///
/// Everything a group pays for that happens in the real world — match tickets,
/// tournament entry fees, fines — is a real-world service and stays on the
/// web checkout. This screen is only the plan itself, which unlocks features
/// inside the app, and Apple requires that to be an in-app purchase.
///
/// Prices shown are StoreKit's own, read from the device. We never quote a
/// number of our own next to a purchase button: Apple's price is what the user
/// will actually be charged, in their currency, including their tax.
class GroupPlanScreen extends ConsumerStatefulWidget {
  const GroupPlanScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<GroupPlanScreen> createState() => _GroupPlanScreenState();
}

class _GroupPlanScreenState extends ConsumerState<GroupPlanScreen> {
  StreamSubscription<List<PurchaseDetails>>? _purchases;
  Map<String, ProductDetails> _details = const {};
  /// Ids StoreKit said it does not know. These are not "still loading" — no
  /// amount of waiting turns them into a price.
  Set<String> _missing = const {};
  /// A transport failure on the last lookup (offline, sandbox unreachable).
  String? _priceError;
  bool _pricesLoading = false;
  /// The exact set of ids the last lookup asked for. build() re-requests
  /// prices after every frame, so without this the answer's own setState would
  /// trigger the next lookup, forever — a steady drip of StoreKit queries that
  /// on a real device eventually starts coming back empty.
  Set<String> _pricesAskedFor = const {};
  String? _busyProductId;
  bool _restoring = false;
  /// Product ids we've already handed to the server this session, so a
  /// re-delivered StoreKit event doesn't redeem twice.
  final Set<String> _seen = {};

  @override
  void initState() {
    super.initState();
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
    _purchases?.cancel();
    super.dispose();
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadPrices(IapCatalogue cat, {bool force = false}) async {
    final ids = <String>{
      for (final plan in cat.plans) ...plan.products.values,
    };
    if (ids.isEmpty) return;
    if (!force && setEquals(ids, _pricesAskedFor)) return;
    _pricesAskedFor = ids;
    if (mounted) setState(() => _pricesLoading = true);

    final res = await ref.read(iapRepositoryProvider).productDetails(ids);
    if (!mounted) return;
    setState(() {
      _pricesLoading = false;
      // Keep any price we already had: a flaky lookup shouldn't blank a card
      // that was fine a second ago.
      _details = {..._details, ...res.found};
      _missing = res.error == null ? res.notFound : const {};
      _priceError = res.error;
    });
    if (kDebugMode && res.notFound.isNotEmpty) {
      // The single most useful line when a plan says "not available": the
      // exact ids the store rejected, to compare against App Store Connect or
      // the local .storekit file.
      debugPrint('[iap] StoreKit does not know: ${res.notFound.join(', ')}'
          '${res.error != null ? ' (error: ${res.error})' : ''}');
    }
  }

  Future<void> _retryPrices() async {
    final cat = ref.read(iapCatalogueProvider(widget.groupId)).valueOrNull;
    if (cat != null) await _loadPrices(cat, force: true);
  }

  Future<void> _buy(String productId) async {
    final product = _details[productId];
    if (product == null) {
      _say('That plan isn\'t available from the App Store right now.');
      return;
    }
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

  Future<void> _restore() async {
    setState(() => _restoring = true);
    try {
      final n = await ref.read(iapRepositoryProvider).restore();
      ref.invalidate(iapCatalogueProvider(widget.groupId));
      ref.invalidate(groupOverviewProvider(widget.groupId));
      _say(n > 0 ? 'Restored $n subscription${n == 1 ? '' : 's'}.' : 'Nothing to restore.');
    } catch (e) {
      _say('$e');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

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
      body: AsyncView(
        value: cat,
        onRetry: () => ref.invalidate(iapCatalogueProvider(widget.groupId)),
        data: (c) {
          // Fetching StoreKit prices is a side effect of showing the list;
          // doing it off-frame keeps build() pure.
          WidgetsBinding.instance.addPostFrameCallback((_) => _loadPrices(c));

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

          return RefreshIndicator(
            onRefresh: () async {
              await ref.read(iapRepositoryProvider).refresh(widget.groupId);
              ref.invalidate(iapCatalogueProvider(widget.groupId));
              await _retryPrices();
            },
            child: ListView(
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
                if (c.viaApple && c.renewsAt != null) const SizedBox(height: 12),
                for (final plan in c.plans) ...[
                  _PlanCard(
                    plan: plan,
                    details: _details,
                    missing: _missing,
                    loading: _pricesLoading,
                    failed: _priceError != null,
                    busyProductId: _busyProductId,
                    onBuy: _buy,
                  ),
                  const SizedBox(height: 10),
                ],
                if (_priceError != null && !_pricesLoading)
                  _PriceNotice(
                    icon: Icons.wifi_off_rounded,
                    text: 'Couldn\'t reach the App Store for prices. '
                        '${_priceError!}',
                    action: 'Try again',
                    onAction: _retryPrices,
                  )
                else if (_missing.isNotEmpty && !_pricesLoading)
                  _PriceNotice(
                    icon: Icons.storefront_outlined,
                    text: 'Some options aren\'t on the App Store yet, so they '
                        'can\'t be bought here for now.'
                        '${kDebugMode ? '\n\nUnknown to StoreKit: ${_missing.join(', ')}' : ''}',
                  ),
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
                  'Prices are set and billed by Apple in your App Store '
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
            ),
          );
        },
      ),
    );
  }

  Widget _legalLink(AppPalette p, String label, String path) {
    final base = ref.read(appConfigProvider).apiBaseUrl;
    return InkWell(
      onTap: () => launchUrl(Uri.parse('$base$path'),
          mode: LaunchMode.inAppBrowserView),
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
    return Center(
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

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.details,
    required this.missing,
    required this.loading,
    required this.failed,
    required this.busyProductId,
    required this.onBuy,
  });

  final IapPlan plan;
  final Map<String, ProductDetails> details;
  final Set<String> missing;
  final bool loading;
  final bool failed;
  final String? busyProductId;
  final ValueChanged<String> onBuy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Longest commitment first — a year reads as the better deal, and it's the
    // one most groups want once they've decided.
    const order = ['year', 'month', 'week', 'day'];
    final intervals = plan.products.keys.toList()
      ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));

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
              if (plan.isCurrent)
                SpBadge('Current plan', tone: p.accent),
            ]),
            if (plan.description != null) ...[
              const SizedBox(height: 4),
              Text(plan.description!,
                  style: TextStyle(color: p.muted, fontSize: 12.5, height: 1.35)),
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
            if (!plan.isCurrent && intervals.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final interval in intervals)
                Builder(builder: (_) {
                  final productId = plan.products[interval]!;
                  final d = details[productId];
                  final busy = busyProductId == productId;
                  // Four honest states. "Loading" is only true while a lookup
                  // is actually in flight; an id the store rejected, or a
                  // lookup that failed, says so instead of spinning.
                  final String label;
                  if (busy) {
                    label = 'Working…';
                  } else if (d != null) {
                    // Apple's own localized price string — never one of ours.
                    label = '${d.price} / $interval';
                  } else if (loading) {
                    label = 'Loading price…';
                  } else if (missing.contains(productId)) {
                    label = 'Not available yet · $interval';
                  } else if (failed) {
                    label = 'Price unavailable · $interval';
                  } else {
                    label = 'Loading price…';
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SpButton(
                      label: label,
                      expand: true,
                      onTap:
                          busy || d == null ? null : () => onBuy(productId),
                    ),
                  );
                }),
            ],
          ]),
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
