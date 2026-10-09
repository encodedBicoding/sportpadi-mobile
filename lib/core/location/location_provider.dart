import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// The user's location for event recommendations (web useLocation twin).
class UserLocation {
  const UserLocation(
      {required this.lat, required this.lng, this.label = 'you'});
  final double lat;
  final double lng;
  final String label;
}

class LocationState {
  const LocationState({
    this.location,
    this.radiusMiles = 25,
    this.loading = false,
    this.denied = false,
    this.error,
  });
  final UserLocation? location;
  final int radiusMiles;
  final bool loading;

  /// Permission permanently denied — surface the "enable in settings" hint.
  final bool denied;
  final String? error;

  LocationState copyWith({
    UserLocation? location,
    bool clearLocation = false,
    int? radiusMiles,
    bool? loading,
    bool? denied,
    String? error,
    bool clearError = false,
  }) =>
      LocationState(
        location: clearLocation ? null : (location ?? this.location),
        radiusMiles: radiusMiles ?? this.radiusMiles,
        loading: loading ?? this.loading,
        denied: denied ?? this.denied,
        error: clearError ? null : (error ?? this.error),
      );
}

/// Kept alive for the whole session so the fix persists across tabs.
class LocationController extends Notifier<LocationState> {
  @override
  LocationState build() => const LocationState();

  void setRadius(int miles) {
    state = state.copyWith(radiusMiles: miles.clamp(1, 500));
  }

  void clear() => state = state.copyWith(clearLocation: true, clearError: true);

  /// Read the position ONLY if the OS permission is already granted — never
  /// shows a prompt. For surfaces that are nice-to-have with a fix (the Home
  /// weather card) rather than built around one (Discover). Returns whether
  /// permission was already there.
  Future<bool> ensureIfPermitted() async {
    if (state.location != null) return true;
    if (state.loading) return false;
    try {
      final perm = await Geolocator.checkPermission();
      final granted = perm == LocationPermission.whileInUse ||
          perm == LocationPermission.always;
      if (!granted) return false;
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      await request();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Ask for permission and read the device position. Location is required
  /// for recommendations, so this is called automatically on Discover.
  Future<void> request() async {
    if (state.loading) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        state = state.copyWith(
            loading: false,
            error: 'Turn on location services to see events near you.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        state = state.copyWith(
          loading: false,
          denied: perm == LocationPermission.deniedForever,
          error: 'Location permission is needed to recommend events near you.',
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low),
      );
      state = state.copyWith(
        location: UserLocation(
            lat: pos.latitude, lng: pos.longitude, label: 'your location'),
        loading: false,
        denied: false,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
          loading: false, error: 'Could not read your location.');
    }
  }
}

final locationProvider =
    NotifierProvider<LocationController, LocationState>(LocationController.new);
