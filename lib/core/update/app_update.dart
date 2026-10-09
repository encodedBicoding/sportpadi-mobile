import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart'
    show kDebugMode, debugPrint, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:sportpadi_mobile/core/network/dio_client.dart';
import 'package:sportpadi_mobile/core/push/push_service.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/shared/format/parse.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/*
 * App version tracking (docs/design/2026-redesign.md row 76).
 *
 * Once per session — the first frame of a cold start, and coming back after
 * 30+ minutes away — the app asks the server whether it's up to date
 * (GET /api/mobile/app-version; the owner sets the latest and minimum
 * versions in the console). That call also reports this install's version.
 *
 *   required  → a full-screen "Time to update" over everything.
 *   available → a dismissible card above the dock. On Android, "Update"
 *               hands to Google Play's in-app update: it downloads in the
 *               background while the app stays usable, then "Restart" installs
 *               it. iOS can't update itself — the button opens the App Store.
 *               "Not now" hides it for that version for a day.
 *
 * Errors never block anyone: no answer = no prompt.
 */

enum UpdateStatus { current, available, required }

class AppUpdateCheck {
  const AppUpdateCheck({
    required this.status,
    this.latestVersion,
    this.minVersion,
    this.storeUrl,
    this.notes,
  });
  final UpdateStatus status;
  final String? latestVersion;
  final String? minVersion;
  final String? storeUrl;
  final String? notes;

  factory AppUpdateCheck.fromJson(Map<String, dynamic> j) => AppUpdateCheck(
        status: switch (j['status']) {
          'required' => UpdateStatus.required,
          'available' => UpdateStatus.available,
          _ => UpdateStatus.current,
        },
        latestVersion: parseStr(j['latestVersion']),
        minVersion: parseStr(j['minVersion']),
        storeUrl: parseStr(j['storeUrl']),
        notes: parseStr(j['notes']),
      );
}

class AppUpdateRepository {
  AppUpdateRepository(this._dio, this._installId);
  final Dio _dio;
  final Future<String?> Function() _installId;

  static bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// Android without a console link: this app's own Play listing.
  static Future<String?> playListing() async {
    try {
      final id = (await PackageInfo.fromPlatform()).packageName;
      return 'https://play.google.com/store/apps/details?id=$id';
    } catch (_) {
      return null;
    }
  }

  /// iOS without a console link: this app's own App Store listing (the
  /// region-less form opens the viewer's own storefront).
  static const appStoreListing = 'https://apps.apple.com/app/id6808458151';

  /// The store page for this device — console override, else the listing.
  static Future<String?> storeUrl(String? fromServer) async {
    if (fromServer != null && fromServer.isNotEmpty) return fromServer;
    return isAndroid ? playListing() : appStoreListing;
  }

  /// "Update in Google Play" / "Update in the App Store".
  static String get storeName => isAndroid ? 'Google Play' : 'the App Store';

  /// Null when it couldn't ask (offline, server down) — never a prompt then.
  Future<AppUpdateCheck?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      // iOS: "Version 17.5 (Build …)". Android's is the kernel string, which
      // says nothing useful — skipped.
      String? os;
      if (!isAndroid) {
        try {
          final v = Platform.operatingSystemVersion;
          os = v.length > 64 ? v.substring(0, 64) : v;
        } catch (_) {}
      }
      final install = await _installId();
      final res = await _dio.get('/api/mobile/app-version', queryParameters: {
        'platform': isAndroid ? 'android' : 'ios',
        'v': info.version,
        if (info.buildNumber.isNotEmpty) 'build': info.buildNumber,
        if (install != null) 'install': install,
        if (os != null) 'os': os,
      });
      if (res.data is! Map) return null;
      return AppUpdateCheck.fromJson(Map<String, dynamic>.from(res.data as Map));
    } catch (e) {
      if (kDebugMode) debugPrint('[update] check failed: $e');
      return null;
    }
  }
}

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>((ref) {
  final push = ref.watch(pushServiceProvider);
  return AppUpdateRepository(ref.watch(dioProvider), () async {
    try {
      return await push.deviceId();
    } catch (_) {
      return null;
    }
  });
});

/// Wraps the whole app (app.dart builder) and draws the update prompts over
/// it. Lives above the Navigator, so it paints its own overlay rather than
/// pushing routes.
class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({super.key, required this.child});
  final Widget child;

  /// True while a prompt is on screen — pop-up messages wait their turn.
  static bool showing = false;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

enum _Android { idle, downloading, downloaded }

