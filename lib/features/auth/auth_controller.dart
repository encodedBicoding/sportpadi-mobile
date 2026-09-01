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

  Future<void> signOut() async {
    // Forget this device's push token before the session dies (best-effort).
    await ref.read(pushServiceProvider).unregister();
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncData(SessionState.unauthenticated);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, SessionState>(AuthController.new);
