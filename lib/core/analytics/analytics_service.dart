import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Google Analytics for the app (GA4 via Firebase Analytics) — the mobile
/// twin of the web's gtag.js. Fully guarded like PushService: until Firebase
/// is configured (`flutterfire configure`), every call is a quiet no-op.
/// Once the Firebase project is linked to the GA4 property, screen views and
/// events land beside the web stream's page views.
class AnalyticsService {
  FirebaseAnalytics? _analytics;
  bool _tried = false;
  String? _lastScreen;

  Future<void> init() async {
    if (_tried) return;
    _tried = true;
    try {
      await Firebase.initializeApp();
      _analytics = FirebaseAnalytics.instance;
      await _analytics!.setAnalyticsCollectionEnabled(true);
    } catch (e) {
      // Not configured yet — normal until `flutterfire configure` is run.
      if (kDebugMode) {
        debugPrint('[analytics] Firebase not configured, disabled: $e');
      }
      _analytics = null;
    }
  }

  /// Screen names come from router locations; collapse ids so screens
  /// aggregate ("/groups/:id" instead of one screen per uuid).
  static final _uuidRe = RegExp(
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');

  Future<void> logScreen(String location) async {
    final a = _analytics;
    if (a == null) return;
    var name = location.split('?').first;
    name = name.replaceAll(_uuidRe, ':id');
    if (name.isEmpty) name = '/';
    if (name == _lastScreen) return;
    _lastScreen = name;
    try {
      await a.logScreenView(screenName: name);
    } catch (_) {/* never let analytics break navigation */}
  }

  Future<void> logEvent(String name, [Map<String, Object>? params]) async {
    final a = _analytics;
    if (a == null) return;
    try {
      await a.logEvent(name: name, parameters: params);
    } catch (_) {}
  }
}

final analyticsServiceProvider =
    Provider<AnalyticsService>((ref) => AnalyticsService());
