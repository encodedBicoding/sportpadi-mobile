import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/features/settings/timezone_provider.dart';
import 'package:sportpadi_mobile/shared/format/instant.dart';
import 'package:sportpadi_mobile/shared/widgets/sp_sheet.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// What the picker returns for "Use device time zone".
const _automatic = '\u0000automatic';

/// Settings → Time zone: "Automatic · Africa/Lagos" (follows the phone) or a
/// zone the player picked. Tapping opens the picker. Only the device's zone
/// is read — no location permission.
class TimezoneCard extends ConsumerStatefulWidget {
  const TimezoneCard({super.key});

  @override
  ConsumerState<TimezoneCard> createState() => _TimezoneCardState();
}

class _TimezoneCardState extends ConsumerState<TimezoneCard> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Normally loaded when the shell mounted; make sure, without blocking.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(timezoneControllerProvider).loaded) {
        ref.read(timezoneControllerProvider.notifier).sync();
      }
    });
  }

  Future<void> _open() async {
    final pref = ref.read(timezoneControllerProvider);
    final choice = await showSpSheet<String>(
      context,
      scrollable: false,
      padding: EdgeInsets.zero,
      builder: (_) => _TimezonePickerSheet(
        current: pref.auto ? null : pref.timezone,
        device: deviceTimezone,
      ),
    );
    if (choice == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final c = ref.read(timezoneControllerProvider.notifier);
      if (choice == _automatic) {
        await c.useDeviceZone();
      } else {
        await c.pickZone(choice);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pref = ref.watch(timezoneControllerProvider);
    final device = deviceTimezone;
    final picked = pref.auto ? null : pref.timezone;
    final deviceName =
        device != null ? timezoneDisplayName(device) : "your phone's zone";
    final title = picked != null
        ? timezoneDisplayName(picked)
        : 'Automatic · $deviceName';
    final offset = zoneOffsetLabel(picked ?? device);
    return GlassCard(
      onTap: _busy ? null : _open,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const SpIconTile(Icons.public_rounded, size: 38, iconSize: 19),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
              if (offset != null) ...[
                const SizedBox(height: 2),
                Text(offset, style: TextStyle(color: p.muted, fontSize: 11.5)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          if (_busy)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.chevron_right_rounded, color: p.muted),
        ]),
        const SizedBox(height: 10),
        Text(
          'Messages, discussions, announcements and notifications show in '
          "this zone. Events show in the venue's time, with yours alongside.",
          style: TextStyle(color: p.muted, fontSize: 12, height: 1.4),
        ),
      ]),
    );
  }
}

class _TimezonePickerSheet extends StatefulWidget {
  const _TimezonePickerSheet({required this.current, required this.device});

  /// The picked zone, or null when on automatic.
  final String? current;
  final String? device;

  @override
  State<_TimezonePickerSheet> createState() => _TimezonePickerSheetState();
}

class _TimezonePickerSheetState extends State<_TimezonePickerSheet> {
  final _search = TextEditingController();
  final List<String> _all = allTimezones();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static String _norm(String s) => s.toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final device = widget.device;
    final auto = widget.current == null;
    final list = _q.isEmpty
        ? _all
        : _all.where((z) => _norm(z).contains(_q)).toList();
    return Column(children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: SpSheetHeader(
          icon: Icons.public_rounded,
          title: 'Time zone',
          subtitle: 'For messages, discussions, announcements and '
              'notifications. No location needed.',
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: ListTile(
          leading: Icon(Icons.smartphone_rounded,
              color: auto ? p.greenText : p.muted),
          title: Text(
            device != null
                ? 'Use device time zone (${timezoneDisplayName(device)})'
                : 'Use device time zone',
            style: TextStyle(
                color: p.ink,
                fontWeight: auto ? FontWeight.w700 : FontWeight.w500),
          ),
          subtitle: Text('Follows your phone, including when you travel.',
              style: TextStyle(color: p.muted, fontSize: 12)),
          trailing:
              auto ? Icon(Icons.check_rounded, color: p.greenText) : null,
          onTap: () => Navigator.of(context).pop(_automatic),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _q = _norm(v.trim())),
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search time zones (e.g. London)',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
      ),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                      _all.isEmpty
                          ? "Time zones couldn't be loaded on this phone."
                          : 'No time zone matches.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.muted)),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final z = list[i];
                  final on = z == widget.current;
                  final offset = zoneOffsetLabel(z);
                  return ListTile(
                    dense: true,
                    title: Text(timezoneDisplayName(z),
                        style: TextStyle(
                            color: p.ink,
                            fontSize: 14,
                            fontWeight:
                                on ? FontWeight.w700 : FontWeight.w500)),
                    subtitle: offset == null
                        ? null
                        : Text(offset,
                            style: TextStyle(color: p.muted, fontSize: 11.5)),
                    trailing: on
                        ? Icon(Icons.check_rounded, color: p.greenText)
                        : null,
                    onTap: () => Navigator.of(context).pop(z),
                  );
                },
              ),
      ),
    ]);
  }
}
