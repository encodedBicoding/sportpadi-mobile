import 'package:flutter/widgets.dart';

import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/format/zone_rules.dart';

/// Keeps every open screen's times on the newest zone rules.
///
/// The formatters (`instant.dart`, `event_time.dart`) are plain functions read
/// during build, and most event widgets are stateless, so when the server's
/// rules land AFTER a screen was built (a slow first start, or a new tz
/// version) nothing would repaint it: an event page would keep "PST" until
/// the next scroll. When the rules really change (`zoneRulesRevision` — not on
/// a re-fetch of the same answer) — or the PHONE moved zone
/// (`deviceZoneChanges`: every "is this the phone's own zone" answer flips) —
/// everything under this widget is marked to rebuild once. On every resume,
/// signed in or not, it re-reads the phone's zone and asks for fresh rules
/// (at most every 12 hours — zone_rules.dart): the signed-in shell's timezone
/// sync is the only other trigger, and visitors never run it.
class TimeZoneRulesHost extends StatefulWidget {
  const TimeZoneRulesHost({super.key, required this.child});

  final Widget child;

  @override
  State<TimeZoneRulesHost> createState() => _TimeZoneRulesHostState();
}

class _TimeZoneRulesHostState extends State<TimeZoneRulesHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    zoneRulesRevision.addListener(_rulesChanged);
    deviceZoneChanges.addListener(_rulesChanged);
  }

  @override
  void dispose() {
    deviceZoneChanges.removeListener(_rulesChanged);
    zoneRulesRevision.removeListener(_rulesChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ignore: discarded_futures
      _onResume();
    }
  }

  Future<void> _onResume() async {
    // The zone first: the rules request names it (`?zones=`).
    await refreshDeviceTimezone();
    await refreshTimeZoneRules();
  }

  void _rulesChanged() {
    // After the current frame: never mark widgets dirty mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void rebuild(Element e) {
        e.markNeedsBuild();
        e.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
