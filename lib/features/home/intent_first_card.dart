import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/data/wards/wards_repository.dart';
import 'package:sportpadi_mobile/features/groups/groups_providers.dart';
import 'package:sportpadi_mobile/features/onboarding/intent_cards.dart';
import 'package:sportpadi_mobile/features/onboarding/intents.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Which intent's "do the thing" card should lead Home right now (null =
/// the normal quick actions): a guardian with no wards, a coach or host
/// with no group. Everything else on Home — "Suggested for you" included —
/// is the same for everyone; a parent may want a game of their own later.
/// Web twin: components/home/IntentFirstCard.tsx.
String? intentHomeCard(WidgetRef ref) {
  final intent = ref.watch(meProvider).valueOrNull?.intent;
  if (intent == null || intent == 'play') return null;
  if (intent == 'guardian') {
    final wards = ref.watch(myWardsProvider).valueOrNull;
    return wards != null && wards.wards.isEmpty ? 'guardian' : null;
  }
  final groups = ref.watch(myGroupsProvider).valueOrNull;
  return groups != null && groups.isEmpty ? intent : null;
}

/// The first card on Home for someone who came with a purpose and hasn't
/// acted on it yet. Goes away once the ward / group exists.
class IntentFirstCard extends ConsumerWidget {
  const IntentFirstCard({super.key, required this.intentKey});
  final String intentKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final i = intentByKey(intentKey);
    if (i == null) return const SizedBox.shrink();
    final (bg, fg) = intentTint(p, i.key);
    final (title, body, cta) = switch (i.key) {
      'guardian' => (
          'Add your child to get going',
          'Their RSVPs, tickets and QR check-in all come to you.',
          'Add my child'
        ),
      'coach' => (
          'Set up your team',
          'Create your group, add the roster — squads for tournaments follow.',
          'Create my group & team'
        ),
      _ => (
          'Create your group',
          'Then add your first event — tickets, check-in and teams are built in.',
          'Create my group'
        ),
    };
    return GlassCard(
      onTap: () => context.go(i.destination),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
          child: Icon(i.icon, color: fg, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body,
                    style: TextStyle(
                        color: p.muted, fontSize: 12.5, height: 1.35)),
                const SizedBox(height: 10),
                SpButton(
                    label: cta,
                    icon: Icons.arrow_forward_rounded,
                    tone: SpButtonTone.brand,
                    onTap: () => context.go(i.destination)),
              ]),
        ),
      ]),
    );
  }
}
