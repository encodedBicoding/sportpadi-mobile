import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/location/location_provider.dart';
import 'package:sportpadi_mobile/core/theme/app_colors.dart';
import 'package:sportpadi_mobile/data/weather/weather_repository.dart';
import 'package:sportpadi_mobile/shared/widgets/ui.dart';

/// Home weather card (signed-in, app only). Shown once the session has a
/// location fix: current temperature and condition, today's range, and the
/// server's one-line remark ("It's warm outside — don't forget to stay
/// hydrated"). Nothing at all without a fix or while loading, so Home never
/// shows an empty weather box.
class WeatherCard extends ConsumerStatefulWidget {
  const WeatherCard({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsets padding;

  @override
  ConsumerState<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends ConsumerState<WeatherCard> {
  /// Permission already granted earlier (Discover, or a past session) but
  /// no fix yet this session → read it silently. Never prompts from Home.
  bool _checked = false;
  bool _permitted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensure());
  }

  Future<void> _ensure() async {
    final ok = await ref.read(locationProvider.notifier).ensureIfPermitted();
    if (mounted) {
      setState(() {
        _checked = true;
        _permitted = ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.padding;
    final locState = ref.watch(locationProvider);
    final loc = locState.location;
    final p = context.palette;

    if (loc == null) {
      // No fix and no permission: one quiet row that offers it. Nothing
      // while we're still checking, nothing if it's permanently refused
      // (Discover explains that one properly).
      if (!_checked || _permitted || locState.denied || locState.loading) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: padding,
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          onTap: () async {
            await ref.read(locationProvider.notifier).request();
            if (mounted) setState(() => _permitted = true);
          },
          child: Row(children: [
            SpIconTile(Icons.wb_sunny_outlined,
                bg: p.accentTint, fg: p.greenText, size: 36, iconSize: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text("See today's weather for your games",
                  style: TextStyle(
                      color: p.ink,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
            ),
            Text('Allow location',
                style: TextStyle(
                    color: p.greenText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ]),
        ),
      );
    }

    final w = ref.watch(weatherProvider).valueOrNull;
    if (w == null) return const SizedBox.shrink();

    final f = _useFahrenheit(context);
    String deg(double c) => f ? '${(c * 9 / 5 + 32).round()}°' : '${c.round()}°';
    final unit = f ? 'F' : 'C';
    final (bg, fg) = _tint(p, w.mood);

    return Padding(
      padding: padding,
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(15)),
              child: Icon(_iconFor(w.icon), color: fg, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${deg(w.tempC)}$unit',
                          style: TextStyle(
                              color: p.ink,
                              fontSize: 22,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(w.condition,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: p.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                    const SizedBox(height: 3),
                    Text(
                      [
                        'H ${deg(w.hiC)} · L ${deg(w.loC)}',
                        if ((w.feelsC - w.tempC).abs() >= 2)
                          'feels ${deg(w.feelsC)}',
                        if (w.rainChance != null && w.rainChance! >= 20)
                          'rain ${w.rainChance}%',
                        if (w.windKph >= 25) 'wind ${w.windKph.round()} km/h',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ]),
            ),
          ]),
          if (w.remark.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(14)),
              child: Text(w.remark,
                  style: TextStyle(
                      color: fg,
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600)),
            ),
          ],
          if (w.attribution.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(w.attribution,
                style: TextStyle(color: p.muted, fontSize: 9.5)),
          ],
        ]),
      ),
    );
  }

  /// °F where that's what people read (US and the few others); °C elsewhere.
  static bool _useFahrenheit(BuildContext context) {
    final cc = Localizations.maybeLocaleOf(context)?.countryCode ?? '';
    return cc == 'US' || cc == 'LR' || cc == 'MM';
  }

  static IconData _iconFor(String icon) => switch (icon) {
        'sun' => Icons.wb_sunny_rounded,
        'moon' => Icons.nightlight_round,
        'partly' => Icons.wb_cloudy_rounded,
        'partly_night' => Icons.nights_stay_rounded,
        'cloud' => Icons.cloud_rounded,
        'fog' => Icons.foggy,
        'drizzle' => Icons.grain_rounded,
        'rain' => Icons.umbrella_rounded,
        'snow' => Icons.ac_unit_rounded,
        'storm' => Icons.thunderstorm_rounded,
        _ => Icons.cloud_rounded,
      };

  /// Card tint by the server's mood: warm tones for heat, blue-ish for wet
  /// and cold, the brand green when it's simply a good day.
  static (Color, Color) _tint(AppPalette p, String mood) => switch (mood) {
        'hot' || 'warm' => (p.orangeTint, p.orangeInk),
        'wet' || 'stormy' || 'snowy' || 'cold' || 'cool' || 'windy' => (
            p.surface2,
            p.ink
          ),
        _ => (p.accentTint, p.greenText),
      };
}
