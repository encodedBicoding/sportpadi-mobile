import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';

/// AdMob (Google Mobile Ads), Android and iOS.
///
/// Two units per platform, two jobs: an APP OPEN ad shown when the app comes
/// back to the foreground after a real absence, and a NATIVE ad rendered
/// inline where the app's own first-party ad slots already sit (Home,
/// Browse). Each store is a separate AdMob "app" with its own app id and
/// unit ids — the app ids live in AndroidManifest.xml / Info.plist, the unit
/// ids here.
///
/// Debug builds use Google's sample unit ids. Real ids on a debug build are
/// a policy violation (invalid traffic) that can get the AdMob account
/// limited, so the switch is on kDebugMode, not on a flag someone can forget.
class AdMobIds {
  AdMobIds._();

  // Android (AdMob app ca-app-pub-5037534828580049~4304696149).
  static const _androidAppOpen = 'ca-app-pub-5037534828580049/8613751446'; // SP-AND-OVERLAY
  static const _androidNative = 'ca-app-pub-5037534828580049/4545504766'; // SP-AND-NATIVE

  // iOS (AdMob app ca-app-pub-5037534828580049~8777402976).
  static const _iosAppOpen = 'ca-app-pub-5037534828580049/4140153963'; // SP-IOS-APP-OPEN
  static const _iosNative = 'ca-app-pub-5037534828580049/7410592823'; // SP-IOS-NATIVE-ADV

  // Google's public test units — always fill, never earn.
  static const _testAppOpenAndroid = 'ca-app-pub-3940256099942544/9257395921';
  static const _testNativeAndroid = 'ca-app-pub-3940256099942544/2247696110';
  static const _testAppOpenIos = 'ca-app-pub-3940256099942544/5575463023';
  static const _testNativeIos = 'ca-app-pub-3940256099942544/3986624511';

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static String? get appOpen {
    if (!supported) return null;
    if (Platform.isIOS) return kDebugMode ? _testAppOpenIos : _iosAppOpen;
    return kDebugMode ? _testAppOpenAndroid : _androidAppOpen;
  }

  static String? get native {
    if (!supported) return null;
    if (Platform.isIOS) return kDebugMode ? _testNativeIos : _iosNative;
    return kDebugMode ? _testNativeAndroid : _androidNative;
  }
}

/// SDK initialisation, once, lazily, and never on the critical path: the
/// first widget that needs an ad awaits it; app start does not.
class AdMob {
  AdMob._();
  static Future<void>? _init;
  static bool _ready = false;
  static bool get ready => _ready;

  static Future<void> init() {
    if (!AdMobIds.supported) return Future.value();
    return _init ??= _start();
  }

  static Future<void> _start() async {
    try {
      // iOS: App Tracking Transparency first. The answer decides whether the
      // SDK may use the IDFA (personalised ads) or must serve without it;
      // asking AFTER the first request would waste that request and, per
      // Apple's 5.1.2, is the wrong order. A "no" is respected — ads still
      // serve, just non-personalised — and the prompt is only ever shown once
      // by the OS, so this is cheap on every later launch.
      if (Platform.isIOS) {
        final status = await AppTrackingTransparency.trackingAuthorizationStatus;
        if (status == TrackingStatus.notDetermined) {
          // iOS only presents the dialog once the app is active with a
          // window up; asked during launch it silently returns
          // "notDetermined" and the prompt is lost for that run.
          await WidgetsBinding.instance.endOfFrame;
          await Future<void>.delayed(const Duration(seconds: 1));
          // If another system alert is up (the notification permission
          // prompt, typically) iOS answers "notDetermined" without showing
          // ours and asks again next launch — fine. What must NOT happen is
          // ads waiting forever on a prompt that never resolves.
          await AppTrackingTransparency.requestTrackingAuthorization()
              .timeout(const Duration(seconds: 15), onTimeout: () => status);
        }
      }
      final st = await MobileAds.instance.initialize();
      _ready = true;
      if (kDebugMode) {
        final adapters = st.adapterStatuses.entries
            .map((e) => '${e.key}=${e.value.state.name}')
            .join(', ');
        debugPrint('[admob] ready on ${Platform.operatingSystem} '
            '(native unit ${AdMobIds.native}); adapters: $adapters');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[admob] init failed: $e');
    }
  }
}

// ── App open ─────────────────────────────────────────────────────────────────

/// Loads one app-open ad ahead of time and shows it when the app returns to
/// the foreground — but only after a real absence, and not too often.
///
/// The rules are what keep this format from being hated:
///   • never on cold start (the first frame is for the app, and a deep link
///     or push tap is often what launched it);
///   • only after the app was actually in the background for a while
///     ([minAway]) — flipping to a Custom Tab to pay and straight back is
///     not "returning to the app";
///   • at most once per [minGap];
///   • a loaded ad is only good for four hours (Google's rule), then it's
///     thrown away and reloaded.
class AppOpenAdManager {
  AppOpenAdManager._();
  static final AppOpenAdManager instance = AppOpenAdManager._();

  static const minAway = Duration(seconds: 30);
  static const minGap = Duration(minutes: 10);
  static const maxAge = Duration(hours: 4);

