import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/core/update/app_update.dart';
import 'package:sportpadi_mobile/data/ads/ads_repository.dart';
import 'package:sportpadi_mobile/features/ads/promo_widgets.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// Pop-up messages (docs/design/2026-redesign.md row 71): when the app opens
/// — a cold start, a sign-in, or coming back after a long while — ask the
/// server for the best pop-up slot that has something for THIS person and
/// show it once: a bottom sheet, a spotlight card or a What's new story. The
/// server applies the audience and each message's caps
/// (packages/api/src/ads/decide.ts); this only draws, and reports views,
/// taps and closes back. It waits for the screen to be clear (the
/// notifications explainer, any open sheet) and gives up rather than
/// interrupting. Web twin: apps/web/src/components/ads/PopupHost.tsx.
class PopupMessages {
  PopupMessages._();

  /// The screen currently looking for a pop-up. A shell that went away (the
  /// guest shell, on sign-in) doesn't block the next one.
  static BuildContext? _owner;

  /// This run's ticket, so the run that finishes clears only its own claim
  /// (without touching a BuildContext after the awaits).
  static Object? _ownerToken;

  /// Coming back to the app counts as "opening" it after this long away.
  static const resumeAfter = Duration(minutes: 30);

  static Future<void> maybeShow(BuildContext context, WidgetRef ref) async {
    final owner = _owner;
    if (owner != null && owner.mounted) return;
    _owner = context;
    final token = Object();
    _ownerToken = token;
    try {
      // The screen must be clear: this route on top, no sheet or dialog.
      var clear = false;
      for (var i = 0; i < 10; i++) {
        if (!context.mounted) return;
        final route = ModalRoute.of(context);
        if (route == null || route.isCurrent) {
          clear = true;
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      if (!clear || !context.mounted) return;

      final repo = ref.read(adsRepositoryProvider);
      final slots = await repo.serveSlots(const [], popup: true);
      if (slots.isEmpty || slots.first.ads.isEmpty || !context.mounted) return;
      // An update prompt is up — don't stack a message on top of it.
      if (AppUpdateGate.showing) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        return; // something opened meanwhile
      }
      final slot = slots.first;

      final viewed = <String>{};
      void seen(ServedAd ad) {
        if (viewed.add(ad.id) && ad.logViews) {
          // ignore: unawaited_futures
          repo.log('impression', ad.id, ad.slotId);
        }
      }

      final String? result;
      if (slot.display == 'modal') {
        result = await showDialog<String>(
          context: context,
          barrierColor: const Color(0x8C0E1411),
          builder: (_) => _Spotlight(ad: slot.ads.first, onSeen: seen),
        );
      } else {
        result = await showSpSheet<String>(
          context,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          builder: (_) => slot.display == 'whats_new'
              ? _Story(ads: slot.ads, onSeen: seen)
              : _SheetMessage(ad: slot.ads.first, onSeen: seen),
        );
      }

      // Tapped through: open it (the tap is what's counted). Otherwise it was
      // closed — tell the server, which hides it for good if it should.
      if (result != null && result.startsWith('open:')) {
        final id = result.substring(5);
        final ad = slot.ads.where((a) => a.id == id).firstOrNull;
        if (ad != null && context.mounted) await openServedAd(ref, ad);
      } else {
        for (final id in viewed) {
          // ignore: unawaited_futures
          repo.dismiss(id);
        }
      }
    } finally {
      if (identical(_ownerToken, token)) {
        _owner = null;
        _ownerToken = null;
      }
    }
  }
}

/// The art, rounded, with the AD badge when it's sponsored.
class _Art extends StatelessWidget {
  const _Art({required this.ad, required this.aspectRatio});
  final ServedAd ad;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(children: [
          PromoArt(ad: ad, aspectRatio: aspectRatio),
          Positioned(right: 8, top: 8, child: AdBadge(ad: ad)),
        ]),
      );
}

