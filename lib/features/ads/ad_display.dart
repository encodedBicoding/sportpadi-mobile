import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/ads/ads_repository.dart';
import 'package:sportpadi_mobile/features/ads/promo_widgets.dart';

/// Flexible ad unit — hand it slot keys; each slot shows what the server
/// picked for this viewer (packages/api/src/ads/decide.ts) in the slot's
/// DISPLAY, set per slot in the owner console:
///   banner   — image ads in place; [carousel] says stacked or rotating
///   carousel — swipeable message cards that move on by themselves
///   card     — one message card, closable
///   top_bar  — a slim one-line strip, closable
/// Pop-up displays (bottom sheet, spotlight, What's new) aren't drawn here —
/// PopupMessages shows them when the app opens.
///   AdDisplay(slots: ['mobile-home'])                       → per slot
///   AdDisplay(slots: ['mobile-home','x'], carousel: true)   → banners rotate
/// Renders nothing (zero height) when nothing matches, so it can sit
/// anywhere. Location targeting is server-side; the widget also quietly
/// refreshes the viewer's locale when OS location permission is already
/// granted. Web twin: apps/web/src/components/ads/AdDisplay.tsx.
class AdDisplay extends ConsumerStatefulWidget {
  const AdDisplay({
    super.key,
    required this.slots,
    this.carousel = false,
    this.interval = const Duration(seconds: 6),
  });
  final List<String> slots;
  final bool carousel;
  final Duration interval;

  @override
  ConsumerState<AdDisplay> createState() => _AdDisplayState();
}

class _AdImage extends StatelessWidget {
  const _AdImage({required this.ad});
  final ServedAd ad;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ratio = ad.aspectRatio;
    final img = CachedNetworkImage(
      imageUrl: ad.imageUrl,
      width: double.infinity,
      fit: ratio != null ? BoxFit.cover : BoxFit.fitWidth,
      placeholder: (_, __) => AspectRatio(
        aspectRatio: ratio ?? 3.2,
        child: Container(color: p.surface2),
      ),
      errorWidget: (_, __, ___) => AspectRatio(
        aspectRatio: ratio ?? 3.2,
        child: Container(
          color: p.surface2,
          alignment: Alignment.center,
          child: Text(ad.advertiserName ?? ad.altText ?? 'Sponsored',
              style: TextStyle(color: p.muted, fontSize: 12)),
        ),
      ),
    );
    return ratio != null ? AspectRatio(aspectRatio: ratio, child: img) : img;
  }
}

class _AdDisplayState extends ConsumerState<AdDisplay> {
  Timer? _spin;
  int _idx = 0;
  final _seen = <String>{};
  final _closed = <String>{};
  // Personalisation happens inside servedSlotsProvider (before the serve
  // call), so location-targeted ads can match on the first render.

  @override
  void dispose() {
    _spin?.cancel();
    super.dispose();
  }

  void _impress(ServedAd ad) {
    if (_seen.add(ad.id) && ad.logViews) {
      // ignore: unawaited_futures
      ref.read(adsRepositoryProvider).log('impression', ad.id, ad.slotId);
    }
  }

  void _close(ServedAd ad) {
    // ignore: unawaited_futures
    ref.read(adsRepositoryProvider).dismiss(ad.id);
    setState(() => _closed.add(ad.id));
  }

  Widget _frame(ServedAd ad) {
    final p = context.palette;
    _impress(ad);
    if (ad.isPromo) {
      return PromoCard(ad: ad, onOpen: () => openServedAd(ref, ad));
    }
    return InkWell(
      onTap: () => openServedAd(ref, ad),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          // Like the web unit (w-full h-auto): full width at the creative's
          // own aspect ratio — never cropped. A "WxH" size pre-reserves the
          // height so the layout doesn't jump; otherwise the image sizes
          // itself once decoded.
          _AdImage(ad: ad),
          Positioned(right: 6, top: 6, child: AdBadge(ad: ad)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slots =
        ref.watch(servedSlotsProvider(widget.slots.join(','))).valueOrNull;
    final inline = [
      for (final s in slots ?? const <ServedSlot>[])
        if (!s.isPopup)
          ServedSlot(
            key: s.key,
            slotId: s.slotId,
            display: s.display,
            ads: [
              for (final a in s.ads)
                if (!_closed.contains(a.id)) a
            ],
          ),
    ].where((s) => s.ads.isNotEmpty).toList();
    if (inline.isEmpty) return const SizedBox.shrink();
    // Safety net: an ad must never take a screen down. If a parent hands us
    // unbounded width (a Row, a horizontal list) the frame can't lay out, so
    // render nothing instead of throwing.
    return LayoutBuilder(builder: (context, constraints) {
      if (!constraints.hasBoundedWidth) return const SizedBox.shrink();
      final banners = [
        for (final s in inline)
          if (s.display == 'banner') ...s.ads,
      ];
      final rest = inline.where((s) => s.display != 'banner').toList();
      final parts = <Widget>[
        for (final s in rest)
          switch (s.display) {
            'carousel' => _PromoCarousel(
                // A new set of ads (e.g. after a location fix) is a new
                // carousel: page, timer and viewport start fresh.
                key:
                    ValueKey('${s.slotId}:${s.ads.map((a) => a.id).join(',')}'),
                ads: s.ads,
                interval: widget.interval,
                onSeen: _impress,
              ),
            'top_bar' => _topBar(s.ads.first),
            _ => Builder(builder: (_) {
                final ad = s.ads.first;
                _impress(ad);
                return PromoCard(
                  ad: ad,
                  onOpen: () => openServedAd(ref, ad),
                  onClose: () => _close(ad),
                );
              }),
          },
        if (banners.isNotEmpty) _banners(context, banners),
      ];
      return Column(children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          parts[i],
        ],
      ]);
    });
  }

