import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/onboarding/intents.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The intent picked before sign-up, remembered for the session so the
/// email-verification step (which swaps the whole stack) still ends on the
/// wizard. Cleared when the wizard opens.
final pendingIntentProvider = StateProvider<String?>((_) => null);

/// Colours per intent, shared by the welcome cards, the wizard and Home.
(Color, Color) intentTint(AppPalette p, String key) => switch (key) {
      'coach' => (p.orangeTint, p.orangeInk),
      'guardian' => (p.wardTint, p.ward),
      'host' => (p.hero, p.onHero),
      _ => (p.accentTint, p.greenText),
    };

/// Where a card sends you: signed out → sign in / up with the wizard as the
/// redirect; signed in → the wizard directly.
void openIntent(BuildContext context, WidgetRef ref, UserIntent i) {
  final signedIn =
      ref.read(authControllerProvider).valueOrNull?.isAuthenticated ?? false;
  final start = '/start/${i.key}';
  if (signedIn) {
    context.push(start);
  } else {
    ref.read(pendingIntentProvider.notifier).state = i.key;
    context.push(
        '/sign-in?intent=${i.key}&redirect=${Uri.encodeComponent(start)}');
  }
}

/// "What brings you to SportPadi?" — the four doors on the welcome screen.
/// Each sells one reason to be here and takes the visitor straight into
/// that journey (web twin: components/intents/IntentCards.tsx).
class IntentCards extends ConsumerWidget {
  const IntentCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Eyebrow('Start here'),
      const SizedBox(height: 4),
      Text('What brings you to SportPadi?',
          style: TextStyle(
              color: p.ink,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4)),
      const SizedBox(height: 2),
      Text("Pick one and we'll take you straight there.",
          style: TextStyle(color: p.muted, fontSize: 12.5)),
      const SizedBox(height: 12),
      for (final (n, i) in intents.indexed) ...[
        if (n > 0) const SizedBox(height: 8),
        _IntentCard(intent: i, onTap: () => openIntent(context, ref, i)),
      ],
    ]);
  }
}

class _IntentCard extends StatelessWidget {
  const _IntentCard({required this.intent, required this.onTap});
  final UserIntent intent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg) = intentTint(p, intent.key);
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
          child: Icon(intent.icon, color: fg, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(intent.title,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(intent.blurb,
                    style: TextStyle(
                        color: p.muted, fontSize: 12.5, height: 1.35)),
              ]),
        ),
        const SizedBox(width: 6),
        Icon(Icons.chevron_right_rounded, color: p.muted, size: 22),
      ]),
    );
  }
}
