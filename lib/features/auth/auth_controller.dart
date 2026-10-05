import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/push/push_service.dart';
import 'package:sportpadi_mobile/data/auth/auth_models.dart';
import 'package:sportpadi_mobile/data/auth/auth_repository.dart';
import 'package:sportpadi_mobile/data/auth/social_sign_in.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';

/// Holds the global session. Sign-in / sign-up throw on failure so the screen
/// can show the error locally; only a success mutates the global session, which
/// keeps the router redirect stable.
class AuthController extends AsyncNotifier<SessionState> {
  @override
  Future<SessionState> build() async {
    try {
      final user = await ref.read(authRepositoryProvider).currentUser();
      return SessionState(user: user);
    } catch (_) {
      return SessionState.unauthenticated;
    }
  }

  Future<void> signIn(String email, String password) async {
    final user = await ref
        .read(authRepositoryProvider)
        .signIn(email: email, password: password);
    state = AsyncData(SessionState(user: user));
  }

  Future<void> signUp(String name, String email, String password) async {
    final user = await ref
        .read(authRepositoryProvider)
        .signUp(name: name, email: email, password: password);
    state = AsyncData(SessionState(user: user));
  }

  /// Google: native account chooser → ID token → our session.
  /// Throws [SocialSignInCancelled] when the sheet was dismissed.
  Future<void> signInWithGoogle() async {
    final cred = await ref.read(socialSignInProvider).google();
    await _finishSocial(cred);
  }

  /// Apple (iOS): the system sheet → ID token (+ nonce) → our session. The
  /// name Apple shares on the very first sign-in is saved to the profile
  /// here, because the token itself never carries it.
  Future<void> signInWithApple() async {
    final cred = await ref.read(socialSignInProvider).apple();
    await _finishSocial(cred);
  }

  Future<void> _finishSocial(SocialCredential cred) async {
    final repo = ref.read(authRepositoryProvider);
    final user = await repo.signInWithIdToken(
      provider: cred.provider,
      idToken: cred.idToken,
      nonce: cred.nonce,
      accessToken: cred.accessToken,
    );
    state = AsyncData(SessionState(user: user));
    // First Apple sign-in: the account was just made nameless (the server
    // falls back to "New player"); put the shared name on the profile.
    final name = cred.fullName;
    if (name != null && _looksNameless(user)) {
      try {
        await ref
            .read(profileRepositoryProvider)
            .updateMe({'displayName': name});
      } catch (_) {
        /* cosmetic — they can set it in Settings */
      }
    }
  }

  static bool _looksNameless(AuthUser u) {
    final n = u.name.trim();
    return n.isEmpty ||
        n == u.email ||
        n == u.email.split('@').first ||
        n == 'New player';
  }

  /// Re-read the session from the server (after verifying an email, etc.).
  Future<void> refresh() async {
    try {
      final user = await ref.read(authRepositoryProvider).currentUser();
      state = AsyncData(SessionState(user: user));
    } catch (_) {
      /* keep the current session on a transient failure */
    }
  }

  Future<void> sendVerificationCode() async {
    final email = state.value?.user?.email;
    if (email == null || email.isEmpty) return;
    await ref.read(authRepositoryProvider).sendVerificationCode(email);
  }

  /// Confirm the emailed code; on success the session flips to verified and
  /// the router releases the user into the app.
  Future<void> verifyEmail(String otp) async {
    final email = state.value?.user?.email;
    if (email == null || email.isEmpty) {
      throw StateError('No signed-in email to verify.');
    }
    final user = await ref
        .read(authRepositoryProvider)
        .verifyEmail(email: email, otp: otp);
    if (user != null) state = AsyncData(SessionState(user: user));
  }

  Future<void> signOut() async {
    // Forget this device's push token before the session dies (best-effort).
    await ref.read(pushServiceProvider).unregister();
    await ref.read(authRepositoryProvider).signOut();
    await ref.read(socialSignInProvider).googleSignOut();
    state = const AsyncData(SessionState.unauthenticated);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, SessionState>(AuthController.new);
