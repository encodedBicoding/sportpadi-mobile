import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/push/push_service.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/notifications/notification_permission_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// The always-there reminder on Home when this device can't receive pushes
/// for the signed-in user. The soft-ask sheet (NotificationPermissionSheet)
/// is throttled by the platform guidelines — three asks, a week apart — and
/// that budget lives in secure storage, which on iOS survives a reinstall;
/// so after a delete-and-reinstall (permission reset by the OS) or an update
/// where registration failed, the sheet stayed quiet and the user never knew.
/// This card isn't throttled: it shows until the device is registered, and
/// "Later" only hides it until the next launch.
///
/// One tap fixes whatever is wrong:
///   • never asked   → the explainer, then the OS dialog
///   • refused       → the explainer, then the system Settings page
///   • allowed but the server doesn't have this device → register again
class NotificationsNudgeCard extends ConsumerStatefulWidget {
  const NotificationsNudgeCard({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<NotificationsNudgeCard> createState() => _NotificationsNudgeCardState();
}

/// "Later" on this launch — comes back next time the app starts.
final _nudgeHiddenProvider = StateProvider<bool>((_) => false);

class _NotificationsNudgeCardState extends ConsumerState<NotificationsNudgeCard> {
  bool _busy = false;

  Future<void> _fix(AuthorizationStatus status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final push = ref.read(pushServiceProvider);
      if (status == AuthorizationStatus.notDetermined || status == AuthorizationStatus.denied) {
        final denied = status == AuthorizationStatus.denied;
        final allow = await showSpSheet<bool>(
          context,
          builder: (_) => NotificationPermissionSheet(settings: denied),
        );
        if (allow != true) return;
        if (denied) {
          // Only the system page can flip a refusal; the shell's resume hook
          // re-reads the status and registers when the user comes back.
          await AppSettings.openAppSettings(type: AppSettingsType.notification);
          return;
        }
        final s = await push.requestPermission();
        if (!mounted) return;
        ref.read(pushStatusProvider.notifier).state = s;
        return;
      }
      // Allowed, but the server doesn't have this device: register again.
      final s = await push.onAppResumed();
      if (!mounted) return;
      ref.read(pushStatusProvider.notifier).state = s;
      setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final status = ref.watch(pushStatusProvider);
    final hidden = ref.watch(_nudgeHiddenProvider);
    final push = ref.read(pushServiceProvider);
    // Nothing to say: not configured (null), hidden for this launch, or the
    // device is allowed AND registered.
    if (status == null || hidden) return const SizedBox.shrink();
    final allowed = status == AuthorizationStatus.authorized || status == AuthorizationStatus.provisional;
    if (allowed && push.registeredWithServer) return const SizedBox.shrink();

    final String title;
    final String body;
    final String cta;
    if (status == AuthorizationStatus.notDetermined) {
      title = 'Turn on notifications';
      body = "Game reminders, team news and updates for your groups can't reach this phone yet.";
      cta = 'Turn on';
    } else if (status == AuthorizationStatus.denied) {
      title = 'Notifications are off';
      body = 'This phone has notifications switched off for SportPadi, so game reminders and updates can\'t reach you here.';
      cta = 'Settings';
    } else {
      title = "Notifications aren't connected";
      body = push.lastRegisterError != null
          ? "Notifications are allowed, but this phone couldn't be registered — try again."
          : 'Notifications are allowed, but this phone isn\'t registered for your account yet.';
      cta = 'Connect';
    }

    return Padding(
      padding: widget.padding,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SpIconTile(Icons.notifications_active_outlined, bg: p.orangeTint, fg: p.orangeInk),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: p.ink, fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(body, style: TextStyle(color: p.muted, fontSize: 12, height: 1.35)),
              const SizedBox(height: 10),
              Row(children: [
                Material(
                  color: p.hero,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: _busy ? null : () => _fix(status),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: _busy
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: p.onHero))
                          : Text(cta,
                              style: TextStyle(color: p.onHero, fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: () => ref.read(_nudgeHiddenProvider.notifier).state = true,
                  style: TextButton.styleFrom(
                      foregroundColor: p.muted, padding: const EdgeInsets.symmetric(horizontal: 10)),
                  child: const Text('Later', style: TextStyle(fontSize: 12.5)),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
