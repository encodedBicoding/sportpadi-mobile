import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sportpadi_mobile/core/push/push_service.dart';
import 'package:sportpadi_mobile/data/auth/auth_models.dart';
import 'package:sportpadi_mobile/data/auth/auth_repository.dart';
import 'package:sportpadi_mobile/data/auth/social_sign_in.dart';
import 'package:sportpadi_mobile/data/profile/profile_repository.dart';
import 'package:sportpadi_mobile/core/i18n/l10n.dart';

/// Holds the global session. Sign-in / sign-up throw on failure so the screen
/// can show the error locally; only a success mutates the global session, which
/// keeps the router redirect stable.
class AuthController extends AsyncNotifier<SessionState> {
  /// A session check that could not REACH the server is asked again, this
  /// long after each failure. The owner's dev server can take longer than
  /// `dio_client.dart`'s 20 s receive budget to compile a cold route, and a
  /// phone that has just woken up has no network for a second or two; both
  /// answer on the second or third ask. Until one of them does, the session
  /// is [SessionState.unknown] — never "signed out".
  static const _recheckDelays = <Duration>[
    Duration(seconds: 2),
    Duration(seconds: 6),
    Duration(seconds: 15),
  ];

  /// Set when the provider is disposed: a re-check still in flight must not
  /// touch `state` after that (the idiom LiveGameController uses).
  bool _closed = false;

  @override
  Future<SessionState> build() async {
    _closed = false;
    ref.onDispose(() {
      _closed = true;
    });
    final first = await _check();
    if (!first.isUnknown) return first;
    // We could not reach the server. Say "don't know" straight away — the
    // router then leaves the user on the page they asked for instead of
    // bouncing them — and keep asking behind them, so a slow route turns
    // into the real session without them doing anything.
    // ignore: discarded_futures
    _recheck();
    return first;
  }

  /// Ask the server once. [SessionState.unknown] when it could not answer the
  /// question, which is NOT the same as answering "no session".
  Future<SessionState> _check() async {
    try {
      // null means the answer really was "no session": no token to ask with,
      // or a hard 401 (AuthRepository.currentUser).
      final user = await ref.read(authRepositoryProvider).currentUser();
      return SessionState(user: user);
    } catch (_) {
      // Everything currentUser() THROWS is a failure to establish the
      // session, never an answer about it — a 401 is the one answer it would
      // have, and that comes back as null above. The transport failures (a
      // receive timeout, a dead network) carry no status at all
      // (`ApiException.statusCode` is null for them, core/network/
      // api_exception.dart); a 5xx or a CDN challenge page carries one but
      // still never said "signed out", so it is just as unknown. Reading any
      // of these as a sign-out was the bug: one slow route signed the owner
      // out of an app that still held a perfectly good token, and the router
      // moved them off the match they had just opened.
      return SessionState.unknown;
    }
  }

  /// Keep asking, while the answer is still "don't know".
  Future<void> _recheck() async {
    for (final wait in _recheckDelays) {
      await Future<void>.delayed(wait);
      if (_closed) return;
      // A sign-in, sign-up or sign-out landed while we waited: that answer is
      // authoritative and ours is stale.
      if (state.valueOrNull?.isUnknown != true) return;
      final next = await _check();
      if (_closed || state.valueOrNull?.isUnknown != true) return;
      if (!next.isUnknown) {
        // AsyncData, never AsyncLoading: the router pins every location to
        // `/` while auth is loading, so going back to loading mid-session
        // would drop the user onto the splash screen.
        state = AsyncData(next);
        return;
      }
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
      throw StateError(l10n.auth_noSignedInEmailTo);
    }
    final user = await ref
        .read(authRepositoryProvider)
        .verifyEmail(email: email, otp: otp);
    if (user != null) state = AsyncData(SessionState(user: user));
  }

  /// The server refused this device's token on a request that carried it
  /// (core/network/auth_interceptor.dart — it is already cleared): the
  /// session is over. Signed out, once — a second 401 in flight finds it so
  /// and does nothing, and with the token gone no request can 401 for that
  /// reason again, so it cannot loop. A session that is already signed out
  /// stays as it is.
  void tokenRejected() {
    final s = state.valueOrNull;
    if (s == null || (!s.isAuthenticated && !s.isUnknown)) return;
    state = const AsyncData(SessionState.unauthenticated);
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
