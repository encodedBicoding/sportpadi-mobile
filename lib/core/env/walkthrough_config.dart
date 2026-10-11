/// Where the intent walkthrough clips (walkthrough-<intent>.mp4) are served
/// from — the media host by default (same bucket the website's feature
/// pages use), overridable per build:
///
///   flutter build ... --dart-define=WALKTHROUGH_BASE_URL=https://…
class WalkthroughConfig {
  static const _define = String.fromEnvironment('WALKTHROUGH_BASE_URL');
  static const defaultBase =
      'https://assets.sportpadi.com/walkthroughs';

  /// Base URL without a trailing slash.
  static String get base {
    final v = _define.trim().replaceAll(RegExp(r'/+$'), '');
    return v.isNotEmpty ? v : defaultBase;
  }
}
