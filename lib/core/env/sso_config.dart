import 'dart:io' show Platform;

/// Sign in with Google / Apple — build-time configuration.
///
/// Google needs ONE id in the app: the **Web application** OAuth client id of
/// the project (the same `GOOGLE_CLIENT_ID` the server verifies against).
/// It is passed as `serverClientId`, so the ID token Google mints carries it
/// as the audience on both platforms. Supply it at build time:
///
///   --dart-define=GOOGLE_SERVER_CLIENT_ID=1234-abc.apps.googleusercontent.com
///
/// or fill in [_googleServerClientIdDefault] below. iOS additionally needs an
/// **iOS** client id (`GIDClientID`) plus its reversed id as a URL scheme in
/// Info.plist — see docs/sso-setup.md. Android needs the signing SHA-1s
/// registered on an **Android** client id in the same project (nothing in
/// the app).
///
/// Apple needs nothing here: the "Sign in with Apple" capability on the app
/// id, and the server's `APPLE_SIGNIN_*` keys.
class SsoConfig {
  SsoConfig._();

  // Paste the Web client id here if you'd rather not pass --dart-define.
  static const _googleServerClientIdDefault = '912400814442-a20qhp3ad9j2odl228go85aeums28099.apps.googleusercontent.com';
  static const _googleIosClientIdDefault = '912400814442-vh4apvldg04oea6sa8gs6k7lasnpsm1m.apps.googleusercontent.com';

  static const googleServerClientId = String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
      defaultValue: _googleServerClientIdDefault);

  /// Optional: overrides Info.plist's GIDClientID on iOS.
  static const googleIosClientId = String.fromEnvironment(
      'GOOGLE_IOS_CLIENT_ID',
      defaultValue: _googleIosClientIdDefault);

  /// Draw the Google button at all? Without a server client id the token
  /// would have the wrong audience and the server would refuse it.
  static bool get googleEnabled => googleServerClientId.isNotEmpty;

  /// Apple's button is iOS-only (Apple's rule covers iOS apps; Android users
  /// have Google + email).
  static bool get appleEnabled => Platform.isIOS;
}
