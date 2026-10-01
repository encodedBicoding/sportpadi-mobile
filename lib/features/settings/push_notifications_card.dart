import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/push/push_service.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// "Push notifications" on Settings.
///
/// In the live app this is ONE row: a green check when this device can
/// receive pushes (permission granted and the token registered with the
/// server), otherwise a tappable row that fixes it — the OS prompt when
/// the user was never asked, the system Settings page when they refused,
/// a retry when the permission is fine but registration didn't go through.
///
/// Debug builds get the full chain underneath (token, server, a real test
/// push and FCM's per-device verdict), because that's where a "no row is
/// red yet nothing arrives" problem is diagnosed. None of it ships.
class PushNotificationsCard extends ConsumerStatefulWidget {
  const PushNotificationsCard({super.key});

  @override
  ConsumerState<PushNotificationsCard> createState() =>
      _PushNotificationsCardState();
}

class _PushNotificationsCardState extends ConsumerState<PushNotificationsCard>
    with WidgetsBindingObserver {
  bool _busy = false;

  // Debug-only diagnostics.
  ({bool serverEnabled, int devices})? _server;
  String? _serverError;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kDebugMode) _loadServer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the system Settings page: re-read the permission and, if it
  /// was just granted, register the device — so the row goes green on its
  /// own without the user doing anything else.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final push = ref.read(pushServiceProvider);
    final status = await push.onAppResumed();
    if (!mounted) return;
    ref.read(pushStatusProvider.notifier).state = status;
    if (kDebugMode) await _loadServer();
    if (mounted) setState(() {});
  }

  Future<void> _loadServer() async {
    try {
      final st = await ref.read(pushServiceProvider).serverStatus();
      if (mounted) setState(() => _server = st);
    } catch (e) {
      if (mounted) setState(() => _serverError = '$e');
    }
  }

  /// The single tap that makes the row green, whatever is currently wrong.
  Future<void> _fix(AuthorizationStatus? status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final push = ref.read(pushServiceProvider);
      if (status == AuthorizationStatus.denied) {
        // Only the system page can flip a refusal; the resume hook above
        // finishes the job when the user comes back.
        await AppSettings.openAppSettings(type: AppSettingsType.notification);
        return;
      }
      if (status == AuthorizationStatus.notDetermined) {
        final s = await push.requestPermission();
        if (!mounted) return;
        ref.read(pushStatusProvider.notifier).state = s;
      }
      // Granted (now or earlier) but not registered: register.
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final r = await ref.read(pushServiceProvider).sendSelfTest();
      final why = r.errors.isEmpty ? '' : '\nFCM said: ${r.errors.join('; ')}';
      setState(() => _testResult = r.ok > 0
          ? 'Sent to ${r.ok} device${r.ok == 1 ? '' : 's'} — it should arrive within a few seconds.$why'
          : 'The server tried ${r.devices} device${r.devices == 1 ? '' : 's'} and none accepted it.$why');
    } catch (e) {
      setState(() => _testResult = '$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final push = ref.watch(pushServiceProvider);
    final status = ref.watch(pushStatusProvider) ?? push.status;

    final allowed = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
    final ready = allowed && push.registeredWithServer;
    final unavailable = status == null;

    final String detail;
    if (ready) {
      detail = 'On — this device can receive notifications.';
    } else if (unavailable) {
      detail = 'Not available on this device.';
    } else if (status == AuthorizationStatus.denied) {
      detail = 'Off — turned off in your phone\'s settings. Tap to turn on.';
    } else if (status == AuthorizationStatus.notDetermined) {
      detail = 'Off — tap to allow notifications on this device.';
    } else {
      // Allowed by the OS, but the server doesn't have this device yet.
      detail = 'Finishing setup… tap to retry.';
    }

    final tappable = !ready && !unavailable && !_busy;

    Widget leading;
    if (_busy) {
      leading = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      leading = Icon(
        ready
            ? Icons.check_circle_rounded
            : unavailable
                ? Icons.notifications_off_outlined
                : Icons.error_rounded,
        size: 20,
        color: ready ? p.accent : (unavailable ? p.muted : p.danger),
      );
    }

    final row = InkWell(
      onTap: tappable ? () => _fix(status) : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(width: 24, child: Center(child: leading)),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Push notifications',
                  style: TextStyle(
                      color: p.ink, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(detail,
                  style: TextStyle(color: p.muted, fontSize: 12, height: 1.3)),
            ]),
          ),
          if (tappable) ...[
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 20, color: p.muted),
          ],
        ]),
      ),
    );

    return GlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row,
        if (kDebugMode) ..._debugRows(p, push, status, allowed),
      ]),
    );
  }

  // ── Debug builds only: the whole chain, link by link ───────────────────

  List<Widget> _debugRows(
    AppPalette p,
    PushService push,
    AuthorizationStatus? status,
    bool allowed,
  ) {
    final token = push.token;
    final permissionText = switch (status) {
      AuthorizationStatus.authorized => 'Allowed',
      AuthorizationStatus.provisional => 'Allowed (quiet)',
      AuthorizationStatus.denied => 'Denied in system settings',
      AuthorizationStatus.notDetermined => 'Not asked yet',
      null => 'Unknown — Firebase not initialised',
    };

    Widget row(String label, String value,
            {required bool ok, Widget? trailing}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
                ok
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                size: 15,
                color: ok ? p.accent : p.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                    Text(value, style: TextStyle(color: p.muted, fontSize: 11)),
                  ]),
            ),
            if (trailing != null) trailing,
          ]),
        );

    return [
      const SizedBox(height: 8),
      Divider(height: 1, color: p.muted.withAlpha(60)),
      const SizedBox(height: 8),
      Text('DEBUG · push diagnostics',
          style: TextStyle(
              color: p.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6)),
      const SizedBox(height: 4),
      row('Notification permission', permissionText, ok: allowed),
      row(
        'Device token',
        token == null
            ? 'None yet — the device hasn\'t registered with Firebase'
            : '${token.substring(0, 12)}… (tap to copy)',
        ok: token != null,
        trailing: token == null
            ? null
            : IconButton(
                tooltip: 'Copy token',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: token));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Token copied')));
                },
                icon: const Icon(Icons.copy_rounded, size: 15),
              ),
      ),
      row(
        'Registered with SportPadi',
        push.registeredWithServer
            ? 'Yes — this sign-in'
            : (push.lastRegisterError ?? 'Not yet'),
        ok: push.registeredWithServer,
      ),
      row(
        'Server',
        _serverError ??
            (_server == null
                ? 'Checking…'
                : _server!.serverEnabled
                    ? 'Push enabled · ${_server!.devices} device${_server!.devices == 1 ? '' : 's'} on your account'
                    : 'Push is not configured on the server'),
        ok: _server?.serverEnabled == true && (_server?.devices ?? 0) > 0,
      ),
      const SizedBox(height: 8),
      SpButton(
        label: _testing ? 'Sending…' : 'Send me a test notification',
        icon: Icons.notifications_active_outlined,
        expand: true,
        onTap: _testing ? null : _test,
      ),
      if (_testResult != null) ...[
        const SizedBox(height: 8),
        SelectableText(_testResult!,
            style: TextStyle(color: p.muted, fontSize: 12, height: 1.35)),
      ],
    ];
  }
}
