class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.image,
    this.emailVerified = false,
  });

  final String id;
  final String name;
  final String email;
  final String? image;

  /// Better Auth `user.emailVerified`. Every account must confirm its address
  /// before it can create, join or buy — the server refuses those calls until
  /// it's true, and the router parks the user on /verify-email.
  final bool emailVerified;

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? j['displayName'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        image: (j['image'] ?? j['avatarUrl']) as String?,
        emailVerified: j['emailVerified'] == true,
      );
}

class SessionState {
  const SessionState({this.user, this.unreachable = false});

  final AuthUser? user;

  /// The session could not be CHECKED: the request asking for it never came
  /// back with an answer (a receive timeout, no network, a firewall's HTML
  /// page, a 5xx). None of those says anything about the session, so this is
  /// neither signed in nor signed out — see [isUnknown].
  final bool unreachable;

  bool get isAuthenticated => user != null;

  /// "Don't know": nothing says this device has a session, and nothing says
  /// it hasn't. [isAuthenticated] stays false on purpose — an unchecked
  /// session must never open a screen that shows somebody's data — but the
  /// router reads this as "leave them where they are" instead of as a
  /// sign-out, so a slow server can't move a user off the page they asked
  /// for (core/router/app_router.dart).
  bool get isUnknown => user == null && unreachable;

  bool get needsEmailVerification => user != null && !user!.emailVerified;

  /// The server answered, and the answer was "no session" (or there was no
  /// token to ask with). This is the only signed-OUT state.
  static const SessionState unauthenticated = SessionState();

  /// The server could not be asked. Only [AuthController.build] makes one.
  static const SessionState unknown = SessionState(unreachable: true);
}

/// Settings → Sign-in methods (GET /api/mobile/sign-in-methods).
class SignInMethods {
  const SignInMethods({
    required this.email,
    required this.hasPassword,
    required this.linked,
    required this.available,
    required this.methodCount,
  });

  final String email;

  /// An email + password exists for this account.
  final bool hasPassword;

  /// Linked providers: 'google' / 'apple'.
  final List<String> linked;

  /// Providers this server has keys for (so can link).
  final List<String> available;

  /// Password + links. One must always remain.
  final int methodCount;

  bool get lastOne => methodCount <= 1;

  factory SignInMethods.fromJson(Map<String, dynamic> j) {
    final linked = (j['linked'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => m['provider'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    return SignInMethods(
      email: j['email'] as String? ?? '',
      hasPassword: j['hasPassword'] == true,
      linked: linked,
      available: (j['available'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      methodCount: (j['methodCount'] as num?)?.toInt() ??
          ((j['hasPassword'] == true ? 1 : 0) + linked.length),
    );
  }
}
