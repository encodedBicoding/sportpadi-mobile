import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/location/location_provider.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';
import 'package:sportpadi_mobile/core/network/dio_client.dart';

/// Current conditions for the Home weather card (GET /api/mobile/weather).
/// The server composes the remark from the numbers (packages/api weather.ts)
/// and caches per ~1 km cell, so the app just shows what it's given.
class Weather {
  const Weather({
    required this.condition,
    required this.icon,
    required this.isDay,
    required this.tempC,
    required this.feelsC,
    required this.hiC,
    required this.loC,
    required this.humidity,
    required this.windKph,
    required this.rainChance,
    required this.remark,
    required this.mood,
    required this.attribution,
  });

  final String condition;

  /// sun | moon | cloud | fog | drizzle | rain | snow | storm | partly |
  /// partly_night.
  final String icon;
  final bool isDay;
  final double tempC;
  final double feelsC;
  final double hiC;
  final double loC;
  final int humidity;
  final double windKph;
  final int? rainChance;
  final String remark;

  /// great | hot | warm | mild | cool | cold | wet | stormy | snowy | windy.
  final String mood;
  final String attribution;

  factory Weather.fromJson(Map<String, dynamic> j) => Weather(
        condition: j['condition'] as String? ?? 'Cloudy',
        icon: j['icon'] as String? ?? 'cloud',
        isDay: j['isDay'] != false,
        tempC: (j['tempC'] as num?)?.toDouble() ?? 0,
        feelsC: (j['feelsC'] as num?)?.toDouble() ?? 0,
        hiC: (j['hiC'] as num?)?.toDouble() ?? 0,
        loC: (j['loC'] as num?)?.toDouble() ?? 0,
        humidity: (j['humidity'] as num?)?.toInt() ?? 0,
        windKph: (j['windKph'] as num?)?.toDouble() ?? 0,
        rainChance: (j['rainChance'] as num?)?.toInt(),
        remark: j['remark'] as String? ?? '',
        mood: j['mood'] as String? ?? 'mild',
        attribution: j['attribution'] as String? ?? '',
      );
}

class WeatherRepository {
  WeatherRepository(this._dio);
  final Dio _dio;

  Future<Weather?> now(double lat, double lng) async {
    try {
      final res = await _dio.get('/api/mobile/weather',
          queryParameters: {'lat': lat, 'lng': lng});
      if (res.data is! Map) return null;
      return Weather.fromJson(Map<String, dynamic>.from(res.data as Map));
    } on DioException catch (e) {
      throw apiError(e, fallback: 'Could not load the weather.');
    }
  }
}

final weatherRepositoryProvider =
    Provider<WeatherRepository>((ref) => WeatherRepository(ref.watch(dioProvider)));

/// The weather at the session's location fix; null until there is one. Keyed
/// on a coarse (~1 km) rounding of the fix so a wobbling GPS doesn't refetch.
final weatherProvider = FutureProvider.autoDispose<Weather?>((ref) async {
  final loc = ref.watch(locationProvider.select((s) => s.location));
  if (loc == null) return null;
  final lat = (loc.lat * 100).round() / 100;
  final lng = (loc.lng * 100).round() / 100;
  // Hold the answer for 20 minutes — the server caches for the same span.
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 20), link.close);
  ref.onDispose(timer.cancel);
  return ref.read(weatherRepositoryProvider).now(lat, lng);
});
