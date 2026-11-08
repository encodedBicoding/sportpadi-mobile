import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/push/push_service.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Pre-permission explainer (the "soft ask"). Shown before the one-shot OS
/// dialog so the user knows what they'd get; "Not now" is respected and the
/// OS is never asked behind their back.
class NotificationPermissionSheet extends ConsumerWidget {
  const NotificationPermissionSheet({super.key, this.settings = false});

  /// The OS already said no. The system dialog can't be shown a second time,
  /// so the button hands the user to Settings instead of asking again.
  final bool settings;

  /// Shows the sheet if the guidelines say it's time (the device can't
  /// receive, and the throttle allows). Returns the resulting status, or null
  /// if nothing was shown.
  ///
  /// Two variants from one decision: never asked → explain, then the OS
  /// dialog; refused → explain, then Settings. On the way back from Settings
  /// the shell's resume hook re-reads the status and registers the device.
  static Future<AuthorizationStatus?> maybeShow(
      BuildContext context, WidgetRef ref) async {
    final push = ref.read(pushServiceProvider);
    if (!await push.shouldPrompt()) return null;
    await push.markPrompted();
    if (!context.mounted) return null;
    final denied = push.status == AuthorizationStatus.denied;
    final allow = await showSpSheet<bool>(
      context,
      builder: (_) => NotificationPermissionSheet(settings: denied),
    );
    if (allow != true) return push.status;
    if (denied) {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
      return push.status;
    }
    final status = await push.requestPermission();
    ref.read(pushStatusProvider.notifier).state = status;
    return status;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    Widget row(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: p.accent.withAlpha(30),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: p.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700)),
                    Text(body,
                        style: TextStyle(
                            color: p.muted, fontSize: 12, height: 1.35)),
                  ]),
            ),
          ]),
        );

    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.notifications_active_rounded, size: 40, color: p.accent),
          const SizedBox(height: 10),
          Text(settings ? context.l10n.inbox_notificationsAreOff : context.l10n.inbox_stayInTheLoop,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: p.ink, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            settings
                ? context.l10n.inbox_thisDeviceHasNotificationsSwitched
                : context.l10n.inbox_turnOnNotificationsSoYou,
            textAlign: TextAlign.center,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 18),
          row(Icons.sports_soccer_rounded, context.l10n.inbox_gameReminders,
              context.l10n.inbox_kickOffTimesVenueChanges),
          row(Icons.groups_rounded, context.l10n.inbox_teamAssignments,
              context.l10n.inbox_findOutWhichSideYoure),
          row(Icons.confirmation_number_rounded, context.l10n.inbox_ticketsPayments,
              context.l10n.inbox_purchaseConfirmationsRefundsAndCheck),
          row(Icons.account_balance_wallet_rounded, context.l10n.inbox_groupAdminAlerts,
              context.l10n.inbox_withdrawalApprovalsAndNewFollowers),
          const SizedBox(height: 6),
          SpButton(
            label: settings ? context.l10n.inbox_openSettings : context.l10n.inbox_turnOnNotifications,
            icon:
                settings ? Icons.settings_rounded : Icons.notifications_rounded,
            expand: true,
            onTap: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.inbox_notNow, style: TextStyle(color: p.muted)),
          ),
        ]);
  }
}

/// Inline banner for the Notifications screen when the OS permission is off:
/// the system dialog can't be shown twice, so this hands the user to Settings.
class NotificationsOffBanner extends ConsumerWidget {
  const NotificationsOffBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(pushStatusProvider);
    final p = context.palette;
    if (status == null ||
        status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional) {
      return const SizedBox.shrink();
    }
    final notAsked = status == AuthorizationStatus.notDetermined;
    Future<void> act() async {
      if (notAsked) {
        final s = await ref.read(pushServiceProvider).requestPermission();
        ref.read(pushStatusProvider.notifier).state = s;
      } else {
        await AppSettings.openAppSettings(type: AppSettingsType.notification);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          SpIconTile(Icons.notifications_off_outlined,
              bg: p.orangeTint, fg: p.orangeInk),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.l10n.inbox_pushNotificationsAreOff,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700)),
              Text(
                notAsked
                    ? context.l10n.inbox_turnThemOnForGame
                    : context.l10n.inbox_allowSportPadiInYourDevice,
                style: TextStyle(color: p.muted, fontSize: 12, height: 1.35),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Material(
            color: p.hero,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: act,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Text(notAsked ? context.l10n.inbox_turnOn : context.l10n.inbox_settings,
                    style: TextStyle(
                        color: p.onHero,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
