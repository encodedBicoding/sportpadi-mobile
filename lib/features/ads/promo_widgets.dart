import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/ads/ads_repository.dart';
import 'package:sportpadi_mobile/features/inbox/announcement_card.dart'
    show openAnnouncementUrl;

/// Shared parts for SportPadi messages and sponsored ads in every display
/// (AdDisplay inline, PopupMessages on open). The server decides WHAT to show
/// (packages/api/src/ads/decide.ts); these draw it and report back a view, a
/// tap or a close — which is what each message's caps count. Web twin:
/// apps/web/src/components/ads/promo.tsx.

/// Panel colours for a message with no picture: (background, foreground).
(Color, Color) promoAccent(AppPalette p, String? accent) => switch (accent) {
      'ink' => (p.hero, p.onHero),
      'orange' => (p.orange, Colors.white),
      'blue' => (const Color(0xFF2563EB), Colors.white),
      _ => (p.accentDeep, Colors.white),
    };

/// Tap: count it, then open — our own pages in the app (same resolver as
/// deep links and pushes), anything else in the browser.
Future<void> openServedAd(WidgetRef ref, ServedAd ad) async {
  // ignore: unawaited_futures
  ref.read(adsRepositoryProvider).log('click', ad.id, ad.slotId);
  await openAnnouncementUrl(ref, ad.clickUrl);
}

/// The picture — always whole, never cropped — or a coloured panel with
/// soft circles when there isn't one ([aspectRatio] sizes the panel).
///
/// A picture shows at its own shape ([fixed] false), capped at [maxHeight]
/// (default: 55% of the screen) and letterboxed if taller. In a [fixed] box
/// (carousel cards share one height) it's fitted inside [aspectRatio],
/// letterboxed rather than cut.
class PromoArt extends StatelessWidget {
  const PromoArt({
    super.key,
    required this.ad,
    this.aspectRatio = 16 / 8,
    this.compact = false,
    this.fixed = false,
    this.maxHeight,
  });
  final ServedAd ad;
  final double aspectRatio;
  final bool compact;
  final bool fixed;
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg) = promoAccent(p, ad.accent);
    final panel = Container(
      color: bg,
      child: Stack(children: [
        Positioned(
          right: -30,
          top: -40,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(color: Colors.white.withAlpha(26), shape: BoxShape.circle),
          ),
        ),
        Positioned(
          right: 60,
          bottom: -46,
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(color: Colors.white.withAlpha(26), shape: BoxShape.circle),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 14,
          child: Icon(Icons.auto_awesome_rounded, color: fg, size: compact ? 20 : 30),
        ),
      ]),
    );
    if (!ad.hasImage) return AspectRatio(aspectRatio: aspectRatio, child: panel);
    if (fixed) {
      return AspectRatio(
        aspectRatio: aspectRatio,
        child: ColoredBox(
          color: p.surface2,
          child: CachedNetworkImage(
            imageUrl: ad.imageUrl,
            fit: BoxFit.contain,
            placeholder: (_, __) => const SizedBox.shrink(),
            errorWidget: (_, __, ___) => panel,
          ),
        ),
      );
    }
    final cap = maxHeight ?? MediaQuery.sizeOf(context).height * 0.55;
    return ColoredBox(
      color: p.surface2,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: cap),
        child: CachedNetworkImage(
          imageUrl: ad.imageUrl,
          // Full width at the picture's own height (contain keeps all of it
          // when the cap kicks in).
          width: double.infinity,
          fit: BoxFit.contain,
          placeholder: (_, __) => AspectRatio(aspectRatio: 16 / 9, child: Container(color: p.surface2)),
          errorWidget: (_, __, ___) => AspectRatio(aspectRatio: aspectRatio, child: panel),
        ),
      ),
    );
  }
}

/// "AD" on sponsored creatives; SportPadi's own messages carry no badge.
class AdBadge extends StatelessWidget {
  const AdBadge({super.key, required this.ad});
  final ServedAd ad;

  @override
  Widget build(BuildContext context) {
    if (ad.isPromo) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('AD',
          style: TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6)),
    );
  }
}

/// Title, body and the button.
class PromoText extends StatelessWidget {
  const PromoText({
    super.key,
    required this.ad,
    required this.onOpen,
    this.large = false,
    this.clamp = false,
  });
  final ServedAd ad;
  final VoidCallback onOpen;
  final bool large;
  /// Two lines each at most (cards in a carousel share one height).
  final bool clamp;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final title = ad.title ?? ad.advertiserName ?? ad.altText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Text(title,
              maxLines: clamp ? 2 : null,
              overflow: clamp ? TextOverflow.ellipsis : null,
              style: TextStyle(
                  color: p.ink,
                  fontSize: large ? 20 : 15.5,
                  height: 1.25,
                  fontWeight: FontWeight.w800)),
        if (ad.body != null) ...[
          SizedBox(height: large ? 8 : 5),
          Text(ad.body!,
              maxLines: clamp ? 2 : null,
              overflow: clamp ? TextOverflow.ellipsis : null,
              style: TextStyle(color: p.muted, fontSize: large ? 14.5 : 13, height: 1.35)),
        ],
        SizedBox(height: large ? 16 : 10),
        Material(
          color: p.ink,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onOpen,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: large ? 20 : 16, vertical: large ? 12 : 9),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(ad.ctaLabel ?? 'Learn more',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: p.bg,
                          fontSize: large ? 14.5 : 13,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 3),
                Icon(Icons.chevron_right_rounded, size: 17, color: p.bg),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

/// One message card: art on top, words and a button below; optional close.
class PromoCard extends StatelessWidget {
  const PromoCard({
    super.key,
    required this.ad,
    required this.onOpen,
    this.onClose,
    this.clamp = false,
  });
  final ServedAd ad;
  final VoidCallback onOpen;
  final VoidCallback? onClose;
  final bool clamp;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(children: [
            GestureDetector(
                onTap: onOpen,
                // In a carousel every card is one height: fit the picture in
                // its box. On its own, show it at its own shape.
                child: PromoArt(
                    ad: ad,
                    aspectRatio: 16 / 7,
                    compact: true,
                    fixed: clamp,
                    maxHeight: 360)),
            // Left, so the close button never covers the disclosure.
            Positioned(left: 8, top: 8, child: AdBadge(ad: ad)),
            if (onClose != null)
              Positioned(
                right: 6,
                top: 6,
                child: Material(
                  color: Colors.black38,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onClose,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.close_rounded, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: PromoText(ad: ad, onOpen: onOpen, clamp: clamp),
          ),
        ],
      ),
    );
  }
}
