import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/onboarding/intent_cards.dart';
import 'package:sportpadi_mobile/features/onboarding/intents.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// /start/<intent> — the onboarding-style carousel after sign-in: one page
/// per step (a picture of the thing, a title, a paragraph) with a
/// "Step 2 of 4" counter and segmented progress, then the first relevant
/// page. Records the intent on the profile when opened (so Home can put the
/// right card first) and marks it seen on finish or skip.
/// Web twin: app/start/[intent]/StartWizard.tsx.
class StartWizardScreen extends ConsumerStatefulWidget {
  const StartWizardScreen({super.key, required this.intentKey});
  final String intentKey;

  @override
  ConsumerState<StartWizardScreen> createState() => _StartWizardScreenState();
}

class _StartWizardScreenState extends ConsumerState<StartWizardScreen> {
  final _pages = PageController();
  int _step = 0;
  bool _leaving = false;

  UserIntent? get _intent => intentByKey(widget.intentKey);

  @override
  void initState() {
    super.initState();
    final i = _intent;
    if (i != null) {
      // Fire-and-forget: the wizard must never wait on this.
      // ignore: discarded_futures
      ref.read(profileRepositoryProvider).setIntent(i.key).catchError((_) {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(pendingIntentProvider.notifier).state = null;
      });
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Never waits on the network: the "seen" write goes in the background
  /// and the destination replaces the wizard at once (so Back doesn't
  /// return here).
  void _finish() {
    final i = _intent;
    if (i == null || _leaving) return;
    _leaving = true;
    final repo = ref.read(profileRepositoryProvider);
    // ignore: discarded_futures
    repo.setIntent(i.key, seen: true).catchError((_) {}).whenComplete(() {
      if (mounted) ref.invalidate(meProvider);
    });
    context.go(i.destination);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The shots are small bundled assets; warm them so swipes don't flash.
    final i = _intent;
    if (i != null) {
      for (final s in i.steps) {
        // ignore: discarded_futures
        precacheImage(AssetImage(s.image), context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final i = _intent;
    if (i == null) {
      return Scaffold(
          backgroundColor: p.bg,
          body: Center(
              child: Text('Not sure what you were after — head Home.',
                  style: TextStyle(color: p.muted))));
    }
    final (bg, fg) = intentTint(p, i.key);
    final total = i.steps.length;
    final last = _step == total - 1;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Header: what this is about, where we are, and a way out.
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(12)),
                child: Icon(i.icon, color: fg, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow(i.title),
                      const SizedBox(height: 2),
                      Text('Step ${_step + 1} of $total',
                          style: TextStyle(
                              color: p.muted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ]),
              ),
              TextButton(
                  onPressed: _finish,
                  child: Text('Skip',
                      style: TextStyle(
                          color: p.muted, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 12),
            // Segmented progress — one bar per page so the total is obvious.
            Row(children: [
              for (var k = 0; k < total; k++) ...[
                if (k > 0) const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 5,
                    decoration: BoxDecoration(
                        color: k <= _step ? p.ink : p.line,
                        borderRadius: BorderRadius.circular(999)),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 18),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: total,
                onPageChanged: (n) => setState(() => _step = n),
                itemBuilder: (_, n) => _Slide(
                  step: i.steps[n],
                  index: n,
                  total: total,
                  frame: bg,
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Dots on their own line — the CTA ("Create my group & team")
            // needs the full width on a phone.
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var k = 0; k < total; k++)
                GestureDetector(
                  onTap: () => _pages.animateToPage(k,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: k == _step ? 22 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: k == _step ? p.ink : p.line,
                        borderRadius: BorderRadius.circular(999)),
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              if (_step > 0) ...[
                SpButton(
                  label: 'Back',
                  icon: Icons.arrow_back_rounded,
                  onTap: () => _pages.previousPage(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: SpButton(
                  label: last ? i.cta : 'Next',
                  icon: Icons.arrow_forward_rounded,
                  expand: true,
                  tone: last ? SpButtonTone.brand : SpButtonTone.ink,
                  onTap: last
                      ? _finish
                      : () => _pages.nextPage(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// One page: a picture of the thing, a title, a paragraph. Nothing else —
/// the counter and progress live in the header so each page stays focused.
class _Slide extends StatelessWidget {
  const _Slide({
    required this.step,
    required this.index,
    required this.total,
    required this.frame,
  });
  final IntentStep step;
  final int index;
  final int total;
  final Color frame;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Scrolls only when it has to (small phones, large text).
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: frame,
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Image.asset(step.image,
                  fit: BoxFit.fitWidth,
                  width: double.infinity,
                  semanticLabel: step.title),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: p.surface.withAlpha(235),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withAlpha(20),
                        blurRadius: 6,
                        offset: const Offset(0, 2)),
                  ],
                ),
                child: Text('${index + 1}/$total',
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        Text(step.title,
            style: TextStyle(
                color: p.ink,
                fontSize: 26,
                height: 1.15,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6)),
        const SizedBox(height: 10),
        Text(step.body,
            style: TextStyle(color: p.muted, fontSize: 16, height: 1.45)),
      ]),
    );
  }
}