  Widget _topBar(ServedAd ad) {
    final p = context.palette;
    final (bg, fg) = promoAccent(p, ad.accent);
    _impress(ad);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => openServedAd(ref, ad),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Row(children: [
            if (ad.isPromo)
              Icon(Icons.auto_awesome_rounded, size: 17, color: fg)
            else
              AdBadge(ad: ad),
            const SizedBox(width: 10),
            Expanded(
              child: Text(ad.title ?? ad.body ?? ad.advertiserName ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      height: 1.3,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(46),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(ad.ctaLabel ?? 'See',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: fg,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
                Icon(Icons.chevron_right_rounded, size: 15, color: fg),
              ]),
            ),
            IconButton(
              onPressed: () => _close(ad),
              icon: Icon(Icons.close_rounded, size: 18, color: fg),
              visualDensity: VisualDensity.compact,
              tooltip: 'Close',
            ),
          ]),
        ),
      ),
    );
  }

  Widget _banners(BuildContext context, List<ServedAd> ads) {
    if (!widget.carousel) {
      return Column(children: [
        for (var i = 0; i < ads.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _frame(ads[i]),
        ],
      ]);
    }

    if (ads.length > 1) {
      _spin ??= Timer.periodic(widget.interval, (_) {
        if (mounted) setState(() => _idx++);
      });
    }
    final p = context.palette;
    final current = ads[_idx % ads.length];
    return Column(children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: KeyedSubtree(key: ValueKey(current.id), child: _frame(current)),
      ),
      if (ads.length > 1) ...[
        const SizedBox(height: 6),
        _Dots(
            count: ads.length,
            index: _idx % ads.length,
            color: p.accent,
            rest: p.muted.withAlpha(80)),
      ],
    ]);
  }
}

class _Dots extends StatelessWidget {
  const _Dots(
      {required this.count,
      required this.index,
      required this.color,
      required this.rest});
  final int count;
  final int index;
  final Color color;
  final Color rest;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: i == index ? 14 : 5,
              height: 5,
              decoration: BoxDecoration(
                color: i == index ? color : rest,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
}

/// Swipeable message cards that move on by themselves (paused while a finger
/// is on them). A view counts when a card comes on screen.
class _PromoCarousel extends ConsumerStatefulWidget {
  const _PromoCarousel({
    super.key,
    required this.ads,
    required this.interval,
    required this.onSeen,
  });
  final List<ServedAd> ads;
  final Duration interval;
  final void Function(ServedAd ad) onSeen;

  @override
  ConsumerState<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends ConsumerState<_PromoCarousel> {
  late final PageController _pc =
      PageController(viewportFraction: widget.ads.length > 1 ? 0.88 : 1);
  Timer? _timer;
  int _page = 0;
  bool _touching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.ads.isNotEmpty) widget.onSeen(widget.ads.first);
    });
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    if (widget.ads.length <= 1) return;
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted || _touching || !_pc.hasClients) return;
      final next = (_page + 1) % widget.ads.length;
      // ignore: discarded_futures
      _pc.animateToPage(next,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ads = widget.ads;
    return LayoutBuilder(builder: (context, c) {
      final fraction = ads.length > 1 ? 0.88 : 1.0;
      final cardW = c.maxWidth * fraction;
      // Art (16:7) + two-line title, two-line body and the button.
      final textH = MediaQuery.textScalerOf(context).scale(1) * 150;
      final height = cardW * 7 / 16 + textH + 30;
      return Column(children: [
        SizedBox(
          height: height,
          child: Listener(
            onPointerDown: (_) => _touching = true,
            onPointerUp: (_) => _touching = false,
            onPointerCancel: (_) => _touching = false,
            child: PageView.builder(
              controller: _pc,
              padEnds: false,
              itemCount: ads.length,
              onPageChanged: (i) {
                setState(() => _page = i);
                widget.onSeen(ads[i]);
                _restart();
              },
              itemBuilder: (context, i) {
                final ad = ads[i];
                return Padding(
                  padding: EdgeInsets.only(right: ads.length > 1 ? 10 : 0),
                  child: ad.isPromo
                      ? SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: PromoCard(
                            ad: ad,
                            clamp: true,
                            onOpen: () => openServedAd(ref, ad),
                          ),
                        )
                      // A sponsored creative keeps its own shape (never
                      // cropped to the card height).
                      : Align(
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            onTap: () => openServedAd(ref, ad),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: AspectRatio(
                                aspectRatio: ad.aspectRatio ?? 16 / 7,
                                child: Stack(fit: StackFit.expand, children: [
                                  ad.hasImage
                                      ? CachedNetworkImage(
                                          imageUrl: ad.imageUrl,
                                          fit: BoxFit.contain,
                                          placeholder: (_, __) =>
                                              Container(color: p.surface2),
                                          errorWidget: (_, __, ___) =>
                                              Container(color: p.surface2),
                                        )
                                      : Container(color: p.surface2),
                                  Positioned(
                                      right: 8, top: 8, child: AdBadge(ad: ad)),
                                ]),
                              ),
                            ),
                          ),
                        ),
                );
              },
            ),
          ),
        ),
        if (ads.length > 1) ...[
          const SizedBox(height: 8),
          _Dots(
              count: ads.length,
              index: _page,
              color: p.accent,
              rest: p.muted.withAlpha(80)),
        ],
      ]);
    });
  }
}
