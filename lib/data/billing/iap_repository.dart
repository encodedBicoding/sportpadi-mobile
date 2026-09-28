import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';

/// A plan a group can buy, as the server describes it.
class IapPlan {
  const IapPlan({
    required this.tierId,
    required this.name,
    required this.description,
    required this.isCurrent,
    required this.features,
    required this.products,
    required this.webPrices,
  });

  final String tierId;
  final String name;
  final String? description;
  final bool isCurrent;
  final List<String> features;

  /// interval -> App Store product id.
  final Map<String, String> products;

  /// interval -> the price shown on the web, in minor units + currency. Only a
  /// fallback for layout before StoreKit answers; what the user commits to is
  /// always Apple's own localized price.
  final Map<String, ({int minor, String currency})> webPrices;

  factory IapPlan.fromJson(Map<String, dynamic> j) {
    final products = <String, String>{};
    for (final p in (j['products'] is List ? j['products'] as List : const [])) {
      if (p is! Map) continue;
      final interval = parseStr(p['interval']);
      final id = parseStr(p['productId']);
      if (interval != null && id != null) products[interval] = id;
    }
    final prices = <String, ({int minor, String currency})>{};
    for (final p in (j['webPrices'] is List ? j['webPrices'] as List : const [])) {
      if (p is! Map) continue;
      final interval = parseStr(p['interval']);
      if (interval == null) continue;
      prices[interval] = (
        minor: parseInt(p['priceCents']) ?? 0,
        currency: parseStr(p['currency']) ?? 'USD',
      );
    }
    return IapPlan(
      tierId: parseStr(j['tierId']) ?? '',
      name: parseStr(j['name']) ?? 'Plan',
      description: parseStr(j['description']),
      isCurrent: j['isCurrent'] == true,
      features: [
        for (final f in (j['features'] is List ? j['features'] as List : const []))
          if (parseStr(f) != null) parseStr(f)!
      ],
      products: products,
      webPrices: prices,
    );
  }
}

/// StoreKit's answer to a price lookup.
class IapPriceResult {
  const IapPriceResult({
    this.found = const {},
    this.notFound = const {},
    this.error,
  });

  /// product id -> details, for every id the store recognised.
  final Map<String, ProductDetails> found;

  /// Ids the store does not know. Permanent until the catalogue changes —
  /// retrying the same query returns the same answer.
  final Set<String> notFound;

  /// A transport-level failure, in which case `notFound` holds every id asked
  /// for and a retry may well succeed.
  final String? error;
}

/// What the app may offer for one group.
class IapCatalogue {
  const IapCatalogue({
    required this.available,
    required this.managedElsewhere,
    required this.plans,
    required this.currentProvider,
    required this.renewsAt,
    required this.cancelAtPeriodEnd,
  });

  /// The server has App Store credentials configured.
  final bool available;

  /// This group's plan is billed somewhere else already — buying again here
  /// would charge them twice, so we don't offer it.
  final bool managedElsewhere;

  final List<IapPlan> plans;
  final String? currentProvider;
  final DateTime? renewsAt;
  final bool cancelAtPeriodEnd;

  bool get viaApple => currentProvider == 'apple';

  factory IapCatalogue.fromJson(Map<String, dynamic> j) {
    final current = j['current'] is Map
        ? Map<String, dynamic>.from(j['current'] as Map)
        : const <String, dynamic>{};
    return IapCatalogue(
      available: j['available'] == true,
      managedElsewhere: j['managedElsewhere'] == true,
      currentProvider: parseStr(current['provider']),
      renewsAt: DateTime.tryParse(parseStr(current['renewsAt']) ?? ''),
      cancelAtPeriodEnd: current['cancelAtPeriodEnd'] == true,
      plans: [
        for (final t in (j['tiers'] is List ? j['tiers'] as List : const []))
          if (t is Map) IapPlan.fromJson(Map<String, dynamic>.from(t))
      ],
    );
  }
}

/// Buying a group's plan through the App Store.
///
/// Apple owns the transaction; the server owns the entitlement. This class
/// only carries a purchase from one to the other: StoreKit hands back a
/// transaction id, we post it, and the server asks Apple what it is. Nothing
/// here decides whether a group is entitled to anything — it can't, and
/// shouldn't be able to.
class IapRepository {
  IapRepository(this._ref);
  final Ref _ref;

  static final InAppPurchase _iap = InAppPurchase.instance;

  /// iOS only for now — Play Billing is a separate integration.
  static bool get supportedPlatform => Platform.isIOS;

  Future<IapCatalogue> catalogue(String groupId) async {
    try {
      final res = await _ref
          .read(dioProvider)
          .get('/api/mobile/iap', queryParameters: {'groupId': groupId});
      if (res.data is! Map) throw ApiException('Plans unavailable.');
      return IapCatalogue.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      throw apiError(e, fallback: 'Could not load plans.');
    }
  }

