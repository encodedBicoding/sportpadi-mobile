import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/ads/ads_repository.dart';

/// Flexible ad unit — hand it any slot keys and a mode:
///   AdDisplay(slots: ['mobile-home'])                       → static, stacked
///   AdDisplay(slots: ['mobile-home','x'], carousel: true)   → one rotating frame
/// Renders nothing (zero height) when no ads match, so it can sit anywhere.
/// Location targeting is server-side; the widget also quietly refreshes the
/// viewer's locale when OS location permission is already granted.
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

bool _personalizedThisRun = false;

class _AdDisplayState extends ConsumerState<AdDisplay> {
  Timer? _spin;
  int _idx = 0;
  final _seen = <String>{};

  @override
  void initState() {
    super.initState();
    if (!_personalizedThisRun) {
      _personalizedThisRun = true;
      // Fire and forget; never blocks or prompts.
      // ignore: unawaited_futures
      ref.read(adsRepositoryProvider).personalizeIfPermitted();
    }
  }

  @override
  void dispose() {
    _spin?.cancel();
    super.dispose();
  }

  void _impress(ServedAd ad) {
    if (_seen.add(ad.id)) {
      // ignore: unawaited_futures
      ref.read(adsRepositoryProvider).log('impression', ad.id, ad.slotId);
    }
  }

  Future<void> _open(ServedAd ad) async {
    // ignore: unawaited_futures
    ref.read(adsRepositoryProvider).log('click', ad.id, ad.slotId);
    final uri = Uri.tryParse(ad.clickUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Widget _frame(ServedAd ad) {
    final p = context.palette;
    _impress(ad);
    return InkWell(
      onTap: () => _open(ad),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          AspectRatio(
            aspectRatio: 3.2, // banner-ish; image covers
            child: Image.network(
              ad.imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: Container(
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
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ads =
        ref.watch(servedAdsProvider(widget.slots.join(','))).valueOrNull;
    if (ads == null || ads.isEmpty) return const SizedBox.shrink();

    if (!widget.carousel) {
      return Column(children: [
        for (var i = 0; i < ads.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _frame(ads[i]),
        ],
      ]);
    }

    _spin ??= Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _idx++);
    });
    final p = context.palette;
    final current = ads[_idx % ads.length];
    return Column(children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        child: KeyedSubtree(
            key: ValueKey(current.id), child: _frame(current)),
      ),
      if (ads.length > 1) ...[
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < ads.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: i == _idx % ads.length ? 14 : 5,
                height: 5,
                decoration: BoxDecoration(
                  color: i == _idx % ads.length
                      ? p.accent
                      : p.muted.withAlpha(80),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    ]);
  }
}
