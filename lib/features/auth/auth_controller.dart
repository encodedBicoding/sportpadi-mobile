import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/push/push_service.dart';
import 'package:sportpadi_mobile/data/auth/auth_models.dart';
import 'package:sportpadi_mobile/data/auth/auth_repository.dart';

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
    state = const AsyncData(SessionState.unauthenticated);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, SessionState>(AuthController.new);
