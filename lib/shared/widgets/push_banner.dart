import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/push/push_alert.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/shell/notification_target.dart';

/// Renders a push that arrived while the app was open, as a banner over
/// whatever is on screen. Wrapped around the whole app (MaterialApp.builder)
/// so it works on every route, and identical on iOS and Android.
///
/// Tap → opens the notification's destination. Swipe up or wait ~6s → gone.
class PushBannerHost extends ConsumerStatefulWidget {
  const PushBannerHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PushBannerHost> createState() => _PushBannerHostState();
}

class _PushBannerHostState extends ConsumerState<PushBannerHost> {
  Timer? _timer;
  int? _shownId;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    _timer?.cancel();
    _timer = null;
    if (mounted) ref.read(foregroundPushProvider.notifier).state = null;
  }

  void _open(PushAlert alert, BuildContext context) {
    _dismiss();
    // Same rules as a tapped system notification.
    openNotificationTarget(ref, alert.url);
  }

  @override
  Widget build(BuildContext context) {
    final alert = ref.watch(foregroundPushProvider);

    // Start (or restart) the auto-dismiss whenever a new alert appears.
    if (alert != null && alert.id != _shownId) {
      _shownId = alert.id;
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 6), _dismiss);
    } else if (alert == null) {
      _shownId = null;
    }

    return Stack(children: [
      widget.child,
      // Positioned rather than inside the child's tree so it floats above
      // dialogs, sheets and tabs alike.
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, anim) => SlideTransition(
            position: Tween<Offset>(
                    begin: const Offset(0, -1), end: Offset.zero)
                .animate(
                    CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: alert == null
              ? const SizedBox.shrink(key: ValueKey('none'))
              : _Banner(
                  key: ValueKey(alert.id),
                  alert: alert,
                  onTap: () => _open(alert, context),
                  onDismiss: _dismiss,
                ),
        ),
      ),
    ]);
  }
}

class _Banner extends StatelessWidget {
  const _Banner(
      {super.key,
      required this.alert,
      required this.onTap,
      required this.onDismiss});
  final PushAlert alert;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Dismissible(
          key: ValueKey('push-${alert.id}'),
          direction: DismissDirection.up,
          onDismissed: (_) => onDismiss(),
          child: Material(
            color: p.surface,
            elevation: 8,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: p.line),
                ),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: p.accent.withAlpha(36),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.notifications_active_rounded,
                            size: 18, color: p.accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(alert.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: p.ink,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700)),
                              if (alert.body != null && alert.body!.isNotEmpty)
                                Text(alert.body!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: p.muted,
                                        fontSize: 12,
                                        height: 1.35)),
                            ]),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        icon:
                            Icon(Icons.close_rounded, size: 17, color: p.muted),
                        onPressed: onDismiss,
                        tooltip: 'Dismiss',
                      ),
                    ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
