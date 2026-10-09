import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:sportpadi_mobile/core/env/sso_config.dart';
import 'package:sportpadi_mobile/core/network/api_exception.dart';

/// What a native sign-in button hands back: the provider's ID token (the
/// server verifies it and mints our session), the raw nonce the token was
/// bound to (Apple), and — first Apple sign-in only — the name Apple shares
/// exactly once, which we save to the profile ourselves.
class SocialCredential {
  const SocialCredential({
    required this.provider,
    required this.idToken,
    this.nonce,
    this.accessToken,
    this.givenName,
    this.familyName,
  });

  final String provider; // 'google' | 'apple'
  final String idToken;
  final String? nonce;
  final String? accessToken;
  final String? givenName;
  final String? familyName;

  String? get fullName {
    final n = [givenName, familyName]
        .where((s) => s != null && s.trim().isNotEmpty)
        .map((s) => s!.trim())
        .join(' ');
    return n.isEmpty ? null : n;
  }
}

/// Thrown when the user dismissed the provider's sheet — not an error to
/// show, just nothing to do.
class SocialSignInCancelled implements Exception {
  const SocialSignInCancelled();
}

/// Drives the native Google / Apple sheets and returns a [SocialCredential].
/// No network to our server here — [AuthRepository] does that.
class SocialSignIn {
  bool _googleReady = false;

  Future<void> _ensureGoogle() async {
    if (_googleReady) return;
    if (!SsoConfig.googleEnabled) {
      throw ApiException(
          'Google sign-in is not set up in this build (GOOGLE_SERVER_CLIENT_ID).');
    }
    await GoogleSignIn.instance.initialize(
      serverClientId: SsoConfig.googleServerClientId,
      clientId: SsoConfig.googleIosClientId.isEmpty
          ? null
          : SsoConfig.googleIosClientId,
    );
    _googleReady = true;
  }

  Future<SocialCredential> google() async {
    await _ensureGoogle();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      // Always leave a trace: a misconfigured signing key looks exactly like
      // a dismissed sheet from the outside, and this is the only clue.
      debugPrint('[google sign-in] ${e.code.name}: ${e.description}');
      if (e.code == GoogleSignInExceptionCode.canceled &&
          !_looksLikeNoCredential(e)) {
        throw const SocialSignInCancelled();
      }
      throw ApiException(_googleMessage(e));
    }
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw ApiException(
          "Google didn't return a sign-in token. Check the build's client ids.");
    }
    // No name needed: Google's token carries it and the server reads it.
    return SocialCredential(provider: 'google', idToken: idToken);
  }

  /// Best-effort: drop the cached Google account so the chooser appears next
  /// time (and a shared device doesn't silently reuse the last account).
  Future<void> googleSignOut() async {
    if (!_googleReady) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {/* nothing to do */}
  }

  Future<SocialCredential> apple() async {
    if (!SsoConfig.appleEnabled) {
      throw ApiException('Sign in with Apple is only available on iOS.');
    }
    final rawNonce = _randomNonce();
    final AuthorizationCredentialAppleID cred;
    try {
      cred = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        // Apple binds the token to the HASH; the server gets the raw nonce
        // and checks sha256(raw) == token.nonce.
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled ||
          e.code == AuthorizationErrorCode.unknown) {
        // `unknown` is what iOS reports when the sheet is dismissed before
        // Apple answers (and when the simulator has no Apple ID signed in).
        throw const SocialSignInCancelled();
      }
      throw ApiException('Apple sign-in failed (${e.code.name}).');
    }
    final idToken = cred.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw ApiException("Apple didn't return a sign-in token.");
    }
    return SocialCredential(
      provider: 'apple',
      idToken: idToken,
      nonce: rawNonce,
      accessToken: cred.authorizationCode,
      givenName: cred.givenName,
      familyName: cred.familyName,
    );
  }

  static String _randomNonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final r = Random.secure();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)])
        .join();
  }

  /// Credential Manager reports "no credentials" both when the device has
  /// no Google account AND when this install's signing certificate (SHA-1)
  /// isn't registered on an Android OAuth client — a Play Store install is
  /// signed by Play's key, not the upload key. Either way, silence helps
  /// nobody, so it is not treated as a cancel.
  static bool _looksLikeNoCredential(GoogleSignInException e) {
    final d = (e.description ?? '').toLowerCase();
    return d.contains('no credential') ||
        d.contains('nocredential') ||
        d.contains('no accounts');
  }

  static String _googleMessage(GoogleSignInException e) {
    if (e.code == GoogleSignInExceptionCode.canceled &&
        _looksLikeNoCredential(e)) {
      return 'No Google account could be used on this device. If you do have '
          "one, this build's signing key isn't registered for Google "
          'sign-in yet.';
    }
    switch (e.code) {
      case GoogleSignInExceptionCode.clientConfigurationError:
        return 'Google sign-in is misconfigured for this build (client ids / SHA-1).';
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google Play services are missing or out of date on this device.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return "Google sign-in isn't available right now. Try again in a moment.";
      case GoogleSignInExceptionCode.unknownError:
        // "[28444] Developer console is not set up correctly" lands here on
        // Android when the signing SHA-1 is missing from the OAuth client.
        final d = e.description ?? '';
        return d.contains('28444') || d.toLowerCase().contains('developer console')
            ? "Google sign-in isn't set up for this build's signing key yet "
                '(Google Cloud: Android OAuth client SHA-1).'
            : (d.isEmpty ? 'Google sign-in failed. Please try again.' : d);
      default:
        return e.description ?? 'Google sign-in failed. Please try again.';
    }
  }
}

final socialSignInProvider = Provider<SocialSignIn>((_) => SocialSignIn());