class _AppUpdateGateState extends ConsumerState<AppUpdateGate>
    with WidgetsBindingObserver {
  static const _resumeAfter = Duration(minutes: 30);
  static const _snoozeFor = Duration(hours: 24);
  static const _kSnooze = 'sp_update_snooze'; // "<version>|<epoch ms>"
  static const _storage = FlutterSecureStorage();

  AppUpdateCheck? _check;
  bool _hidden = false; // "Not now" this session
  _Android _android = _Android.idle;
  DateTime? _awaySince;
  bool _checking = false;
  bool _busy = false; // an Update tap in progress
  StreamSubscription<InstallStatus>? _installSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _installSub?.cancel();
    AppUpdateGate.showing = false;
    super.dispose();
  }

  /// Android back while the required screen is up: swallow it, so routes
  /// hidden underneath don't pop. (This observer registers before the
  /// Router's, so it's asked first.)
  @override
  Future<bool> didPopRoute() async =>
      _check?.status == UpdateStatus.required;

  /// Google Play's download progress for a flexible update (Android). Started
  /// once, on the first Update tap; drives the card's "Downloading…" /
  /// "Restart" states and drops back if the download fails or is cancelled.
  void _listenToPlay() {
    if (_installSub != null) return;
    try {
      _installSub = InAppUpdate.installUpdateListener.listen((s) {
        if (!mounted) return;
        final next = switch (s) {
          InstallStatus.pending || InstallStatus.downloading =>
            _Android.downloading,
          InstallStatus.downloaded => _Android.downloaded,
          InstallStatus.failed || InstallStatus.canceled => _Android.idle,
          _ => _android,
        };
        if (next != _android) {
          setState(() {
            _android = next;
            if (next == _Android.downloaded) _hidden = false;
          });
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _awaySince ??= DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      final away = _awaySince;
      _awaySince = null;
      // A new session after a long while — or still blocked (they may have
      // just updated in the store and come back).
      if ((away != null && DateTime.now().difference(away) >= _resumeAfter) ||
          _check?.status == UpdateStatus.required) {
        _run();
      }
    }
  }

  Future<void> _run() async {
    if (_checking) return;
    _checking = true;
    try {
      final c = await ref.read(appUpdateRepositoryProvider).check();
      if (!mounted || c == null) return;
      var hidden = false;
      if (c.status == UpdateStatus.available) {
        hidden = await _snoozed(c.latestVersion);
      }
      // A Play download finished earlier but wasn't installed yet.
      var android = _android;
      if (AppUpdateRepository.isAndroid && c.status != UpdateStatus.current) {
        try {
          final info = await InAppUpdate.checkForUpdate();
          if (info.installStatus == InstallStatus.downloaded) {
            android = _Android.downloaded;
            hidden = false;
          } else if (info.installStatus == InstallStatus.downloading ||
              info.installStatus == InstallStatus.pending) {
            android = _Android.downloading;
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _check = c;
        _hidden = hidden;
        _android = android;
      });
    } finally {
      _checking = false;
    }
  }

  Future<bool> _snoozed(String? version) async {
    if (version == null) return false;
    try {
      final raw = await _storage.read(key: _kSnooze);
      if (raw == null) return false;
      final parts = raw.split('|');
      if (parts.length != 2 || parts[0] != version) return false;
      final at = DateTime.fromMillisecondsSinceEpoch(int.tryParse(parts[1]) ?? 0);
      return DateTime.now().difference(at) < _snoozeFor;
    } catch (_) {
      return false;
    }
  }

  Future<void> _notNow() async {
    final v = _check?.latestVersion;
    setState(() => _hidden = true);
    if (v == null) return;
    try {
      await _storage.write(
          key: _kSnooze, value: '$v|${DateTime.now().millisecondsSinceEpoch}');
    } catch (_) {}
  }

  Future<void> _openStore() async {
    final url = await AppUpdateRepository.storeUrl(_check?.storeUrl);
    if (url == null) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// "Update": Android tries Google Play's in-app update (background download
  /// for the optional one, Play's full-screen flow for a required one); when
  /// Play can't (not installed from Play, rollout hasn't reached this phone),
  /// and on iOS, the store page opens instead.
  Future<void> _update() async {
    if (_busy) return; // a double tap must not start two Play flows
    _busy = true;
    try {
      await _doUpdate();
    } finally {
      _busy = false;
    }
  }

  Future<void> _doUpdate() async {
    final required = _check?.status == UpdateStatus.required;
    if (AppUpdateRepository.isAndroid) {
      if (_android == _Android.downloaded) {
        try {
          // Installs and restarts the app (the future never returns).
          await InAppUpdate.completeFlexibleUpdate();
          return;
        } catch (_) {}
      }
      AppUpdateInfo? info;
      try {
        info = await InAppUpdate.checkForUpdate();
      } catch (e) {
        if (kDebugMode) debugPrint('[update] Play in-app update: $e');
      }
      if (info != null &&
          info.updateAvailability == UpdateAvailability.updateAvailable) {
        if (required && info.immediateUpdateAllowed) {
          try {
            final r = await InAppUpdate.performImmediateUpdate();
            // Done, or they backed out of Play's screen — ours still blocks.
            if (r != AppUpdateResult.inAppUpdateFailed) return;
          } catch (_) {}
        } else if (!required && info.flexibleUpdateAllowed) {
          _listenToPlay();
          if (mounted) setState(() => _android = _Android.downloading);
          try {
            // Resolves once the download has finished — or declined/failed.
            final r = await InAppUpdate.startFlexibleUpdate();
            if (!mounted) return;
            if (r == AppUpdateResult.success) {
              setState(() {
                _android = _Android.downloaded;
                _hidden = false;
              });
            } else {
              setState(() => _android = _Android.idle);
              if (r == AppUpdateResult.userDeniedUpdate) {
                await _notNow();
                return;
              }
              // Play's flow failed to start: the store page is the sure way.
              await _openStore();
            }
          } catch (_) {
            // Failed mid-download: back to the plain card, no surprise store.
            if (mounted) setState(() => _android = _Android.idle);
          }
          return;
        }
      }
    }
    await _openStore();
  }

  @override
  Widget build(BuildContext context) {
    final c = _check;
    final required = c?.status == UpdateStatus.required;
    final card = !required &&
        !_hidden &&
        (c?.status == UpdateStatus.available ||
            _android == _Android.downloaded);
    AppUpdateGate.showing = required || card;
    if (required) FocusManager.instance.primaryFocus?.unfocus();
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      if (required)
        Positioned.fill(
          child: _RequiredScreen(
            check: c!,
            onUpdate: _update,
          ),
        )
      else if (card)
        Positioned(
          left: 12,
          right: 12,
          // Just above the dock (6 + 64 + 10 tall).
          bottom: MediaQuery.paddingOf(context).bottom + 92,
          child: _UpdateCard(
            check: c,
            android: _android,
            onUpdate: _update,
            onLater: _notNow,
          ),
        ),
    ]);
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.check,
    required this.android,
    required this.onUpdate,
    required this.onLater,
  });
  final AppUpdateCheck? check;
  final _Android android;
  final VoidCallback onUpdate;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final v = check?.latestVersion;
    final (String title, String body) = switch (android) {
      _Android.downloading => (
          'Downloading the update…',
          'Keep using SportPadi — we’ll let you know when it’s ready.'
        ),
      _Android.downloaded => (
          'Update ready',
          'Restart SportPadi to finish installing${v != null ? ' version $v' : ''}.'
        ),
      _Android.idle => (
          'A new version of SportPadi is here',
          [
            if (v != null) 'Version $v',
            if (check?.notes != null) check!.notes!,
          ].join(' · ')
        ),
    };
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        decoration: BoxDecoration(
          color: p.hero,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [
            BoxShadow(
                color: Color(0x330E1411), blurRadius: 24, offset: Offset(0, 8)),
          ],
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: p.accent, borderRadius: BorderRadius.circular(12)),
            child: android == _Android.downloading
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.system_update_rounded,
                    color: Colors.white, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: p.onHero,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800)),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: p.heroMuted, fontSize: 12.5, height: 1.35)),
                  ],
                  const SizedBox(height: 8),
                  Row(children: [
                    TextButton(
                      onPressed: onLater,
                      style: TextButton.styleFrom(
                          foregroundColor: p.heroMuted,
                          visualDensity: VisualDensity.compact),
                      child: Text(
                          android == _Android.downloading ? 'Hide' : 'Not now'),
                    ),
                    const Spacer(),
                    if (android != _Android.downloading)
                      FilledButton.icon(
                        onPressed: onUpdate,
                        style: FilledButton.styleFrom(
                            backgroundColor: p.accentDeep,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            shape: const StadiumBorder()),
                        icon: Icon(
                            android == _Android.downloaded
                                ? Icons.restart_alt_rounded
                                : Icons.download_rounded,
                            size: 16),
                        label: Text(android == _Android.downloaded
                            ? 'Restart'
                            : 'Update in ${AppUpdateRepository.storeName}'),
                      ),
                  ]),
                ]),
          ),
        ]),
      ),
    );
  }
}

class _RequiredScreen extends StatelessWidget {
  const _RequiredScreen({required this.check, required this.onUpdate});
  final AppUpdateCheck check;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final v = check.latestVersion ?? check.minVersion;
    return Material(
      color: p.bg,
      child: SafeArea(
        child: LayoutBuilder(
          // Scrolls when long notes or large text don't fit.
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 48),
              child: IntrinsicHeight(
                child: Column(children: [
            const Spacer(),
            SpIconTile(Icons.system_update_rounded,
                size: 72, iconSize: 34, bg: p.accentTint, fg: p.greenText),
            const SizedBox(height: 20),
            Text('Time to update',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: p.ink, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
                'This version of SportPadi is no longer supported. '
                'Update${v != null ? ' to version $v' : ''} to keep using the app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 14.5, height: 1.45)),
            if (check.notes != null) ...[
              const SizedBox(height: 16),
              GlassCard(
                child: Text(check.notes!,
                    style: TextStyle(color: p.ink, fontSize: 13.5, height: 1.45)),
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: SpButton(
                label: 'Update in ${AppUpdateRepository.storeName}',
                icon: Icons.download_rounded,
                expand: true,
                tone: SpButtonTone.brand,
                onTap: onUpdate,
              ),
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