class _NotNow extends StatelessWidget {
  const _NotNow();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TextButton(
      onPressed: () => Navigator.of(context).pop(),
      style: TextButton.styleFrom(
        foregroundColor: p.muted,
        minimumSize: const Size.fromHeight(44),
      ),
      child:
          const Text('Not now', style: TextStyle(fontWeight: FontWeight.w600)),
    );
  }
}

/// Bottom sheet: one message springing up from the bottom.
class _SheetMessage extends StatefulWidget {
  const _SheetMessage({required this.ad, required this.onSeen});
  final ServedAd ad;
  final void Function(ServedAd) onSeen;

  @override
  State<_SheetMessage> createState() => _SheetMessageState();
}

class _SheetMessageState extends State<_SheetMessage> {
  @override
  void initState() {
    super.initState();
    widget.onSeen(widget.ad);
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Art(ad: ad, aspectRatio: 16 / 9),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: PromoText(
            ad: ad,
            large: true,
            onOpen: () => Navigator.of(context).pop('open:${ad.id}'),
          ),
        ),
        const SizedBox(height: 6),
        const _NotNow(),
      ],
    );
  }
}

/// Spotlight: a centred card over the screen.
class _Spotlight extends StatefulWidget {
  const _Spotlight({required this.ad, required this.onSeen});
  final ServedAd ad;
  final void Function(ServedAd) onSeen;

  @override
  State<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<_Spotlight> {
  @override
  void initState() {
    super.initState();
    widget.onSeen(widget.ad);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ad = widget.ad;
    return Dialog(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(children: [
                PromoArt(ad: ad, aspectRatio: 4 / 3),
                Positioned(left: 10, top: 10, child: AdBadge(ad: ad)),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Material(
                    color: Colors.black38,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(7),
                        child: Icon(Icons.close_rounded,
                            size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: PromoText(
                  ad: ad,
                  large: true,
                  onOpen: () => Navigator.of(context).pop('open:${ad.id}'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _NotNow(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What's new: several messages as a story — progress bars, swipe or
/// Next / Back, Done on the last.
class _Story extends StatefulWidget {
  const _Story({required this.ads, required this.onSeen});
  final List<ServedAd> ads;
  final void Function(ServedAd) onSeen;

  @override
  State<_Story> createState() => _StoryState();
}

class _StoryState extends State<_Story> {
  int _i = 0;

  @override
  void initState() {
    super.initState();
    widget.onSeen(widget.ads.first);
  }

  void _go(int i) {
    if (i < 0 || i >= widget.ads.length) return;
    setState(() => _i = i);
    widget.onSeen(widget.ads[i]);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ads = widget.ads;
    final ad = ads[_i];
    final last = _i == ads.length - 1;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -150) _go(_i + 1);
        if (v > 150) _go(_i - 1);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ads.length > 1) ...[
            Row(children: [
              for (var k = 0; k < ads.length; k++) ...[
                if (k > 0) const SizedBox(width: 4),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 4,
                    decoration: BoxDecoration(
                      color: k <= _i ? p.accent : p.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 12),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Column(
              key: ValueKey(ad.id),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Art(ad: ad, aspectRatio: 4 / 3),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ads.length > 1
                            ? "WHAT'S NEW · ${_i + 1} OF ${ads.length}"
                            : "WHAT'S NEW",
                        style: TextStyle(
                            color: p.greenText,
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      PromoText(
                        ad: ad,
                        large: true,
                        onOpen: () =>
                            Navigator.of(context).pop('open:${ad.id}'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            if (ads.length > 1)
              IconButton.filledTonal(
                onPressed: _i == 0 ? null : () => _go(_i - 1),
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Back',
              ),
            const Spacer(),
            TextButton(
              onPressed:
                  last ? () => Navigator.of(context).pop() : () => _go(_i + 1),
              style: TextButton.styleFrom(foregroundColor: p.ink),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(last ? 'Done' : 'Next',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (!last) const Icon(Icons.chevron_right_rounded, size: 20),
              ]),
            ),
          ]),
        ],
      ),
    );
  }
}
