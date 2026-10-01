import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A push that arrived while the app was OPEN.
///
/// Neither platform shows a system notification for a foreground message —
/// Android never does, and iOS only with `setForegroundNotificationPresentation
/// Options`, which would make the two platforms behave differently. So the app
/// renders its own banner instead: identical on iOS and Android, and tappable
/// straight through to whatever the notification is about.
class PushAlert {
  PushAlert({required this.title, this.body, this.url})
      : id = DateTime.now().microsecondsSinceEpoch;

  final int id;
  final String title;
  final String? body;

  /// Web-shaped destination from the push payload (`data.url`).
  final String? url;
}

/// The banner currently on screen (null = none). Set by PushService's
/// foreground handler; cleared when it's tapped, dismissed or times out.
final foregroundPushProvider = StateProvider<PushAlert?>((_) => null);