  AppOpenAd? _ad;
  DateTime? _loadedAt;
  DateTime? _lastShownAt;
  bool _showing = false;
  bool _loading = false;

  bool get _isFresh =>
      _ad != null &&
      _loadedAt != null &&
      DateTime.now().difference(_loadedAt!) < maxAge;

  Future<void> load() async {
    final id = AdMobIds.appOpen;
    if (id == null || _loading || _isFresh) return;
    _loading = true;
    await AdMob.init();
    await AppOpenAd.load(
      adUnitId: id,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loadedAt = DateTime.now();
          _loading = false;
        },
        onAdFailedToLoad: (err) {
          _loading = false;
          if (kDebugMode) debugPrint('[admob] app open failed to load: $err');
        },
      ),
    );
  }

  /// Called by [AppOpenAdHost] when the app comes back to the foreground.
  void showIfAvailable({required Duration awayFor}) {
    if (!AdMobIds.supported || _showing) return;
    if (awayFor < minAway) return;
    final last = _lastShownAt;
    if (last != null && DateTime.now().difference(last) < minGap) return;
    if (!_isFresh) {
      // Stale or missing: drop it and fetch one for next time.
      _ad?.dispose();
      _ad = null;
      unawaited(load());
      return;
    }
    final ad = _ad!;
    _ad = null;
    _loadedAt = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _showing = true,
      onAdDismissedFullScreenContent: (a) {
        _showing = false;
        _lastShownAt = DateTime.now();
        a.dispose();
        unawaited(load());
      },
      onAdFailedToShowFullScreenContent: (a, err) {
        _showing = false;
        a.dispose();
        if (kDebugMode) debugPrint('[admob] app open failed to show: $err');
        unawaited(load());
      },
    );
    ad.show();
  }
}

/// Wrap the app once. Watches the lifecycle and hands foreground returns to
/// [AppOpenAdManager]; preloads the first ad shortly after launch so the
/// first eligible return has something to show.
class AppOpenAdHost extends StatefulWidget {
  const AppOpenAdHost({super.key, required this.child});
  final Widget child;

  @override
  State<AppOpenAdHost> createState() => _AppOpenAdHostState();
}

class _AppOpenAdHostState extends State<AppOpenAdHost>
    with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    if (!AdMobIds.supported) return;
    WidgetsBinding.instance.addObserver(this);
    // Preload off the launch path. A few seconds in, the home screen is up
    // and the network is warm; nothing about start-up waits for this.
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) unawaited(AppOpenAdManager.instance.load());
    });
  }

  @override
  void dispose() {
    if (AdMobIds.supported) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _pausedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final since = _pausedAt;
        _pausedAt = null;
        // No recorded pause = cold start (or a transient inactive state such
        // as the notification shade), and neither gets an ad.
        if (since == null) return;
        AppOpenAdManager.instance
            .showIfAvailable(awayFor: DateTime.now().difference(since));
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ── Native ───────────────────────────────────────────────────────────────────

/// One native ad, rendered with Google's built-in template (no platform-side
/// factory to maintain), styled to sit among the app's own cards.
///
/// Takes no space until an ad has actually loaded, so a no-fill never leaves
/// a hole in a list; `padding` is applied only then, so the surrounding
/// spacing stays right in both cases. Each instance is one ad request; give
/// list occurrences a key so recycling doesn't reuse a disposed ad.
class AdMobNativeCard extends StatefulWidget {
  const AdMobNativeCard({
    super.key,
    this.template = TemplateType.medium,
    this.padding = EdgeInsets.zero,
  });

  final TemplateType template;
  final EdgeInsets padding;

  @override
  State<AdMobNativeCard> createState() => _AdMobNativeCardState();
}

class _AdMobNativeCardState extends State<AdMobNativeCard> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The template style needs the palette, which needs an inherited theme —
    // so the request waits for the widget to be in the tree (this runs once
    // right after initState). One request per instance, whatever happens.
    if (!_requested && AdMobIds.native != null) {
      _requested = true;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final id = AdMobIds.native;
    if (id == null || !mounted) return;
    await AdMob.init();
    if (!mounted) return;
    final p = context.palette;
    final ad = NativeAd(
      adUnitId: id,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (kDebugMode) debugPrint('[admob] native loaded');
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          if (kDebugMode) debugPrint('[admob] native failed to load: $err');
          if (mounted) setState(() => _ad = null);
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: widget.template,
        mainBackgroundColor: p.surface,
        cornerRadius: 14,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: p.accent,
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: p.ink,
          style: NativeTemplateFontStyle.bold,
          size: 15,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: p.muted,
          style: NativeTemplateFontStyle.normal,
          size: 13,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: p.muted,
          style: NativeTemplateFontStyle.normal,
          size: 12,
        ),
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    final p = context.palette;
    // Google's minimums for the templates: small 320×90, medium 320×320.
    final height = widget.template == TemplateType.small ? 100.0 : 340.0;
    return Padding(
      padding: widget.padding,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: AdWidget(ad: ad),
      ),
    );
  }
}
