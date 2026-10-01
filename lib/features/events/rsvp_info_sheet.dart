import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';

/// Shown right after an RSVP: it tells the organiser you're planning to come,
/// but doesn't hold a place — checking in at the venue does. Then why showing
/// up is worth it (the XP for checking in, arriving early, the streak).
class RsvpInfoSheet extends StatefulWidget {
  const RsvpInfoSheet({super.key});

  static const _storage = FlutterSecureStorage();
  static const _key = 'sp_rsvp_info_dismissed';
  static bool? _dismissed;

  /// Show it unless the player asked not to see it again.
  static Future<void> maybeShow(BuildContext context) async {
    _dismissed ??=
        (await _storage.read(key: _key).catchError((_) => null)) == '1';
    if (_dismissed == true || !context.mounted) return;
    await showSpSheet<void>(
      context,
      builder: (_) => const RsvpInfoSheet(),
    );
  }

  @override
  State<RsvpInfoSheet> createState() => _RsvpInfoSheetState();
}

class _RsvpInfoSheetState extends State<RsvpInfoSheet> {
  bool _dontShow = false;

  Future<void> _close() async {
    if (_dontShow) {
      RsvpInfoSheet._dismissed = true;
      try {
        await RsvpInfoSheet._storage.write(key: RsvpInfoSheet._key, value: '1');
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget row(IconData icon, String text, String xp) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                  color: p.accent.withAlpha(26), shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: p.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
                child:
                    Text(text, style: TextStyle(color: p.ink, fontSize: 13.5))),
            Text(xp,
                style: TextStyle(
                    color: p.accent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800)),
          ]),
        );
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SpSheetHeader(
            icon: Icons.event_available_rounded,
            title: "You've RSVP'd",
            subtitle:
                "This lets the organiser know you're planning to come — it doesn't lock in your spot. "
                'Your place is confirmed when you check in at the venue.',
          ),
          const SizedBox(height: 14),
          Text('SHOW UP AND EARN',
              style: TextStyle(
                  color: p.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1)),
          const SizedBox(height: 4),
          row(Icons.auto_awesome_rounded, 'For your RSVP', '+10 XP'),
          row(Icons.qr_code_scanner_rounded, 'Check in at the venue', '+25 XP'),
          row(Icons.timer_outlined, 'Check in 10+ minutes before kick-off',
              '+10 XP'),
          row(Icons.local_fire_department_rounded,
              'Keep your weekly streak going', '🔥'),
          const SizedBox(height: 6),
          Text(
              'RSVP\'d within 24 hours of kick-off? Showing up also earns Last-minute hero.',
              style: TextStyle(color: p.muted, fontSize: 11.5)),
          const SizedBox(height: 10),
          CheckboxListTile(
            value: _dontShow,
            onChanged: (v) => setState(() => _dontShow = v ?? false),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text("Don't show this again",
                style: TextStyle(color: p.muted, fontSize: 12.5)),
          ),
          const SizedBox(height: 4),
          FilledButton(onPressed: _close, child: const Text('Got it')),
        ]);
  }
}