  /// Ask the App Store for the real, localized price of each product.
  ///
  /// StoreKit answers in three parts and all three matter: the products it
  /// knows, the ids it has never heard of, and an outright error. A product
  /// that is "not found" is not loading — it is mis-typed, not yet approved in
  /// App Store Connect, or missing from the local StoreKit configuration —
  /// and the screen must say so rather than spin forever.
  Future<IapPriceResult> productDetails(Set<String> ids) async {
    if (ids.isEmpty) return const IapPriceResult();
    if (!supportedPlatform) {
      return IapPriceResult(notFound: ids, error: 'Not supported on this device.');
    }
    try {
      if (!await _iap.isAvailable()) {
        return IapPriceResult(
          notFound: ids,
          error: 'The App Store isn\'t reachable right now.',
        );
      }
      final res = await _iap.queryProductDetails(ids);
      return IapPriceResult(
        found: {for (final p in res.productDetails) p.id: p},
        notFound: res.notFoundIDs.toSet(),
        error: res.error?.message,
      );
    } catch (e) {
      return IapPriceResult(notFound: ids, error: '$e');
    }
  }

  /// Hand a completed purchase to the server. Returns true when the group is
  /// entitled afterwards.
  Future<bool> redeem(String groupId, String transactionId) async {
    try {
      final res = await _ref.read(dioProvider).post('/api/mobile/iap', data: {
        'action': 'redeem',
        'groupId': groupId,
        'transactionId': transactionId,
      });
      final m = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
      return m['entitled'] == true;
    } catch (e) {
      throw apiError(e, fallback: 'We could not confirm that purchase.');
    }
  }

  /// "Restore purchases" — Apple requires this for auto-renewing subscriptions.
  /// Replays StoreKit's history so anything bought on this Apple ID reaches the
  /// server, then re-syncs every subscription the account already has.
  Future<int> restore() async {
    if (supportedPlatform && await _iap.isAvailable()) {
      await _iap.restorePurchases();
    }
    try {
      final res = await _ref
          .read(dioProvider)
          .post('/api/mobile/iap', data: {'action': 'restore'});
      final m = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
      return parseInt(m['restored']) ?? 0;
    } catch (e) {
      throw apiError(e, fallback: 'Could not restore purchases.');
    }
  }

  /// Re-check one group's plan — used right after a purchase completes and
  /// when the plans screen is opened.
  Future<bool> refresh(String groupId) async {
    try {
      final res = await _ref.read(dioProvider).post('/api/mobile/iap',
          data: {'action': 'refresh', 'groupId': groupId});
      final m = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
      return m['entitled'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Start a purchase.
  ///
  /// The group's id goes on the purchase as `applicationUserName`, which the
  /// StoreKit plugin maps to Apple's `appAccountToken`. That is what binds an
  /// Apple-ID-owned subscription to one group, and because Apple records it,
  /// the server can read the binding back from Apple rather than trusting the
  /// phone for it.
  Future<void> buy({
    required ProductDetails product,
    required String groupId,
  }) async {
    final param = PurchaseParam(
      productDetails: product,
      applicationUserName: groupId,
    );
    final started = await _iap.buyNonConsumable(purchaseParam: param);
    if (!started) {
      throw ApiException('The App Store could not start that purchase.');
    }
  }

  /// StoreKit's stream of purchase updates.
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  /// Tell StoreKit we're done with a purchase. Until this is called Apple
  /// re-delivers it on every launch (and, on iOS, keeps showing the user a
  /// pending transaction).
  Future<void> complete(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  /// Apple's own subscription-management screen — the only place an App Store
  /// subscription can be cancelled or changed. Linking here is expected of us:
  /// it's Apple's page, not a way around their checkout.
  Future<void> openAppleSubscriptionSettings() async {
    if (!supportedPlatform) return;
    await launchUrl(
      Uri.parse('https://apps.apple.com/account/subscriptions'),
      mode: LaunchMode.externalApplication,
    );
  }

  /// Apple's Offer Code redemption sheet — the App Store's own "have a
  /// code?" for subscriptions. Codes are created in App Store Connect
  /// against a subscription (free months, a discount) and redeemed here;
  /// the resulting purchase arrives on [purchaseStream] like a paid one, so
  /// the server verifies and applies it through the same path. This is the
  /// compliant shape of "promo codes" on iOS: the code never bypasses the
  /// store, it goes through it.
  Future<void> presentOfferCodeSheet() async {
    if (!supportedPlatform) return;
    await _iap
        .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>()
        .presentCodeRedemptionSheet();
  }
}

final iapRepositoryProvider =
    Provider<IapRepository>((ref) => IapRepository(ref));

final iapCatalogueProvider = FutureProvider.autoDispose
    .family<IapCatalogue, String>((ref, groupId) =>
        ref.watch(iapRepositoryProvider).catalogue(groupId));
