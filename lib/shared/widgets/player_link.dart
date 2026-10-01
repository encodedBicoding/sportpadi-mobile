import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/features/shell/home_shell.dart'
    show homeTabIndexProvider;

/// Tap a person, open their profile — anywhere a player shows up (rosters,
/// lineups, check-ins, team lists, leaderboards, posts…). Your own name opens
/// your own Profile tab; anyone else's opens their public page
/// (/players/<userId>), which shows "This profile is private" when they've
/// turned that on. Web twin: apps/web/src/components/players/PlayerLink.tsx.
void openPlayerProfile(BuildContext context, WidgetRef ref, String? userId) {
  if (userId == null || userId.isEmpty) return;
  final me = ref.read(authControllerProvider).valueOrNull?.user?.id;
  if (me != null && me == userId) {
    // Profile is tab 4 of the signed-in shell.
    ref.read(homeTabIndexProvider.notifier).state = 4;
    context.go('/home');
    return;
  }
  context.push('/players/$userId');
}

/// Wraps a name / avatar so a tap opens that person's profile. Taps don't
/// reach the row underneath, so rows with their own action keep it. Without
/// a [userId] the child is shown as it is.
class PlayerTap extends ConsumerWidget {
  const PlayerTap({
    super.key,
    required this.userId,
    required this.child,
    this.borderRadius = 10,
  });

  final String? userId;
  final Widget child;
  final double borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = userId;
    if (id == null || id.isEmpty) return child;
    return Semantics(
      button: true,
      label: 'View profile',
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: () => openPlayerProfile(context, ref, id),
        child: child,
      ),
    );
  }
}
