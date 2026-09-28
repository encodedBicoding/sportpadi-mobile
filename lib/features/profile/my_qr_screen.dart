import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/async_view.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_leading.dart';

/// The player's personal QR — organizers scan it at the gate.
class MyQrScreen extends ConsumerWidget {
  const MyQrScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const SpLeading(),
        backgroundColor: p.bg,
        surfaceTintColor: p.bg,
        title: const Text('My QR code',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: AsyncView(
        value: me,
        onRetry: () => ref.invalidate(meProvider),
        data: (profile) {
          final code = profile?.qrCode;
          if (code == null || code.isEmpty) {
            return Center(
              child: Text('No QR code on your profile yet.',
                  style: TextStyle(color: p.muted)),
            );
          }
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: QrImageView(
                      data: code, size: 230, backgroundColor: Colors.white),
                ),
                const SizedBox(height: 14),
                Text(profile!.displayName,
                    style: TextStyle(
                        color: p.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Show this to an organizer to be identified.',
                    style: TextStyle(color: p.muted, fontSize: 12.5)),
              ],
            ),
          );
        },
      ),
    );
  }
}
