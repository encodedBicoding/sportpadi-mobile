import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/features/auth/auth_controller.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/format/zone_rules.dart' show zoneRulesCover;

/// The signed-in player's time-zone setting, as the server holds it.
class TimezonePref {
  const TimezonePref({this.timezone, this.auto = true, this.loaded = false});

  /// The profile's IANA zone. On automatic it tracks the device.
  final String? timezone;

  /// True: follow the device. False: [timezone] was picked in Settings.
  final bool auto;

  /// False until the server has answered once this session.
  final bool loaded;

  factory TimezonePref.fromJson(dynamic data) {
    final m = data is Map ? data : const {};
    return TimezonePref(
      timezone: parseStr(m['timezone']),
      auto: m['auto'] is bool ? m['auto'] as bool : true,
      loaded: true,
    );
  }
}

/// Keeps the profile's zone in step with the phone and tells the instant
/// formatters (`instant.dart`) which zone to use. [sync] runs when the
/// signed-in shell mounts (i.e. after sign-in) and whenever the app resumes.
class TimezoneController extends Notifier<TimezonePref> {
  Future<void>? _syncing;

  @override
  TimezonePref build() {
    // A different account (or none): forget the last one's picked zone.
    ref.listen<String?>(
      authControllerProvider.select((s) => s.valueOrNull?.user?.id),
      (prev, next) {
        if (prev != next) {
          setViewerTimezone(null);
          state = const TimezonePref();
        }
      },
    );
    return const TimezonePref();
  }

  static const _path = '/api/mobile/me/timezone';

  void _apply(TimezonePref pref) {
    // Automatic: the device's zone (re-read on every resume) is the truth;
    // picked: the profile's.
    setViewerTimezone(pref.auto ? null : pref.timezone);
    // Always a new object, so watchers repaint even when only the device's
    // zone moved (Notifier compares by identity).
    state = TimezonePref(
        timezone: pref.timezone, auto: pref.auto, loaded: pref.loaded);
  }

  /// Load the setting; on automatic, report the device's zone if the profile
  /// has a different one. Best-effort — offline keeps the last known state.
  Future<void> sync() =>
      _syncing ??= _sync().whenComplete(() => _syncing = null);

  Future<void> _sync() async {
    final device = await refreshDeviceTimezone();
    // The server's current zone rules (at most twice a day — zone_rules.dart),
    // alongside the profile read; in before the repaint below. Never throws.
    final rules = refreshTimeZoneRules();
    try {
      final dio = ref.read(dioProvider);
      var pref = TimezonePref.fromJson((await dio.get(_path)).data);
      if (pref.auto && device != null && pref.timezone != device) {
        final res = await dio.post(
          _path,
          data: {'timezone': device, 'source': 'device'},
        );
        pref = TimezonePref.fromJson(res.data);
      }
      await rules;
      _apply(pref);
    } catch (_) {
      // Re-publish anyway: the device zone may have moved while offline.
      await rules;
      _apply(state);
    }
  }

  /// Settings: show everything in [zone] from now on (automatic off).
  Future<void> pickZone(String zone) async {
    try {
      final res = await ref.read(dioProvider).post(
        _path,
        data: {'timezone': zone, 'source': 'manual'},
      );
      _apply(TimezonePref.fromJson(res.data));
    } catch (e) {
      throw apiError(e, fallback: 'Could not change your time zone.');
    }
    // A picked name the server's last answer didn't have (the picker lists
    // the bundled table's names, some of them stale): ask for it now rather
    // than show the bundled rules for up to 12 hours. Never throws.
    if (!zoneRulesCover(zone) && await refreshTimeZoneRules(force: true)) {
      _apply(state);
    }
  }

  /// Settings: back to following the device.
  Future<void> useDeviceZone() async {
    final device = await refreshDeviceTimezone();
    try {
      final res = await ref.read(dioProvider).post(
        _path,
        data: {'timezone': device ?? 'UTC', 'source': 'auto'},
      );
      _apply(TimezonePref.fromJson(res.data));
    } catch (e) {
      throw apiError(e, fallback: 'Could not change your time zone.');
    }
  }
}

final timezoneControllerProvider =
    NotifierProvider<TimezoneController, TimezonePref>(TimezoneController.new);

/// The zone timestamps are shown in right now ("Africa/Lagos"), or null when
/// unknown. Watch it in a screen that shows timestamps so a change in
/// Settings (or a resume in a new zone) repaints it.
final viewerTimezoneProvider = Provider<String?>((ref) {
  ref.watch(timezoneControllerProvider);
  return viewerTimezone;
});
