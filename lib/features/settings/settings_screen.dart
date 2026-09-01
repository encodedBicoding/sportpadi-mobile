import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/env/app_config.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Settings — account info and sign out (the only place sign out lives).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final me = ref.watch(meProvider).valueOrNull;
    final config = ref.watch(appConfigProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('Settings',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Eyebrow('Account'),
          const SizedBox(height: 8),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (me != null) ...[
                  _row(context, 'Name', me.displayName),
                  _row(context, 'Username', '@${me.username}'),
                ] else
                  Text('Loading…',
                      style: TextStyle(color: p.muted, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Eyebrow('App'),
          const SizedBox(height: 8),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row(context, 'Server', config.apiBaseUrl),
                _row(context, 'Flavor', config.flavor.name),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _confirmSignOut(context, ref),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color.fromRGBO(222, 33, 33, 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, size: 18, color: p.danger),
                    const SizedBox(width: 8),
                    Text('Sign out',
                        style: TextStyle(
                            color: p.danger,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: TextStyle(color: p.muted, fontSize: 12.5)),
        ),
        Expanded(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: p.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}
